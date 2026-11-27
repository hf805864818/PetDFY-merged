//
//  PDDiagnostics.m — 诊断报告实现
//

#import "PDDiagnostics.h"
#import "PDJailbreak.h"
#import "PDAssetInstaller.h"
#import "PDPreferences.h"
#import <UIKit/UIKit.h>
#import <unistd.h>
#import <spawn.h>
#import <sys/wait.h>

static NSString *const kPDPrefsDomain = @"com.susudear.petdfyprefs";

// 最近一次导入
static NSString *gLastZip = nil;
static BOOL gLastOK = NO;
static NSString *gLastDetail = nil;
static NSInteger gLastFiles = 0;
static NSTimeInterval gLastAt = 0;
static BOOL gHasImport = NO;

// 渲染状态
static BOOL gRendererOK = NO;
static BOOL gRigOK = NO;
static NSString *gRenderDetail = nil;
static BOOL gHasRender = NO;

void PDRecordImportResult(NSString *zipPath, BOOL success, NSString *detail, NSInteger files) {
    gLastZip = [zipPath copy];
    gLastOK = success;
    gLastDetail = [detail copy];
    gLastFiles = files;
    gLastAt = [[NSDate date] timeIntervalSince1970];
    gHasImport = YES;
    PDWriteDiagnosticsReport();
}

void PDRecordRenderState(BOOL rendererOK, BOOL rigOK, NSString *detail) {
    gRendererOK = rendererOK;
    gRigOK = rigOK;
    gRenderDetail = [detail copy];
    gHasRender = YES;
    PDWriteDiagnosticsReport();
}

NSString *PDDiagnosticsReportPath(void) {
    return [PDDataDirectory() stringByAppendingPathComponent:@"petdfy-report.txt"];
}

static NSString *PDFmtTime(NSTimeInterval t) {
    if (t <= 0) return @"-";
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"MM-dd HH:mm:ss";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static NSString *PDYesNo(BOOL v) { return v ? @"有" : @"无"; }

static NSString *PDFileState(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return @"缺失";
    if (isDir) {
        NSArray *kids = [fm contentsOfDirectoryAtPath:path error:NULL];
        return [NSString stringWithFormat:@"有(%lu项)", (unsigned long)kids.count];
    }
    NSDictionary *a = [fm attributesOfItemAtPath:path error:NULL];
    unsigned long long sz = [a[NSFileSize] unsignedLongLongValue];
    return [NSString stringWithFormat:@"有(%lluB)", sz];
}

NSString *PDBuildDiagnosticsReport(void) {
    NSMutableString *s = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];

    [s appendString:@"== PetDFY 素材诊断 ==\n"];
    [s appendFormat:@"时间: %@\n", PDFmtTime([[NSDate date] timeIntervalSince1970])];
    [s appendFormat:@"注入进程: %@ (pid %d)\n", @"SpringBoard", (int)getpid()];

    // 1) 偏好中的状态
    CFStringRef dom = (__bridge CFStringRef)kPDPrefsDomain;
    id status = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AssetDownloadStatus"), dom));
    id outfit = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Outfit"), dom));
    id scheme = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Scheme"), dom));
    [s appendFormat:@"\n[偏好]\n  AssetDownloadStatus = %@  （注意：这个值来自设置面板，不代表导入成功）\n",
        status ?: @"(空)"];
    [s appendFormat:@"  Outfit = %@   Scheme = %@\n", outfit ?: @"(空)", scheme ?: @"(空)"];

    // 2) 投递目录
    [s appendString:@"\n[导入投递目录]\n"];
    NSArray *spool = [PDAssetInstaller spoolDirectories];
    NSInteger zipTotal = 0;
    for (NSString *dir in spool) {
        NSArray *kids = [fm contentsOfDirectoryAtPath:dir error:NULL];
        if (!kids) {
            [s appendFormat:@"  ✗ %@  (不存在/不可读)\n", dir];
            continue;
        }
        NSMutableArray *zips = [NSMutableArray array];
        for (NSString *n in kids) {
            if ([[n.pathExtension lowercaseString] isEqualToString:@"zip"]) [zips addObject:n];
        }
        zipTotal += zips.count;
        [s appendFormat:@"  ✓ %@  zip=%lu\n", dir, (unsigned long)zips.count];
        for (NSString *z in zips) {
            NSString *p = [dir stringByAppendingPathComponent:z];
            NSDictionary *a = [fm attributesOfItemAtPath:p error:NULL];
            unsigned long long sz = [a[NSFileSize] unsignedLongLongValue];
            [s appendFormat:@"      - %@ (%llu B)\n", z, sz];
        }
    }
    [s appendFormat:@"  合计待导入 ZIP: %ld\n", (long)zipTotal];

    // 3) 资源根
    [s appendString:@"\n[素材根]\n"];
    NSMutableArray *roots = [NSMutableArray array];
    for (NSString *r in PDLegacyImportedRoots()) [roots addObject:r];
    for (NSString *r in PDAssetBundleRoots()) [roots addObject:r];
    NSString *chosen = nil;
    for (NSString *r in roots) {
        BOOL complete = [PDAssetInstaller assetRootIsComplete:r];
        if (![fm fileExistsAtPath:r]) continue;
        [s appendFormat:@"  %@ %@  完整=%@\n", complete ? @"✓" : @"·", r, PDYesNo(complete)];
        if (complete && !chosen) chosen = r;
    }
    if (!chosen) {
        [s appendString:@"  ✗ 没有任何完整的素材根（缺 live/model.json 或 originals/）\n"];
    } else {
        [s appendFormat:@"  → 实际使用: %@\n", chosen];
    }

    // 4) 关键文件
    if (chosen) {
        [s appendString:@"\n[关键文件]\n"];
        [s appendFormat:@"  live/model.json      : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"live/model.json"])];
        [s appendFormat:@"  originals/model.json : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"originals/model.json"])];
        [s appendFormat:@"  clips.plist          : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"clips.plist"])];
        [s appendFormat:@"  frames/              : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"frames"])];
        [s appendFormat:@"  originals/tex/       : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"originals/tex"])];
        [s appendFormat:@"  originals/outfits/   : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"originals/outfits"])];
        [s appendFormat:@"  Whale.metal          : %@\n", PDFileState([chosen stringByAppendingPathComponent:@"Whale.metal"])];

        // 5) 模型里的服装
        NSString *livePath = [chosen stringByAppendingPathComponent:@"live/model.json"];
        NSData *d = [NSData dataWithContentsOfFile:livePath];
        if (d) {
            id json = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *models = json[@"models"];
                if ([models isKindOfClass:[NSDictionary class]]) {
                    NSArray *ids = [[models allKeys] sortedArrayUsingSelector:@selector(compare:)];
                    [s appendFormat:@"\n[模型服装] 共 %lu 套\n  %@\n",
                        (unsigned long)ids.count, [ids componentsJoinedByString:@", "]];
                    if (outfit && ![models objectForKey:outfit]) {
                        [s appendFormat:@"  ✗ 当前 Outfit=%@ 不在模型里 → 角色会加载失败\n", outfit];
                    }
                } else {
                    [s appendString:@"\n[模型服装] ✗ live/model.json 里没有 models 字段\n"];
                }
            }
        } else {
            [s appendString:@"\n[模型服装] ✗ 读不到 live/model.json\n"];
        }

        // 6) 贴图数量
        NSString *texDir = [chosen stringByAppendingPathComponent:@"originals/tex"];
        NSArray *texs = [fm contentsOfDirectoryAtPath:texDir error:NULL];
        if (texs) {
            NSInteger png = 0;
            for (NSString *t in texs) {
                if ([[t.pathExtension lowercaseString] isEqualToString:@"png"]) png++;
            }
            [s appendFormat:@"\n[贴图] originals/tex 下 png=%ld\n", (long)png];
        }
    }

    // 7) 最近导入
    [s appendString:@"\n[最近导入]\n"];
    if (!gHasImport) {
        [s appendString:@"  本次启动后还没有导入记录\n"];
    } else {
        [s appendFormat:@"  文件: %@\n", gLastZip.lastPathComponent ?: @"-"];
        [s appendFormat:@"  时间: %@\n", PDFmtTime(gLastAt)];
        [s appendFormat:@"  结果: %@\n", gLastOK ? @"成功" : @"失败"];
        [s appendFormat:@"  解出文件: %ld\n", (long)gLastFiles];
        [s appendFormat:@"  详情: %@\n", gLastDetail ?: @"-"];
    }

    // 8) 渲染
    [s appendString:@"\n[渲染]\n"];
    if (!gHasRender) {
        [s appendString:@"  尚未初始化（或插件未在 SpringBoard 加载）\n"];
    } else {
        [s appendFormat:@"  渲染器: %@\n", gRendererOK ? @"OK" : @"失败"];
        [s appendFormat:@"  LiveRig: %@\n", gRigOK ? @"OK" : @"失败"];
        if (gRenderDetail.length) [s appendFormat:@"  详情: %@\n", gRenderDetail];
    }

    // 9) 权限/可写性
    [s appendString:@"\n[目录可写性]\n"];
    [s appendFormat:@"  %@ : %@\n", PDDataDirectory(), [fm isWritableFileAtPath:PDDataDirectory()] ? @"可写" : @"不可写"];
    for (NSString *b in PDAssetBundleRoots()) {
        if ([fm fileExistsAtPath:b]) {
            [s appendFormat:@"  %@ : %@\n", b, [fm isWritableFileAtPath:b] ? @"可写" : @"不可写"];
            break;
        }
    }

    [s appendString:@"\n== 报告结束 ==\n"];
    return s;
}

void PDWriteDiagnosticsReport(void) {
    NSString *report = PDBuildDiagnosticsReport();
    NSString *path = PDDiagnosticsReportPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:PDDataDirectory() withIntermediateDirectories:YES attributes:nil error:NULL];
    [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    // 同步给设置页（诊断页轮询此通知）
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.susudear.petdfy/diagnostics"), NULL, NULL, true);
}
