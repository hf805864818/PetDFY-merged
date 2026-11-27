//
//  PDVoiceOutput.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  Host IPC.  Every frame written to stdout is
//      [u32 big-endian totalLength][u8 command = 0][payload]
//  where totalLength counts the command byte plus the JSON payload.
//  Events are JSON objects; the launcher reads them from the helper's stdout.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 0x100184618  emit(event): serialise `event` as JSON and write one frame to fd 1.
/// Exits with status 2 when the object cannot be serialised or exceeds 64 KiB.
void PDVoiceEmit(NSDictionary *_Nullable event);

NS_ASSUME_NONNULL_END
