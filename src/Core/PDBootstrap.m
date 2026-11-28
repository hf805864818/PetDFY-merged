//
//  PDBootstrap.m — 加载标记 + 启动入口 + 启动守卫（build.96 重写）
//
//  为什么重写：
//    · 旧实现 kPDBuildTag 写死 "build.077"。build.078+ 全部沿用同一个 tag，
//      设备上的状态文件停在 build.077|2，于是 attempts>=2 永久 SKIP。
//      实测：2026-11-28 12:54:58 UTC 起每次 SpringBoard 启动都只打
//      "boot guard: 2 consecutive crashes -> SKIP"，build.93/94/95 从未执行过 start。
//    · 旧实现把「25 秒存活」当健康判据。respring / 手动注销 / 其它插件崩溃
//      都会计数 +1，两次就把桌宠永久关掉，且用户看不到任何提示。
//    · 新实现：
//        1) tag 取编译时间戳，每次构建不同 -> 新包必然重置计数；
//        2) 第 4 次起改为延迟 10 秒启动，不再永久禁用；
//        3) 首帧真正提交后才算健康（PDBootGuardMarkHealthy 由渲染器调用）；
//        4) 状态/日志路径经 PDJailbreakWritable 解析，RootHide 两套视图都能写。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <unistd.h>
#import "PDOverlayController.h"
#import "PDBoot.h"
#import "PDJailbreak.h"

static NSString * const kPDBootStateName = @"petdfy-boot.state";
static NSString * const kPDDisableName   = @"petdfy-disable";

/// RootHide 下 /var/mobile 在 SpringBoard 与越狱 App 里指向不同物理目录；
/// 这里统一走 PDJailbreakWritable（已存在则原样返回），保证写进当前进程真实可见的位置。
static NSString *PDMediaPath(NSString *name) {
    NSString *dir = PDJailbreakWritable(@"/var/mobile/Media");
    return [dir stringByAppendingPathComponent:name];
}

void PDInitLog(NSString *fmt, ...) {
    @autoreleasepool {
        va_list ap; va_start(ap, fmt);
        NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
        va_end(ap);
        NSString *path = PDMediaPath(@"petdfy-diag.txt");
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

/// 构建戳：每编译一次都不同，取代写死的 build.077。
static NSString *PDBuildStamp(void) {
    static NSString *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSString stringWithFormat:@"%s %s", __DATE__, __TIME__];
    });
    return stamp;
}

static int gPDBootStartDelay = 0;

static int PDBootReadAttempts(void) {
    NSString *s = [NSString stringWithContentsOfFile:PDMediaPath(kPDBootStateName)
                                            encoding:NSUTF8StringEncoding error:NULL];
    if (!s.length) return 0;
    NSArray *parts = [s componentsSeparatedByString:@"|"];
    // 旧格式 build.077|2 与旧 tag 不同 -> 自动清零
    if (parts.count < 2 || ![parts[0] isEqualToString:PDBuildStamp()]) return 0;
    return [parts[1] intValue];
}

static void PDBootWriteAttempts(int n) {
    NSString *line = [NSString stringWithFormat:@"%@|%d|%.0f",
                      PDBuildStamp(), n, [[NSDate date] timeIntervalSince1970]];
    [line writeToFile:PDMediaPath(kPDBootStateName)
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:NULL];
}

BOOL PDBootGuardAllow(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:PDMediaPath(kPDDisableName)]) {
        PDInitLog(@"boot guard: %@ exists -> tweak disabled", kPDDisableName);
        return NO;
    }
    int attempts = PDBootReadAttempts();
    if (attempts >= 3) {
        // 不永久禁用：延迟 10 秒再起，避免「开机即崩 -> 安全模式」死循环，
        // 也保证用户重新插电/注销后仍有恢复机会。
        gPDBootStartDelay = 10;
        PDInitLog(@"boot guard: %d attempts -> delayed start in %ds (tag=%@)",
                  attempts, gPDBootStartDelay, PDBuildStamp());
    }
    PDBootWriteAttempts(attempts + 1);
    PDInitLog(@"boot guard: allow boot, attempt=%d tag=%@", attempts + 1, PDBuildStamp());
    return YES;
}

int PDBootGuardStartDelay(void) { return gPDBootStartDelay; }

void PDBootGuardMarkHealthy(void) {
    PDBootWriteAttempts(0);
    PDInitLog(@"boot guard: healthy (first frame submitted, attempts reset)");
}

BOOL PDHairTintAtBootAllowed(void) {
    // 每帧都会问，必须缓存，绝不能在 draw 路径里反复查磁盘
    static int cached = -1;
    if (cached < 0) {
        cached = [[NSFileManager defaultManager]
                  fileExistsAtPath:PDMediaPath(@"petdfy-hairtint-on")] ? 1 : 0;
    }
    return cached == 1;
}

__attribute__((constructor))
static void PDBootstrap(void) {
    @autoreleasepool {
        NSString *marker = [NSString stringWithFormat:@"PetDFY main loaded\npid=%d\ndate=%@\n",
                            getpid(), [NSDate date]];
        [marker writeToFile:PDMediaPath(@"petdfy-main-loaded.txt")
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:NULL];

        PDInitLog(@"=== PetDFY %@ bootstrap pid=%d ===", PDBuildStamp(), getpid());
        if (!PDBootGuardAllow()) {
            return;
        }

        double delay = 1.0 + (double)PDBootGuardStartDelay();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PDInitLog(@"bootstrap: calling start (delay=%.0fs)", delay);
            [[PDOverlayController sharedController] start];
        });

        // 兜底：60 秒仍未提交首帧则记录一次，便于区分「没启动」与「启动了没画面」
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PDInitLog(@"watchdog: 60s elapsed, if no frame yet check PDOverlayController/ensureWindow");
        });
    }
}
