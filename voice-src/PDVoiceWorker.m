//
//  PDVoiceWorker.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  opus parameters recovered from the -prepare: completion block:
//      opus_encoder_create(16000, 1, OPUS_APPLICATION_AUDIO /*0x801*/, &err)
//      OPUS_SET_BITRATE(64000)  OPUS_SET_COMPLEXITY(5)  OPUS_SET_SIGNAL(VOICE)
//  framing: 16 byte stream header "#!OPUS_RAW_V1\x02\x01\x00" once, then
//      [u16 LE frameLength][opus frame] per 20 ms frame,
//      flushed when the pending block would exceed 3000 bytes.
//

#import "PDVoiceWorker.h"
#import "PDWeTypeClient.h"
#import "PDVoiceOutput.h"
#import "PDVoiceProtocol.h"
#import "PDAssetImporter.h"

#import <opus/opus.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

static NSString *const kPDIdentityPath =
    @"/var/mobile/Library/Application Support/PetDFY/voice-identity.plist";   // 0x1002642c0

/// 16 bytes appended once in front of the very first opus frame.
static const uint8_t kPDVoiceStreamHeader[16] = {
    '#', '!', 'O', 'P', 'U', 'S', '_', 'R', 'A', 'W', '_', 'V', '1', 0x02, 0x01, 0x00
};

static const int kPDSampleRate = 16000;
static const int kPDChannels = 1;
static const int kPDFrameSamples = 320;          // 20 ms at 16 kHz
static const int kPDFrameBytes = kPDFrameSamples * (int)sizeof(int16_t);   // 640
static const int kPDMaxPayload = 1500;           // 0x5dc opus output ceiling
static const int kPDMaxAudioChunk = 0x1901;      // 0x100184a58: 长度 >= 0x1901 即报 106
static const NSUInteger kPDMaxPacketBlock = 2999;   // encodeAvailable 封包阈值（0xbb7）
static const uint64_t kPDMaxQueuedBytes = 80001; // then fail(109)
static const NSInteger kPDMaxEmptyPolls = 31;    // then fail(104)
static const NSTimeInterval kPDStoppingDeadline = 8.0;

static double PDUptime(void) {
    return [NSProcessInfo processInfo].systemUptime;
}

@interface PDVoiceWorker () {
    dispatch_queue_t _queue;            // 0x08
    dispatch_source_t _timer;           // 0x10  pump timer (100 ms)
    dispatch_source_t _watchdog;        // 0x18  one shot startup watchdog
    PDWeTypeClient *_client;            // 0x20
    OpusEncoder *_encoder;              // 0x28
    NSMutableData *_pcm;                // 0x30
    NSMutableArray<NSData *> *_packets; // 0x38
    NSString *_voiceID;                 // 0x40
    NSString *_text;                    // 0x48
    BOOL _started;                      // 0x50
    BOOL _ready;                        // 0x51
    BOOL _stopping;                     // 0x52
    BOOL _inFlight;                     // 0x53
    BOOL _headerSent;                   // 0x54
    BOOL _endSent;                      // 0x55
    BOOL _traditional;                  // 0x56
    uint64_t _queuedBytes;              // 0x58
    uint64_t _pollCount;                // 0x60
    uint32_t _sequence;                 // 0x68
    double _nextRequestAt;              // 0x70
    double _stoppingAt;                 // 0x78
}
@end

@implementation PDVoiceWorker

- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    if ((self = [super init])) {
        _queue = queue;
        _pcm = [NSMutableData data];
        _packets = [NSMutableArray array];
        _voiceID = [[NSUUID UUID] UUIDString];
        _text = @"";

        // Startup watchdog: the shipped helper exits(1) if nothing happened for
        // 165 s (dispatch_time(0, 0x266AC43200)).
        _watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
        dispatch_source_set_timer(_watchdog,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)165 * NSEC_PER_SEC),
                                  DISPATCH_TIME_FOREVER,
                                  0);
        dispatch_source_set_event_handler(_watchdog, ^{
            exit(1);
        });
        dispatch_resume(_watchdog);
    }
    return self;
}

#pragma mark - failure + emit

- (void)fail:(NSInteger)code {
    [_client cancel];
    PDVoiceEmit(@{ @"type": @"error", @"code": @(code) });
    exit(1);
}

- (void)failWithError:(NSError *)error {
    [_client cancel];
    NSMutableDictionary *event = [@{
        @"type": @"error",
        @"domain": error.domain ?: @"",
        @"code": @(error.code),
    } mutableCopy];
    // 0x100184844-0x100184870: userInfo[@"stage"] 非空时写 event[@"stage"]（键名同为 stage）
    NSString *stage = error.userInfo[@"stage"];
    if (stage != nil) {
        event[@"stage"] = stage;
    }
    // 0x100184874-0x100184900: 若带 NSUnderlyingError，补 underlyingDomain / underlyingCode
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (underlying != nil) {
        event[@"underlyingDomain"] = underlying.domain ?: @"";
        event[@"underlyingCode"] = @(underlying.code);
    }
    PDVoiceEmit(event);
    exit(1);
}

#pragma mark - opus

- (void)encodeAvailable {
    NSMutableData *out = [NSMutableData data];
    if (!_headerSent) {
        [out appendBytes:kPDVoiceStreamHeader length:sizeof(kPDVoiceStreamHeader)];
        _headerSent = YES;
    }

    NSUInteger consumed = 0;
    while (_pcm.length >= (NSUInteger)kPDFrameBytes) {
        const uint8_t *pcm = (const uint8_t *)_pcm.bytes;
        uint8_t frame[kPDMaxPayload];
        int frames = opus_encode(_encoder,
                                 (const opus_int16 *)(pcm + consumed),
                                 kPDFrameSamples,
                                 frame, kPDMaxPayload);
        if (frames < 0) {
            [self fail:108];
            return;
        }
        // Flush the pending block as soon as it would reach 2999 bytes
        // (0x100184fa0: sub #2999 / cmn #-3002 / b.hi -> skip when < 2999).
        if (out.length + (NSUInteger)frames >= kPDMaxPacketBlock) {
            [self addPacket:out];
            out = [NSMutableData data];
        }
        uint16_t length = (uint16_t)frames;                 // little endian prefix
        [out appendBytes:&length length:sizeof(length)];
        [out appendBytes:frame length:(NSUInteger)frames];
        consumed += kPDFrameBytes;
        if (_pcm.length - consumed < (NSUInteger)kPDFrameBytes) {
            break;
        }
    }
    if (consumed != 0) {
        [_pcm replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
    }
    [self addPacket:out];

    if (_queuedBytes >= kPDMaxQueuedBytes) {
        [self fail:109];
    }
}

- (void)addPacket:(NSData *)packet {
    if (packet.length != 0) {
        [_packets addObject:[packet copy]];
        _queuedBytes += packet.length;
    }
}

#pragma mark - pump

- (void)pump {
    if (!_ready || _inFlight) {
        return;
    }
    double now = PDUptime();
    if (now < _nextRequestAt) {
        return;
    }
    if (_packets.count == 0 && !_stopping) {
        return;
    }

    NSMutableData *body = [NSMutableData data];
    while (_packets.count != 0) {
        NSData *first = _packets.firstObject;
        if (body.length + first.length > 3000) {     // 0x1001851a4: cmp #0xbb8 / b.hi
            break;
        }
        [body appendData:first];
        _queuedBytes -= first.length;
        [_packets removeObjectAtIndex:0];
    }

    BOOL end = _stopping && _packets.count == 0;
    uint32_t sequence = 0;
    if (body.length != 0) {
        sequence = ++_sequence;
    }
    if (end) {
        _endSent = YES;
        if (body.length == 0) {
            if (++_pollCount >= (uint64_t)kPDMaxEmptyPolls) {
                [self fail:104];
                return;
            }
        }
    }

    _inFlight = YES;
    _nextRequestAt = PDUptime() + 0.1;                       // provisional pacing

    __weak PDVoiceWorker *weakSelf = self;
    [_client sendAudio:body
               voiceID:_voiceID
              sequence:sequence
                   end:end
           traditional:_traditional
            completion:^(NSDictionary *result, NSError *error) {
        PDVoiceWorker *self_ = weakSelf;
        if (self_ == nil) {
            return;
        }
        self_->_inFlight = NO;
        if (error != nil) {
            [self_ failWithError:error];
            return;
        }
        NSString *text = result[@"text"];
        BOOL final = [result[@"final"] boolValue];
        if (final) {
            if (!self_->_endSent) {
                [self_ fail:110];
                return;
            }
            PDVoiceEmit(@{ @"type": @"final", @"text": text ?: @"" });
            [self_->_client cancel];
            exit(0);
        }
        if (text.length != 0 && ![text isEqual:self_->_text]) {
            self_->_text = [text copy];
            PDVoiceEmit(@{ @"type": @"partial", @"text": text });
        }
        if (self_->_endSent) {
            double interval = [result[@"interval"] doubleValue] / 1000.0;
            interval = fmax(interval, 0.1);
            interval = fmin(interval, 1.0);
            self_->_nextRequestAt = PDUptime() + interval;
        }
        [self_ pump];
    }];
}

#pragma mark - commands

- (void)command:(uint8_t)command data:(NSData *)data {
    // 0x100184a24: 非 1/4 的命令先看 _ready，未就绪一律 105
    if (command != 1 && command != 4 && !_ready) {
        [self fail:105];
        return;
    }
    switch (command) {
        case 1: {                                   // start
            if (_started) {
                [self fail:100];
                return;
            }
            _started = YES;

            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![json isKindOfClass:[NSDictionary class]]) {
                [self fail:101];
                return;
            }
            id model = json[@"model"];
            if (![model isKindOfClass:[NSString class]] || [model length] > 0x40 ||
                [model dataUsingEncoding:NSASCIIStringEncoding] == nil) {
                [self fail:101];
                return;
            }
            // 0x100184b18-0x100184b50: traditional 必须是 NSNumber，否则 fail(101)
            id traditional = json[@"traditional"];
            if (![traditional isKindOfClass:[NSNumber class]]) {
                [self fail:101];
                return;
            }
            _traditional = [traditional boolValue];

            _client = [[PDWeTypeClient alloc] initWithQueue:_queue
                                               identityURL:[NSURL fileURLWithPath:kPDIdentityPath]
                                                     model:(NSString *)model];

            __weak PDVoiceWorker *weakSelf = self;
            [_client prepare:^(NSError *error) {
                PDVoiceWorker *self_ = weakSelf;
                if (self_ == nil) {
                    return;
                }
                if (error != nil) {
                    [self_ failWithError:error];
                    return;
                }
                int opusError = 0;
                self_->_encoder = opus_encoder_create(kPDSampleRate, kPDChannels,
                                                      OPUS_APPLICATION_AUDIO, &opusError);
                if (self_->_encoder == NULL || opusError != 0) {
                    [self_ fail:103];
                    return;
                }
                opus_encoder_ctl(self_->_encoder, OPUS_SET_BITRATE(64000));
                opus_encoder_ctl(self_->_encoder, OPUS_SET_COMPLEXITY(5));
                opus_encoder_ctl(self_->_encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));

                self_->_ready = YES;
                self_->_nextRequestAt = PDUptime();

                self_->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self_->_queue);
                dispatch_source_set_timer(self_->_timer,
                                          dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                                          100 * NSEC_PER_MSEC,
                                          15 * NSEC_PER_MSEC);
                dispatch_source_set_event_handler(self_->_timer, ^{
                    PDVoiceWorker *worker = weakSelf;
                    if (worker == nil) {
                        return;
                    }
                    if (worker->_stopping &&
                        PDUptime() - worker->_stoppingAt > kPDStoppingDeadline) {
                        [worker fail:104];        // 0x100184ec0: 超过 8 s 才失败
                        return;
                    }
                    [worker pump];                // stopping 但未超时 → 继续泵，收敛尾部与 final
                });
                dispatch_resume(self_->_timer);

                PDVoiceEmit(@{ @"type": @"ready" });
            }];
            return;
        }

        case 2: {                                   // audio chunk
            if (!_ready) {
                [self fail:105];
                return;
            }
            if (_stopping) {
                [self fail:106];
                return;
            }
            if ((data.length & 1) != 0 || data.length >= (NSUInteger)kPDMaxAudioChunk) {   // 最大 6400 字节
                [self fail:106];
                return;
            }
            [_pcm appendData:data];
            [self encodeAvailable];
            [self pump];                      // 0x100184a70 -> encodeAvailable -> pump
            return;
        }

        case 3: {                                   // end of stream
            if (!_ready) {
                [self fail:105];
                return;
            }
            if (data.length != 0) {
                [self fail:106];
                return;
            }
            if (_stopping) {
                return;
            }
            _stopping = YES;
            _stoppingAt = PDUptime();
            // The original truncates the residual PCM to one frame before the
            // final encode; kept verbatim (drops < 640 trailing bytes).
            if (_pcm.length != 0) {
                [_pcm setLength:kPDFrameBytes];
                [self encodeAvailable];       // 0x100184c7c: 只在有残留 PCM 时编码
            }
            [self pump];
            return;
        }

        case 4: {                                   // one shot asset request
            if (_started) {
                [self fail:100];
                return;
            }
            _started = YES;
            dispatch_source_set_timer(_watchdog,
                                      dispatch_time(DISPATCH_TIME_NOW, (int64_t)700 * NSEC_PER_SEC),
                                      DISPATCH_TIME_FOREVER, 0);

            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSDictionary *result = PDRunAssetRequestWithProgress((NSDictionary *)json, ^(NSDictionary *progress) {
                PDVoiceEmit(progress);
            });
            // 0x1001849c4: the result itself is emitted, then the process exits on
            // result["type"] != "asset-result".
            PDVoiceEmit(result);
            exit(![result[@"type"] isEqual:@"asset-result"]);
        }

        default:
            [self fail:107];
            return;
    }
}

@end



