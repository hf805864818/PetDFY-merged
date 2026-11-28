//
//  PDNative_ClipboardManager.m
//  PetDFY
//
//  剪贴板读写：优先走 pasteboardd 的磁盘缓存（Manifest.plist + 每项一个文件），
//  缓存不可用时退回主剪贴板直读；iOS 16 起读写都放到私有队列并加 5 秒超时。
//
//  二进制证据
//    image base  : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表      : 3 条（1 条 `+` / 2 条 `-`）
//                    +sharedInstance     0x7190c  26 insns
//                    -readClipboard      0x71974  1107 insns
//                    -writeText:         0x72ac0  876 insns
//    instanceSize: 8（0x08）—— 无实例 ivar，单例存静态槽（0x6b… 同款 dispatch_once 模式）
//
//  区间内静态实体（全部由调用点定位，符号表无名）
//    0x72d24  PDClipboardNeedsOffMainQueue()   processInfo.operatingSystemVersion.major > 15
//    0x72f3c  PDClipboardParseManifest(NSData*)  plist 解析
//    0x72fe4  PDDataLooksLikeImage(NSData*)      长度 >= 8 + 8 字节魔数比较
//    0x73048  PDStringIsControlOnly(NSString*)   controlCharacterSet + characterIsMember
//    0x73140  PDStringLooksLikeURL(NSString*)    http:// https:// file:// 前缀
//    0x7344c  PDManifestEntryComparator           modifiedAt → size → path
//    0x735e0  直读剪贴板块体（invoke）
//    0x72e7c / 0x72e5c  写队列块体 / 队列 label
//    0x73584  读队列 label "com.witchan.ios-mcp.clipboard.read"
//    0x72e5c  写队列 label "com.witchan.ios-mcp.clipboard.write"
//
//  关键常量（Observed）
//    缓存根目录候选（__NSConstantArray @0x107c78，元素 @0x106430）：
//      /private/var/mobile/Library/Caches/com.apple.Pasteboard
//      /var/mobile/Library/Caches/com.apple.Pasteboard
//      /var/jb/private/var/mobile/Library/Caches/com.apple.Pasteboard
//      /var/jb/var/mobile/Library/Caches/com.apple.Pasteboard
//    剪贴板名 0x719a78 "com.apple.UIKit.pboard.general"（SHA-1 → 十六进制作子目录名）
//    结果键 0x724c0 "text" / 0x72500 "hasImage" / 0x72534 "hasURL" / 0x72a1c "cacheMiss" / 0x725a8 "url"
//
//  符号修正（跨单元一致性，2026-11-28）
//    +sharedInstance 是**类方法**（sign = +，0x7190c）。已改为 `+`；
//    方法体内 `[[self class] new]` 在类方法里等价于 `[PDNative_ClipboardManager new]`，
//    不涉及 ivar（本类 instanceSize=8，无实例 ivar）。
//
//  标记：[0xADDR] = 指令地址；Assumed = 语义推断；NOT RUN = 未运行
//        直调 0xADDR = 已落到具名入口（本文件 CALL 0 处）
//

#import "PDNative_ClipboardManager.h"
#import "PDNative_MCPLogger.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *const kPDClipboardPasteboardName = @"com.apple.UIKit.pboard.general"; // [0x719a78]
static NSString *const kPDClipboardReadQueueLabel = @"com.witchan.ios-mcp.clipboard.read";   // [0x73584]
static NSString *const kPDClipboardWriteQueueLabel = @"com.witchan.ios-mcp.clipboard.write"; // [0x72e5c]
static NSString *const kPDClipboardManifestName = @"Manifest.plist";                        // [0x71b7c]
static const NSTimeInterval kPDClipboardTimeout = 5.0;   // 0x72850 / 0x72b7c：5 * NSEC_PER_SEC

static BOOL PDClipboardNeedsOffMainQueue(void);          // 0x72d24
static NSString *PDClipboardCacheDirectory(void);        // 0x719c4..0x71b30 段落
static id PDClipboardParseManifest(NSData *data);        // 0x72f3c
static BOOL PDDataLooksLikeImage(NSData *data);          // 0x72fe4
static BOOL PDStringIsControlOnly(NSString *text);       // 0x73048
static BOOL PDStringLooksLikeURL(NSString *text);        // 0x73140

@implementation PDNative_ClipboardManager

// ---------------------------------------------------------------------------
// +[PDNative_ClipboardManager sharedInstance]  imp=0x7190c insns=26
//   （方法表 sign 列为 +：类方法单例；实现是 dispatch_once）
// ---------------------------------------------------------------------------
+ (instancetype)sharedInstance {
    static id shared = nil;                                 // 静态槽 0x200
    static dispatch_once_t once;                            // 静态槽 0x208
    // [0x71918] ldr x8,[x8,#0x208]; cmn x8,#1 → 未初始化
    dispatch_once(&once, ^{                                 // [0x71944]，块 0xf2298
        shared = [[self class] new];                        // [0x7195c] objc_alloc_init(类槽 0xa0)
    });
    return shared;                                          // [0x71930]
}

// ---------------------------------------------------------------------------
// -[PDNative_ClipboardManager readClipboard]  imp=0x71974 insns=1107
//
//   骨架（Observed）：
//     1  在 4 个候选根目录里挑第一个“存在且是目录”的
//     2  子目录名 = SHA1("com.apple.UIKit.pboard.general") 的小写十六进制
//     3  读 <cacheDir>/Manifest.plist → 清单数组
//     4  contentsOfDirectoryAtPath: 枚举，跳过 Manifest.plist，目录项取 {path,size,modifiedAt}
//     5  sortUsingComparator:（modifiedAt → size → path）
//     6  逐项读文件：像图片的只标记 hasImage，否则 UTF-8 解码取文本
//     7  组装 {text, hasImage, hasURL}（可加 url），并打点日志
//     8  缓存没有可读内容时退回直读主剪贴板（iOS 16+ 走私有队列 + 5 秒超时）
// ---------------------------------------------------------------------------
- (NSDictionary *)readClipboard {
    NSFileManager *fm = [NSFileManager defaultManager];      // [0x719ac]
    NSString *text = nil;
    NSString *urlString = nil;
    BOOL hasImage = NO;
    BOOL hasURL = NO;
    BOOL cacheMiss = NO;

    NSString *cacheDir = PDClipboardCacheDirectory();        // 见下方静态函数（0x719c4 段）
    BOOL cacheUsable = (cacheDir != nil);
    if (cacheUsable) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:cacheDir isDirectory:&isDir] || !isDir) {
            cacheUsable = NO;                                // [0x71b64]
        }
    }
    if (!cacheUsable) {
        // [0x71bd8] @"[Clipboard] Pasteboard cache directory missing"
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(@"[witchan][ios-mcp]%@", @"[Clipboard] Pasteboard cache directory missing");
        }
    } else {
        NSData *manifestData =
            [NSData dataWithContentsOfFile:
                [cacheDir stringByAppendingPathComponent:kPDClipboardManifestName]];  // [0x71b9c]
        NSArray *manifest = manifestData ? PDClipboardParseManifest(manifestData) : nil; // [0x71bb0]
        if (manifest) {
            NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];            // [0x71db8]
            // [0x71da4] contentsOfDirectoryAtPath:error:
            NSArray *names = [fm contentsOfDirectoryAtPath:cacheDir error:NULL];
            for (NSString *name in names) {
                if ([name isEqualToString:kPDClipboardManifestName]) {                     // [0x71e4c]
                    continue;
                }
                NSString *path = [cacheDir stringByAppendingPathComponent:name];           // [0x71e5c]
                BOOL itemIsDir = NO;
                if (![fm fileExistsAtPath:path isDirectory:&itemIsDir] || itemIsDir) {
                    continue;                                                              // [0x71e8c]
                }
                NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];          // [0x71e9c]
                id size = attrs[NSFileSize];                                               // 0x71edc
                id modified = attrs[NSFileModificationDate] ?: [NSDate distantPast];       // [0x71efc]
                // [0x71f50] dictionaryWithObjects:forKeys:count:3
                [entries addObject:@{ @"path": path,
                                      @"size": size ?: @0,
                                      @"modifiedAt": modified }];
            }
            // [0x71fb8] 排序（比较器 0x7344c：modifiedAt → size → path）
            [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSComparisonResult r = [b[@"modifiedAt"] compare:a[@"modifiedAt"]];         // [0x7347c]
                if (r != NSOrderedSame) { return r; }
                unsigned long long sa = [a[@"size"] unsignedLongLongValue];                 // [0x734a4]
                unsigned long long sb = [b[@"size"] unsignedLongLongValue];                 // [0x734c4]
                if (sa != sb) { return sa < sb ? NSOrderedDescending : NSOrderedAscending; }
                return [a[@"path"] compare:b[@"path"]];                                     // [0x73524]
            }];
            NSMutableArray<NSString *> *paths =
                [NSMutableArray arrayWithCapacity:entries.count];                           // [0x71fd4]
            for (NSDictionary *entry in entries) {
                [paths addObject:entry[@"path"]];                                           // [0x72048]
            }
            // [0x720c8] 逐项取内容
            for (NSString *path in paths) {
                NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];          // [0x7211c]
                unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];        // [0x72138]
                // 已定案 0x720e8/0x72144/0x72148: x26 = -0x100001，add 后 cmn x8,#0x100000 / b.lo
                //   → 判据是 size > 0x100000（1 MiB）就跳过，不是 4 MiB。
                if (size > 1024ull * 1024) {
                    continue;
                }
                NSData *data = [NSData dataWithContentsOfFile:path];                        // [0x7215c]
                if (!data) { continue; }
                if (PDDataLooksLikeImage(data)) {                                           // [0x72170] bl 0x72fe4
                    hasImage = YES;
                    continue;
                }
                NSString *candidate = [[NSString alloc] initWithData:data
                                                            encoding:NSUTF8StringEncoding]; // [0x7218c]
                if (!candidate.length) { continue; }
                if (PDStringIsControlOnly(candidate)) { continue; }                         // [0x721a0]
                if (PDStringLooksLikeURL(candidate)) {                                      // [0x721f8]
                    hasURL = YES;
                    urlString = candidate;
                }
                // 已定案 0x721f0: 无前置判空，mov x26,x0（retain 候选）每轮覆盖；循环结束后
                //   0x724f4 str x20,[sp,#0x168] 把 x26 当作 "text" 写进结果 → 取最后一条，不是第一条。
                text = candidate;
            }
        }
    }

    // ---- 组装结果（0x724c0..0x72574） ----
    // [0x72570] dictionaryWithObjects:forKeys:count:4（text/hasImage/hasURL[/url]）
    NSMutableDictionary *result = [@{ @"text": text ?: [NSNull null],
                                      @"hasImage": @(hasImage),
                                      @"hasURL": @(hasURL) } mutableCopy];              // [0x7257c]
    if (urlString.length) {
        result[@"url"] = urlString;                                                     // [0x725b4]
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {                     // [0x725c0]
        // [0x72618] @"[Clipboard] Read pasteboard cache textChars=%lu hasImage=%@ hasURL=%@ files=%lu"
        NSLog(@"[witchan][ios-mcp]%@",
              [NSString stringWithFormat:
                  @"[Clipboard] Read pasteboard cache textChars=%lu hasImage=%@ hasURL=%@ files=%lu",
                  (unsigned long)text.length, hasImage ? @"yes" : @"no",
                  hasURL ? @"yes" : @"no", (unsigned long)result.count]);
    }

    // ---- 缓存没有可读内容 → 直读（0x7268c..0x726fc） ----
    BOOL cacheHasContent = (text.length > 0);
    if (!cacheHasContent) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {                  // [0x72764]
            // [0x72774] @"[Clipboard] Pasteboard cache has no readable content; falling back to direct clipboard read"
            NSLog(@"[witchan][ios-mcp]%@",
                  @"[Clipboard] Pasteboard cache has no readable content; falling back to direct clipboard read");
        }
        NSDictionary *direct = nil;                                                      // 0x727b8 起
        if (PDClipboardNeedsOffMainQueue()) {                                            // [0x727d0]
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);                     // [0x727dc]
            __block NSDictionary *boxed = nil;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{                            // [0x72848] 块 invoke 0x735a4
                boxed = PDClipboardReadDirect();                                          // 见下
                dispatch_semaphore_signal(sem);                                           // [0x735dc]
            });
            // 5 秒超时（0x72850 movz/movk 组出 5 * NSEC_PER_SEC）
            if (dispatch_semaphore_wait(sem,
                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPDClipboardTimeout * NSEC_PER_SEC))) != 0) {
                if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                    // [0x7288c] @"[Clipboard] Direct clipboard read timed out after 5s; pasteboardd may be busy"
                    NSLog(@"[witchan][ios-mcp]%@",
                          @"[Clipboard] Direct clipboard read timed out after 5s; pasteboardd may be busy");
                }
            }
            direct = boxed;
        } else {
            direct = PDClipboardReadDirect();                                             // [0x72910] 主线程直接调
        }
        if (direct) {
            cacheMiss = YES;
            // [0x72a1c] cacheMiss 标记 + 合并直读结果
            result[@"text"] = direct[@"text"] ?: [NSNull null];
            result[@"hasImage"] = direct[@"hasImage"] ?: @NO;
            result[@"hasURL"] = direct[@"hasURL"] ?: @NO;
            result[@"cacheMiss"] = @YES;
            if (direct[@"url"]) { result[@"url"] = direct[@"url"]; }
        }
    }
    return result;                                                                        // [0x729b4]
}

// ---------------------------------------------------------------------------
// -[PDNative_ClipboardManager writeText:]  imp=0x72ac0 insns=876
//   iOS 16+：私有队列写 + 5 秒超时；否则主线程直接 setString:。
// ---------------------------------------------------------------------------
- (BOOL)writeText:(NSString *)text {
    if (!text) {                                                                          // [0x72adc]
        return NO;                                                                        // [0x72bf0]
    }
    if (PDClipboardNeedsOffMainQueue()) {                                                  // [0x72ae0]
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);                           // [0x72b04]
        __block BOOL wrote = NO;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{                                 // [0x72b74] 块 invoke 0x72e7c
            [[UIPasteboard generalPasteboard] setString:text];                             // [0x72eb0]
            wrote = YES;
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {                // [0x72ed0]
                // [0x72ef0] @"[Clipboard] Wrote clipboard textChars=%lu"
                NSLog(@"[witchan][ios-mcp]%@",
                      [NSString stringWithFormat:@"[Clipboard] Wrote clipboard textChars=%lu",
                          (unsigned long)text.length]);
            }
            dispatch_semaphore_signal(sem);                                                // [0x72f38]
        });
        if (dispatch_semaphore_wait(sem,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPDClipboardTimeout * NSEC_PER_SEC))) != 0) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                // [0x72bb8] @"[Clipboard] Write clipboard timed out after 5s; pasteboardd may be busy"
                NSLog(@"[witchan][ios-mcp]%@",
                      @"[Clipboard] Write clipboard timed out after 5s; pasteboardd may be busy");
            }
            return NO;
        }
        return wrote;
    }
    // [0x72ea0] 直接写
    [[UIPasteboard generalPasteboard] setString:text];
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {                        // [0x72dd8]
        // [0x72df8] @"[Clipboard] Wrote clipboard directly textChars=%lu"
        NSLog(@"[witchan][ios-mcp]%@",
              [NSString stringWithFormat:@"[Clipboard] Wrote clipboard directly textChars=%lu",
                  (unsigned long)text.length]);
    }
    return YES;
}

@end

#pragma mark - 静态函数

// 0x72d24..0x72d74（21 insns）：major > 15（即 iOS 16 及以上）
static BOOL PDClipboardNeedsOffMainQueue(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];                                     // [0x72d3c]
    if (!info) { return NO; }                                                              // [0x72d48]
    NSOperatingSystemVersion v = info.operatingSystemVersion;                              // [0x72d54]
    return v.majorVersion > 15;                                                            // [0x72d6c] cmp #0xf
}

// 0x719c4..0x71b30 段（缓存目录推导）：
//   候选数组 0x107c78（4 条，见文件头），取第一个 exists && isDirectory 的作为根；
//   子目录名 = SHA1("com.apple.UIKit.pboard.general") 的小写十六进制（0x71af4 appendFormat "%02x" × 20）。
static NSString *PDClipboardCacheDirectory(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        @"/private/var/mobile/Library/Caches/com.apple.Pasteboard",     // 0xfe9c8
        @"/var/mobile/Library/Caches/com.apple.Pasteboard",             // 0xfe9e8
        @"/var/jb/private/var/mobile/Library/Caches/com.apple.Pasteboard", // 0xfea08
        @"/var/jb/var/mobile/Library/Caches/com.apple.Pasteboard",      // 0xfea28
    ];
    NSString *root = nil;
    for (NSString *candidate in roots) {                                                   // [0x719d8]
        BOOL isDir = NO;
        BOOL exists = [fm fileExistsAtPath:candidate isDirectory:&isDir];                   // [0x71a28]
        if (exists && isDir) {                                                             // [0x71a38]
            root = candidate;
            break;
        }
    }
    if (!root) { return nil; }
    // [0x71a80] dataUsingEncoding: → [0x71ab8] CC_SHA1 → 20 字节 → "%02x" 拼接
    NSData *seed = [kPDClipboardPasteboardName dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH] = {0};
    CC_SHA1(seed.bytes, (CC_LONG)seed.length, digest);                                      // [0x71ab8]
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {                                      // [0x71afc] cmp #0x14
        [hex appendFormat:@"%02x", digest[i]];                                             // [0x71af4]
    }
    return [root stringByAppendingPathComponent:hex];                                      // [0x71b24]
}

// 0x72f3c..0x72fe4（42 insns）：Manifest.plist → plist 对象
static id PDClipboardParseManifest(NSData *data) {
    if (!data.length) { return nil; }                                                      // [0x72f5c]
    return [NSPropertyListSerialization propertyListWithData:data
                                                     options:0
                                                      format:NULL
                                                       error:NULL];                        // [0x72f7c]
}

// 0x72fe4..0x73048（25 insns）：长度 >= 8 且前 8 字节 == "bplist00"
//   已定案 0x7301c..0x7302c：mov x9,#0x7062 / movk 0x696c,16 / movk 0x7473,32 / movk 0x3030,48
//   → 0x30307473696c7062，小端即 'b''p''l''i''s''t''0''0'；只有这**一条** 8 字节比较，
//   没有 PNG/JPEG/ftyp 魔数表。函数真实语义是“缓存文件是二进制 plist”（调用点据此置 hasImage）。
static BOOL PDDataLooksLikeImage(NSData *data) {
    if (data.length < 8) { return NO; }                                                    // [0x72ffc] cmp #8
    const uint64_t magic = *(const uint64_t *)data.bytes;                                   // [0x73014]/[0x73018]
    return magic == 0x30307473696C7062ULL;                                                  // [0x7302c] cmp x8,x9
}

// 0x73048..0x73140（61 insns）：全是控制字符（且允许 \r\n）则视为不可读
static BOOL PDStringIsControlOnly(NSString *text) {
    if (!text.length) { return YES; }                                                      // [0x7306c]
    NSCharacterSet *control = [NSCharacterSet controlCharacterSet];                        // [0x73078]
    NSUInteger i = 0;
    BOOL sawPrintable = NO;
    for (i = 0; i < text.length; i++) {                                                     // [0x730dc]
        unichar c = [text characterAtIndex:i];                                              // [0x730a8]
        if (c == '\r' || c == '\n') { continue; }                                           // [0x730ac] ccmp
        if ([control characterIsMember:c]) { continue; }                                    // [0x730c8]
        sawPrintable = YES;
        break;
    }
    return !sawPrintable;                                                                  // [0x730e4]
}

// 0x73140..0x731ac（27 insns）：http:// / https:// / file:// 前缀
static BOOL PDStringLooksLikeURL(NSString *text) {
    NSString *lower = text.lowercaseString;                                                 // [0x7314c]
    if ([lower hasPrefix:@"http://"]) { return YES; }                                       // [0x73160]
    if ([lower hasPrefix:@"https://"]) { return YES; }                                      // [0x73174]
    if ([lower hasPrefix:@"file://"]) { return YES; }                                        // [0x73190]
    return NO;
}

// 0x735e0 段（直读块体）：主剪贴板 → {text, hasImage, hasURL[, url]}
static NSDictionary *PDClipboardReadDirect(void) {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];                                    // [0x73618]
    NSString *text = pb.string;                                                             // [0x73624]
    BOOL hasImage = pb.hasImages;                                                           // [0x73634]
    BOOL hasURL = pb.hasURLs;                                                               // [0x73640]
    NSURL *url = hasURL ? pb.URL : nil;                                                     // [0x73650]
    NSMutableDictionary *result = [@{ @"text": text ?: [NSNull null],
                                      @"hasImage": @(hasImage),
                                      @"hasURL": @(hasURL) } mutableCopy];                  // [0x736f0]
    if (url.absoluteString.length) {                                                        // [0x73728]
        result[@"url"] = url.absoluteString;                                                // [0x73758]
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {                         // [0x73768]
        // [0x737ac] @"[Clipboard] Read clipboard directly textChars=%lu hasImage=%@ hasURL=%@"
        NSLog(@"[witchan][ios-mcp]%@",
              [NSString stringWithFormat:
                  @"[Clipboard] Read clipboard directly textChars=%lu hasImage=%@ hasURL=%@",
                  (unsigned long)text.length, hasImage ? @"yes" : @"no", hasURL ? @"yes" : @"no"]);
    }
    return [result copy];                                                                    // [0x737e4]
}

#pragma mark - §SELFCHECK
// 括号走查：3 个方法 + 6 个静态函数全部闭合；readClipboard 里两层 for、两个排序块、
//   直读超时块各自闭合；writeText 的块与信号量配对。
// 方法计数：method-table 3 条 → 本文件 3 个方法。
// 已定案（本轮，见 out/notes/assume-b.md）：
//   · 单个文件上传上限 = 0x100000（1 MiB），不是 4 MB —— 0x720e8/0x72148。
//   · PDDataLooksLikeImage 只比 "bplist00" —— 0x7301c..0x7302c，无 PNG/JPEG/ftyp 表。
//   · 缓存文本取最后一条可读文件（0x721f0 无判空覆盖写 + 0x724f4 写入 "text"）。
// 已定案 0x71bc4..0x71c0c（原判二选一，取 A）：目录缺失分支是「两条日志，且同在 debug 开关内」。
//   进入条件（0x71b30..0x71b74）：dirPath==nil（0x71b54 `cbz x8,#0x71bbc`）或
//     `fileExistsAtPath:isDirectory:` 返回 exists&&isDir==false（0x71b6c/0x71b70 `csel` + 0x71b74 `tbz w8,#0,#0x71bbc`）。
//   0x71bc4 `bl sel:isDebugLoggingEnabled`；0x71bc8 `cbz w0,#0x71c10` —— 单个门同时跳过两条日志。
//   门内：x2 = CF "[Clipboard] Pasteboard cache directory missing"（0x71bd8）→ `stringWithFormat:`（0x71bdc）
//     → `_NSLog`，格式串 CF "[witchan][ios-mcp]%@"（0x71bf4，调用 0x71bf8）
//     → `[PDNative_MCPLogger logMessage:]`（0x71c04，实参同为该串，0x71c00 `ldr x2,[sp,#0x30]`）。
//   两条日志之间没有分支（0x71bf8→0x71bfc→0x71c04 顺序直落），B（只有一条）被排除，无需真机。
// NOT RUN：未编译/未运行。
