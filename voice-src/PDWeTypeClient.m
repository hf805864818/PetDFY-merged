//
//  PDWeTypeClient.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//  Method layout mirrors the original class_ro: initWithQueue:identityURL:model:,
//  headersForBody:task:kind:token:, exchangePath:task:body:headers:completion:,
//  finishHandshake:error:, prepare:, timestampThen:failure:,
//  publicKeyForNewIdentity:completion:, saveIdentityWithError:,
//  generateUIN:completion:, sendAudio:voiceID:sequence:end:traditional:completion:,
//  cancel, dealloc.
//

#import "PDWeTypeClient.h"
#import "PDVoiceProtocol.h"
#import "PDVoiceOutput.h"
#import <sys/stat.h>
#import <unistd.h>

NSString *const PDVoiceProtocolErrorDomain = @"PetDFY.VoiceProtocol";

NSString *const kPDWTHost = @"wetype.weixin.qq.com";        // 0x1002643a0
NSString *const kPDWTWSPath = @"wxws_pb";                   // 0x100264cf8 (subprotocol)

static NSString *const kPDWTIdentityURLString =
    @"/var/mobile/Library/Application Support/PetDFY/voice-identity.plist";   // 0x1002642c0

static NSError *PDWTError(NSInteger code) {
    return [NSError errorWithDomain:PDVoiceProtocolErrorDomain code:code userInfo:nil];
}

// Fixed identity plist keys (0x1002647c0 / 0x100264280 / 0x1002647e0 / 0x100264800).
static NSString *const kPDKeyDeviceCode = @"deviceCode";
static NSString *const kPDKeyModel = @"model";
static NSString *const kPDKeyServerPublic = @"serverPublic";
static NSString *const kPDKeyUin = @"uin";

@implementation PDWeTypeClient {
    BOOL _ready;                        // ivar 0x08
    uint32_t _task;                     // ivar 0x0c
    dispatch_queue_t _queue;            // ivar 0x10
    NSURLSession *_session;             // ivar 0x18
    NSURLSessionWebSocketTask *_socket; // ivar 0x20
    NSURL *_identityURL;                // ivar 0x28
    NSString *_model;                   // ivar 0x30
    NSString *_deviceCode;              // ivar 0x38
    NSString *_serverPublic;            // ivar 0x40
    PDWeTypeKeyAgreement *_agreement;   // ivar 0x48
    NSData *_sessionKey;                // ivar 0x50
    uint64_t _uin;                      // ivar 0x58
    uint64_t _timestamp;                // ivar 0x60
    uint64_t _generation;               // ivar 0x68
    uint64_t _handshakeRequest;         // ivar 0x70
    id _pendingHandshake;               // ivar 0x78
}

@synthesize queue = _queue, session = _session, socket = _socket, identityURL = _identityURL;
@synthesize model = _model, deviceCode = _deviceCode, serverPublic = _serverPublic;
@synthesize agreement = _agreement, sessionKey = _sessionKey;
@synthesize uin = _uin, timestamp = _timestamp, task = _task, generation = _generation;
@synthesize handshakeRequest = _handshakeRequest, ready = _ready, pendingHandshake = _pendingHandshake;

#pragma mark - lifetime

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                  identityURL:(NSURL *)identityURL
                        model:(NSString *)model {
    if ((self = [super init])) {
        _queue = queue;
        _identityURL = identityURL;
        _model = [model copy];
        _task = 1000;                                    // 0x3e8

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 10.0;
        configuration.URLCache = nil;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCredentialStorage = nil;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)dealloc {
    [self cancel];
}

- (void)cancel {
    _generation += 1;
    _ready = NO;
    _pendingHandshake = nil;
    [_socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway /* 1001 */ reason:nil];
    _socket = nil;
    [_session invalidateAndCancel];
    _session = nil;
    _sessionKey = nil;
    _agreement = nil;
}

#pragma mark - headers

- (NSDictionary<NSString *, NSString *> *)headersForBody:(NSData *)body
                                                    task:(uint32_t)task
                                                    kind:(PDWeTypeKind)kind
                                                   token:(NSString *)token {
    NSMutableString *trace = [NSMutableString stringWithString:[[NSUUID UUID].UUIDString
                                                              stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    // 0x100185c50-0x100185c84: Kb-TraceId 取去横线小写 UUID 的前 16 个字符再入字典
    NSString *traceID = [[trace lowercaseString] substringToIndex:16];

    NSMutableDictionary<NSString *, NSString *> *headers = [@{
        @"Kb-OsType": PDWTOsType,
        @"Kb-Version": PDWTVersion,
        @"Kb-SystemVersion": PDWTSystemVersion,
        @"Kb-PackageType": PDWTPackageType,
        @"Kb-Scene": PDWTScene,
        @"Use_DebugNet": @"0",
        @"Kb-CompressionType": @"1",
        @"Kb-TimeStamp": [NSString stringWithFormat:@"%llu", (unsigned long long)_timestamp],
        @"Kb-BodyMd5": PDWTMD5(body),
        @"Kb-TraceId": traceID,
        @"Kb-TaskId": [NSString stringWithFormat:@"%@", @(task)],
        @"Content-Type": @"application/octet-stream",
    } mutableCopy];

    // Header order used for Kb-Sign.  The base list is Kb-OsType, Kb-Version,
    // Kb-Scene; then the kind specific keys; Kb-TraceId / Kb-TaskId last.
    NSMutableArray<NSString *> *order = [@[@"Kb-OsType", @"Kb-Version", @"Kb-Scene"] mutableCopy];

    switch (kind) {
        case PDWeTypeKindData: {
            headers[@"Kb-CmdId"] = PDWTCmdID;            // "4547"
            headers[@"Kb-SubCmdId"] = @"0";
            [order addObjectsFromArray:@[@"Kb-CmdId", @"Kb-SubCmdId"]];
            [order addObjectsFromArray:@[@"Kb-TimeStamp", @"Kb-BodyMd5"]];
            headers[@"Kb-Uin"] = [NSString stringWithFormat:@"%llu", (unsigned long long)_uin];
            [order addObject:@"Kb-Uin"];
            NSString *sharedKey = [[NSString alloc] initWithData:_sessionKey encoding:NSUTF8StringEncoding];
            if (sharedKey.length >= 4) {
                headers[@"Kb-SharedKeySuffix"] = [sharedKey substringFromIndex:sharedKey.length - 4];
            }
            break;
        }
        case PDWeTypeKindGenUin: {
            [order addObjectsFromArray:@[@"Kb-TimeStamp", @"Kb-BodyMd5"]];
            headers[@"Kb-GenUinToken"] = token ?: @"";
            [order addObject:@"Kb-GenUinToken"];
            break;
        }
        case PDWeTypeKindTimestamp:
        default: {
            [order addObjectsFromArray:@[@"Kb-TimeStamp", @"Kb-BodyMd5"]];
            headers[@"Kb-Uin"] = [NSString stringWithFormat:@"%llu", (unsigned long long)_uin];
            break;
        }
    }
    if (kind != PDWeTypeKindData) {
        // 0x100185e1c: 非 kind 2 的请求带 Kb-DeviceCodeRestrictionV2=1（不进签名串）
        headers[@"Kb-DeviceCodeRestrictionV2"] = @"1";
    }
    [order addObjectsFromArray:@[@"Kb-TraceId", @"Kb-TaskId"]];

    NSMutableString *signInput = [NSMutableString string];
    for (NSString *key in order) {
        NSString *value = headers[key];
        if (value != nil) {
            [signInput appendString:value];
        }
    }
    [signInput appendString:PDWTSignSecret];
    headers[@"Kb-Sign"] = PDWTSHA256(signInput);

    return [headers copy];
}

#pragma mark - websocket exchange

- (void)finishHandshake:(NSDictionary *)fields error:(NSError *)error {
    void (^callback)(NSDictionary *, NSError *) = _pendingHandshake;
    _pendingHandshake = nil;
    if (callback != nil) {
        callback(fields, error);
    }
}

- (void)exchangePath:(NSString *)path
                task:(uint32_t)task
                body:(NSData *)body
             headers:(NSDictionary<NSString *, NSString *> *)headers
          completion:(void (^)(NSDictionary *, NSError *))completion {
    if (_pendingHandshake != nil) {
        completion(nil, PDWTError(10));                  // handshake already in flight
        return;
    }

    // Outer frame: {1:"POST", 3:path, 4:"", 5:{1:name,2:value}*, 6:body}
    NSMutableData *frame = [NSMutableData data];
    [frame appendData:PDWTString(1, @"POST")];
    [frame appendData:PDWTString(3, path)];
    [frame appendData:PDWTString(4, @"")];

    NSMutableDictionary<NSString *, NSString *> *allHeaders = [NSMutableDictionary dictionary];
    allHeaders[@"HOST"] = kPDWTHost;
    allHeaders[@"Content-Type"] = @"application/octet-stream";
    allHeaders[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)body.length];
    if (headers.count) {
        [allHeaders addEntriesFromDictionary:headers];
    }
    for (NSString *key in allHeaders) {
        NSMutableData *pair = [NSMutableData data];
        [pair appendData:PDWTString(1, key)];
        [pair appendData:PDWTString(2, allHeaders[key])];
        [frame appendData:PDWTBlob(5, pair)];
    }
    [frame appendData:PDWTBlob(6, body ?: [NSData data])];

    // Websocket message: {1:0, 2:0, 3:task, 5:frame}
    NSMutableData *message = [NSMutableData data];
    [message appendData:PDWTInteger(1, 0)];
    [message appendData:PDWTInteger(2, 0)];
    [message appendData:PDWTInteger(3, task)];
    [message appendData:PDWTBlob(5, frame)];

    _pendingHandshake = [completion copy];
    uint64_t generation = _generation;
    uint64_t request = ++_handshakeRequest;

    __weak PDWeTypeClient *weakSelf = self;
    NSURLSessionWebSocketMessage *wsMessage =
        [[NSURLSessionWebSocketMessage alloc] initWithData:message];
    [_socket sendMessage:wsMessage completionHandler:^(NSError *sendError) {
        dispatch_async(weakSelf.queue, ^{
            PDWeTypeClient *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.generation != generation ||
                strongSelf.handshakeRequest != request) {
                return;
            }
            if (sendError != nil) {
                [strongSelf finishHandshake:nil error:sendError];
                return;
            }
            [strongSelf.socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *reply,
                                                                     NSError *receiveError) {
                dispatch_async(strongSelf.queue, ^{
                    if (strongSelf.generation != generation || strongSelf.handshakeRequest != request) {
                        return;
                    }
                    NSDictionary *fields = PDWTFields(reply.data);
                    NSDictionary *payload = fields ? PDWTFields(PDWTData(fields, 4)) : nil;
                    if (receiveError != nil) {
                        [strongSelf finishHandshake:nil error:receiveError];
                        return;
                    }
                    if (payload == nil) {
                        [strongSelf finishHandshake:nil error:PDWTError(11)];
                        return;
                    }
                    if (PDWTNumber(fields, 2) != task) {
                        [strongSelf finishHandshake:nil error:PDWTError(11)];
                        return;
                    }
                    [strongSelf finishHandshake:payload error:nil];
                });
            }];
        });
    }];

    // 10 s reply deadline, matching configuration.timeoutIntervalForResource.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), _queue, ^{
        PDWeTypeClient *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.generation != generation ||
            strongSelf.handshakeRequest != request || strongSelf.pendingHandshake == nil) {
            return;
        }
        [strongSelf finishHandshake:nil error:PDWTError(12)];
    });
}

#pragma mark - prepare

- (void)prepare:(void (^)(NSError *))completion {
    if (_ready) {
        completion(nil);
        return;
    }

    NSDictionary *identity = [NSDictionary dictionaryWithContentsOfURL:_identityURL];
    NSString *deviceCode = identity[kPDKeyDeviceCode];
    NSString *model = identity[kPDKeyModel];
    NSString *serverPublic = identity[kPDKeyServerPublic];
    NSString *uin = identity[kPDKeyUin];

    BOOL reusable = [deviceCode isKindOfClass:[NSString class]] && deviceCode.length == 0x40 &&
                    [model isKindOfClass:[NSString class]] && model.length > 0 &&
                    [serverPublic isKindOfClass:[NSString class]];
    if (reusable) {
        NSData *publicKey = PDWTUnhex(serverPublic);
        if (publicKey.length == 0x21 && [uin isKindOfClass:[NSString class]] && uin.longLongValue > 0) {
            _deviceCode = deviceCode;
            _model = model;
            _serverPublic = serverPublic;
            _uin = (uint64_t)uin.longLongValue;
        } else {
            reusable = NO;
        }
    }
    if (!reusable) {
        // No usable identity yet: mint a device code and start a fresh handshake.
        _deviceCode = PDWTNewDeviceCode(_model);
        _serverPublic = @"";
        _uin = 0;
    }

    _agreement = [[PDWeTypeKeyAgreement alloc] init];
    if (_deviceCode == nil || _agreement.publicKey == nil) {
        completion(PDWTError(13));
        return;
    }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"wss://%@/", kPDWTHost]];
    _socket = [_session webSocketTaskWithURL:url protocols:@[kPDWTWSPath]];
    _socket.maximumMessageSize = 0x100000;
    [_socket resume];

    __weak PDWeTypeClient *weakSelf = self;
    [self timestampThen:^{
        PDWeTypeClient *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf publicKeyForNewIdentity:(strongSelf.uin == 0) completion:completion];
    } failure:completion];
}

#pragma mark - timestamp

- (void)timestampThen:(void (^)(void))then failure:(void (^)(NSError *))failure {
    __weak PDWeTypeClient *weakSelf = self;
    [self exchangePath:@"/timestamp"
                  task:0x7fffffff
                  body:[NSData data]
               headers:nil
            completion:^(NSDictionary *fields, NSError *error) {
        PDWeTypeClient *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (error != nil) {
            failure(error);
            return;
        }
        uint64_t stamp = PDWTNumber(PDWTFields(PDWTData(fields, 5)), 1);
        if (PDWTNumber(fields, 2) != 200 || stamp == 0) {
            failure(PDWTError(14));
            return;
        }
        strongSelf.timestamp = stamp;
        then();
    }];
}

#pragma mark - oauth_pubkey_v2

- (void)publicKeyForNewIdentity:(BOOL)newIdentity completion:(void (^)(NSError *))completion {
    NSMutableData *request = [PDWTString(1, _agreement.publicKey) mutableCopy];
    [request appendData:PDWTString(2, _serverPublic ?: @"")];
    [request appendData:PDWTInteger(3, newIdentity ? 1 : 0)];
    [request appendData:PDWTString(4, _deviceCode)];
    if (newIdentity) {
        [request appendData:PDWTString(6, @"")];
    } else {
        [request appendData:PDWTInteger(5, _uin)];
    }
    [request appendData:PDWTString(7, @"")];
    [request appendData:PDWTString(8, _model)];
    [request appendData:PDWTString(9, @"PetDFY")];

    NSData *appKey = [PDWTAppID dataUsingEncoding:NSASCIIStringEncoding];
    NSData *body = PDWTCrypt(request, appKey, kCCEncrypt);
    if (body == nil) {
        completion(PDWTError(15));
        return;
    }
    // 0x100187450: kind 传 0（不是 2），因此头里没有 Kb-CmdId/Kb-SubCmdId，且带 Kb-DeviceCodeRestrictionV2
    NSDictionary *headers = [self headersForBody:body task:0x7ffffffe kind:PDWeTypeKindTimestamp token:nil];

    __weak PDWeTypeClient *weakSelf = self;
    [self exchangePath:@"/oauth_pubkey_v2"
                  task:0x7ffffffe
                  body:body
               headers:headers
            completion:^(NSDictionary *fields, NSError *error) {
        PDWeTypeClient *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        // 0x10018758c: 这里用的是块捕获的 appKey（首轮还没有 sessionKey），不是 sessionKey
        NSData *appKey = [PDWTAppID dataUsingEncoding:NSASCIIStringEncoding];
        NSDictionary *decoded = PDWTFields(PDWTCrypt(PDWTData(fields, 5), appKey, kCCDecrypt));
        if (error != nil) {
            completion(error);
            return;
        }
        if (PDWTNumber(fields, 2) != 200 || decoded[@1] == nil || PDWTNumber(decoded, 1) != 0) {
            completion(PDWTError(16));
            return;
        }

        NSString *serverPublic = [[NSString alloc] initWithData:PDWTData(decoded, 2)
                                                       encoding:NSUTF8StringEncoding];
        NSData *sessionKey = [strongSelf.agreement deriveKey:serverPublic];
        if (sessionKey == nil) {
            completion(PDWTError(17));
            return;
        }
        strongSelf.sessionKey = sessionKey;
        strongSelf.serverPublic = serverPublic;

        if (newIdentity) {
            NSString *token = [[NSString alloc] initWithData:PDWTData(decoded, 4)
                                                    encoding:NSUTF8StringEncoding];
            [strongSelf generateUIN:token completion:completion];
            return;
        }

        NSError *saveError = nil;
        if ([strongSelf saveIdentityWithError:&saveError]) {
            strongSelf.ready = YES;
            [strongSelf.socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure /* 1000 */
                                            reason:nil];
            strongSelf.socket = nil;
            completion(nil);
        } else {
            completion(saveError);
        }
    }];
}

#pragma mark - identity persistence

/// 0x100187b88  PDVoiceStorageError(stage, underlying)
/// domain "PetDFY.VoiceStorage", code 18, userInfo {stage, NSUnderlyingError}.
static NSError *PDVoiceStorageError(NSString *stage, NSError *underlying) {
    NSMutableDictionary *info = [@{ @"stage": stage ?: @"" } mutableCopy];
    if (underlying != nil) {
        info[NSUnderlyingErrorKey] = underlying;
    }
    return [NSError errorWithDomain:@"PetDFY.VoiceStorage" code:18 userInfo:info];
}

- (BOOL)saveIdentityWithError:(NSError **)error {
    NSURL *directory = [_identityURL URLByDeletingLastPathComponent];
    NSError *directoryError = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:directory
                                       withIntermediateDirectories:YES
                                                        attributes:@{NSFilePosixPermissions: @(0700)}
                                                             error:&directoryError];
    if (!ok) {
        if (error) {
            *error = PDVoiceStorageError(@"identity-directory", directoryError);
        }
        return NO;
    }

    NSDictionary *identity = @{
        kPDKeyDeviceCode: _deviceCode ?: @"",
        kPDKeyModel: _model ?: @"",
        kPDKeyServerPublic: _serverPublic ?: @"",
        kPDKeyUin: [NSString stringWithFormat:@"%llu", (unsigned long long)_uin],
    };
    NSError *encodeError = nil;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:identity
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&encodeError];
    if (plist == nil) {
        if (error) {
            *error = PDVoiceStorageError(@"identity-write", encodeError);
        }
        return NO;
    }

    NSError *writeError = nil;
    if (![plist writeToURL:_identityURL options:NSDataWritingAtomic error:&writeError]) {
        if (error) {
            *error = PDVoiceStorageError(@"identity-write", writeError);
        }
        return NO;
    }

    chmod([_identityURL fileSystemRepresentation], 0600);
    // The shipped helper also pins the file protection class so the plist stays
    // readable by the helper while the device is locked.
    [[NSFileManager defaultManager] setAttributes:@{
        NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication,
    } ofItemAtPath:_identityURL.path error:NULL];
    return YES;
}

#pragma mark - gen_uin_v2

- (void)generateUIN:(NSString *)token completion:(void (^)(NSError *))completion {
    if (token.length == 0) {
        completion(PDWTError(19));
        return;
    }
    NSString *trace = [[NSUUID UUID].UUIDString
                       stringByAppendingFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000.0];

    NSMutableData *request = [PDWTString(1, _deviceCode) mutableCopy];
    [request appendData:PDWTString(2, _serverPublic ?: @"")];
    [request appendData:PDWTString(4, trace)];
    [request appendData:PDWTString(5, @"")];

    NSData *body = PDWTCrypt(request, _sessionKey, kCCEncrypt);
    NSDictionary *headers = [self headersForBody:body task:0x7ffffffd kind:PDWeTypeKindGenUin token:token];

    __weak PDWeTypeClient *weakSelf = self;
    [self exchangePath:@"/gen_uin_v2"
                  task:0x7ffffffd
                  body:body
               headers:headers
            completion:^(NSDictionary *fields, NSError *error) {
        PDWeTypeClient *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        // /gen_uin_v2 的响应体用 sessionKey 解（oauth 那一步已建立），此处不是 appKey
        NSDictionary *decoded = PDWTFields(PDWTCrypt(PDWTData(fields, 5), strongSelf.sessionKey, kCCDecrypt));
        if (error != nil) {
            completion(error);
            return;
        }
        if (PDWTNumber(fields, 2) != 200 || decoded[@1] == nil || PDWTNumber(decoded, 1) != 0 ||
            PDWTNumber(decoded, 2) == 0) {
            completion(PDWTError(20));
            return;
        }
        strongSelf.uin = PDWTNumber(decoded, 2);

        // Re-run the timestamp exchange, then finish the identity handshake.
        [strongSelf timestampThen:^{
            [strongSelf publicKeyForNewIdentity:NO completion:completion];
        } failure:completion];
    }];
}

#pragma mark - audio

- (void)sendAudio:(NSData *)audio
          voiceID:(NSString *)voiceID
         sequence:(uint32_t)sequence
              end:(BOOL)end
      traditional:(BOOL)traditional
       completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!_ready || voiceID.length == 0 || audio.length >= 0xdad) {
        completion(nil, PDWTError(21));
        return;
    }

    // {2:voiceID, 3:0, 4:audio, 5:5, 6:end, 7:sequence, 8:"", 9:traditional,
    //  11:audio.length, 14:0, 15:0, 16:"", 17:0, 19:0}
    NSMutableData *message = [PDWTString(2, voiceID) mutableCopy];
    [message appendData:PDWTInteger(3, 0)];
    [message appendData:PDWTBlob(4, audio)];
    [message appendData:PDWTInteger(5, 5)];
    [message appendData:PDWTInteger(6, end ? 1 : 0)];
    [message appendData:PDWTInteger(7, sequence)];
    [message appendData:PDWTBlob(8, [NSData data])];
    [message appendData:PDWTInteger(9, traditional ? 1 : 0)];
    [message appendData:PDWTInteger(11, audio.length)];
    [message appendData:PDWTInteger(14, 0)];
    [message appendData:PDWTInteger(15, 0)];
    [message appendData:PDWTString(16, @"")];
    [message appendData:PDWTInteger(17, 0)];
    [message appendData:PDWTInteger(19, 0)];

    NSData *body = PDWTCrypt(PDWTBlob(1, message), _sessionKey, kCCEncrypt);
    if (body == nil) {
        completion(nil, PDWTError(22));
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/api_v2", kPDWTHost]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    uint32_t task = _task;
    _task = task + 1;
    request.allHTTPHeaderFields = [self headersForBody:body task:task kind:PDWeTypeKindData token:nil];

    uint64_t generation = _generation;
    __weak PDWeTypeClient *weakSelf = self;
    NSURLSessionDataTask *dataTask =
        [_session dataTaskWithRequest:request completionHandler:^(NSData *data,
                                                                 NSURLResponse *response,
                                                                 NSError *error) {
        dispatch_async(weakSelf.queue, ^{
            PDWeTypeClient *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.generation != generation) {
                return;
            }
            NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            if (error != nil) {
                completion(nil, error);
                return;
            }
            if (http.statusCode != 200 || data.length == 0 || data.length > 0x100000) {
                completion(nil, PDWTError(23));
                return;
            }
            NSString *expectedMD5 = [http valueForHTTPHeaderField:@"Kb-BodyMd5"];
            if (expectedMD5.length != 0 && ![PDWTMD5(data) isEqual:[expectedMD5 uppercaseString]]) {
                completion(nil, PDWTError(24));
                return;
            }

            NSData *plain = PDWTCrypt(data, strongSelf.sessionKey, kCCDecrypt);
            NSString *compression = [http valueForHTTPHeaderField:@"Kb-CompressionType"] ?: @"1";
            if ([compression isEqual:@"2"]) {
                plain = PDWTSnappyDecode(plain);
            } else if (![compression isEqual:@"1"]) {
                plain = nil;
            }

            NSDictionary *fields = PDWTFields(plain);
            NSDictionary *layer2 = PDWTFields(PDWTData(fields, 1));
            NSDictionary *status = PDWTFields(PDWTData(layer2, 1));
            if (layer2 == nil || status[@1] == nil || PDWTNumber(status, 1) != 0) {
                completion(nil, PDWTError(25));
                return;
            }

            NSString *echoedVoiceID = [[NSString alloc] initWithData:PDWTData(layer2, 2)
                                                            encoding:NSUTF8StringEncoding];
            if (echoedVoiceID.length != 0 && ![echoedVoiceID isEqual:voiceID]) {
                completion(nil, PDWTError(26));
                return;
            }

            NSString *text = [[NSString alloc] initWithData:PDWTData(layer2, 4)
                                                   encoding:NSUTF8StringEncoding];
            NSString *textAlt = [[NSString alloc] initWithData:PDWTData(layer2, 13)
                                                      encoding:NSUTF8StringEncoding];
            NSString *partial = [[NSString alloc] initWithData:PDWTData(layer2, 15)
                                                      encoding:NSUTF8StringEncoding];
            NSString *chosen = partial.length ? partial : (textAlt.length ? textAlt : text);

            NSDictionary *result = @{
                @"text": chosen ?: @"",
                @"final": @(PDWTNumber(status, 5) == 1),
                @"interval": @(PDWTNumber(status, 6)),
                @"maxPacketSize": @(PDWTNumber(status, 7)),
            };
            completion(result, nil);
        });
    }];
    [dataTask resume];
}

@end

