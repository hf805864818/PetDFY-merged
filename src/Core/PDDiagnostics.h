//
//  PDDiagnostics.h — 素材/渲染诊断报告
//
//  生成一份人类可读的中文报告，写到数据目录的 petdfy-report.txt。
//  设置里的「素材诊断」页面直接读这个文件显示，用户不用抓日志。
//

#pragma once

#import <Foundation/Foundation.h>

/// 记录一次导入尝试的结果（成功/失败原因/文件/解出数量）
void PDRecordImportResult(NSString *zipPath, BOOL success, NSString *detail, NSInteger files);

/// 记录渲染器与 rig 的初始化结果
void PDRecordRenderState(BOOL rendererOK, BOOL rigOK, NSString *detail);

/// 生成完整报告文本
NSString *PDBuildDiagnosticsReport(void);

/// 生成并写入 <数据目录>/petdfy-report.txt
void PDWriteDiagnosticsReport(void);

/// 报告文件路径
NSString *PDDiagnosticsReportPath(void);
