//
//  PDBoot.h — 启动守卫 / 启动阶段日志
//
#import <Foundation/Foundation.h>

/// 追加一行到 /var/mobile/Media/petdfy-diag.txt（带时间戳，文件上限 256KB）
void PDInitLog(NSString *fmt, ...);

/// 连续崩溃保护：第 3 次启动会跳过整个 tweak，避免无限安全模式
BOOL PDBootGuardAllow(void);
/// 启动满 25 秒后调用，清零崩溃计数
void PDBootGuardMarkHealthy(void);

/// 启动期是否允许跑发色扩展（默认 NO；放 /var/mobile/Media/petdfy-hairtint-on 可强制打开）
BOOL PDHairTintAtBootAllowed(void);
