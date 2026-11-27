//
//  PDBootstrap.m — 加载标记 + 启动入口 + 启动守卫
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import "PDOverlayController.h"
#import "PDBoot.h"

static NSString * const kPDBootStatePath = @"/var/mobile/Media/petdfy-boot.state";
static NSString * const kPDDisablePath   = @"/var/mobile/Media/petdfy-disable";

void PDInitLog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list ap; va_start(ap, fmt);
        NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);
        NSString *path = @"/var/mobile/Media/petdfy-diag.txt";
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if ([attrs fileSize] > 262144) [[NSData data] writeToFile:path atomically:YES];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) return;
        [h seekToEndOfFile];
        [h writeData:[[NSString stringWithFormat:@"[%@] %@\n", [NSDate date], line]
                      dataUsingEncoding:NSUTF8StringEncoding]];
        [h synchronizeFile];
        [h closeFile];
    }
}

static NSString * const kPDBuildTag = @"build.077";

static int PDBootReadAttempts(void) {
    NSString *s = [NSString stringWithContentsOfFile:kPDBootStatePath
                                            encoding:NSUTF8StringEncoding error:NULL];
    if (![s hasPrefix:kPDBuildTag]) return 0;   // 新版本自动清零
    NSArray *parts = [s componentsSeparatedByString:@"|"];
    return parts.count > 1 ? [parts[1] intValue] : 0;
}

static void PDBootWriteAttempts(int n) {
    [[NSString stringWithFormat:@"%@|%d", kPDBuildTag, n] writeToFile:kPDBootStatePath
                                                           atomically:YES
                                                             encoding:NSUTF8StringEncoding
                                                                error:NULL];
}

BOOL PDBootGuardAllow(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kPDDisablePath]) {
        PDInitLog(@"boot guard: %@ exists -> tweak disabled", kPDDisablePath);
        return NO;
    }
    int attempts = PDBootReadAttempts();
    if (attempts >= 2) {
        // 保持 2，不再清零：以后每次启动都跳过，直到用户删除状态文件或装新版本。
        PDInitLog(@"boot guard: %d consecutive crashes -> SKIP (delete %@ to retry)", attempts, kPDBootStatePath);
        return NO;
    }
    PDBootWriteAttempts(attempts + 1);
    PDInitLog(@"boot guard: allow boot, attempt=%d", attempts + 1);
    return YES;
}

void PDBootGuardMarkHealthy(void) {
    PDBootWriteAttempts(0);
    PDInitLog(@"boot guard: healthy (attempts reset)");
}

BOOL PDHairTintAtBootAllowed(void) {
    // 每帧都会问，必须缓存，绝不能在 draw 路径里反复查磁盘
    static int cached = -1;
    if (cached < 0) {
        cached = [[NSFileManager defaultManager]
                  fileExistsAtPath:@"/var/mobile/Media/petdfy-hairtint-on"] ? 1 : 0;
    }
    return cached == 1;
}

__attribute__((constructor))
static void PDBootstrap(void) {
    @autoreleasepool {
        NSString *marker = [NSString stringWithFormat:@"PetDFY main loaded\npid=%d\ndate=%@\n",
                            getpid(), [NSDate date]];
        [marker writeToFile:@"/var/mobile/Media/petdfy-main-loaded.txt"
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:NULL];

        PDInitLog(@"=== PetDFY build.077 bootstrap pid=%d ===", getpid());
        if (!PDBootGuardAllow()) {
            return;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PDInitLog(@"bootstrap: calling start");
            [[PDOverlayController sharedController] start];
        });

        // 25 秒后仍存活 → 清零崩溃计数
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PDBootGuardMarkHealthy();
        });
    }
}
