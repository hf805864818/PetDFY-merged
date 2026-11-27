//
//  PDAIHelpers.h
//  PetDFYPrefs — PDAI* C 函数族（AI 请求/响应/工具/提示词构造）还原
//
//  来源：build.080 arm64 dylib（MH_DYLIB，image base = 0）
//        反汇编切片 extract/slices/PetDFYPrefs_arm64
//  每个声明后的注释是符号地址。签名由调用点与寄存器用法推定。
//  说明：本族函数全部是 C 函数（无 Objective-C 方法），由 PDChatService 调用。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 基础取值

/// 值转字符串：非 NSString 一律给 @""。       // 0x001329c
FOUNDATION_EXPORT NSString *PDAIString(id _Nullable obj);

/// 值转 double：NSString 用 NSScanner scanDouble: 且要求 isAtEnd；
/// NaN / ±inf 回落到 fallback。              // 0x00132f8
FOUNDATION_EXPORT double PDAINumber(id _Nullable obj, double fallback);

/// 读 NSUserDefaults（CFPreferences，domain com.susudear.petdfyprefs）；nil 时用 fallback。 // 0x00133d8
FOUNDATION_EXPORT id PDAIPreference(NSString *key, id fallback);

/// 把字典逐项写回 CFPreferences 并同步，再发 Darwin 通知。 // 0x001343c
FOUNDATION_EXPORT void PDAIWritePreferences(NSDictionary<NSString *, id> *values);

#pragma mark - 形象词表 / 工具声明

/// 内置工具声明 + 已授权设备工具声明拼接。      // 0x0013580
FOUNDATION_EXPORT NSArray<NSDictionary *> *PDAIToolDeclarations(void);

/// manifest.vocab 的可变副本里追加 play_ball 一条，再 copy。 // 0x0013630
FOUNDATION_EXPORT NSArray<NSDictionary *> *PDAIVocabulary(void);

FOUNDATION_EXPORT NSString *PDAIDefaultEnvironment(void);  // 0x001370c
FOUNDATION_EXPORT NSString *PDAIDefaultPersona(void);      // 0x0013718
FOUNDATION_EXPORT NSString *PDAIOrientation(void);         // 0x0013724

/// 词 → 词条。索引：id、各语言 names 原文与 lowercase，先查 lowercase 再查原文。 // 0x0013730
FOUNDATION_EXPORT NSDictionary * _Nullable PDAIWord(NSString * _Nullable token);

/// 词数组 → @{@"actions": [id], @"dropped": [原文或 @"null"]}。 // 0x0013ae4
FOUNDATION_EXPORT NSDictionary<NSString *, NSArray *> *PDAIParseActions(NSArray *tokens);

/// 台词脚本 → @{@"beats": [段], @"dropped": [词]}；段 = @{actions, anchors, text}。 // 0x0013cac
FOUNDATION_EXPORT NSDictionary<NSString *, NSArray *> *PDAIParseScript(NSString * _Nullable script);

/// 段总时长：每段 0.5 起底 + (len/20 + 1.6 + len*0.07)/max(rate,0.5)，最后取整到 0.1s。 // 0x00146ec
FOUNDATION_EXPORT double PDAIScriptSeconds(NSArray *beats, double rate);

/// 可自主调整的键：figure, scheme, roam, snoreSeconds, sound, scale, bubbleSize, fontSize, theme, hoverButtons, user。 // 0x00148a8
FOUNDATION_EXPORT NSArray<NSString *> *PDAISelfKeys(void);

/// 键 → @(是否直接生效)，按 AISelfAdjust（any/off/custom）裁决。 // 0x00148b4
FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> *PDAIDirectSettings(void);

/// 环境模板变量表（10 个 pet.* 键）。         // 0x0014af0
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *PDAIPromptValues(void);

/// AI* 偏好 → 短键字典（base/model/protocol/...）。 // 0x0015774
FOUNDATION_EXPORT NSDictionary<NSString *, id> *PDAIProviderSettings(void);

/// base + endpoint(或按 protocol 选) → 只接受 http/https 且 host 非空的 NSURL，否则 nil。 // 0x00158dc
FOUNDATION_EXPORT NSURL * _Nullable PDAIEndpoint(NSDictionary *settings);

/// 粗算 token：ASCII 3 字节 1 token，非 ASCII 每字 2；数组 +4/项，字典 +4/对，其他 4。 // 0x0015c28
FOUNDATION_EXPORT NSUInteger PDAIEstimatedTokens(id _Nullable obj);

/// 图片请求去重键：endpoint|protocol|model|extra|headers，换行连接。 // 0x0015f10
FOUNDATION_EXPORT NSString *PDAIImageEndpointKey(NSDictionary *settings);

/// 把已在 keepIDs 中的图片附件从历史里摘掉，并写入 [image_not_delivered] 说明。 // 0x00160c0
FOUNDATION_EXPORT NSArray *PDAIHistoryWithoutImages(NSArray *messages, id keepIDs);

/// 遍历请求体，是否含 image_url / input_image 部件。 // 0x0016554
FOUNDATION_EXPORT BOOL PDAIRequestHasImages(id _Nullable payload);

/// 本轮实际送达过的图片 id 集合（按 data: URI 命中）。 // 0x0016888
FOUNDATION_EXPORT NSSet<NSString *> *PDAISentImageIDs(id payload, NSArray *history, NSString *root);

/// 从上一条 user/_handoff 与最后一条 assistant 之间截断，只保留之前的消息并摘掉其中的图片。 // 0x0016c14
FOUNDATION_EXPORT NSArray *PDAIContextSinceLastDelivery(NSArray *messages);

/// 400/413 且非“上下文超限”类报错时才允许图片重试。 // 0x0016f44
FOUNDATION_EXPORT BOOL PDAIImageRetryAllowed(NSInteger status, id _Nullable body, id _Nullable error);

/// 图片安全交接边界：最后一条“无 _handoff 的 user”之前的位置，找不到给 NSIntegerMax。 // 0x00171b4
FOUNDATION_EXPORT NSInteger PDAIImageSafeHandoffBoundary(NSArray *messages);

/// 组请求体；协议必须是 chat/responses，否则置 error 并返回 nil。 // 0x0017460
FOUNDATION_EXPORT NSMutableDictionary * _Nullable PDAIRequestBody(NSString * _Nullable instructions,
                                                                 NSArray * _Nullable history,
                                                                 NSArray * _Nullable tools,
                                                                 NSDictionary *settings,
                                                                 NSString *root,
                                                                 NSError *_Nullable *_Nullable error);

/// 响应归一：responses 走 output 数组，chat 走 choices[0].message。 // 0x00192a8
FOUNDATION_EXPORT id _Nullable PDAINormalizeResponse(NSDictionary * _Nullable response,
                                                     NSDictionary *settings,
                                                     NSError *_Nullable *_Nullable error);

/// 交接笔记：早段 + 近段，按 recentCount 与 token 预算折叠。 // 0x0019c00
FOUNDATION_EXPORT NSString *PDAIHandoffNote(NSArray *messages, NSUInteger recentCount, NSUInteger tokenBudget);

/// “[system] 交接完了。…” 提示语，带根目录。 // 0x001a648
FOUNDATION_EXPORT NSString *PDAIHandoffNotice(NSString *root);

NS_ASSUME_NONNULL_END
