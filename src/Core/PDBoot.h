//
//  PDBoot.h — 启动守卫 / 启动阶段日志
//
#import <Foundation/Foundation.h>

/// 追加一行到 /var/mobile/Media/petdfy-diag.txt（带时间戳，文件上限 256KB）
void PDInitLog(NSString *fmt, ...);

/// 连续崩溃保护：最多连续 3 次异常启动后改为延迟 10 秒启动（不再永久禁用）
BOOL PDBootGuardAllow(void);
/// 返回本次启动需要额外延迟的秒数（正常为 0）
int PDBootGuardStartDelay(void);
/// 首帧真正提交后调用，清零崩溃计数
void PDBootGuardMarkHealthy(void);

/// 启动期是否允许跑发色扩展（默认 NO；放 /var/mobile/Media/petdfy-hairtint-on 可强制打开）
BOOL PDHairTintAtBootAllowed(void);
