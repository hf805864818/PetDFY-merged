# PetDFYPrefs · 类 / 方法清单（build.080 arm64）

> 来源：`PetDFYPrefs`（`MH_DYLIB`，arm64 + arm64e，`minos 16.0`，未签名，SHA-256 `2d6e25f08dee51844f5a3562042ceedb6ee baeb320af64c9666daf15b094763b`）。
> 该 bundle 的 `__TEXT` 从 `0x0` 起（image base = 0），与 `petdfy-voice` 的 `0x100000000` 不同——解析器按切片基址重算后得到下列结果。

## 0 概览

| 项 | 值 |
|---|---|
| 类型 | `MH_DYLIB`（PreferenceBundle 插件） |
| 加载路径 | `/Library/PreferenceBundles/PetDFYPrefs.bundle/PetDFYPrefs` |
| 依赖 | objc / Foundation / CoreFoundation / UIKit / CoreGraphics / AVFoundation / ImageIO / UniformTypeIdentifiers / Preferences / libSystem + `@loader_path/.jbroot/usr/lib/libroothide.dylib` |
| 段 | `__TEXT` 0–0x4c000、`__DATA_CONST` 0x4c000–0x54000、`__DATA` 0x54000–0x5c000 |
| 类 | **18** 个（含 `pdHeader` 等辅助类；`PDLocalizationBundle` 无方法） |
| 方法 | **268** 个 |
| ivar | **67** 个 |
| 属性 | **80** 个 |
| 协议 | 6 个（NSObject、UIDocumentPickerDelegate、UIScrollViewDelegate、UITextViewDelegate、UITableViewDataSource、UITableViewDelegate） |
| Category | 0 个 |

> README 说「14 个 PD UI 类」，实际是 **18 个**：多出来的 4 个是非 UI 服务类（`PDChatService`、`PDChatStore` 等），其中 `PDChatService` 一个类就有 87 个方法。

## 1 类清单（按代码量降序）

> 「约指令数」= 从方法 imp 到本 dylib 下一个方法入口的指令数（含对齐填充），仅用于排序与估算规模；
> 全 bundle 合计 **≈ 28,910 条指令**，是 `petdfy-voice` 应用层（10,062 条）的约 **2.9 倍**。

| 类 | 父类 | instsize | 方法 | ivar | 属性 | 约指令数 |
|---|---|---:|---:|---:|---:|---:|
| `PDChatService` | ext:_OBJC_CLASS_$_NSObject | 240 | 87 | 31 | 32 | 12478 |
| `PDAIMemory` | ext:_OBJC_CLASS_$_NSObject | 16 | 22 | 1 | 1 | 4257 |
| `PDRootListController` | ext:_OBJC_CLASS_$_PSListController | 32 | 25 | 2 | 6 | 2623 |
| `PDChatHistoryController` | ext:_OBJC_CLASS_$_UITableViewController | 32 | 14 | 3 | 3 | 2157 |
| `PDChatMemoryController` | ext:_OBJC_CLASS_$_UIViewController | 48 | 26 | 5 | 9 | 1044 |
| `PDChatPromptController` | ext:_OBJC_CLASS_$_UIViewController | 16 | 9 | 1 | 5 | 1037 |
| `PDLabeledSliderCell` | ext:_OBJC_CLASS_$_PSSliderTableCell | 8 | 7 | 0 | 0 | 951 |
| `PDMemoryEditor` | ext:_OBJC_CLASS_$_UIViewController | 48 | 16 | 5 | 5 | 745 |
| `PDSwitchWithInfoCell` | ext:_OBJC_CLASS_$_PSSwitchTableCell | 24 | 7 | 1 | 1 | 690 |
| `PDSpeechSettingsController` | ? | 32 | 7 | 0 | 0 | 608 |
| `PDPreferences` | ext:_OBJC_CLASS_$_NSObject | 88 | 18 | 15 | 15 | 581 |
| `PDSpeechStyleController` | ext:_OBJC_CLASS_$_UIViewController | 16 | 5 | 1 | 1 | 554 |
| `PDProviderController` | ? | 32 | 5 | 0 | 0 | 374 |
| `PDModelListController` | ext:_OBJC_CLASS_$_UITableViewController | 16 | 7 | 1 | 1 | 370 |
| `PDSectionTitleCell` | ext:_OBJC_CLASS_$_PSTableCell | 16 | 7 | 1 | 1 | 341 |
| `PDDeviceControlController` | ? | 32 | 3 | 0 | 0 | 53 |
| `PDAssetDownloadController` | ? | 32 | 3 | 0 | 0 | 47 |
| `PDLocalizationBundle` | ext:_OBJC_CLASS_$_NSObject | 8 | 0 | 0 | 0 | 0 |

## 2 逐类方法表

### `PDModelListController` : ext:_OBJC_CLASS_$_UITableViewController   (instsize 16, va 0x584c8)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | @"NSArray" | `_models` |

**property**

| 名称 | attribute |
|---|---|
| `models` | `T@"NSArray",&,N,V_models` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x4710 | `viewDidLoad` | `v16@0:8` |
| 0x4774 | `tableView:numberOfRowsInSection:` | `q32@0:8@16q24` |
| 0x47a8 | `tableView:cellForRowAtIndexPath:` | `@32@0:8@16@24` |
| 0x4ad4 | `tableView:didSelectRowAtIndexPath:` | `v32@0:8@16@24` |
| 0x4ca0 | `models` | `@16@0:8` |
| 0x4cb0 | `setModels:` | `v24@0:8@16` |
| 0x4cc4 | `.cxx_destruct` | `v16@0:8` |

### `PDRootListController` : ext:_OBJC_CLASS_$_PSListController   (instsize 32, va 0x58518)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x10 | B | `_assetCopying` |
| 0x18 | @"UIView" | `_pdHeader` |

**property**

| 名称 | attribute |
|---|---|
| `pdHeader` | `T@"UIView",&,N,V_pdHeader` |
| `assetCopying` | `TB,N,V_assetCopying` |
| `hash` | `TQ,R` |
| `superclass` | `T#,R` |
| `description` | `T@"NSString",R,C` |
| `debugDescription` | `T@"NSString",?,R,C` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x4cd8 | `localizedSpecifiers:` | `@24@0:8@16` |
| 0x5104 | `specifiers` | `@16@0:8` |
| 0x5158 | `viewDidLoad` | `v16@0:8` |
| 0x5494 | `viewDidLayoutSubviews` | `v16@0:8` |
| 0x54dc | `viewWillAppear:` | `v20@0:8B16` |
| 0x5524 | `dealloc` | `v16@0:8` |
| 0x5580 | `updateAssetStatus` | `v16@0:8` |
| 0x57f8 | `retryAssets` | `v16@0:8` |
| 0x58e8 | `importAssets` | `v16@0:8` |
| 0x59e8 | `documentPicker:didPickDocumentsAtURLs:` | `v32@0:8@16@24` |
| 0x648c | `removeAssets` | `v16@0:8` |
| 0x68e4 | `installHeader` | `v16@0:8` |
| 0x6b2c | `setPreferenceValue:specifier:` | `v32@0:8@16@24` |
| 0x6d30 | `sendCommand:` | `v24@0:8@16` |
| 0x6d8c | `openAIChat` | `v16@0:8` |
| 0x6d98 | `editAIPrompt` | `v16@0:8` |
| 0x6df0 | `openAIHistory` | `v16@0:8` |
| 0x6e4c | `editAIMemory` | `v16@0:8` |
| 0x6ea4 | `fetchAIModels` | `v16@0:8` |
| 0x7158 | `configureAIKey` | `v16@0:8` |
| 0x757c | `pdHeader` | `@16@0:8` |
| 0x758c | `setPdHeader:` | `v24@0:8@16` |
| 0x75a0 | `assetCopying` | `B16@0:8` |
| 0x75b0 | `setAssetCopying:` | `v20@0:8B16` |
| 0x75c0 | `.cxx_destruct` | `v16@0:8` |

### `PDSpeechStyleController` : ext:_OBJC_CLASS_$_UIViewController   (instsize 16, va 0x58568)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | @"UITextView" | `_editor` |

**property**

| 名称 | attribute |
|---|---|
| `editor` | `T@"UITextView",&,N,V_editor` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x75d4 | `viewDidLoad` | `v16@0:8` |
| 0x7c60 | `save` | `v16@0:8` |
| 0x7e44 | `editor` | `@16@0:8` |
| 0x7e54 | `setEditor:` | `v24@0:8@16` |
| 0x7e68 | `.cxx_destruct` | `v16@0:8` |

### `PDAssetDownloadController` : ?   (instsize 32, va 0x585b8)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x7e7c | `specifiers` | `@16@0:8` |
| 0x7ed0 | `viewDidLoad` | `v16@0:8` |
| 0x7f34 | `installHeader` | `v16@0:8` |

### `PDSpeechSettingsController` : ?   (instsize 32, va 0x58608)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x7f38 | `specifiers` | `@16@0:8` |
| 0x80e0 | `viewDidLoad` | `v16@0:8` |
| 0x8144 | `installHeader` | `v16@0:8` |
| 0x8148 | `viewWillAppear:` | `v20@0:8B16` |
| 0x8190 | `editDoubaoStyle` | `v16@0:8` |
| 0x81e4 | `configureDoubaoKey` | `v16@0:8` |
| 0x85f8 | `setPreferenceValue:specifier:` | `v32@0:8@16@24` |

### `PDProviderController` : ?   (instsize 32, va 0x58658)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x88b8 | `specifiers` | `@16@0:8` |
| 0x890c | `viewDidLoad` | `v16@0:8` |
| 0x8970 | `installHeader` | `v16@0:8` |
| 0x8974 | `viewWillAppear:` | `v20@0:8B16` |
| 0x89bc | `setPreferenceValue:specifier:` | `v32@0:8@16@24` |

### `PDDeviceControlController` : ?   (instsize 32, va 0x586a8)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x8e90 | `specifiers` | `@16@0:8` |
| 0x8ee4 | `viewDidLoad` | `v16@0:8` |
| 0x8f48 | `installHeader` | `v16@0:8` |

### `PDLabeledSliderCell` : ext:_OBJC_CLASS_$_PSSliderTableCell   (instsize 8, va 0x586f8)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x8f64 | `controlChanged:` | `v24@0:8@16` |
| 0x9074 | `layoutSubviews` | `v16@0:8` |
| 0x90d8 | `refreshCellContentsWithSpecifier:` | `v24@0:8@16` |
| 0x9120 | `prepareForReuse` | `v16@0:8` |
| 0x9168 | `pd_enableValueLabelInput` | `v16@0:8` |
| 0x9698 | `pd_preventValueLabelClipping:` | `v24@0:8@16` |
| 0x97c4 | `pd_promptForSliderValue` | `v16@0:8` |

### `PDSectionTitleCell` : ext:_OBJC_CLASS_$_PSTableCell   (instsize 16, va 0x58748)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | @"UILabel" | `_sectionTitleLabel` |

**property**

| 名称 | attribute |
|---|---|
| `sectionTitleLabel` | `T@"UILabel",&,N,V_sectionTitleLabel` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x9e40 | `initWithStyle:reuseIdentifier:specifier:` | `@40@0:8q16@24@32` |
| 0xa18c | `refreshCellContentsWithSpecifier:` | `v24@0:8@16` |
| 0xa22c | `pd_refreshTitleWithSpecifier:` | `v24@0:8@16` |
| 0xa2e8 | `tintColorDidChange` | `v16@0:8` |
| 0xa35c | `sectionTitleLabel` | `@16@0:8` |
| 0xa36c | `setSectionTitleLabel:` | `v24@0:8@16` |
| 0xa380 | `.cxx_destruct` | `v16@0:8` |

### `PDSwitchWithInfoCell` : ext:_OBJC_CLASS_$_PSSwitchTableCell   (instsize 24, va 0x58798)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x10 | @"UIButton" | `_infoButton` |

**property**

| 名称 | attribute |
|---|---|
| `infoButton` | `T@"UIButton",&,N,V_infoButton` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0xa394 | `initWithStyle:reuseIdentifier:specifier:` | `@40@0:8q16@24@32` |
| 0xa57c | `pd_infoButtonTapped` | `v16@0:8` |
| 0xa7ac | `tintColorDidChange` | `v16@0:8` |
| 0xa81c | `refreshCellContentsWithSpecifier:` | `v24@0:8@16` |
| 0xa88c | `infoButton` | `@16@0:8` |
| 0xa89c | `setInfoButton:` | `v24@0:8@16` |
| 0xa8b0 | `.cxx_destruct` | `v16@0:8` |

### `PDChatService` : ext:_OBJC_CLASS_$_NSObject   (instsize 240, va 0x587e8)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | B | `_busy` |
| 0x9 | B | `_wakePending` |
| 0xa | B | `_maintainingData` |
| 0x10 | @"NSURL" | `_historyURL` |
| 0x18 | @? | `_stateProvider` |
| 0x20 | @? | `_toolHandler` |
| 0x28 | @? | `_deviceToolHandler` |
| 0x30 | @? | `_turnStateHandler` |
| 0x38 | @? | `_interruptionHandler` |
| 0x40 | @? | `_historyClearedHandler` |
| 0x48 | @"NSMutableArray" | `_mutableHistory` |
| 0x50 | @"NSMutableArray" | `_pendingEvents` |
| 0x58 | @"NSMutableArray" | `_pendingAttachments` |
| 0x60 | @"NSString" | `_dataDirectory` |
| 0x68 | @"NSURLSession" | `_session` |
| 0x70 | @"NSURLSessionDataTask" | `_task` |
| 0x78 | @"NSObject<OS_dispatch_queue>" | `_storageQueue` |
| 0x80 | @"PDAIMemory" | `_memory` |
| 0x88 | @"NSArray" | `_calls` |
| 0x90 | @"NSMutableDictionary" | `_toolMedia` |
| 0x98 | @"NSMutableDictionary" | `_refusedImages` |
| 0xa0 | Q | `_callIndex` |
| 0xa8 | Q | `_round` |
| 0xb0 | Q | `_generation` |
| 0xb8 | @"NSString" | `_lastMaintenanceID` |
| 0xc0 | Q | `_contextStart` |
| 0xc8 | @"NSString" | `_handoffFile` |
| 0xd0 | @"NSString" | `_handoffText` |
| 0xd8 | @"NSString" | `_lastStampDay` |
| 0xe0 | @"NSString" | `_lastText` |
| 0xe8 | @? | `_legacyCompletion` |

**property**

| 名称 | attribute |
|---|---|
| `mutableHistory` | `T@"NSMutableArray",&,N,V_mutableHistory` |
| `pendingEvents` | `T@"NSMutableArray",&,N,V_pendingEvents` |
| `pendingAttachments` | `T@"NSMutableArray",&,N,V_pendingAttachments` |
| `dataDirectory` | `T@"NSString",C,N,V_dataDirectory` |
| `historyURL` | `T@"NSURL",&,N,V_historyURL` |
| `session` | `T@"NSURLSession",&,N,V_session` |
| `task` | `T@"NSURLSessionDataTask",&,N,V_task` |
| `storageQueue` | `T@"NSObject<OS_dispatch_queue>",&,N,V_storageQueue` |
| `memory` | `T@"PDAIMemory",&,N,V_memory` |
| `calls` | `T@"NSArray",&,N,V_calls` |
| `toolMedia` | `T@"NSMutableDictionary",&,N,V_toolMedia` |
| `refusedImages` | `T@"NSMutableDictionary",&,N,V_refusedImages` |
| `callIndex` | `TQ,N,V_callIndex` |
| `round` | `TQ,N,V_round` |
| `generation` | `TQ,V_generation` |
| `busy` | `TB,N,V_busy` |
| `wakePending` | `TB,N,V_wakePending` |
| `maintainingData` | `TB,N,V_maintainingData` |
| `lastMaintenanceID` | `T@"NSString",C,N,V_lastMaintenanceID` |
| `contextStart` | `TQ,N,V_contextStart` |
| `handoffFile` | `T@"NSString",C,N,V_handoffFile` |
| `handoffText` | `T@"NSString",C,N,V_handoffText` |
| `lastStampDay` | `T@"NSString",C,N,V_lastStampDay` |
| `lastText` | `T@"NSString",C,N,V_lastText` |
| `legacyCompletion` | `T@?,C,N,V_legacyCompletion` |
| `history` | `T@"NSArray",R,N` |
| `stateProvider` | `T@?,C,N,V_stateProvider` |
| `toolHandler` | `T@?,C,N,V_toolHandler` |
| `deviceToolHandler` | `T@?,C,N,V_deviceToolHandler` |
| `turnStateHandler` | `T@?,C,N,V_turnStateHandler` |
| `interruptionHandler` | `T@?,C,N,V_interruptionHandler` |
| `historyClearedHandler` | `T@?,C,N,V_historyClearedHandler` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0xae5c | `handleDataMaintenanceRequest:` | `v24@0:8@16` |
| 0xc658 | `init` | `@16@0:8` |
| 0xc6bc | `initWithDataDirectory:sessionConfiguration:` | `@32@0:8@16@24` |
| 0xd2bc | `history` | `@16@0:8` |
| 0xd2f0 | `error:code:` | `@32@0:8@16q24` |
| 0xd3b8 | `isConfigured` | `B16@0:8` |
| 0xd4a0 | `stamp:` | `@24@0:8@16` |
| 0xd604 | `sendText:completion:` | `v32@0:8@16@?24` |
| 0xd6d8 | `enqueueEvent:wake:preempt:` | `v32@0:8@16B24B28` |
| 0xd810 | `persistHistory` | `v16@0:8` |
| 0xd934 | `appendPendingEvents` | `v16@0:8` |
| 0xdafc | `startTurn` | `v16@0:8` |
| 0xdc04 | `enqueueUserText:images:` | `v32@0:8@16@24` |
| 0xe48c | `requestRound` | `v16@0:8` |
| 0xfa88 | `sendPreparedRequest:settings:retryBytes:sentImages:endpoint:generation:recovering:` | `v68@0:8@16@24@32@40@48Q56B64` |
| 0x102a0 | `handleMessage:` | `v24@0:8@16` |
| 0x10984 | `recordTool:receipt:` | `v32@0:8@16@24` |
| 0x10b90 | `runNextTool` | `v16@0:8` |
| 0x1219c | `saveImage:` | `@24@0:8@16` |
| 0x12398 | `skipRemaining:` | `v24@0:8@16` |
| 0x12454 | `finish:` | `v24@0:8@16` |
| 0x1269c | `cancel` | `v16@0:8` |
| 0x1280c | `clearHistory` | `v16@0:8` |
| 0x12820 | `performDataMaintenance:path:completion:` | `v40@0:8@16@24@?32` |
| 0x12f38 | `historyURL` | `@16@0:8` |
| 0x12f40 | `setHistoryURL:` | `v24@0:8@16` |
| 0x12f4c | `busy` | `B16@0:8` |
| 0x12f54 | `setBusy:` | `v20@0:8B16` |
| 0x12f5c | `stateProvider` | `@?16@0:8` |
| 0x12f64 | `setStateProvider:` | `v24@0:8@?16` |
| 0x12f6c | `toolHandler` | `@?16@0:8` |
| 0x12f74 | `setToolHandler:` | `v24@0:8@?16` |
| 0x12f7c | `deviceToolHandler` | `@?16@0:8` |
| 0x12f84 | `setDeviceToolHandler:` | `v24@0:8@?16` |
| 0x12f8c | `turnStateHandler` | `@?16@0:8` |
| 0x12f94 | `setTurnStateHandler:` | `v24@0:8@?16` |
| 0x12f9c | `interruptionHandler` | `@?16@0:8` |
| 0x12fa4 | `setInterruptionHandler:` | `v24@0:8@?16` |
| 0x12fac | `historyClearedHandler` | `@?16@0:8` |
| 0x12fb4 | `setHistoryClearedHandler:` | `v24@0:8@?16` |
| 0x12fbc | `mutableHistory` | `@16@0:8` |
| 0x12fc4 | `setMutableHistory:` | `v24@0:8@16` |
| 0x12fd0 | `pendingEvents` | `@16@0:8` |
| 0x12fd8 | `setPendingEvents:` | `v24@0:8@16` |
| 0x12fe4 | `pendingAttachments` | `@16@0:8` |
| 0x12fec | `setPendingAttachments:` | `v24@0:8@16` |
| 0x12ff8 | `dataDirectory` | `@16@0:8` |
| 0x13000 | `setDataDirectory:` | `v24@0:8@16` |
| 0x13008 | `session` | `@16@0:8` |
| 0x13010 | `setSession:` | `v24@0:8@16` |
| 0x1301c | `task` | `@16@0:8` |
| 0x13024 | `setTask:` | `v24@0:8@16` |
| 0x13030 | `storageQueue` | `@16@0:8` |
| 0x13038 | `setStorageQueue:` | `v24@0:8@16` |
| 0x13044 | `memory` | `@16@0:8` |
| 0x1304c | `setMemory:` | `v24@0:8@16` |
| 0x13058 | `calls` | `@16@0:8` |
| 0x13060 | `setCalls:` | `v24@0:8@16` |
| 0x1306c | `toolMedia` | `@16@0:8` |
| 0x13074 | `setToolMedia:` | `v24@0:8@16` |
| 0x13080 | `refusedImages` | `@16@0:8` |
| 0x13088 | `setRefusedImages:` | `v24@0:8@16` |
| 0x13094 | `callIndex` | `Q16@0:8` |
| 0x1309c | `setCallIndex:` | `v24@0:8Q16` |
| 0x130a4 | `round` | `Q16@0:8` |
| 0x130ac | `setRound:` | `v24@0:8Q16` |
| 0x130b4 | `generation` | `Q16@0:8` |
| 0x130bc | `setGeneration:` | `v24@0:8Q16` |
| 0x130c4 | `wakePending` | `B16@0:8` |
| 0x130cc | `setWakePending:` | `v20@0:8B16` |
| 0x130d4 | `maintainingData` | `B16@0:8` |
| 0x130dc | `setMaintainingData:` | `v20@0:8B16` |
| 0x130e4 | `lastMaintenanceID` | `@16@0:8` |
| 0x130ec | `setLastMaintenanceID:` | `v24@0:8@16` |
| 0x130f4 | `contextStart` | `Q16@0:8` |
| 0x130fc | `setContextStart:` | `v24@0:8Q16` |
| 0x13104 | `handoffFile` | `@16@0:8` |
| 0x1310c | `setHandoffFile:` | `v24@0:8@16` |
| 0x13114 | `handoffText` | `@16@0:8` |
| 0x1311c | `setHandoffText:` | `v24@0:8@16` |
| 0x13124 | `lastStampDay` | `@16@0:8` |
| 0x1312c | `setLastStampDay:` | `v24@0:8@16` |
| 0x13134 | `lastText` | `@16@0:8` |
| 0x1313c | `setLastText:` | `v24@0:8@16` |
| 0x13144 | `legacyCompletion` | `@?16@0:8` |
| 0x1314c | `setLegacyCompletion:` | `v24@0:8@?16` |
| 0x13154 | `.cxx_destruct` | `v16@0:8` |

### `PDAIMemory` : ext:_OBJC_CLASS_$_NSObject   (instsize 16, va 0x58838)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | @"NSString" | `_root` |

**property**

| 名称 | attribute |
|---|---|
| `root` | `T@"NSString",R,C,N,V_root` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x1a688 | `initWithRoot:` | `@24@0:8@16` |
| 0x1a924 | `path:` | `@24@0:8@16` |
| 0x1abf8 | `writablePath:error:` | `@32@0:8@16^@24` |
| 0x1b3fc | `prepareWrite:error:` | `B32@0:8@16^@24` |
| 0x1b520 | `files` | `@16@0:8` |
| 0x1b824 | `read:error:` | `@32@0:8@16^@24` |
| 0x1b838 | `imageForHandle:` | `@24@0:8@16` |
| 0x1bb04 | `systemContext` | `@16@0:8` |
| 0x1bccc | `isProtectedFile:` | `B24@0:8@16` |
| 0x1be50 | `protected:` | `B24@0:8@16` |
| 0x1bec4 | `removeGeneratedFiles:` | `B24@0:8^@16` |
| 0x1bed0 | `removeConversationHandoffs:` | `B24@0:8^@16` |
| 0x1bedc | `removeFilesForConversationOnly:error:` | `B28@0:8B16^@20` |
| 0x1c69c | `snapshot:operation:` | `v32@0:8@16@24` |
| 0x1c90c | `write:path:operation:error:` | `B48@0:8@16@24@32^@40` |
| 0x1c9b4 | `lineRange:args:` | `{_NSRange=QQ}32@0:8@16@24` |
| 0x1cadc | `lines:` | `@24@0:8@16` |
| 0x1cb54 | `glob:` | `@24@0:8@16` |
| 0x1cd20 | `executeTool:arguments:` | `@32@0:8@16@24` |
| 0x1ce0c | `run:arguments:` | `@32@0:8@16@24` |
| 0x1e8f8 | `root` | `@16@0:8` |
| 0x1e900 | `.cxx_destruct` | `v16@0:8` |

### `PDChatPromptController` : ext:_OBJC_CLASS_$_UIViewController   (instsize 16, va 0x58888)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | @"UITextView" | `_editor` |

**property**

| 名称 | attribute |
|---|---|
| `editor` | `T@"UITextView",&,N,V_editor` |
| `hash` | `TQ,R` |
| `superclass` | `T#,R` |
| `description` | `T@"NSString",R,C` |
| `debugDescription` | `T@"NSString",?,R,C` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x1e90c | `viewDidLoad` | `v16@0:8` |
| 0x1f648 | `savedTemplate` | `@16@0:8` |
| 0x1f6d0 | `insertVariable:` | `v24@0:8@16` |
| 0x1f7f0 | `resetTemplate` | `v16@0:8` |
| 0x1f848 | `save` | `v16@0:8` |
| 0x1f900 | `textViewDidChange:` | `v24@0:8@16` |
| 0x1f908 | `editor` | `@16@0:8` |
| 0x1f918 | `setEditor:` | `v24@0:8@16` |
| 0x1f92c | `.cxx_destruct` | `v16@0:8` |

### `PDMemoryEditor` : ext:_OBJC_CLASS_$_UIViewController   (instsize 48, va 0x588d8)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | B | `_initialViewportPending` |
| 0x10 | @"PDAIMemory" | `_memory` |
| 0x18 | @"NSString" | `_path` |
| 0x20 | @"NSString" | `_original` |
| 0x28 | @"UITextView" | `_editor` |

**property**

| 名称 | attribute |
|---|---|
| `memory` | `T@"PDAIMemory",&,N,V_memory` |
| `path` | `T@"NSString",C,N,V_path` |
| `original` | `T@"NSString",C,N,V_original` |
| `editor` | `T@"UITextView",&,N,V_editor` |
| `initialViewportPending` | `TB,N,V_initialViewportPending` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x1f940 | `viewDidLoad` | `v16@0:8` |
| 0x1fe70 | `pd_positionInitialText` | `v16@0:8` |
| 0x1ffe0 | `viewDidLayoutSubviews` | `v16@0:8` |
| 0x20028 | `viewDidAppear:` | `v20@0:8B16` |
| 0x20094 | `save` | `v16@0:8` |
| 0x203dc | `memory` | `@16@0:8` |
| 0x203ec | `setMemory:` | `v24@0:8@16` |
| 0x20400 | `path` | `@16@0:8` |
| 0x20410 | `setPath:` | `v24@0:8@16` |
| 0x2041c | `original` | `@16@0:8` |
| 0x2042c | `setOriginal:` | `v24@0:8@16` |
| 0x20438 | `editor` | `@16@0:8` |
| 0x20448 | `setEditor:` | `v24@0:8@16` |
| 0x2045c | `initialViewportPending` | `B16@0:8` |
| 0x2046c | `setInitialViewportPending:` | `v20@0:8B16` |
| 0x2047c | `.cxx_destruct` | `v16@0:8` |

### `PDChatMemoryController` : ext:_OBJC_CLASS_$_UIViewController   (instsize 48, va 0x58928)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | B | `_cleaning` |
| 0x10 | @"PDAIMemory" | `_memory` |
| 0x18 | @"UITableView" | `_table` |
| 0x20 | @"NSArray" | `_files` |
| 0x28 | @"NSArray" | `_protectedFiles` |

**property**

| 名称 | attribute |
|---|---|
| `memory` | `T@"PDAIMemory",&,N,V_memory` |
| `table` | `T@"UITableView",&,N,V_table` |
| `files` | `T@"NSArray",&,N,V_files` |
| `protectedFiles` | `T@"NSArray",&,N,V_protectedFiles` |
| `cleaning` | `TB,N,V_cleaning` |
| `hash` | `TQ,R` |
| `superclass` | `T#,R` |
| `description` | `T@"NSString",R,C` |
| `debugDescription` | `T@"NSString",?,R,C` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x204e4 | `viewDidLoad` | `v16@0:8` |
| 0x20678 | `viewWillAppear:` | `v20@0:8B16` |
| 0x206c0 | `reloadFiles` | `v16@0:8` |
| 0x20850 | `numberOfSectionsInTableView:` | `q24@0:8@16` |
| 0x20858 | `tableView:numberOfRowsInSection:` | `q32@0:8@16q24` |
| 0x208d0 | `tableView:titleForHeaderInSection:` | `@32@0:8@16q24` |
| 0x20930 | `tableView:titleForFooterInSection:` | `@32@0:8@16q24` |
| 0x209d4 | `fileAtIndexPath:` | `@24@0:8@16` |
| 0x20a54 | `canEditFile:` | `B24@0:8@16` |
| 0x20ab0 | `tableView:cellForRowAtIndexPath:` | `@32@0:8@16@24` |
| 0x20d24 | `tableView:didSelectRowAtIndexPath:` | `v32@0:8@16@24` |
| 0x20e24 | `tableView:canEditRowAtIndexPath:` | `B32@0:8@16@24` |
| 0x20eb8 | `tableView:commitEditingStyle:forRowAtIndexPath:` | `v40@0:8@16q24@32` |
| 0x21070 | `confirmCleanup` | `v16@0:8` |
| 0x211e8 | `maintain:path:` | `v32@0:8@16@24` |
| 0x2141c | `memory` | `@16@0:8` |
| 0x2142c | `setMemory:` | `v24@0:8@16` |
| 0x21440 | `table` | `@16@0:8` |
| 0x21450 | `setTable:` | `v24@0:8@16` |
| 0x21464 | `files` | `@16@0:8` |
| 0x21474 | `setFiles:` | `v24@0:8@16` |
| 0x21488 | `protectedFiles` | `@16@0:8` |
| 0x21498 | `setProtectedFiles:` | `v24@0:8@16` |
| 0x214ac | `cleaning` | `B16@0:8` |
| 0x214bc | `setCleaning:` | `v20@0:8B16` |
| 0x214cc | `.cxx_destruct` | `v16@0:8` |

### `PDChatHistoryController` : ext:_OBJC_CLASS_$_UITableViewController   (instsize 32, va 0x58978)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | B | `_cleaning` |
| 0x10 | @"NSArray" | `_rows` |
| 0x18 | Q | `_loadGeneration` |

**property**

| 名称 | attribute |
|---|---|
| `rows` | `T@"NSArray",&,N,V_rows` |
| `loadGeneration` | `TQ,N,V_loadGeneration` |
| `cleaning` | `TB,N,V_cleaning` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x21534 | `viewDidLoad` | `v16@0:8` |
| 0x21658 | `viewWillAppear:` | `v20@0:8B16` |
| 0x216a0 | `reloadHistory` | `v16@0:8` |
| 0x227c0 | `confirmClearHistory` | `v16@0:8` |
| 0x22bac | `tableView:numberOfRowsInSection:` | `q32@0:8@16q24` |
| 0x22be0 | `tableView:titleForFooterInSection:` | `@32@0:8@16q24` |
| 0x22c34 | `tableView:cellForRowAtIndexPath:` | `@32@0:8@16@24` |
| 0x230d4 | `rows` | `@16@0:8` |
| 0x230e4 | `setRows:` | `v24@0:8@16` |
| 0x230f8 | `loadGeneration` | `Q16@0:8` |
| 0x23108 | `setLoadGeneration:` | `v24@0:8Q16` |
| 0x23118 | `cleaning` | `B16@0:8` |
| 0x23128 | `setCleaning:` | `v20@0:8B16` |
| 0x23138 | `.cxx_destruct` | `v16@0:8` |

### `PDPreferences` : ext:_OBJC_CLASS_$_NSObject   (instsize 88, va 0x589c8)

**ivar**

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x8 | B | `_enabled` |
| 0x9 | B | `_interactive` |
| 0xa | B | `_responsive` |
| 0xb | B | `_soundEnabled` |
| 0xc | B | `_stroking` |
| 0xd | B | `_keyboardAvoidanceEnabled` |
| 0x10 | d | `_size` |
| 0x18 | d | `_bottomInset` |
| 0x20 | d | `_keyboardAvoidanceExtra` |
| 0x28 | q | `_framesPerSecond` |
| 0x30 | @"NSString" | `_scheme` |
| 0x38 | @"NSString" | `_outfit` |
| 0x40 | @"NSString" | `_roam` |
| 0x48 | @"NSString" | `_doubleTapAction` |
| 0x50 | @"NSString" | `_longPressAction` |

**property**

| 名称 | attribute |
|---|---|
| `enabled` | `TB,R,N,V_enabled` |
| `interactive` | `TB,R,N,V_interactive` |
| `responsive` | `TB,R,N,V_responsive` |
| `soundEnabled` | `TB,R,N,V_soundEnabled` |
| `stroking` | `TB,R,N,V_stroking` |
| `size` | `Td,R,N,V_size` |
| `bottomInset` | `Td,R,N,V_bottomInset` |
| `keyboardAvoidanceEnabled` | `TB,R,N,V_keyboardAvoidanceEnabled` |
| `keyboardAvoidanceExtra` | `Td,R,N,V_keyboardAvoidanceExtra` |
| `framesPerSecond` | `Tq,R,N,V_framesPerSecond` |
| `scheme` | `T@"NSString",R,C,N,V_scheme` |
| `outfit` | `T@"NSString",R,C,N,V_outfit` |
| `roam` | `T@"NSString",R,C,N,V_roam` |
| `doubleTapAction` | `T@"NSString",R,C,N,V_doubleTapAction` |
| `longPressAction` | `T@"NSString",R,C,N,V_longPressAction` |

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|
| 0x236e8 | `init` | `@16@0:8` |
| 0x23738 | `reload` | `v16@0:8` |
| 0x23b84 | `enabled` | `B16@0:8` |
| 0x23b8c | `interactive` | `B16@0:8` |
| 0x23b94 | `responsive` | `B16@0:8` |
| 0x23b9c | `soundEnabled` | `B16@0:8` |
| 0x23ba4 | `stroking` | `B16@0:8` |
| 0x23bac | `size` | `d16@0:8` |
| 0x23bb4 | `bottomInset` | `d16@0:8` |
| 0x23bbc | `keyboardAvoidanceEnabled` | `B16@0:8` |
| 0x23bc4 | `keyboardAvoidanceExtra` | `d16@0:8` |
| 0x23bcc | `framesPerSecond` | `q16@0:8` |
| 0x23bd4 | `scheme` | `@16@0:8` |
| 0x23bdc | `outfit` | `@16@0:8` |
| 0x23be4 | `roam` | `@16@0:8` |
| 0x23bec | `doubleTapAction` | `@16@0:8` |
| 0x23bf4 | `longPressAction` | `@16@0:8` |
| 0x23bfc | `.cxx_destruct` | `v16@0:8` |

### `PDLocalizationBundle` : ext:_OBJC_CLASS_$_NSObject   (instsize 8, va 0x58a40)

**方法**

| imp | 选择器 | 类型编码 |
|---|---|---|

## 4 C 函数层（**上一版漏了，本轮补上**）

`__symtab` 的 section 1 里除 268 个 ObjC 方法外，还有 **55 个 C 函数**，合计 **33,401 条指令**
——与 ObjC 方法层（32,187 条）几乎等量。上一版清单只统计了方法，属遗漏，这里补齐。

`petdfy-voice` 应用层是 10,062 条指令；`PetDFYPrefs` 合计 **≈ 65,588 条**，即 **6.5 倍**。

### 4.1 按族分组

| 族 | 符号 | 地址范围 | 规模 |
|---|---|---|---|
| 资产子系统（与 voice 同源） | `PDAssetSpecification` / `PDAssetStatePath` / `PDAssetImportDirectory` / `PDAssetImportPath` / `PDAssetSafeRelativePath` / `PDAssetRegularPath` / `PDAssetDownloadURL` | `0x4000`–`0x46d0` | 7 个 / 452 条 |
| AI 请求/响应构造 | `PDAIString` `PDAINumber` `PDAIPreference` `PDAIWritePreferences` `PDAIToolDeclarations` `PDAIVocabulary` `PDAIDefaultEnvironment` `PDAIDefaultPersona` `PDAIOrientation` `PDAIWord` `PDAIParseActions` `PDAIParseScript` `PDAIScriptSeconds` `PDAISelfKeys` `PDAIDirectSettings` `PDAIPromptValues` `PDAIProviderSettings` `PDAIEndpoint` `PDAIEstimatedTokens` `PDAIImageEndpointKey` `PDAIHistoryWithoutImages` `PDAIRequestHasImages` `PDAISentImageIDs` `PDAIContextSinceLastDelivery` `PDAIImageRetryAllowed` `PDAIImageSafeHandoffBoundary` `PDAIRequestBody` `PDAINormalizeResponse` `PDAIHandoffNote` `PDAIHandoffNotice` | `0x1329c`–`0x1a648` | 30 个 / ~18k 条 |
| 密钥与状态存储 | `PDLoadAIAPIKey` `PDHasAIAPIKey` `PDStoreAIAPIKey` `PDLoadDoubaoAPIKey` `PDHasDoubaoAPIKey` `PDStoreDoubaoAPIKey` `PDDoubaoSpeechStatus` `PDStoreDoubaoSpeechStatus` | `0x2314c`–`0x236d0` | 8 个 / ~0.2k 条 |
| 路径与本地化 | `PDResourcePath` `PDDataPath` `PDLocalizedString` | `0x236d0`–`0x23ee4` | 3 个 / ~1.2k 条 |
| 设备工具（权限/提示/结果） | `PDDeviceToolDeclarations` `PDIsDeviceTool` `PDDeviceToolEnabled` `PDEnabledDeviceToolDeclarations` `PDDeviceToolPermissionError` `PDDeviceToolPrompt` `PDDeviceToolResult` | `0x23ee4`–`0x24a00` | 7 个 / ~3k 条 |

### 4.2 归属

- 资产 7 个与 `petdfy-voice` **逐指令同源**（归一化立即数后逐条比对：`PDAssetSpecification` 90/90、`PDAssetStatePath` 6/6、`PDAssetImportDirectory` 3/3、`PDAssetImportPath` 169/169、`PDAssetSafeRelativePath` 127/127、`PDAssetRegularPath` 83/83、`PDAssetDownloadURL` 105/104 前缀全等），直接复用 `src/petdfy-voice/PDAssetImporter.m`，不重写。
- 其余 48 个由 `prefs-ai-cfuncs`（AI 请求层）与 `prefs-misc-cfuncs`（存储/路径/设备工具）并行还原。

### 4.3 规模修正

| 层 | 数量 | 指令 |
|---|---:|---:|
| ObjC 方法 | 268 | 32,187 |
| C 函数 | 55 | 33,401 |
| **合计** | **323** | **≈65,588** |

对照：`petdfy-voice` 应用层 10,062 条 ⇒ `PetDFYPrefs` 是 **6.5 倍**。

## 5 还原完成状态（最终）

| 层 | 目标 | 已实现 | 说明 |
|---|---:|---:|---|
| ObjC 方法 | 264 | **264** | `tools/prefs_audit.py`：缺 0、TODO 0、属性不符 0 |
| C 函数 | 55 | **55** | 48 个在 `src/PetDFYPrefs/`（`PDAIHelpers.m` 30 + `PDSupport.m` 18），7 个资产函数复用 `src/petdfy-voice/PDAssetImporter.m`（逐指令同源） |
| 属性 / ivar | 80 / 67 | 全部 | 二进制 `__objc_property_list` / `__objc_ivar_list` 全量对拍 |
| 源码规模 | — | **43 文件 / 418 KB / 7,414 行** | `src/PetDFYPrefs/` |

### 5.1 资产子系统（7 个函数）

归一化立即数后**逐指令**比对：`PDAssetSpecification` 90/90、`PDAssetStatePath` 6/6、
`PDAssetImportDirectory` 3/3、`PDAssetImportPath` 169/169、`PDAssetSafeRelativePath` 127/127、
`PDAssetRegularPath` 83/83、`PDAssetDownloadURL` 105/104（第 105 条已是下一个函数）→ **7/7 IDENTICAL**。

### 5.2 仍在账上的 `Assumed`（均已在源码就地标注）

| # | 位置 | 内容 |
|---|---|---|
| 1 | `PDAIMemory -imageForHandle:` `mem:` 分支 | 与 `log:` 汇合，返回 `{data,mime}` 而非文件内容（反直觉，需实机验证） |
| 2 | `PDAIMemory -run:arguments:` `move_file` | 「先写目标再回写源」的顺序为推断 |
| 3 | `PDPreferences -reload` | `Size ∈ [72,220]`、`FPS` 阈值 44/99 的上下界角色分配 |
| 4 | `PDChatService -runNextTool` | 内联图片分支的 block 捕获 |
| 5 | `PDChatService -requestRound` | token 预算寄存器映射（128000/64000/0.85/2048 常量已核） |
| 6 | `PDAIRequestBody` 0x1869c | 「后续图片补一条 user 消息」的回退循环边界 |
| 7 | `PDAIRequestBody` 0x180c8 | synthetic reasoning 的嵌套前置条件顺序 |
| 8 | `PDAIImageSafeHandoffBoundary` 0x173e8 | `csel` 极性（取最后一条 `_handoff` 为假的 user） |
| 9 | `PDSupport` 0x23d84 / 0x24bf4 / 0x534a0 | `bundleForClass:` 实参形态、`numberWithInt` vs `numberWithBool`、字典字段布局 |
| 10 | `Info.plist` 的 `CFBundleIdentifier` / `NSPrincipalClass` | 压缩包无 Info.plist，按惯例推定 |

### 5.3 未做的

- **编译 / 真机：NOT RUN**（本机 Windows 无 clang / iPhoneOS SDK）。
- UI 视觉验证（布局常量已逐条核对，但没有真机截图比对）。

