//
//  PDDiag.h — 落盘诊断日志
//
//  为什么：设置页的「素材已就绪」是 PreferenceBundle 按基包里的
//  asset-manifest.json / .asset-state 算出来的，不代表 ZIP 真的导入成功。
//  要判断 dylib 是否注入、资源根选到哪、渲染器是否初始化成功，
//  必须看 SpringBoard 里本插件的日志。
//
//  这里同时 NSLog + 追加写文件，用户可以直接把
//  <数据目录>/petdfy-diag.log 发出来，不依赖终端过滤。
//

#pragma once

#import <Foundation/Foundation.h>
#import <stdarg.h>
#import <stdio.h>
#import <unistd.h>
#import "PDJailbreak.h"

static inline NSString *PDDiagLogPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = PDDataDirectory();
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        path = [dir stringByAppendingPathComponent:@"petdfy-diag.log"];
        // 简单截断：超过 256KB 就清空，避免无限增长
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
        if ([attrs[NSFileSize] unsignedLongLongValue] > 256 * 1024) {
            [fm removeItemAtPath:path error:NULL];
        }
    });
    return path;
}

static inline void PDDiagLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    if (!msg) return;

    NSLog(@"[PetDFY] %@", msg);

    NSString *line = [NSString stringWithFormat:@"%.0f pid=%d %@\n",
                      [[NSDate date] timeIntervalSince1970], (int)getpid(), msg];
    FILE *f = fopen([PDDiagLogPath() fileSystemRepresentation], "a");
    if (!f) return;
    fputs(line.UTF8String, f);
    fclose(f);
}
