//
//  PDVoiceWorker.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  Owns the opus encoder and the request pump.  The IPC front end (main.m) hands
//  it one command at a time:
//    1  start         payload = JSON {"model": <string>, "traditional": <bool>}
//    2  audio         payload = raw 16 kHz mono PCM16, even length, <= 6400 bytes
//    3  end           payload = empty
//    4  asset request payload = JSON asset request (one shot, process exits)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDVoiceWorker : NSObject

- (instancetype)initWithQueue:(dispatch_queue_t)queue;

/// Dispatches one IPC command.  The worker is single threaded; callers must be
/// on the queue handed to -initWithQueue:.
- (void)command:(uint8_t)command data:(NSData *_Nullable)data;

@end

NS_ASSUME_NONNULL_END
