//
//  PDAssetInstaller.h — 素材包导入安装器
//
//  目标：让「设置 → 下载 → 从文件导入 ZIP」在 rootless / RootHide / rootful
//  三种环境下都能真正落盘并立即生效，且不引入外部二进制依赖。
//
//  与参考包 PetDFY_1.2.1_RootHide.deb 对齐的可观测契约：
//    · 素材根：<jbroot>/Library/Application Support/PetDFY.bundle
//      （其 postinst 预先把该 bundle 下的 originals / live / .asset-state
//        chown 到 501:501，说明导入产物就该落在这里）
//    · 投递目录：/var/mobile/Library/Application Support/PetDFY/AssetImports
//    · 状态键：com.susudear.petdfyprefs 的 AssetDownloadStatus
//    · 状态通知：com.susudear.petdfy/assets-status
//    · 标记文件：.asset-state
//
//  同时保留 1.2 源码既有的 Imported/combined/current 安装位置，双写兼容。
//

#pragma once

#import <Foundation/Foundation.h>

@interface PDAssetInstaller : NSObject

/// 扫描所有投递目录里最新的、结构合法的素材 ZIP 并安装。
/// 返回 YES 表示本次确实安装（或刷新）了素材；NO 表示无需安装/失败。
+ (BOOL)installNewestArchiveIfNeeded:(NSString **)installedRoot
                             message:(NSString **)message;

/// 强制重装指定 ZIP（供调试与「下载/重试」使用）。
+ (BOOL)installArchiveAtPath:(NSString *)zipPath
               installedRoot:(NSString **)installedRoot
                     message:(NSString **)message;

/// 当前可用的素材根（已安装且结构完整），无则返回 nil。
+ (NSString *)currentAssetRoot;

/// 该根是否包含渲染所需的完整结构。
+ (BOOL)assetRootIsComplete:(NSString *)root;

/// 允许被扫描的投递目录（含 jbroot 展开）。
+ (NSArray<NSString *> *)spoolDirectories;

@end
