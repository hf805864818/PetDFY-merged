//
//  PDAssetInstaller.m — 素材包导入安装实现
//

#import "PDAssetInstaller.h"
#import "PDJailbreak.h"
#import "PDZipExtract.h"
#import "PDDiag.h"
#import "PDDiagnostics.h"
#import "PDToast.h"

@interface PDAssetInstaller ()
+ (BOOL)mergeCopyDirectory:(NSString *)src to:(NSString *)dst error:(NSError **)error;
+ (NSString *)tokenForArchive:(NSString *)zipPath;
+ (void)writeStatus:(NSString *)status detail:(NSDictionary *)detail;
+ (NSString *)findArchiveRecursively;
@end

static NSString *const kPDAssetPrefsDomain   = @"com.susudear.petdfyprefs";
static NSString *const kPDAssetStatusKey     = @"AssetDownloadStatus";
static NSString *const kPDAssetStatusNote    = @"com.susudear.petdfy/assets-status";
static NSString *const kPDAssetStateFileName = @".asset-state";

@implementation PDAssetInstaller

#pragma mark - 路径

+ (NSArray<NSString *> *)spoolDirectories {
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];

    // 1) 偏好面板投递目录（rootless / RootHide / rootful 全覆盖）
    for (NSString *p in PDImportSpoolDirectories()) {
        if (![dirs containsObject:p]) [dirs addObject:p];
    }

    // 2) 既有 Imported 目录（1.2 源码路径，保留）
    for (NSString *p in PDLegacyImportedRoots()) {
        if (![dirs containsObject:p]) [dirs addObject:p];
    }

    // 3) Downloads / tmp 兜底：部分文件选择器会把副本留在这里
    for (NSString *rel in @[@"/var/mobile/Downloads", @"/var/mobile/tmp", @"/tmp",
                            @"/var/mobile/Documents"]) {
        for (NSString *p in PDJailbreakCandidates(rel)) {
            if (![dirs containsObject:p]) [dirs addObject:p];
        }
    }
    return dirs;
}

+ (NSString *)findArchiveRecursively {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *bases = @[
        @"/var/mobile/Documents",
        @"/var/mobile/Downloads",
        @"/var/mobile/tmp",
        @"/var/mobile/Library/Application Support/PetDFY",
        @"/tmp",
    ];
    NSString *best = nil;
    NSTimeInterval bestT = -1;
    NSInteger budget = 4000;

    for (NSString *base in bases) {
        NSMutableArray *queue = [NSMutableArray arrayWithObject:@[@(0), base]];
        while (queue.count && budget > 0) {
            NSArray *item = queue.firstObject;
            [queue removeObjectAtIndex:0];
            NSInteger depth = [item[0] integerValue];
            NSString *dir = item[1];
            NSArray *kids = [fm contentsOfDirectoryAtPath:dir error:NULL];
            if (!kids) continue;
            for (NSString *k in kids) {
                if (--budget <= 0) break;
                if ([k hasPrefix:@"."]) continue;
                NSString *p = [dir stringByAppendingPathComponent:k];
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:p isDirectory:&isDir]) continue;
                if (isDir) {
                    if (depth < 3) [queue addObject:@[@(depth + 1), p]];
                    continue;
                }
                if (![[k.pathExtension lowercaseString] isEqualToString:@"zip"]) continue;
                NSDictionary *a = [fm attributesOfItemAtPath:p error:NULL];
                if ([a[NSFileSize] unsignedLongLongValue] < 4096) continue;
                NSTimeInterval t = [a[NSFileModificationDate] timeIntervalSince1970];
                if (t > bestT) { bestT = t; best = p; }
            }
        }
    }
    if (best) PDDiagLog(@"recursive find: %@", best);
    return best;
}

+ (BOOL)assetRootIsComplete:(NSString *)root {
    if (![root isKindOfClass:[NSString class]] || root.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *live = [root stringByAppendingPathComponent:@"live/model.json"];
    NSString *orig = [root stringByAppendingPathComponent:@"originals/model.json"];
    // 渲染必需：live/model.json（模型）或 originals/model.json（部件）；
    // 两者至少其一，且 originals 目录必须存在（贴图来源）。
    BOOL hasLive = [fm fileExistsAtPath:live];
    BOOL hasOrig = [fm fileExistsAtPath:orig];
    BOOL hasOrigDir = [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"originals"]] ||
                      [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"tex"]];
    return (hasLive || hasOrig) && hasOrigDir;
}

+ (NSString *)currentAssetRoot {
    NSMutableArray<NSString *> *cands = [NSMutableArray array];
    // build.93：只写素材根（/var/mobile/Library/Xfy），不再双写 Imported/（省一份 120 MB）
    for (NSString *r in PDAssetBundleRoots()) {
        if (![cands containsObject:r]) [cands addObject:r];
    }

    NSString *best = nil;
    NSTimeInterval bestTime = -1;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *r in cands) {
        if (![self assetRootIsComplete:r]) continue;
        NSString *live = [r stringByAppendingPathComponent:@"live/model.json"];
        NSString *orig = [r stringByAppendingPathComponent:@"originals/model.json"];
        NSString *probe = [fm fileExistsAtPath:live] ? live : orig;
        NSDictionary *attrs = [fm attributesOfItemAtPath:probe error:NULL];
        NSTimeInterval t = attrs ? [attrs[NSFileModificationDate] timeIntervalSince1970] : 0;
        if (t > bestTime) { bestTime = t; best = r; }
    }
    return best;
}

#pragma mark - 偏好与通知

+ (void)writeStatus:(NSString *)status detail:(NSDictionary *)detail {
    CFStringRef domain = (__bridge CFStringRef)kPDAssetPrefsDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)kPDAssetStatusKey,
                             (__bridge CFStringRef)(status ?: @"idle"),
                             domain);
    if (detail) {
        // 明细写入独立键，避免污染面板读取的短状态词
        NSString *json = nil;
        NSData *d = [NSJSONSerialization dataWithJSONObject:detail options:0 error:NULL];
        if (d) json = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (json) {
            CFPreferencesSetAppValue((__bridge CFStringRef)@"AssetInstallDetail",
                                     (__bridge CFStringRef)json, domain);
        }
    }
    CFPreferencesAppSynchronize(domain);

    CFNotificationCenterRef c = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(c,
        (__bridge CFStringRef)kPDAssetStatusNote, NULL, NULL, true);
}

#pragma mark - 复制

/// 递归合并复制 src 到 dst（覆盖同名文件，保留 dst 其它内容）
+ (BOOL)mergeCopyDirectory:(NSString *)src to:(NSString *)dst error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) return NO;
    if (![fm fileExistsAtPath:dst]) {
        if (![fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:src error:error];
    if (!items) return NO;

    for (NSString *item in items) {
        NSString *s = [src stringByAppendingPathComponent:item];
        NSString *d = [dst stringByAppendingPathComponent:item];
        BOOL subIsDir = NO;
        if (![fm fileExistsAtPath:s isDirectory:&subIsDir]) continue;

        if (subIsDir) {
            if (![self mergeCopyDirectory:s to:d error:error]) return NO;
        } else {
            [fm removeItemAtPath:d error:NULL];      // 覆盖
            NSError *e = nil;
            if (![fm copyItemAtPath:s toPath:d error:&e]) {
                if (error) *error = e;
                return NO;
            }
        }
    }
    return YES;
}

+ (NSString *)tokenForArchive:(NSString *)zipPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:zipPath error:NULL];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    NSString *name = zipPath.lastPathComponent;
    return [NSString stringWithFormat:@"%@|%llu", name, size];
}

#pragma mark - 安装

+ (BOOL)installNewestArchiveIfNeeded:(NSString **)installedRoot message:(NSString **)message {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *newest = nil;
    NSTimeInterval newestTime = -1;

    for (NSString *dir in [self spoolDirectories]) {
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
        if (!names.count) continue;
        for (NSString *name in names) {
            if (![[name.pathExtension lowercaseString] isEqualToString:@"zip"]) continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
            if (!attrs) continue;
            NSTimeInterval t = [attrs[NSFileModificationDate] timeIntervalSince1970];
            if (t >= newestTime) { newestTime = t; newest = path; }
        }
    }

    // 诊断：投递目录快照（只在变化时落盘，避免每秒刷屏）
    {
        static NSString *lastSig;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *dir in [self spoolDirectories]) {
            NSArray *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
            NSMutableArray *zips = [NSMutableArray array];
            for (NSString *n in names) {
                if ([[n.pathExtension lowercaseString] isEqualToString:@"zip"]) [zips addObject:n];
            }
            BOOL exists = names != nil;
            [parts addObject:[NSString stringWithFormat:@"%@%@{%@}", exists ? @"" : @"!", dir,
                              [zips componentsJoinedByString:@","]]];
        }
        NSString *sig = [parts componentsJoinedByString:@" | "];
        if (![sig isEqualToString:lastSig]) {
            lastSig = [sig copy];
            PDDiagLog(@"spool: %@", sig);
        }
    }

    if (!newest) {
        // 兜底：设置面板可能把 ZIP 放在别处，做一次有界递归扫描
        NSString *found = [self findArchiveRecursively];
        if (found) {
            newest = found;
            newestTime = [[NSDate date] timeIntervalSince1970];
            PDDiagLog(@"spool empty, fallback zip=%@", found);
        }
    }
    if (!newest) {
        if (message) *message = @"no zip in spool";
        return NO;
    }

    // 去重：标记文件放在数据目录，记录 zip 名+大小
    NSString *dataDir = PDDataDirectory();
    NSString *marker = [dataDir stringByAppendingPathComponent:@"Imported/.asset-import-token"];
    NSString *token = [self tokenForArchive:newest];
    NSString *old = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL];
    if ([old isEqualToString:token]) {
        if (message) *message = @"already imported";
        return NO;
    }

    return [self installArchiveAtPath:newest installedRoot:installedRoot message:message];
}

+ (BOOL)installArchiveAtPath:(NSString *)zipPath
               installedRoot:(NSString **)installedRoot
                     message:(NSString **)message {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:zipPath]) {
        if (message) *message = @"zip missing";
        return NO;
    }

    [self writeStatus:@"installing" detail:@{@"phase": @"extracting", @"zip": zipPath.lastPathComponent}];

    // 1) 暂存目录
    NSString *dataDir = PDDataDirectory();
    NSString *importedDir = [dataDir stringByAppendingPathComponent:@"Imported"];
    [fm createDirectoryAtPath:importedDir withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *stamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *staging = [importedDir stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"staging-%@", stamp]];
    [fm removeItemAtPath:staging error:NULL];
    [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];

    // 2) 解压（自动剥掉单一顶层目录）
    NSString *err = nil;
    NSInteger n = [PDZipExtract extractArchiveAtPath:zipPath
                                         toDirectory:staging
                                    stripSingleRoot:YES
                                             error:&err];

    // 若剥掉后结构仍不完整，但完整时保持单根 → 重试一次不剥
    if (n > 0 && ![self assetRootIsComplete:staging]) {
        NSString *root = [PDZipExtract singleTopLevelDirectoryOfArchive:zipPath];
        if (root.length) {
            NSLog(@"[PetDFY.Import] staging incomplete after strip; retrying without strip");
            [fm removeItemAtPath:staging error:NULL];
            [fm createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:NULL];
            n = [PDZipExtract extractArchiveAtPath:zipPath
                                       toDirectory:staging
                                  stripSingleRoot:NO
                                           error:&err];
        }
    }

    if (n <= 0 || ![self assetRootIsComplete:staging]) {
        [fm removeItemAtPath:staging error:NULL];
        [self writeStatus:@"failed" detail:@{@"phase": @"extract",
                                             @"files": @(n),
                                             @"error": err ?: @"structure"}];
        NSString *msgText = [NSString stringWithFormat:@"extract failed (%ld files, err=%@)", (long)n, err ?: @"structure"];
        if (message) *message = msgText;
        PDDiagLog(@"%@", msgText);
        PDRecordImportResult(zipPath, NO, msgText, n);
        {
            NSString *shortText = [NSString stringWithFormat:
                @"素材导入失败\n文件: %@\n原因: %@\n解出: %ld 个\n\n点一下关闭",
                zipPath.lastPathComponent, msgText ?: @"-", (long)n];
            PDShowToast(shortText, 20);
        }
        return NO;
    }

    // 3) 安装到所有目标根
    NSMutableArray<NSString *> *targets = [NSMutableArray array];

    // 3a) 素材 bundle 根（与参考包 1.2.1 一致，优先）
    for (NSString *bundle in PDAssetBundleRoots()) {
        if (![fm fileExistsAtPath:bundle]) continue;
        if (![fm isWritableFileAtPath:bundle]) continue;
        [targets addObject:bundle];
        break;                       // 只取第一个真实存在的 bundle
    }

    // 3b) 既有 Imported/combined/current（1.2 源码路径，保留）
    NSString *combinedCurrent = [importedDir stringByAppendingPathComponent:@"combined/current"];
    [targets addObject:combinedCurrent];

    // 3c) 若 bundle 不可写，额外落一份到 data 目录根，保证渲染器可读
    if (targets.count == 0) [targets addObject:dataDir];

    NSString *primary = nil;
    NSInteger installed = 0;
    for (NSString *target in targets) {
        NSError *e = nil;
        BOOL ok = NO;
        if ([target isEqualToString:combinedCurrent]) {
            // 整份替换
            [fm removeItemAtPath:target error:NULL];
            [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent]
           withIntermediateDirectories:YES attributes:nil error:NULL];
            ok = [fm moveItemAtPath:staging toPath:target error:&e];
            if (!ok) {
                // 跨卷时退回复制
                [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:NULL];
                ok = [self mergeCopyDirectory:staging to:target error:&e];
            }
        } else {
            // 合并进已有 bundle，保留 Info.plist / Whale.metal
            ok = [self mergeCopyDirectory:staging to:target error:&e];
        }
        if (ok && [self assetRootIsComplete:target]) {
            installed++;
            if (!primary) primary = target;
            PDDiagLog(@"installed into %@", target);
        } else if (ok) {
            // 合并只写进了部分文件（例如 bundle 根目录不可写、只写进了 originals/），
            // 这种半成品不能当作安装成功，否则渲染器会读到不完整的根。
            PDDiagLog(@"target incomplete after merge: %@", target);
        } else {
            PDDiagLog(@"install failed for %@: %@", target, e.localizedDescription);
        }
    }

    // staging 若已被 move 走则不存在；否则清理
    [fm removeItemAtPath:staging error:NULL];

    if (installed == 0) {
        [self writeStatus:@"failed" detail:@{@"phase": @"install"}];
        if (message) *message = @"no writable install target";
        return NO;
    }

    // 4) 标记 + 状态
    NSString *bundleRoot = [PDAssetBundleRoots() firstObject];
    if (bundleRoot) {
        NSString *statePath = [bundleRoot stringByAppendingPathComponent:kPDAssetStateFileName];
        NSDictionary *state = @{
            @"installedAt": @([[NSDate date] timeIntervalSince1970]),
            @"source": zipPath.lastPathComponent,
            @"targets": targets,
            @"files": @(n),
        };
        NSData *sd = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:NULL];
        if (sd) [sd writeToFile:statePath atomically:YES];
    }

    NSString *marker = [importedDir stringByAppendingPathComponent:@".asset-import-token"];
    [[self tokenForArchive:zipPath] writeToFile:marker atomically:YES
                                       encoding:NSUTF8StringEncoding error:NULL];

    [self writeStatus:@"ready" detail:@{@"phase": @"done",
                                        @"root": primary ?: @"",
                                        @"files": @(n)}];

    NSString *msgText = [NSString stringWithFormat:@"installed %ld files -> %@", (long)n, primary];
    PDRecordImportResult(zipPath, YES, msgText, n);
    if (installedRoot) *installedRoot = primary;
    if (message) *message = msgText;
    PDDiagLog(@"%@", msgText);
    {
        NSString *shortText = [NSString stringWithFormat:
            @"素材导入成功\n文件: %@\n解出: %ld 个\n安装到:\n%@\n\n点一下关闭",
            zipPath.lastPathComponent, (long)n, primary ?: @"-"];
        PDShowToast(shortText, 15);
    }
    return YES;
}

@end
