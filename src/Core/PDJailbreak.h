//
//  PDJailbreak.h — 越狱根路径解析（rootless / rootful / RootHide）
//
//  背景：原逆向源码把 /Library/... 与 /var/mobile/... 当绝对路径硬编码。
//  在 RootHide 设备上 /Library 是系统 /Library（mobile 不可写），越狱内容
//  实际位于 jbroot（形如 /.jbroot-XXXXXXXX 或
//  /var/containers/Bundle/Application/<UUID>/.jbroot-XXXXXXXX）。
//  参考包 PetDFY_1.2.1_RootHide.deb 的 postinst 正是用
//  /var/containers/Bundle/Application/.jbroot-* 这套约定做镜像。
//
//  本文件把「越狱根解析」集中到一处，供渲染器 / 帧播放器 / 导入器共用。
//  只做路径解析，不改任何业务行为。
//

#pragma once

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

/// 已探测到的越狱根前缀列表，按优先级排列。
/// 元素是「前缀字符串」，后缀为空表示 rootful（直接用绝对路径）。
/// 例：@"", @"/var/jb", @"/var/containers/Bundle/Application/.jbroot-AB12CD", ...
static inline NSArray<NSString *> *PDJailbreakPrefixes(void) {
    static NSArray<NSString *> *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];

        // 1) rootful：直接绝对路径
        [out addObject:@""];

        // 2) rootless：/var/jb
        [out addObject:@"/var/jb"];

        // 3) RootHide：扫描已知容器目录下 .jbroot-* / .jbroot
        NSArray<NSString *> *bases = @[
            @"/var/containers/Bundle/Application",
            @"/rootfs/var/containers/Bundle/Application",
            @"/",
        ];
        for (NSString *base in bases) {
            NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:base error:NULL];
            for (NSString *name in children) {
                if (![name hasPrefix:@".jbroot"]) continue;
                NSString *p = [base stringByAppendingPathComponent:name];
                BOOL isDir = NO;
                if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                    if (![out containsObject:p]) [out addObject:p];
                }
            }
        }

        // 4) 固定 /rootfs 前缀（checkra1n / palera1n rootful 兼容）
        [out addObject:@"/rootfs"];

        cached = [out copy];
    });
    return cached;
}

/// 把绝对路径按越狱根展开成「所有可能存在的真实路径」，优先返回已存在的。
static inline NSArray<NSString *> *PDJailbreakCandidates(NSString *absolute) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (![absolute isKindOfClass:[NSString class]] || absolute.length == 0) return out;

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *prefix in PDJailbreakPrefixes()) {
        NSString *p = prefix.length ? [prefix stringByAppendingString:absolute] : absolute;
        if (![out containsObject:p]) [out addObject:p];
    }
    // 稳定排序：存在的排前面（保持原有相对顺序）
    NSMutableArray<NSString *> *existing = [NSMutableArray array];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *p in out) {
        if ([fm fileExistsAtPath:p]) [existing addObject:p];
        else [missing addObject:p];
    }
    [existing addObjectsFromArray:missing];
    return existing;
}

/// 返回第一个真实存在的路径；都不存在时返回 nil。
static inline NSString *PDJailbreakExisting(NSString *absolute) {
    for (NSString *p in PDJailbreakCandidates(absolute)) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

/// 返回用于「写入」的路径：取第一个已存在的父目录所在前缀；
/// 若都不存在，返回 rootless/RootHide 优先的候选（第二项），
/// 保证不会误写到 rootful 的 /Library。
static inline NSString *PDJailbreakWritable(NSString *absolute) {
    NSArray<NSString *> *cands = PDJailbreakCandidates(absolute);
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in cands) {
        // 命中已存在的目录/文件，直接用
        if ([fm fileExistsAtPath:p]) {
            // 目录存在且可写才用它
            if ([fm isWritableFileAtPath:p]) return p;
            if ([fm isWritableFileAtPath:[p stringByDeletingLastPathComponent]]) return p;
        }
        // 父目录存在且可写 → 可创建
        NSString *parent = [p stringByDeletingLastPathComponent];
        if ([fm fileExistsAtPath:parent] && [fm isWritableFileAtPath:parent]) return p;
    }
    return cands.count > 1 ? cands[1] : absolute;
}

#pragma mark - 业务路径（集中定义，避免各处硬编码发散）

/// 数据目录：/var/mobile/Library/Application Support/PetDFY
static inline NSString *PDDataDirectory(void) {
    return PDJailbreakWritable(@"/var/mobile/Library/Application Support/PetDFY");
}

/// 导入投递目录：偏好面板把用户选的 ZIP 拷到这里
static inline NSArray<NSString *> *PDImportSpoolDirectories(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *p in PDJailbreakCandidates(@"/var/mobile/Library/Application Support/PetDFY/AssetImports")) {
        [out addObject:p];
    }
    return out;
}

/// 素材根（唯一权威，build.93 起）。
///
/// 为什么是 /var/mobile/Library/Xfy：
///   · 真实路径，RootHide 不重定向 /var/mobile（只重定向 /Library /usr /bin 等）
///   · 路径固定，不随 .jbroot-<UUID> 变化（重建越狱也不影响）
///   · mobile 用户可读写，导入素材不需要 root
///   · 用户在「文件」App 里能直接看到，方便手动放素材
///
/// 旧路径 /Library/Application Support/PetDFY.bundle 不再参与读取。
static inline NSString *PDAssetRootPath(void) {
    return @"/var/mobile/Library/Xfy";
}

static inline NSArray<NSString *> *PDAssetBundleRoots(void) {
    return @[ PDAssetRootPath() ];
}

/// 素材兼容安装位置（1.2 源码既有路径，保留不动）
static inline NSArray<NSString *> *PDLegacyImportedRoots(void) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *rels = @[
        @"/var/mobile/Library/Application Support/PetDFY/Imported/combined/current",
        @"/var/mobile/Library/Application Support/PetDFY/Imported/layered/current",
        @"/var/mobile/Library/Application Support/PetDFY/Imported/current",
        @"/var/mobile/Library/Application Support/PetDFY",
    ];
    for (NSString *rel in rels) {
        for (NSString *p in PDJailbreakCandidates(rel)) [out addObject:p];
    }
    return out;
}
