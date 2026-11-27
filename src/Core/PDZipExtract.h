//
//  PDZipExtract.h — 进程内 ZIP 解压（不依赖 /usr/bin/unzip）
//
//  为什么需要：
//  逆向源码的导入链路调用 posix_spawn 执行 /usr/bin/unzip。在 RootHide
//  设备上该绝对路径不存在（越狱内容在 jbroot 内），spawn 直接失败，
//  导入表现为「面板抖一下、无任何效果」。参考包 1.2.1 不依赖外部工具
//  也能完成导入，因此这里用 zlib 在进程内自行解压，彻底去掉该依赖。
//
//  支持：stored(0) / deflate(8)、ZIP64 尺寸探测、UTF-8 与 CP437 文件名、
//  目录条目、跳过 __MACOSX 与 .DS_Store、路径穿越防护。
//

#pragma once

#import <Foundation/Foundation.h>

@interface PDZipExtract : NSObject

/// 解压 zipPath 到 destination（必须为空目录或不存在）。
/// stripSingleRoot=YES 时，若所有条目都在同一个顶层目录下，自动去掉该层，
/// 使素材包内层目录（originals/ live/ clips.plist）直接落在 destination 下。
/// 返回实际解出的文件数（>=0）；失败返回 -1 并填充 errorDescription。
+ (NSInteger)extractArchiveAtPath:(NSString *)zipPath
                      toDirectory:(NSString *)destination
                 stripSingleRoot:(BOOL)stripSingleRoot
                          error:(NSString **)errorDescription;

/// 只读取条目的第一个顶层目录名（用于 stripSingleRoot 预判），无则返回 nil。
+ (NSString *)singleTopLevelDirectoryOfArchive:(NSString *)zipPath;

@end
