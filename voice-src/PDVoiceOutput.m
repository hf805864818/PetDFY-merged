//
//  PDVoiceOutput.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//

#import "PDVoiceOutput.h"
#import <errno.h>
#import <stdlib.h>
#import <unistd.h>

void PDVoiceEmit(NSDictionary *event) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
    if (json == nil || json.length >= 0x10000) {
        exit(2);
    }

    uint32_t total = (uint32_t)json.length + 1;         // + command byte
    uint8_t header[5];
    header[0] = (uint8_t)(total >> 24);
    header[1] = (uint8_t)(total >> 16);
    header[2] = (uint8_t)(total >> 8);
    header[3] = (uint8_t)total;
    header[4] = 0;                                      // command 0 = event

    NSMutableData *frame = [NSMutableData dataWithBytes:header length:sizeof(header)];
    [frame appendData:json];

    const uint8_t *bytes = (const uint8_t *)frame.bytes;
    NSUInteger length = frame.length;
    NSUInteger written = 0;
    while (written < length) {
        ssize_t n = write(STDOUT_FILENO, bytes + written, length - written);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            exit(0);                                    // peer gone
        }
        if (n == 0) {
            exit(0);
        }
        written += (NSUInteger)n;
    }
}
