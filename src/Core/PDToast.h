//
//  PDToast.h — SpringBoard 内浮层提示（可滚动、可复制）
//
//  用途：导入素材后直接在屏幕上显示结果/诊断，不依赖设置面板与日志抓取。
//

#pragma once
#import <Foundation/Foundation.h>

/// 在 SpringBoard 上显示一个可滚动文本浮层；点一下关闭，或 sec 秒后自动关闭。
void PDShowToast(NSString *text, NSTimeInterval sec);

/// 关闭当前浮层
void PDHideToast(void);