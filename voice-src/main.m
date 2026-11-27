//
//  main.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  Role: stdin/stdout IPC helper for the PetDFY tweak.  The launcher writes
//      [u32 big-endian totalLength][u8 command][payload]
//  frames into the helper's stdin; the helper answers on stdout with
//      [u32 big-endian totalLength][u8 0][JSON]
//  frames (see PDVoiceOutput.m).
//
//  totalLength counts the command byte plus the payload.  Payload length must be
//  in 1..0x10000; zero or larger exits with status 2 (0x10018580c).
//

#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdlib.h>
#import <unistd.h>
#import <dispatch/dispatch.h>

#import "PDVoiceWorker.h"

static const NSUInteger kPDFramePayloadLimit = 0x20000;   // buffered PCM ceiling

int main(void) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);

        // Die with the launcher: DISPATCH_SOURCE_TYPE_PROC / DISPATCH_PROC_EXIT.
        pid_t parent = getppid();
        if (parent < 2) {
            return 0;                         // 0x1001855e0: ppid < 2 → 共享返回 0 的尾部
        }
        {
            dispatch_source_t source =
                dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)parent,
                                       DISPATCH_PROC_EXIT,
                                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
            if (source == NULL) {
                return 1;
            }
            dispatch_source_set_event_handler(source, ^{
                exit(0);
            });
            dispatch_resume(source);
            if (getppid() != parent) {
                return 0;
            }
        }

        dispatch_queue_t queue = dispatch_queue_create("com.susudear.petdfy.voice-service", NULL);
        PDVoiceWorker *worker = [[PDVoiceWorker alloc] initWithQueue:queue];
        NSMutableData *buffer = [NSMutableData data];

        dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, STDIN_FILENO, queue, ^(int error) {
            exit(0);
        });
        dispatch_io_set_low_water(channel, 1);
        dispatch_io_set_high_water(channel, 0x10000);

        dispatch_io_read(channel, 0, SIZE_MAX, queue, ^(bool done, dispatch_data_t data, int error) {
            dispatch_data_t chunk = data;
            if (chunk != NULL && dispatch_data_get_size(chunk) != 0) {
                const void *mapped = NULL;
                size_t size = 0;
                dispatch_data_t region = dispatch_data_create_map(chunk, &mapped, &size);
                if (region != NULL && size != 0) {
                    [buffer appendBytes:mapped length:size];
                }
                if (buffer.length > kPDFramePayloadLimit) {
                    exit(2);
                }

                while (buffer.length > 3) {
                    const uint8_t *bytes = (const uint8_t *)buffer.bytes;
                    uint32_t length = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                                      ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
                    // 0x10018580c: add w8,w23,#-0x10001 / cmp w8,#-0x10001 / b.ls -> exit(2)
                    // 等价于「payload 长度 == 0 或 > 0x10000 就退出」，1..65536 都是合法帧。
                    if (length == 0 || length > 0x10000) {
                        exit(2);
                    }
                    if (buffer.length < (NSUInteger)length + 4) {
                        break;
                    }
                    uint8_t command = bytes[4];
                    NSData *payload = [NSData dataWithBytes:bytes + 5 length:(NSUInteger)length - 1];
                    [buffer replaceBytesInRange:NSMakeRange(0, (NSUInteger)length + 4)
                                      withBytes:NULL
                                         length:0];
                    [worker command:command data:payload];
                }
            }

            if (done || error != 0) {
                exit(0);
            }
        });

        dispatch_main();
    }
    return 0;
}
