//
//  PDNative_MCPLogger.m
//  PetDFY
//
//  iOS-MCP 的本地日志：/var/mobile/Library/Logs/iOSMCP/ios-mcp.log，带 2 MB 轮转 + flock 互斥。
//
//  二进制证据
//    image base  : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表      : out/method-table-all.md → 11 条（**全 `+`**）
//    区间        : 0x6c568 .. 0x6d664
//    instanceSize: 8（0x08）—— 本类无实例 ivar，所有状态放在**另一个**单例对象里：
//                  0x6c6a4  状态单例取用点（dispatch_once 0xf2078）
//                  0x6d61c  单例构造：objc_opt_new(类槽 0xc8) → 静态槽 +0x58
//                  0x6d644  串行队列：dispatch_queue_create("com.witchan.ios-mcp.debug-log", NULL) → +0x68
//                  状态对象字段（由用法反推）：+0x40 lastLogError / +0x48 上次读取时刻 / +0x50 缓存值
//    区间内静态实体
//      0x6c6a4  状态单例 accessor（35 insns）
//      0x6cc28  日志串行队列 accessor（35 insns，dispatch_once 0xf2098）
//      0x6d0e8  setLastLogError（62 insns，@synchronized）
//      0x6d15c  logFail(name, errno)（90 insns，@"%@ failed errno=%d error=%s"）
//      0x6d300  写锁释放辅助（clearLogs 用）
//      0x6d318  clearLogs 的 dispatch_sync 块体（269 insns）
//
//  符号修正（跨单元一致性，2026-11-28）
//    本类 11 条全部是**类方法**（方法表 sign 列为 +，取自元类 ro）。本文件已全部写成 `+`，
//    方法体内不出现任何实例 ivar：状态放在另一个单例对象里（0x6c6a4），
//    `self` 在类方法里就是 Class，`self.logFilePath` 等调用都是对同类类方法的调用，
//    已有二进制印证：0x6c6fc `bl sel:logDirectoryPath`（同一个 objc_msgSend，接收者是类）。
//    logDirectoryPath 只有 3 条指令 —— 0x6c6e4 adrp / 0x6c6e8 add(CFString) / 0x6c6ec ret，
//    返回的是常量串，不读任何静态变量，故实现保持 `return kPDMCPLogDirectory;`。
//
//  标记：[0xADDR] = 指令地址；Assumed = 语义推断；NOT RUN = 未运行
//        直调 0xADDR = 已落到具名入口（本文件 CALL 0 处）
//

#import "PDNative_MCPLogger.h"
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <sys/time.h>
#import <time.h>

// 0x6c6e8 / 0x6c70c / 0x6c74c / 0x6c7a8 / 0x6c890 / 0x6c7a8
static NSString *const kPDMCPLogDirectory = @"/var/mobile/Library/Logs/iOSMCP";
static NSString *const kPDMCPLogFile      = @"ios-mcp.log";
static NSString *const kPDMCPPrevLogFile  = @"ios-mcp.1.log";
static NSString *const kPDMCPLockFile     = @"ios-mcp.lock";
static NSString *const kPDMCPArchivedFmt  = @"ios-mcp.%lu.log";

// 0x6cc5c / 0x6d644
static NSString *const kPDMCPLogQueueLabel = @"com.witchan.ios-mcp.debug-log";

static const off_t kPDMCPLogRotateBytes = 2 * 1024 * 1024;   // 0x6ce98 cmp x8,#0x200,lsl#12
static const NSUInteger kPDMCPMaxMessage = 4096;             // 0x6ca64 cmp x0,#1,lsl#12

// 状态单例：0x6c6a4（dispatch_once token 0x11c060，块体 0x6d610）
//   已定案 0x6d618/0x6d61c：ldr x0,[0x11a0c8] = _OBJC_CLASS_$_NSObject + objc_opt_new
//   → 单例就是 NSObject 实例（不是自定义类），实例指针存在全局 0x11c058。
//   字段偏移（+0x40 lastLogError / +0x48 cacheStamp / +0x50 cachedEnabled）在 NSObject
//   实例上属于越界写入，二进制确实是这么写的（0x6c8d4 / 0x6c59c / 0x6c60c）。
//   日志队列不是结构体字段：已定案 0x6d64c dispatch_queue_create("com.witchan.ios-mcp.debug-log", NULL)
//   结果存在独立全局 0x11c068（紧邻 0x11c058，不是对象 +0x68）。
typedef struct PDMCPLoggerState {
    void *isa;                    // +0x00（类槽 0x11a0c8 = NSObject）
    void *reserved04[7];          // +0x08..0x38
    void *lastLogError;           // +0x40  0x6c8d4
    double  cacheStamp;           // +0x48  0x6c59c / 0x6c678
    BOOL    cachedEnabled;        // +0x50  0x6c60c / 0x6c674
    void *onceToken;              // +0x58  0x6d61c / 0x6d628
} PDMCPLoggerState;

static void *gPDMCPStateObject;    // 0x11c058（单例实例，NSObject）
static void *gPDMCPLogQueueObject; // 0x11c068（dispatch_queue_t，独立全局）

static id PDMCPLoggerStateObject(void);        // 0x6c6a4
static dispatch_queue_t PDMCPLogQueue(void);   // 0x6cc28
static void PDMCPLogSetError(NSString *message);   // 0x6d0e8
static void PDMCPLogFail(NSString *name, int err); // 0x6d15c

@implementation PDNative_MCPLogger

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger isDebugLoggingEnabled]  imp=0x6c568 insns=95
//   2 秒缓存：CFPreferences 读 com.witchan.ios-mcp.preferences/debugLoggingEnabled，
//   支持 CFBoolean 与 CFNumber 两种类型。
// ---------------------------------------------------------------------------
+ (BOOL)isDebugLoggingEnabled {
    double now = CFAbsoluteTimeGetCurrent();                           // [0x6c580]
    id state = PDMCPLoggerStateObject();                               // [0x6c588] bl 0x6c6a4
    objc_sync_enter(state);                                            // [0x6c594]
    double cachedAt = ((PDMCPLoggerState *)state)->cacheStamp;         // [0x6c59c] +0x48
    if (cachedAt != 0.0 && (now - cachedAt) < 2.0) {                   // [0x6c5a0]/[0x6c5b4] fccmp
        BOOL cached = ((PDMCPLoggerState *)state)->cachedEnabled;      // [0x6c60c] +0x50
        objc_sync_exit(state);                                         // [0x6c5c0]
        return cached;                                                 // [0x6c614] cset
    }
    objc_sync_exit(state);                                             // [0x6c5c0]
    // [0x6c5cc] "debugLoggingEnabled" / [0x6c5d4] "com.witchan.ios-mcp.preferences"
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        CFSTR("debugLoggingEnabled"), CFSTR("com.witchan.ios-mcp.preferences"));   // [0x6c5d8]
    BOOL enabled = NO;
    if (!v) {                                                          // [0x6c5dc] cbz
        enabled = NO;                                                  // [0x6c61c]
    } else if (CFGetTypeID(v) == CFBooleanGetTypeID()) {               // [0x6c5e4]/[0x6c5f0]
        enabled = CFBooleanGetValue((CFBooleanRef)v) != 0;             // [0x6c5fc]
    } else if (CFGetTypeID(v) == CFNumberGetTypeID()) {                // [0x6c624]/[0x6c62c]
        int intValue = 0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType /*9*/, &intValue);   // [0x6c640] w1=9
        enabled = intValue != 0;                                       // [0x6c648]
    }
    if (v) { CFRelease(v); }                                           // [0x6c65c]
    id state2 = PDMCPLoggerStateObject();                              // [0x6c660]
    objc_sync_enter(state2);                                           // [0x6c66c]
    ((PDMCPLoggerState *)state2)->cachedEnabled = enabled;             // [0x6c674] +0x50
    ((PDMCPLoggerState *)state2)->cacheStamp = now;                    // [0x6c678] +0x48
    objc_sync_exit(state2);                                            // [0x6c680]
    return enabled;                                                    // [0x6c688]
}

// +[PDNative_MCPLogger logDirectoryPath]  imp=0x6c6e4 insns=3
+ (NSString *)logDirectoryPath { return kPDMCPLogDirectory; }           // [0x6c6e8]

// +[PDNative_MCPLogger logFilePath]  imp=0x6c6f0 insns=16
+ (NSString *)logFilePath {
    return [self.logDirectoryPath stringByAppendingPathComponent:kPDMCPLogFile];   // [0x6c710]
}

// +[PDNative_MCPLogger previousLogFilePath]  imp=0x6c730 insns=16
+ (NSString *)previousLogFilePath {
    return [self.logDirectoryPath stringByAppendingPathComponent:kPDMCPPrevLogFile]; // [0x6c750]
}

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger archivedLogFilePathAtIndex:]  imp=0x6c770 insns=35
//   index == 0 → 当前文件；否则 ios-mcp.<index>.log
// ---------------------------------------------------------------------------
+ (NSString *)archivedLogFilePathAtIndex:(NSUInteger)index {
    if (index == 0) {                                                  // [0x6c784] cbz x2
        return self.logFilePath;                                       // [0x6c7d8]
    }
    NSString *name = [NSString stringWithFormat:kPDMCPArchivedFmt, (unsigned long)index]; // [0x6c7ac]
    return [self.logDirectoryPath stringByAppendingPathComponent:name]; // [0x6c7c0]
}

// +[PDNative_MCPLogger allLogFilePaths]  imp=0x6c7fc insns=30
+ (NSArray<NSString *> *)allLogFilePaths {
    // [0x6c814] NSMutableArray 类槽（0x119000+0xde8）
    NSMutableArray *paths = [NSMutableArray arrayWithObject:self.logFilePath];  // [0x6c82c]
    [paths addObject:[self archivedLogFilePathAtIndex:1]];              // [0x6c844]/[0x6c858]
    return paths;                                                      // [0x6c860]
}

// +[PDNative_MCPLogger lockFilePath]  imp=0x6c874 insns=16
+ (NSString *)lockFilePath {
    return [self.logDirectoryPath stringByAppendingPathComponent:kPDMCPLockFile];   // [0x6c894]
}

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger lastLogError]  imp=0x6c8b4 insns=23
// ---------------------------------------------------------------------------
+ (NSString *)lastLogError {
    id state = PDMCPLoggerStateObject();                               // [0x6c8c0]
    objc_sync_enter(state);                                            // [0x6c8cc]
    // [0x6c8d4] ldr x0,[state+0x40] → [0x6c8d8] copy
    NSString *message = [*(NSString **)((char *)state + 0x40) copy];
    objc_sync_exit(state);                                             // [0x6c8e4]
    return message;                                                    // [0x6c8ec]
}

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger log:]  imp=0x6c910 insns=36
// ---------------------------------------------------------------------------
+ (void)log:(NSString *)format, ... {
    if (!format.length) {                                              // [0x6c930]/[0x6c934]
        return;
    }
    if (!self.isDebugLoggingEnabled) {                                 // [0x6c93c]/[0x6c940]
        return;
    }
    va_list args;
    va_start(args, format);                                            // [0x6c944] add x8,x29,#0x10
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];  // [0x6c960]
    va_end(args);
    NSLog(@"[witchan][ios-mcp] %@", line);                             // [0x6c974]
    [self logMessage:line];                                            // [0x6c980]
}

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger logMessage:]  imp=0x6c9a0 insns=528
//   清洗 → 截断 → 时间戳 → 异步落盘（块体 0x6cc94）。
// ---------------------------------------------------------------------------
+ (void)logMessage:(NSString *)message {
    if (!message.length) {                                             // [0x6c9d8]/[0x6c9dc]
        return;
    }
    if (!self.isDebugLoggingEnabled) {                                 // [0x6c9e4]/[0x6c9e8]
        return;
    }
    NSString *text;
    if ([message isKindOfClass:[NSString class]] && message.length) {   // [0x6ca08]/[0x6ca18]
        // [0x6ca20] 替换 CR；[0x6ca44] 替换 LF → 空格（0x6ca28 目标串 " "）
        text = [message stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if (text.length > kPDMCPMaxMessage) {                          // [0x6ca64] cmp #1<<12
            // [0x6ca84] @"...<truncated>"
            text = [[text substringToIndex:kPDMCPMaxMessage]
                        stringByAppendingString:@"...<truncated>"];    // [0x6ca74]/[0x6ca88]
        }
    } else {
        text = message.description ?: @"";                             // [0x6caa8] 空串常量
    }
    // 时间戳：gettimeofday → localtime_r → strftime("%Y-%m-%d %H:%M:%S") + strftime("%z")
    struct timeval tv;
    gettimeofday(&tv, NULL);                                           // [0x6cabc]
    struct tm tmBuf;
    localtime_r(&tv.tv_sec, &tmBuf);                                   // [0x6cac8]
    char date[64] = {0};
    strftime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", &tmBuf);         // [0x6cae4] CF 0x4a2
    char zone[16] = {0};
    strftime(zone, sizeof(zone), "%z", &tmBuf);                        // [0x6cb00] CF 0x4b4
    // [0x6cb30] @"%s.%03d%s"
    NSString *stamp = [NSString stringWithFormat:@"%s.%03d%s",
                          date, (int)(tv.tv_usec / 1000), zone];
    // [0x6cb50] @"%@ pid=%d %@\n"
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@\n",
                         stamp, (int)getpid(), text];
    NSData *payload = [line dataUsingEncoding:NSUTF8StringEncoding];    // [0x6cb70] w3? → 编码 4
    if (!payload.length) {                                             // [0x6cb7c]/[0x6cb80]
        return;
    }
    dispatch_async(PDMCPLogQueue(), ^{                                 // [0x6cbcc]，块体 0x6cc94
        if (!self.isDebugLoggingEnabled) {                             // [0x6cca0]/[0x6cca4]
            return;
        }
        NSFileManager *fm = [NSFileManager defaultManager];            // [0x6ccb0]
        NSError *dirError = nil;
        // 已定案 0x6cce0/0x6cd00/0x6cd1c: attributes = @{ NSFilePosixPermissions : @0755 }
        //   key = [0xf0488] bind _NSFilePosixPermissions；value = __NSConstantIntegerNumber
        //   @0x108d30，+0x10 载荷 0x1ed = 493 = 0755；dictionaryWithObjects:forKeys:count:（1 对）
        //   之后 attributes 走 x4 传进 createDirectoryAtPath:…，不是 nil。
        [fm createDirectoryAtPath:self.logDirectoryPath
      withIntermediateDirectories:YES
                       attributes:@{ NSFilePosixPermissions : @0755 }
                            error:&dirError];                      // [0x6cd1c]
        if (dirError) {                                                // [0x6cd34] tbz
            // [0x6cdf0] @"createDirectory failed: %@"
            PDMCPLogSetError([NSString stringWithFormat:@"createDirectory failed: %@",
                                 dirError.localizedDescription ?: @"unknown"]);
            return;                                                    // [0x6d07c]
        }
        int lockFD = open(self.lockFilePath.fileSystemRepresentation, O_RDWR | O_CREAT, 0644);
        if (lockFD < 0) {                                              // [0x6cd80] tbnz #0x1f
            PDMCPLogFail(@"open_lock", errno);                          // [0x6ce18]
            return;                                                    // [0x6d078]
        }
        while (flock(lockFD, LOCK_EX) != 0) {                           // [0x6cd90]
            if (errno != EINTR) {                                       // [0x6cda0] cmp #4
                PDMCPLogFail(@"flock", errno);                          // [0x6cdb4]
                break;                                                  // [0x6d070]
            }
        }
        struct stat st;
        if (stat(self.logFilePath.fileSystemRepresentation, &st) == 0) { // [0x6ce50]
            if ((off_t)st.st_size > kPDMCPLogRotateBytes) {              // [0x6ce98] cmp #2<<20
                NSString *archived = [self archivedLogFilePathAtIndex:0]; // [0x6ceac]
                if (unlink(archived.fileSystemRepresentation) != 0 && errno != ENOENT) {
                    PDMCPLogFail(@"unlink_previous", errno);            // [0x6d0d4]
                }
                // [0x6cf00] rename(previous ← current)；ENOENT 视为正常
                if (rename(self.logFilePath.fileSystemRepresentation,
                           self.previousLogFilePath.fileSystemRepresentation) != 0 &&
                    errno != ENOENT) {
                    PDMCPLogFail(@"rotate", errno);                     // [0x6cf3c]
                }
            }
        } else if (errno != ENOENT) {                                   // [0x6ce60] cmp #2
            PDMCPLogFail(@"stat", errno);                               // [0x6ce74]
        }
        int fd = open(self.logFilePath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) {                                                   // [0x6cf70] tbnz
            PDMCPLogFail(@"open_log", errno);                           // [0x6d034]
            flock(lockFD, LOCK_UN);                                     // [0x6d06c]
            close(lockFD);                                              // [0x6d074]
            return;
        }
        const uint8_t *bytes = payload.bytes;                           // [0x6cf90]
        ssize_t remaining = (ssize_t)payload.length;
        while (remaining > 0) {                                         // [0x6cfb0]
            ssize_t written = write(fd, bytes, remaining);              // [0x6cfbc]
            if (written < 0) {
                if (errno == EINTR) { continue; }                       // [0x6cfcc] cmp #4
                PDMCPLogFail(@"write", errno);                          // [0x6d04c]
                break;
            }
            if (written == 0) {                                         // [0x6cfc4] cbz
                PDMCPLogFail(@"write", errno);                          // [0x6d040]
                break;
            }
            bytes += written;
            remaining -= written;
        }
        close(fd);                                                      // [0x6d060]
        flock(lockFD, LOCK_UN);                                         // [0x6d06c]
        close(lockFD);                                                  // [0x6d074]
    });
}

// ---------------------------------------------------------------------------
// +[PDNative_MCPLogger clearLogsWithError:]  imp=0x6d1e0 insns=289
//   在日志串行队列上同步执行：加锁 → 逐个删除 → 回填 lastLogError。
// ---------------------------------------------------------------------------
+ (BOOL)clearLogsWithError:(NSError **)error {
    // [0x6d1f8] x19 = error；[0x6d200] 状态单例 output 槽（x29-0x50）
    __block BOOL ok = NO;
    __block NSError *blockError = nil;                                 // 0x6d300 起的 __block 结构
    dispatch_sync(PDMCPLogQueue(), ^{                                   // [0x6d28c]，块体 0x6d318
        NSFileManager *fm = [NSFileManager defaultManager];             // [0x6d354]
        NSError *dirError = nil;
        [fm createDirectoryAtPath:self.logDirectoryPath
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&dirError];                       // [0x6d3bc]
        NSString *lockPath = self.lockFilePath;                         // [0x6d3c8]
        int lockFD = open(lockPath.fileSystemRepresentation, O_RDWR | O_CREAT, 0644); // [0x6d3e8]
        if (lockFD < 0) {                                               // [0x6d3f4]
            blockError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                             code:errno
                                         userInfo:nil];                 // [0x6d44c]
            ok = NO;                                                    // [0x6d420] strb wzr
        } else {
            while (flock(lockFD, LOCK_EX) != 0) {                       // [0x6d400]
                if (errno != EINTR) {
                    blockError = [NSError errorWithDomain:NSPOSIXErrorDomain
                                                     code:errno
                                                 userInfo:nil];         // [0x6d4a8]
                    ok = NO;
                    break;
                }
            }
            if (!blockError) {
                for (NSString *path in self.allLogFilePaths) {           // [0x6d4cc] countByEnumerating…
                    if ([fm fileExistsAtPath:path]) {                    // [0x6d534]
                        NSError *removeError = nil;
                        BOOL removed = [fm removeItemAtPath:path error:&removeError]; // [0x6d54c]
                        if (!removed) {                                  // [0x6d55c] cbz w25
                            blockError = removeError;                    // [0x6d5a8]
                            break;
                        }
                    }
                }
                ok = (blockError == nil);
            }
            flock(lockFD, LOCK_UN);                                      // [0x6d5bc]
            close(lockFD);                                               // [0x6d5c4]
        }
    });
    if (error && !ok) {                                                  // [0x6d29c]/[0x6d2a0]
        *error = blockError;                                             // [0x6d2b0]
    }
    return ok;                                                           // [0x6d2bc] cset ne
}

@end

#pragma mark - 区间内静态函数

// 0x6c6a4..0x6c6e4（35 insns）：状态单例 accessor。
//   0x6c6b0 ldr x8,[0x11c060] → once token；cmn x8,#1 → 未初始化则 dispatch_once(0xf2078)
//   0x6c6c0 ldr x0,[0x11c058] → retainAutoreleaseReturnValue
static id PDMCPLoggerStateObject(void) {
    static dispatch_once_t once;                                        // 0x11c060
    dispatch_once(&once, ^{                                            // [0x6c6dc]
        // 已定案 0x6d61c/0x6d620: ldr x0,[0x11a0c8](_OBJC_CLASS_$_NSObject) + objc_opt_new
        gPDMCPStateObject = (__bridge_retained void *)[NSObject new];    // → 全局 0x11c058
    });
    return (__bridge id)gPDMCPStateObject;
}

// 0x6cc28..0x6cc68（20 insns）：日志串行队列 accessor（once token 0x11c070，块 0xf2098）
static dispatch_queue_t PDMCPLogQueue(void) {
    static dispatch_once_t once;                                        // 0x11c070（0x6cc34 ldr x8,[0x11c070]）
    dispatch_once(&once, ^{                                            // [0x6cc60]
        // 已定案 0x6d644..0x6d658: label = "com.witchan.ios-mcp.debug-log"，attr = 0，
        //   结果写独立全局 0x11c068（0x6d658 str x0,[x8,#0x68]）。
        gPDMCPLogQueueObject = (__bridge void *)dispatch_queue_create(kPDMCPLogQueueLabel.UTF8String, NULL);
    });
    return (__bridge dispatch_queue_t)gPDMCPLogQueueObject;
}

// 0x6d0e8..0x6d15c（62 insns）：写 lastLogError（@synchronized + copy）。
static void PDMCPLogSetError(NSString *message) {
    id state = PDMCPLoggerStateObject();                               // [0x6d100]
    objc_sync_enter(state);                                            // [0x6d10c]
    *(NSString **)((char *)state + 0x40) = [message copy];             // [0x6d114]
    objc_sync_exit(state);                                             // [0x6d12c]
}

// 0x6d15c..0x6d1e0（90 insns）：组装 "%@ failed errno=%d error=%s" 并落 lastLogError。
static void PDMCPLogFail(NSString *name, int err) {
    // [0x6d1a8] @"%@ failed errno=%d error=%s"；[0x6d198] strerror
    PDMCPLogSetError([NSString stringWithFormat:@"%@ failed errno=%d error=%s",
                         name, err, strerror(err)]);
}

#pragma mark - §SELFCHECK
// 括号走查：11 个方法全闭合；logMessage: 的异步块与 clearLogsWithError: 的同步块各自闭合；
//   所有 while 循环都有出口（EINTR 重试 / break）。
// 方法计数：method-table 11 条 → 本文件 11 个方法。
// 已定案（本轮，见 out/notes/assume-b.md）：
//   · 状态单例的类是 NSObject（0x6d61c 类槽 0x11a0c8 + 0x6d620 objc_opt_new），实例在 0x11c058。
//   · 日志队列是独立全局 0x11c068（0x6d658），不是状态对象 +0x68 的字段。
//   · createDirectory 的 attributes 是 @{NSFilePosixPermissions: @0755}（0x6ccd8 键 / 0x108d30 值 / 0x6ccf8 组字典）。
//   · open 的 flag 组合 —— 已定案：锁文件 0x6cd78 `mov w1,#0x202`（O_RDWR|O_CREAT），
//     日志文件 0x6cf68 `mov w1,#0x209`（O_WRONLY|O_CREAT|O_APPEND，Darwin 的 O_APPEND=0x8）；
//     两处 mode 都是 0x1a4 = 0644。源码写法与二进制一致。
// 已定案 0x6d44c / 0x6d4a8（原判二选一，取 A）：clearLogs 的错误域 = NSPOSIXErrorDomain（直接 errno）。
//   · 0x6d42c/0x6d430/0x6d434 `adrp 0xf0000` + `ldr x8,[x8,#0x4c8]` + `ldr x24,[x8]`
//     → 槽 0xf04c8 绑定符号 `_NSPOSIXErrorDomain`（非 _NSCocoaErrorDomain）。
//   · 0x6d438 `bl ___error` + 0x6d43c `ldrsw x3,[x0]` → code 就是 errno。
//   · 0x6d440 `mov x0,x23`（x23 = 0x119e20 绑 _OBJC_CLASS_$_NSError）+ 0x6d444 `mov x2,x24`。
//   · 第二处 0x6d48c/0x6d490 同一域，0x6d494 `___error` 同一 code 来源 —— 两处同构。
//   全函数内没有引用 _NSCocoaErrorDomain；B 被排除，无需真机。
// NOT RUN：未编译/未运行。
