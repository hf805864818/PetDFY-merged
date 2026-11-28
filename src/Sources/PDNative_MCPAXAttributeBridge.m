//
//  PDNative_MCPAXAttributeBridge.m
//  PetDFY
//
//  Accessibility（AX）桥：不链接私有框架，全部通过 dlopen/dlsym 在运行时绑定；
//  对外提供“按点取元素 + 属性批量读取 + 快照探测”三组能力。
//
//  二进制证据
//    image base  : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表      : out/method-table-all.md → 27 条（全 `-`）
//    区间        : 0x8c74c .. 0x94048（7743 条指令）
//    instanceSize: 8（0x08）—— 无实例 ivar；运行时绑定结果缓存在
//                  静态结构 0x11c728（首字为已绑定标志，+0x18 为另一标志）
//
//  区间内静态实体
//    0x8d9e0 / 0x8da54  诊断字典组装（命中测试用；两条路径同名不同参）
//    0x917f4            XC 属性名规范化（NSString → 私有属性名）
//    0x91e2c            直接属性名规范化
//    0x921e8            参数化属性名规范化
//    0x92310            快照选项规范化（normalizedOptions）
//    0x92884            快照摘要（snapshotSource 判定）
//    0x930f4            子元素包装（{element,pid} → 字典）
//    0x93658            PDAXBindSymbols(void *handle, NSString *name)：把 46 个 dlsym 结果填进 0x11c718
//
//  AX 属性名（Observed，逐字常量；位于 0x91440 段的 isEqualToString: 链）
//    XC 私有属性：automationType, children, AXChildren, childrenCount, elementBaseType,
//      elementType, frame, AXFrame, horizontalSizeClass, identifier, AXIdentifier,
//      isRemoteElement, isUserInteractionEnabled, isVisible, label, AXLabel,
//      localizedStringKey, localizationBundleID, localizationBundlePath,
//      localizedStringTableName, mainWindow, parent, placeholderValue, traits, AXTraits,
//      userTestingElements, userTestingSnapshot, value, AXValue, visibleFrame,
//      viewControllerClassName, viewControllerTitle, verticalSizeClass,
//      windowContextId, windowDisplayId
//    直接属性（0x91c68 段）：visibleElements, explorerElements, elementsWithSemanticContext,
//      nativeFocusableElements, siriContentNativeFocusableElements,
//      siriContentElementsWithSemanticContext, remoteParent, application, remoteApplication,
//      windowContextId, path, visibleFrame, visiblePoint, elementParent, windowDisplayId,
//      containerTypes, focusableFrameForZoom, url, userInputLabels, containerType,
//      centerPoint, privateChildren
//    参数化属性（0x92130 段）：childrenWithRange, userTestingSnapshotParameterized
//
//  符号修正（跨单元一致性，2026-11-28）
//    本类 27 条全部是实例方法（sign 全为 -），无需改动；
//    仅把 `[PDNative_MCPLogger.sharedInstance isDebugLoggingEnabled]` 改为
//    `[PDNative_MCPLogger isDebugLoggingEnabled]`（对方是类方法）。
//
//  标记：[0xADDR] = 指令地址；Assumed = 语义推断；NOT RUN = 未运行
//        直调 0xADDR = 已落到具名 dlsym 槽/静态函数；本文件 CALL 0 处（原 4 处已定案）
//

#import "PDNative_MCPAXAttributeBridge.h"
#import "PDNative_MCPLogger.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// AX 错误码（-errorStringForAXError: 的 switch，0x90330 段逐字）
static NSString *const kPDAXErrorStrings[] = {
    @"success",                 // 0
    @"failure",                 // -25200 系列，按 -errorStringForAXError: 的顺序
    @"illegal argument",
    @"invalid UI element",
    @"cannot complete",
    @"attribute unsupported",
    @"not implemented",
    @"error %d",
    @"no value",
};

// 运行时绑定缓存（已定案 0x93cd4：真基址是 0x11c718，不是 0x11c728）
//   +0x00        dlsym 句柄                         0x93cd4 stp x20, …
//   +0x08..+0x1a8 46 个入口指针，顺序见 kPDAXSymbols  0x93cd8..0x93e30
//   “已绑定”是另一个独立字节 0x11c710                0x935f8 strb w8, [x9, #0x710]
//   已绑定判据 = [0x11c728]（CreateApplication）&& [0x11c740]（CopyAttributeValue）都非零
//                                                   0x93520 ldr x8,[x22] / 0x93524 ldr x9,[x22,#0x18]
typedef struct PDAXRuntime {
    BOOL bound;                 // 0x11c710（源级并入结构，二进制里是独立全局）
} PDAXRuntime;
static PDAXRuntime gAXRuntime;

// 46 个 dlsym 入口的名字与相对 0x11c718 的偏移（0x93688..0x93c84 逐条读出）
typedef struct { const char *name; unsigned int off; } PDAXSymbol;
static const PDAXSymbol kPDAXSymbols[] = {
    { "AXValueCreate",                              0x008 },
    { "AXUIElementCreateApplication",               0x010 },
    { "_AXUIElementCreateAppElementWithPid",        0x018 },
    { "AXUIElementCreateSystemWide",                0x020 },
    { "AXUIElementCopyAttributeValue",              0x028 },
    { "AXUIElementCopyParameterizedAttributeValue", 0x030 },
    { "AXUIElementCopyMultipleAttributeValues",     0x038 },
    { "AXUIElementCopyAttributeNames",              0x040 },
    { "AXUIElementCopyElementAtPosition",           0x048 },
    { "AXUIElementCopyElementAtPositionWithParams", 0x050 },
    { "AXUIElementCopyApplicationAtPosition",       0x058 },
    { "AXUIElementCopyApplicationAndContextAtPosition", 0x060 },
    { "AXUIElementSetMessagingTimeout",             0x068 },
    { "AXUIElementCopyElementWithParameters",       0x070 },
    { "AXUIElementCopyElementUsingContextIdAtPosition", 0x078 },
    { "AXUIElementCopyElementUsingDisplayIdAtPosition", 0x080 },
    { "AXUIElementGetPid",                          0x088 },
    { "_AXAddAssociatedPid",                        0x090 },
    { "_AXIsPidAssociated",                         0x098 },
    { "_AXIsPidAssociatedWithDisplayType",          0x0a0 },
    { "__AXSetRequestingClient",                    0x0a8 },
    { "_AXOverrideRequestingClientType",            0x0b0 },
    { "kAXXCAttributeAutomationType",               0x0b8 },
    { "kAXXCAttributeChildren",                     0x0c0 },
    { "kAXXCAttributeChildrenCount",                0x0c8 },
    { "kAXXCAttributeElementBaseType",              0x0d0 },
    { "kAXXCAttributeElementType",                  0x0d8 },
    { "kAXXCAttributeFrame",                        0x0e0 },
    { "kAXXCAttributeHorizontalSizeClass",          0x0e8 },
    { "kAXXCAttributeIdentifier",                   0x0f0 },
    { "kAXXCAttributeIsRemoteElement",              0x0f8 },
    { "kAXXCAttributeIsUserInteractionEnabled",     0x100 },
    { "kAXXCAttributeIsVisible",                    0x108 },
    { "kAXXCAttributeLabel",                        0x110 },
    { "kAXXCAttributeLocalizedStringKey",           0x118 },
    { "kAXXCAttributeLocalizationBundleID",         0x120 },
    { "kAXXCAttributeLocalizationBundlePath",       0x128 },
    { "kAXXCAttributeLocalizedStringTableName",     0x130 },
    { "kAXXCAttributeMainWindow",                   0x138 },
    { "kAXXCAttributeParent",                       0x140 },
    { "kAXXCAttributePlaceholderValue",             0x148 },
    { "kAXXCAttributeTraits",                       0x150 },
    { "kAXXCAttributeUserTestingElements",          0x158 },
    { "kAXXCAttributeUserTestingSnapshot",          0x160 },
    { "kAXXCAttributeValue",                        0x168 },
    { "kAXXCAttributeVisibleFrame",                 0x170 },
    { "kAXXCAttributeViewControllerClassName",      0x178 },
    { "kAXXCAttributeViewControllerTitle",          0x180 },
    { "kAXXCAttributeVerticalSizeClass",            0x188 },
    { "kAXXCAttributeWindowContextId",              0x190 },
    { "kAXXCAttributeWindowDisplayId",              0x198 },
    { "kAXXCParameterizedAttributeChildrenWithRange", 0x1a0 },
    { "kAXXCParameterizedAttributeUserTestingSnapshotParameterized", 0x1a8 },
};

// 具名入口（PDAXBindSymbols 按上表逐个填入；0x11c718 + off）
typedef AXError (*PDAXAddAssociatedPidFn)(pid_t, pid_t, int);
static void *gAXHandle;                                   // +0x00
static void *gAXValueCreate;                              // +0x08
static void *gAXCreateApplication;                        // +0x10
static void *gAXCreateSystemWide;                         // +0x20
static void *gAXCopyAttributeValue;                       // +0x28
static void *gAXCopyParameterizedAttributeValue;          // +0x30
static void *gAXCopyMultipleAttributeValues;              // +0x38
static void *gAXCopyElementWithParameters;                // +0x70
static void *gAXCopyElementUsingContextIdAtPosition;      // +0x78
static void *gAXGetPid;                                   // +0x88
static PDAXAddAssociatedPidFn gAXAddAssociatedPid;         // +0x90
static BOOL (*gAXIsPidAssociated)(pid_t);                  // +0x98
static BOOL (*gAXIsPidAssociatedWithDisplayType)(pid_t, int); // +0xa0
static void *gAXSetMessagingTimeout;                      // +0x68

// 已定案 0x8ca90..0x8ca9c 与 0x8e4f0..0x8e508（槽 +0x78）——原「6 个平铺形参」是对的，
//   但顺序与形参类型此前写错。两处调用点的寄存器用法完全同构：
//     0x8ca80 str xzr,[sp,#0x18]   → out = NULL
//     0x8ca84 fcvt s0, d9          → s0 = point.x   （0x8c9c4 `fmov d9,d0`，d0 是 CGPoint 的 x）
//     0x8ca88 fcvt s1, d8          → s1 = point.y   （0x8c9c0 `fmov d8,d1`）
//     0x8ca8c add  x2, sp, #0x18   → x2 = &out
//     0x8ca90 mov  x0, x22         → x0 = element
//     0x8ca94 mov  x1, x21         → x1 = contextId
//     0x8ca98 mov  w3, #0          → w3 = option（此点恒为常量 0）
//     0x8ca9c blr  x8              → fn(element, ctxId, &out, option, x, y)
//   另一处 0x8e4e8 `bl intValue` → x3 = option，取自常量数组 0x107ea0 = {0,1,2}（0x8e4d8 逐项枚举），
//   随后 0x8e500 `fmov s0,s10` / 0x8e504 `fmov s1,s11`（s10/s11 由 0x8dc4c/0x8dc50 从 d8=x、d9=y 取得）。
//   两处都证明：x/y 走 s0/s1（float），且 s0 恒为 x、s1 恒为 y。
typedef AXError (*PDAXCopyElementUsingContextIdAtPositionFn)(AXUIElementRef element,
                                                            unsigned int contextId,
                                                            CFTypeRef *out,
                                                            int option,
                                                            float x,
                                                            float y);

static AXError PDAXCopyElementUsingContextId(AXUIElementRef element,
                                             unsigned int contextId,
                                             CFTypeRef *out,
                                             int option,
                                             float x,
                                             float y) {
    PDAXCopyElementUsingContextIdAtPositionFn fn =
        (PDAXCopyElementUsingContextIdAtPositionFn)gAXCopyElementUsingContextIdAtPosition;
    if (!fn) { return kAXErrorFailure; }
    return fn(element, contextId, out, option, x, y);
}

// 已定案 0x8dd88..0x8dd98 与 0x8dfbc（槽 +0x30 = AXUIElementCopyParameterizedAttributeValue）
//   —— 段 1/段 2 的“参数化查询”是 4 个实参，不是 5 个：
//     段 1：x0 = seed（系统级元素）、x1 = 0x16573（0x8dd8c `mov w1,#0x6573` + 0x8dd90 `movk w1,#1,lsl#16`）、
//           x2 = 常量数组 @[AXValue(point), @(displayId)]（0x8dd50 `arrayWithObjects:count:` + w3=2）、x3 = &out
//     段 2：x1 = 0x16574（0x8dfac `add x1,x9,#1`，x9 仍是 0x16573）、
//           x2 = @{ @"contextId" : @(ctxId) }（0x8df50 CF "contextId" + 0x8df88 单键字典）、x3 = &out
//   两个 x1 都是**数值型参数化属性 ID**，本机无法从二进制恢复其符号名 → 下面用常量占位并标 Assumed。
#define kPDAXParamAttrPointToContext   0x16573u   // Assumed：符号名未定，仅寄存器值 Observed
#define kPDAXParamAttrContextToPid     0x16574u   // Assumed：同上

typedef AXError (*PDAXCopyNumericParameterizedFn)(AXUIElementRef element,
                                                 unsigned int attributeId,
                                                 CFTypeRef parameter,
                                                 CFTypeRef *out);

static AXError PDAXCopyNumericParameterized(AXUIElementRef element,
                                            unsigned int attributeId,
                                            CFTypeRef parameter,
                                            CFTypeRef *out) {
    PDAXCopyNumericParameterizedFn fn =
        (PDAXCopyNumericParameterizedFn)gAXCopyParameterizedAttributeValue;
    if (!fn) { return kAXErrorFailure; }
    return fn(element, attributeId, parameter, out);
}

static void PDAXBindRuntimeIfNeeded(void);      // 0x93388 段
static NSDictionary *PDAXDiagnostics(NSString *stage, NSDictionary *fields);

@implementation PDNative_MCPAXAttributeBridge

#pragma mark - 运行时可用性

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge ensureRuntimeAvailable:]  imp=0x8cb4c insns=32
// ---------------------------------------------------------------------------
- (BOOL)ensureRuntimeAvailable:(NSString **)error {
    static dispatch_once_t once;                                        // [0x8cbc4] dispatch_once
    dispatch_once(&once, ^{ PDAXBindRuntimeIfNeeded(); });
    if (!gAXRuntime.bound) {                                            // [0x8cb74] cbz
        if (error) { *error = @"Direct AX runtime unavailable"; }        // 文案 0x…: Direct AX runtime unavailable
        return NO;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge performOnMainThreadSync:]  imp=0x8cbcc insns=22
// ---------------------------------------------------------------------------
- (void)performOnMainThreadSync:(dispatch_block_t)block {
    if (!block) { return; }                                             // [0x8cbdc] cbz
    if ([NSThread isMainThread]) {                                      // [0x8cbec]
        block();
        return;
    }
    dispatch_sync(dispatch_get_main_queue(), block);                     // [0x8cc10]
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge ensureAssociationWithRemotePid:]  imp=0x8cc24 insns=84
//   前台化：把 AX 客户端与目标 pid 建立关联，并按需把目标进程提到前台。
// ---------------------------------------------------------------------------
- (void)ensureAssociationWithRemotePid:(int)pid {
    if (pid < 1) { return; }                                            // [0x8cc3c] cmp w2,#1 / b.lt
    // 已定案 0x8cc4c: ldp x9,x8,[0x11c7a8] → _AXAddAssociatedPid / _AXIsPidAssociated 都必须已绑定
    if (!gAXAddAssociatedPid || !gAXIsPidAssociated) { return; }        // [0x8cc58] b.eq
    pid_t selfPid = getpid();                                           // [0x8cc60]
    BOOL pidAssoc  = gAXIsPidAssociated(pid);                           // 已定案 0x8cc78: blr _AXIsPidAssociated(pid)
    BOOL selfAssoc = gAXIsPidAssociated(selfPid);                       // 已定案 0x8cc88: blr _AXIsPidAssociated(self)
    // 已定案 0x8cca4: blr _AXIsPidAssociatedWithDisplayType(pid, 1)
    BOOL pidAssocDisp = gAXIsPidAssociatedWithDisplayType
                          ? gAXIsPidAssociatedWithDisplayType(pid, 1) : selfAssoc;
    // 已定案 0x8ccc0: blr _AXIsPidAssociatedWithDisplayType(self, 1)
    BOOL selfAssocDisp = gAXIsPidAssociatedWithDisplayType
                          ? gAXIsPidAssociatedWithDisplayType(selfPid, 1) : selfAssoc;
    // 已定案 0x8ccdc: _AXAddAssociatedPid(self, pid, 1)   —— displayType 1 方向
    if (!pidAssocDisp)  { gAXAddAssociatedPid(selfPid, pid, 1); }
    // 已定案 0x8cd14: _AXAddAssociatedPid(pid, self, 1)
    if (!selfAssocDisp) { gAXAddAssociatedPid(pid, selfPid, 1); }
    // 已定案 0x8cd2c: _AXAddAssociatedPid(self, pid, 0)   —— displayType 0 方向
    if (!pidAssoc)      { gAXAddAssociatedPid(selfPid, pid, 0); }
    // 已定案 0x8cd58: _AXAddAssociatedPid(pid, self, 0)（尾调用 br x3）
    if (!selfAssoc)     { gAXAddAssociatedPid(pid, selfPid, 0); }
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copySystemWideElement]  imp=0x9026c insns=23
// ---------------------------------------------------------------------------
- (AXUIElementRef)copySystemWideElement {
    if (![self ensureRuntimeAvailable:NULL]) { return NULL; }            // [0x9026c]
    // 已定案 0x9028c: ldr x8,[0x11c738] = 槽 +0x20 AXUIElementCreateSystemWide；cbz 则返回 NULL
    if (!gAXCreateSystemWide) { return NULL; }                           // [0x90290] cbz x8
    AXUIElementRef element = ((AXUIElementRef (*)(void))gAXCreateSystemWide)();
    // 已定案 0x902a4: ldr x8,[0x11c780] = 槽 +0x68 AXUIElementSetMessagingTimeout(element, 0.25)
    if (element && gAXSetMessagingTimeout) {                             // [0x902a8] cbz x8
        ((AXError (*)(AXUIElementRef, float))gAXSetMessagingTimeout)(element, 0.25f); // [0x902ac] fmov s0,#0.25
    }
    return element;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge getPid:fromElement:]  imp=0x902c8 insns=26
// ---------------------------------------------------------------------------
- (BOOL)getPid:(int *)outPid fromElement:(AXUIElementRef)element {
    if (!element || !outPid) { return NO; }                              // 0x902c8
    pid_t pid = 0;
    AXError err = AXUIElementGetPid(element, &pid);
    if (err != kAXErrorSuccess) { return NO; }
    *outPid = (int)pid;
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge errorStringForAXError:]  imp=0x90330 insns=48
// ---------------------------------------------------------------------------
- (NSString *)errorStringForAXError:(int)code {
    switch (code) {
        case 0:      return @"success";
        case -25200: return @"failure";
        case -25201: return @"illegal argument";
        case -25202: return @"invalid UI element";
        case -25203: return @"cannot complete";
        case -25204: return @"attribute unsupported";
        case -25205: return @"not implemented";
        case -25206: return @"no value";
        default:     return [NSString stringWithFormat:@"error %d", code]; // [0x903…]
    }
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyApplicationElementForPid:error:]
//   imp=0x8cd74 insns=51
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyApplicationElementForPid:(int)pid error:(NSString **)error {
    if (![self ensureRuntimeAvailable:error]) { return NULL; }            // [0x8cd94]
    // 已定案 0x8cd9c: cmp w21,#1 / b.lt → pid < 1 才算非法入参（不是 pid <= 0 的“校验后建元素”）
    if (pid < 1) {
        if (error) { *error = @"AX create_application unavailable"; }
        return NULL;
    }
    AXUIElementRef element = AXUIElementCreateApplication((pid_t)pid);
    if (!element) {
        if (error) {
            *error = [NSString stringWithFormat:@"AX create_application failed for PID %d", pid];
        }
        return NULL;
    }
    return element;
}

#pragma mark - 命中测试

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyBoundedHitAtPoint:application:contextId:expectedPid:error:]
//   imp=0x8c994 insns=110
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyBoundedHitAtPoint:(CGPoint)point
                            application:(AXUIElementRef)application
                              contextId:(unsigned int)contextId
                            expectedPid:(int)expectedPid
                                  error:(NSString **)error
{
    if ([NSThread isMainThread] || !application || contextId == 0) {      // [0x8c9cc] 系列判断
        if (error) {
            *error = @"Native AX hit test requires a background query and valid target context";
        }
        return NULL;
    }
    if (![self ensureRuntimeAvailable:error]) { return NULL; }            // [0x8ca3c]
    AXUIElementRef hit = NULL;
    // 直调 0x8c9d4..0x8ca9c：按 contextId 取元素（参数化）。option 在这一处恒为 0（0x8ca98 `mov w3,#0`）。
    AXError err = PDAXCopyElementUsingContextId(application, contextId, (CFTypeRef *)&hit,
                                                /*option*/0, (float)point.x, (float)point.y);
    if (err != kAXErrorSuccess || !hit) {
        if (error) {
            *error = [NSString stringWithFormat:
                      @"Native AX hit test failed (%d) or returned an unverified PID; no retry", (int)err];
        }
        return NULL;
    }
    int pid = 0;
    if (expectedPid != 0 && (![self getPid:&pid fromElement:hit] || pid != expectedPid)) {
        CFRelease(hit);                                                   // [0x8cae0]
        if (error) { *error = @"Native AX context hit test unavailable"; }
        return NULL;
    }
    return hit;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyContextBoundApplicationElementForPid:diagnostics:error:]
//   imp=0x8ce40 insns=828
// [0x8cfd0]  insn#100
// [0x8d160]  insn#200
// [0x8d2f0]  insn#300
// [0x8d480]  insn#400
// [0x8d610]  insn#500
// [0x8d7a0]  insn#600
// [0x8d930]  insn#700
// [0x8dac0]  insn#800
//   依次尝试种子：system_wide / springboard_app / target_app，再按 contextId 探测。
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyContextBoundApplicationElementForPid:(int)pid
                                              diagnostics:(NSMutableArray *)diagnostics
                                                    error:(NSString **)error
{
    if (![self ensureRuntimeAvailable:error]) {
        if (error) { *error = @"Context-bound application probe unavailable"; }
        return NULL;
    }
    NSMutableArray *seeds = [NSMutableArray array];                       // [0x8ce…] array
    AXUIElementRef systemWide = [self copySystemWideElement];              // 段内 copySystemWideElement
    if (systemWide) {
        [seeds addObject:@{ @"name": @"system_wide", @"element": (__bridge id)systemWide }];
        CFRelease(systemWide);
    }
    AXUIElementRef springboard = [self copyApplicationElementForPid:getpid() error:NULL];
    if (springboard) {
        [seeds addObject:@{ @"name": @"springboard_app", @"element": (__bridge id)springboard }];
        CFRelease(springboard);
    }
    AXUIElementRef target = [self copyApplicationElementForPid:pid error:NULL];
    if (target) {
        [seeds addObject:@{ @"name": @"target_app", @"element": (__bridge id)target }];
        CFRelease(target);
    }
    if (!seeds.count) {
        if (error) { *error = @"No AX seed available for context-bound application probe"; }
        return NULL;
    }
    // ---- 探测点：屏幕九宫格（CGRectIsEmpty / CGRectGetMidX …） ----
    CGRect screen = [UIScreen mainScreen].bounds;
    NSMutableArray *points = [NSMutableArray array];
    if (!CGRectIsEmpty(screen)) {
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(screen),
                                                               CGRectGetMidY(screen))]];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(screen),
                            CGRectGetMinY(screen) + CGRectGetHeight(screen) * 0.25)]];
        [points addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(screen),
                            CGRectGetMinY(screen) + CGRectGetHeight(screen) * 0.75)]];
    }
    if (!points.count) {
        if (error) { *error = @"No probe points available for context-bound application probe"; }
        return NULL;
    }
    for (NSDictionary *seed in seeds) {
        for (NSValue *value in points) {
            CGPoint point = value.CGPointValue;
            AXUIElementRef element = NULL;
            unsigned int contextId = 0;
            // 直调 0x8d9e0：AXUIElementCopyApplicationAndContextAtPosition
            AXError err = AXUIElementCopyApplicationAndContextAtPosition(
                              (AXUIElementRef)seed[@"element"], point.x, point.y,
                              &element, &contextId);
            if (err != kAXErrorSuccess || !element) {
                [diagnostics addObject:PDAXDiagnostics(@"context_bound_application_probe",
                    @{ @"api": @"AXUIElementCopyApplicationAtPosition",
                       @"axError": @(err),
                       @"contextId": @(contextId),
                       @"error": [self errorStringForAXError:err] })];
                continue;
            }
            int hitPid = 0;
            [self getPid:&hitPid fromElement:element];
            if (pid == 0 || hitPid == pid) {
                if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                    NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
                          @"[AXBridge] Context-bound application probe succeeded via %@ point=(%.1f,%.1f) ",
                          seed[@"name"], point.x, point.y]);
                }
                return element;
            }
            CFRelease(element);
            [diagnostics addObject:PDAXDiagnostics(@"context_bound_application_probe",
                @{ @"api": @"AXUIElementCopyApplicationAndContextAtPosition",
                   @"point": [NSString stringWithFormat:@"%@@(%.0f,%.0f)=pid:%d",
                                 seed[@"name"], point.x, point.y, hitPid],
                   @"resolvedPid": @(hitPid),
                   @"contextId": @(contextId) })];
        }
    }
    if (error) { *error = @"Context-bound application probe returned no matching app element"; }
    return NULL;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyContextChainHitElementAtPoint:expectedPid:diagnostics:error:]
//   imp=0x8db30 insns=2016（本文件最大）
// [0x8dcc0]  insn#100
// [0x8de50]  insn#200
// [0x8dfe0]  insn#300
// [0x8e170]  insn#400
// [0x8e300]  insn#500
// [0x8e490]  insn#600
// [0x8e620]  insn#700
// [0x8e7b0]  insn#800
// [0x8e940]  insn#900
// [0x8ead0]  insn#1000
// [0x8ec60]  insn#1100
// [0x8edf0]  insn#1200
// [0x8ef80]  insn#1300
// [0x8f110]  insn#1400
// [0x8f2a0]  insn#1500
// [0x8f430]  insn#1600
// [0x8f5c0]  insn#1700
// [0x8f750]  insn#1800
// [0x8f8e0]  insn#1900
// [0x8fa70]  insn#2000
//
//   三段探测链（每段都在 diagnostics 里留一条 stage 记录）：
//     point_to_context  → context_to_pid → copyElementAtPoint:usingKnownContextId:…（段 3）
//     create_application（拿不到 context 归属时回落）
//     workspace_context_probe（_sharedWorkspaceIfExists / crs_applicationBundleIdentifier）
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyContextChainHitElementAtPoint:(CGPoint)point
                                        expectedPid:(int)expectedPid
                                        diagnostics:(NSMutableArray *)diagnostics
                                              error:(NSString **)error
{
    if (![self ensureRuntimeAvailable:error]) { return NULL; }
    // ---- 段 1：point → context ----
    for (NSNumber *display in PDRecon_displays()) {
        unsigned int displayId = display.unsignedIntValue;
        AXUIElementRef seed = AXUIElementCreateSystemWide();             // 直调 0x8d9e0 前置
        AXValueRef pointValue = AXValueCreate(kAXValueCGPointType, &point);
        unsigned int contextId = 0;
        AXError err = kAXErrorFailure;
        // 段 1：point→context 走槽 +0x30 的 4 参参数化查询（不是槽 +0x78 的 6 参调用）。
        //   0x8dd7c `ldr x8,[0x11c748]`（+0x30）→ 0x8dd88..0x8dd98 `blr x8`：
        //     x0 = seed（0x8dd88 `mov x0,x21`，x21 由 0x8dce0 的 create-seed 得到）
        //     x1 = 0x16573（0x8dd8c `mov w1,#0x6573` / 0x8dd90 `movk w1,#1,lsl#16`）
        //     x2 = @[ AXValue(point), @(displayId) ]（0x8dd1c `valueWithCGPoint:` + 0x8dd40
        //          `numberWithUnsignedInt:` + 0x8dd60 `arrayWithObjects:count:` w3=2）
        //     x3 = &out（0x8dd84 `add x3,sp,#0x240`）
        if (gAXCopyParameterizedAttributeValue != NULL) {                  // 已定案：槽 +0x30（0x11c748）
            CFTypeRef out = NULL;
            CFTypeRef params[2] = { (CFTypeRef)pointValue, (__bridge CFTypeRef)@(displayId) };  // 见上 x2
            CFArrayRef paramArray = CFArrayCreate(kCFAllocatorDefault,
                                                  (const void **)params, 2, &kCFTypeArrayCallBacks);
            err = PDAXCopyNumericParameterized(seed, kPDAXParamAttrPointToContext,
                                               paramArray, &out);
            if (out) {
                // 0x8ddb8 `respondsToSelector:` + 0x8ddd4 `unsignedIntValue` → 结果是 NSNumber
                if (CFGetTypeID(out) == CFNumberGetTypeID()) {
                    contextId = (unsigned int)[(__bridge NSNumber *)out unsignedIntValue];
                }
                CFRelease(out);
            }
            if (paramArray) { CFRelease(paramArray); }
        } else {
            [diagnostics addObject:PDAXDiagnostics(@"point_to_context",
                @{ @"stage": @"point_to_context",
                   @"error": @"point->context parameterized query unavailable" })];
        }
        if (err != kAXErrorSuccess || contextId == 0) {
            [diagnostics addObject:PDAXDiagnostics(@"point_to_context",
                @{ @"displayId": @(displayId), @"point": NSStringFromCGPoint(point),
                   @"contextId": @(contextId),
                   @"error": [self errorStringForAXError:err] })];
            if (pointValue) { CFRelease(pointValue); }
            if (seed) { CFRelease(seed); }
            continue;
        }
        if (pointValue) { CFRelease(pointValue); }
        if (seed) { CFRelease(seed); }
        // ---- 段 2：context → pid ----
        //   0x8df9c..0x8dfbc 同一条槽 +0x30，属性 ID = 0x16574（0x8dfac `add x1,x9,#1`，x9 = 0x16573），
        //   参数是单键字典 @{ @"contextId" : @(ctxId) }（0x8df50 CF "contextId" / 0x8df88 w4=1）。
        AXUIElementRef systemWide = [self copySystemWideElement];
        pid_t pid = 0;
        err = kAXErrorFailure;
        if (gAXCopyParameterizedAttributeValue != NULL) {
            CFTypeRef out = NULL;
            CFDictionaryRef paramDict = (__bridge_retained CFDictionaryRef)
                @{ @"contextId" : @(contextId) };
            err = PDAXCopyNumericParameterized(systemWide, kPDAXParamAttrContextToPid,
                                               paramDict, &out);
            if (out) {
                // 0x8dfdc `respondsToSelector:` + 0x8dfec `intValue`，且 0x8dff4 `cmp w0,#0` / 0x8dff8 `b.le`
                if (CFGetTypeID(out) == CFNumberGetTypeID()) {
                    int v = (int)[(__bridge NSNumber *)out intValue];
                    if (v > 0) { pid = (pid_t)v; }
                }
                CFRelease(out);
            }
            if (paramDict) { CFRelease(paramDict); }
        }
        if (err != kAXErrorSuccess || pid == 0) {
            [diagnostics addObject:PDAXDiagnostics(@"context_to_pid",
                @{ @"stage": @"context_to_pid", @"displayId": @(displayId),
                   @"contextId": @(contextId),
                   @"error": [self errorStringForAXError:err] })];
        } else if (expectedPid != 0 && pid != expectedPid) {
            [diagnostics addObject:PDAXDiagnostics(@"context_to_pid",
                @{ @"stage": @"context_to_pid", @"displayId": @(displayId),
                   @"contextId": @(contextId), @"resolvedPid": @(pid),
                   @"expectedPid": @(expectedPid), @"error": @"pid_mismatch" })];
        }
        if (systemWide) { CFRelease(systemWide); }
        // ---- 段 3：交给本类的“已知 contextId 命中测试” ----
        //   0x8fab0 `copyElementAtPoint:usingKnownContextId:expectedPid:diagnostics:error:`
        //   5 个形参（type encoding `^{__AXUIElement=}56@0:8{CGPoint=dd}16I32i36^@40^@48`）。
        //   注：0x8e548 的 "copyElementUsingContextIdAtPosition" 已定案为 diagnostics 的 stage 串
        //   （0x8e548 与 0x8e558 的 "stage" 成对写入字典），真实调用走 0x11c790（槽 +0x78）：
        //   0x8e4e4 ldr x20,[x8,#0x790] / 0x8e508 blr x20 —— 按静态调用还原是正确的。
        AXUIElementRef hit = [self copyElementAtPoint:point
                                usingKnownContextId:contextId
                                         expectedPid:expectedPid
                                         diagnostics:diagnostics
                                               error:error];
        if (hit) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
                      @"[AXBridge] Context-chain hit-test succeeded point=(%.1f,%.1f) display=%u ctx=%u",
                      point.x, point.y, displayId, contextId]);
            }
            return hit;
        }
        [diagnostics addObject:PDAXDiagnostics(@"copyElementUsingContextIdAtPosition",
            @{ @"displayId": @(displayId), @"point": NSStringFromCGPoint(point),
               @"stage": @"copyElementUsingContextIdAtPosition",
               @"contextId": @(contextId), @"resolvedPid": @(pid),
               @"axError": @((int)kAXErrorFailure),
               @"error": [self errorStringForAXError:kAXErrorFailure] })];
    }
    // ---- 段 4：workspace 上下文探测（_sharedWorkspaceIfExists / crs_applicationBundleIdentifier） ----
    // 已定案 0x8e96c: objc_getClass("FBSWorkspace")；"_sharedWorkspaceIfExists" 是 selector 串
    //   （0x8e97c NSSelectorFromString，fallback 0x8e9a0 "sharedWorkspace"），不是类名。
    Class workspaceClass = objc_getClass("FBSWorkspace");
    SEL sharedWorkspaceSel = NSSelectorFromString(@"_sharedWorkspaceIfExists");
    (void)workspaceClass;
    for (NSNumber *display in PDRecon_displays()) {
        unsigned int displayId = display.unsignedIntValue;
        [diagnostics addObject:PDAXDiagnostics(@"workspace_context_probe",
            @{ @"stage": @"workspace_context_probe",
               @"displayId": @(displayId),
               @"point": NSStringFromCGPoint(point),
               @"bundleId": @"Accessibility",                     // 文案 Accessibility
               @"accessibilityLike": @YES })];
    }
    if (error) { *error = @"AX context-chain hit-test APIs unavailable"; }
    return NULL;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyElementAtPoint:usingKnownContextId:expectedPid:diagnostics:error:]
//   imp=0x8fab0 insns=495
// [0x8fc40]  insn#100
// [0x8fdd0]  insn#200
// [0x8ff60]  insn#300
// [0x900f0]  insn#400
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyElementAtPoint:(CGPoint)point
                usingKnownContextId:(unsigned int)contextId
                         expectedPid:(int)expectedPid
                         diagnostics:(NSMutableArray *)diagnostics
                               error:(NSString **)error
{
    if (![self ensureRuntimeAvailable:error]) {
        if (error) { *error = @"AX known-context hit-test APIs unavailable"; }
        return NULL;
    }
    if (contextId == 0) {
        if (error) { *error = @"Known contextId hit-test requires a non-zero contextId"; }
        return NULL;
    }
    if (expectedPid == 0) {
        if (error) { *error = @"Known contextId hit-test requires expectedPid"; }
        return NULL;
    }
    AXUIElementRef application = [self copyApplicationElementForPid:expectedPid error:NULL];
    if (!application) {
        if (error) { *error = [NSString stringWithFormat:
            @"Failed to create application element for pid=%d ctx=%u", expectedPid, contextId]; }
        return NULL;
    }
    AXUIElementRef best = NULL;
    for (int option = 0; option <= 2; option++) {                          // 0x8e4d8 枚举常量数组 0x107ea0 = {0,1,2}
        AXUIElementRef hit = NULL;
        AXError err = PDAXCopyElementUsingContextId(application, contextId, (CFTypeRef *)&hit,
                                                    option, (float)point.x, (float)point.y);
        if (err == kAXErrorSuccess && hit) {
            int hitPid = 0;
            [self getPid:&hitPid fromElement:hit];
            if (hitPid == expectedPid) {
                if (best) { CFRelease(best); }
                best = hit;
            } else {
                [diagnostics addObject:PDAXDiagnostics(@"known_context_hit_test",
                    @{ @"point": NSStringFromCGPoint(point), @"contextId": @(contextId),
                       @"expectedPid": @(expectedPid), @"axError": @(err),
                       @"hitPid": @(hitPid),
                       @"error": [NSString stringWithFormat:
                           @"AXUIElementCopyElementUsingContextIdAtPosition ctx=%u option=%d resolved pid %d",
                           contextId, option, hitPid] })];
                CFRelease(hit);
            }
        } else {
            [diagnostics addObject:PDAXDiagnostics(@"known_context_hit_test",
                @{ @"strategy": @"known_context_hit_test", @"option": @(option),
                   @"axError": @(err),
                   @"error": [NSString stringWithFormat:
                       @"AXUIElementCopyElementUsingContextIdAtPosition ctx=%u option=%d failed: %@",
                       contextId, option, [self errorStringForAXError:err]] })];
        }
    }
    if (application) { CFRelease(application); }
    if (best) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
                  @"[AXBridge] Known-context hit-test succeeded point=(%.1f,%.1f) ctx=%u option=%d",
                  point.x, point.y, contextId, 0]);
        }
        return best;
    }
    if (error) { *error = @"Known contextId hit-test returned no element"; }
    return NULL;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyHitTestElementAtPoint:expectedPid:allowParameterized:error:]
//   imp=0x903f0 insns=914
// [0x90580]  insn#100
// [0x90710]  insn#200
// [0x908a0]  insn#300
// [0x90a30]  insn#400
// [0x90bc0]  insn#500
// [0x90d50]  insn#600
// [0x90ee0]  insn#700
// [0x91070]  insn#800
// [0x91200]  insn#900
//   依次试 system_wide / springboard_app / target_app 三个种子，允许参数化时优先
//   AXUIElementCopyElementWithParameters（hitTestType 0..N）。
// ---------------------------------------------------------------------------
- (AXUIElementRef)copyHitTestElementAtPoint:(CGPoint)point
                                expectedPid:(int)expectedPid
                         allowParameterized:(BOOL)allowParameterized
                                      error:(NSString **)error
{
    if (![self ensureRuntimeAvailable:error]) { return NULL; }
    NSMutableArray *attempts = [NSMutableArray array];
    NSMutableArray *seeds = [NSMutableArray array];
    AXUIElementRef systemWide = [self copySystemWideElement];
    if (systemWide) {
        [seeds addObject:@{ @"name": @"system_wide", @"element": (__bridge id)systemWide }];
        CFRelease(systemWide);
    }
    AXUIElementRef springboard = [self copyApplicationElementForPid:getpid() error:NULL];
    if (springboard) {
        [seeds addObject:@{ @"name": @"springboard_app", @"element": (__bridge id)springboard }];
        CFRelease(springboard);
    }
    AXUIElementRef target = [self copyApplicationElementForPid:expectedPid error:NULL];
    if (target) {
        [seeds addObject:@{ @"name": @"target_app", @"element": (__bridge id)target }];
        CFRelease(target);
    }
    if (!seeds.count) {
        if (error) { *error = @"No AX seed available for parameterized hit-test"; }
        return NULL;
    }
    // ---- 参数化优先（AXUIElementCopyElementWithParameters） ----
    if (allowParameterized) {
        for (NSDictionary *seed in seeds) {
            // 已定案 0x909d0: 内层循环枚举常量数组 0x107f48（NSConstantArray，count@0x107f50 = 2，
            //   元素 0x108d78/0x108da8，int 载荷 @+0x10 分别为 0 和 2）——不是 0..3 的计数循环。
            for (NSNumber *hitTypeNumber in @[ @0, @2 ]) {
                unsigned int hitType = hitTypeNumber.unsignedIntValue;
                for (NSNumber *display in PDRecon_displays()) {
                    AXUIElementRef hit = NULL;
                    unsigned int displayId = display.unsignedIntValue;
                    unsigned int contextId = 0;
                    AXError err = AXUIElementCopyElementWithParameters(
                                      (AXUIElementRef)seed[@"element"], point.x, point.y,
                                      displayId, contextId, hitType, &hit);
                    if (err == kAXErrorSuccess && hit) {
                        int hitPid = 0;
                        [self getPid:&hitPid fromElement:hit];
                        if (expectedPid == 0 || hitPid == expectedPid) {
                            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                                NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
                                      @"[AXBridge] Parameterized hit-test succeeded via %@ display=%u ctx=%u hitType=%u",
                                      seed[@"name"], displayId, contextId, hitType]);
                            }
                            return hit;
                        }
                        [attempts addObject:PDAXDiagnostics(@"parameterized_hit_test",
                            @{ @"name": seed[@"name"], @"displayId": @(displayId),
                               @"contextId": @(contextId), @"hitTestType": @(hitType),
                               @"error": [NSString stringWithFormat:
                                   @"Parameterized app seed via %@ display=%u resolved pid %d instead of %d",
                                   seed[@"name"], displayId, hitPid, expectedPid] })];
                        CFRelease(hit);
                    } else {
                        [attempts addObject:PDAXDiagnostics(@"parameterized_hit_test",
                            @{ @"name": seed[@"name"],
                               @"error": [NSString stringWithFormat:
                                   @"AXUIElementCopyElementWithParameters via %@ display=%u ctx=%u hitType=%u failed: %@",
                                   seed[@"name"], displayId, contextId, hitType,
                                   [self errorStringForAXError:err]] })];
                    }
                }
            }
        }
        if (error) { *error = @"AXUIElementCopyElementWithParameters unavailable"; }
    }
    // ---- 非参数化：AXUIElementCopyElementAtPosition ----
    for (NSDictionary *seed in seeds) {
        AXUIElementRef hit = NULL;
        AXError err = AXUIElementCopyElementAtPosition((AXUIElementRef)seed[@"element"],
                                                       point.x, point.y, &hit);
        if (err == kAXErrorSuccess && hit) {
            int hitPid = 0;
            [self getPid:&hitPid fromElement:hit];
            if (expectedPid == 0 || hitPid == expectedPid) {
                return hit;
            }
            CFRelease(hit);
            [attempts addObject:PDAXDiagnostics(@"hit_test",
                @{ @"name": seed[@"name"], @"accessibilityLike": @YES,
                   @"error": [NSString stringWithFormat:
                       @"Parameterized app seed via %@ display=%u resolved pid %d instead of %d",
                       seed[@"name"], 0, hitPid, expectedPid] })];
        } else {
            [attempts addObject:PDAXDiagnostics(@"hit_test",
                @{ @"name": seed[@"name"],
                   @"error": [NSString stringWithFormat:@"Application AX hit-test failed: %@",
                                 [self errorStringForAXError:err]] })];
        }
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
              @"[AXBridge] Parameterized hit-test failed for pid=%d point=(%.1f,%.1f): %@",
              expectedPid, point.x, point.y, @"AX hit-test returned no element"]);
    }
    if (error) { *error = allowParameterized ? @"Parameterized AX hit-test returned no element"
                                             : @"AX hit-test returned no element"; }
    return NULL;
}

#pragma mark - 属性读取

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyAttributeObject:attribute:]  imp=0x91238 insns=32
// ---------------------------------------------------------------------------
- (id)copyAttributeObject:(AXUIElementRef)element attribute:(CFStringRef)attribute {
    if (!element || !attribute) { return nil; }                          // 0x91238
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (err != kAXErrorSuccess || !value) { return nil; }
    return (__bridge_transfer id)value;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyAttributeMap:attributes:]  imp=0x912b8 insns=98
// ---------------------------------------------------------------------------
- (NSDictionary *)copyAttributeMap:(AXUIElementRef)element attributes:(NSArray *)attributes {
    if (!element || !attributes.count) { return nil; }                    // [0x912…] count
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < attributes.count; i++) {
        id key = attributes[i];
        id attribute = attributes[i];                                     // objectAtIndexedSubscript:
        if (!attribute || attribute == [NSNull null]) { continue; }
        id value = [self copyAttributeObject:element attribute:(__bridge CFStringRef)attribute];
        map[key] = value ?: [NSNull null];                                // setObject:forKeyedSubscript:
    }
    return map;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyXCAttributeMap:attributeKeys:]
//   imp=0x91440 insns=505
// [0x915d0]  insn#100
// [0x91760]  insn#200
// [0x918f0]  insn#300
// [0x91a80]  insn#400
// [0x91c10]  insn#500
//   XC 属性名 → 私有属性名（0x917f4 规范化），再逐个 copyAttributeObject:。
// ---------------------------------------------------------------------------
- (NSDictionary *)copyXCAttributeMap:(AXUIElementRef)element attributeKeys:(NSArray *)keys {
    if (!keys.count) { return nil; }
    NSMutableArray *resolved = [NSMutableArray array];
    for (NSString *name in keys) {
        NSString *mapped = PDAXResolveXCAttributeName(name);               // 直调 0x917f4
        [resolved addObject:mapped ?: name];
    }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < keys.count; i++) {
        id key = keys[i];
        id attribute = resolved[i];
        if (!attribute || attribute == [NSNull null]) { continue; }
        id value = [self copyAttributeObject:element attribute:(__bridge CFStringRef)attribute];
        map[key] = value ?: [NSNull null];
    }
    return map;
}

// -[PDNative_MCPAXAttributeBridge copyXCAttributeObject:attributeKey:]  imp=0x91c24 insns=17
- (id)copyXCAttributeObject:(AXUIElementRef)element attributeKey:(NSString *)key {
    NSString *mapped = PDAXResolveXCAttributeName(key);                    // 直调 0x917f4
    if (!mapped) { return nil; }
    return [self copyAttributeObject:element attribute:(__bridge CFStringRef)mapped];
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyDirectAttributeMap:attributeKeys:]
//   imp=0x91c68 insns=289（属性名见文件头“直接属性”清单）
// [0x91df8]  insn#100
// [0x91f88]  insn#200
// ---------------------------------------------------------------------------
- (NSDictionary *)copyDirectAttributeMap:(AXUIElementRef)element attributeKeys:(NSArray *)keys {
    if (!keys.count) { return nil; }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *mapped = PDAXResolveDirectAttributeName(key);            // 直调 0x91e2c
        id value = mapped
            ? [self copyAttributeObject:element attribute:(__bridge CFStringRef)mapped]
            : nil;
        map[key] = value ?: [NSNull null];
    }
    return map;
}

// -[PDNative_MCPAXAttributeBridge copyDirectAttributeObject:attributeKey:]  imp=0x920ec insns=17
- (id)copyDirectAttributeObject:(AXUIElementRef)element attributeKey:(NSString *)key {
    NSString *mapped = PDAXResolveDirectAttributeName(key);                // 直调 0x91e2c
    if (!mapped) { return nil; }
    return [self copyAttributeObject:element attribute:(__bridge CFStringRef)mapped];
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyXCParameterizedAttributeObject:attributeKey:parameter:]
//   imp=0x92130 insns=84
//   参数化属性只有两个：childrenWithRange / userTestingSnapshotParameterized
// ---------------------------------------------------------------------------
- (id)copyXCParameterizedAttributeObject:(AXUIElementRef)element
                            attributeKey:(NSString *)key
                               parameter:(id)parameter
{
    NSString *mapped = PDAXResolveParameterizedName(key);                 // 直调 0x921e8
    if (!mapped.length) { return nil; }
    CFTypeRef value = NULL;
    AXError err = AXUIElementCopyParameterizedAttributeValue(element,
                      (__bridge CFStringRef)mapped, (__bridge CFTypeRef)parameter, &value);
    if (err != kAXErrorSuccess || !value) { return nil; }
    return (__bridge_transfer id)value;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyNumericAttributeMap:attributes:]  imp=0x92ac8 insns=98
// ---------------------------------------------------------------------------
- (NSDictionary *)copyNumericAttributeMap:(AXUIElementRef)element attributes:(NSArray *)attributes {
    if (!element || !attributes.count) { return nil; }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < attributes.count; i++) {
        id key = attributes[i];
        id attribute = attributes[i];
        if (!attribute || attribute == [NSNull null]) { continue; }
        id value = [self copyAttributeObject:element attribute:(__bridge CFStringRef)attribute];
        map[key] = value ?: [NSNull null];
    }
    return map;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyNumericAttributeArray:attributeId:]
//   imp=0x92c50 insns=43
//   把单个属性值包成一元数组（数组长度在 0x92c50 段按栈槽固定为 1）。
// ---------------------------------------------------------------------------
- (NSArray *)copyNumericAttributeArray:(AXUIElementRef)element attributeId:(unsigned int)attributeId {
    // 已定案 0x92c70: mov w3,w3 → 0x92c74 bl copyAttributeObject:attribute: ——
    //   二进制里没有 attributeId → 属性名的映射表，attributeId 被零扩展后直接当 attribute 指针传。
    id value = [self copyAttributeObject:element
                               attribute:(__bridge CFStringRef)(uintptr_t)attributeId];
    if (!value) { return nil; }                                            // [0x92cf0] cbz x19
    // 已定案 0x92c7c/0x92c94: 已经是 NSArray 就原样返回，否则包成 1 元数组
    if ([value isKindOfClass:[NSArray class]]) { return value; }           // [0x92c8c] isKindOfClass NSArray
    return [NSArray arrayWithObjects:&value count:1];                       // [0x92cb4] arrayWithObjects:count:
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyStringAttribute:attribute:]  imp=0x93310 insns=30
// ---------------------------------------------------------------------------
- (NSString *)copyStringAttribute:(AXUIElementRef)element attribute:(CFStringRef)attribute {
    id value = [self copyAttributeObject:element attribute:attribute];
    if (value && [value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];                                        // 段内 stringValue
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyNumberAttribute:attribute:]  imp=0x93388 insns=21（实测）
//   已定案 0x93388..0x933d8：方法体只有 21 条指令 —— 取属性值、判 NSNumber、原样返回或 nil。
//   “字符串解析 / WxH / doubleValue”整段在二进制里不存在（0x933dc 起已是 PDAXBindRuntimeIfNeeded，
//   0x93658 起是 PDAXBindSymbols；方法区间外的 0x93ec8/0x93f34/0x93fcc 三个静态里
//   rangeOfString / numberWithUnsignedLongLong 属别的调用点）。method 表“insns=816”是
//   imp..下一条 imp 的粗跨度，不是本方法长度。
// ---------------------------------------------------------------------------
- (NSNumber *)copyNumberAttribute:(AXUIElementRef)element attribute:(CFStringRef)attribute {
    id value = [self copyAttributeObject:element attribute:attribute];     // [0x93394] bl copyAttributeObject:attribute:
    if (![value isKindOfClass:[NSNumber class]]) { return nil; }           // [0x9339c] ldr x0,[0x119d10]=NSNumber / 0x933b4 tbz
    return value;                                                          // [0x933b8] retain / [0x933d0] ret
}

#pragma mark - 子元素与快照

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyChildElementsForElement:]  imp=0x92cfc insns=389
// [0x92e8c]  insn#100
// [0x9301c]  insn#200
// [0x931ac]  insn#300
//   依次尝试 AXChildren / AXVisibleChildren / AXWindows / AXElements /
//   AXFocusedWindow / AXMainWindow，再并上 privateChildren / visibleElements 等直接属性。
// ---------------------------------------------------------------------------
- (NSArray *)copyChildElementsForElement:(AXUIElementRef)element {
    if (!element) { return nil; }
    NSMutableOrderedSet *ordered = [NSMutableOrderedSet orderedSet];
    NSArray *directKeys = @[ @"visibleElements", @"privateChildren", @"children" ];
    NSDictionary *direct = [self copyDirectAttributeMap:element attributeKeys:directKeys];
    for (NSString *key in directKeys) {
        id bucket = direct[key];
        if (bucket && bucket != [NSNull null]) {
            for (id child in bucket) {
                [ordered addObject:PDAXWrapElement(child)];                // 直调 0x930f4
            }
        }
    }
    NSDictionary *xc = [self copyXCAttributeMap:element
                                 attributeKeys:@[ @"children", @"AXChildren",
                                                  @"AXVisibleChildren", @"AXWindows",
                                                  @"AXElements" ]];
    for (NSString *key in xc) {
        id bucket = xc[key];
        if (bucket && bucket != [NSNull null]) {
            for (id child in bucket) { [ordered addObject:PDAXWrapElement(child)]; }
        }
    }
    NSDictionary *single = [self copyAttributeMap:element
                                       attributes:@[ @"AXFocusedWindow", @"AXMainWindow" ]];
    for (NSString *key in single) {
        id child = single[key];
        if (child && child != [NSNull null]) { [ordered addObject:PDAXWrapElement(child)]; }
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:ordered.count];
    for (id wrapped in ordered) {
        if (wrapped == [NSNull null]) { continue; }
        // 若包装对象支持 element 取值则展开
        if ([wrapped respondsToSelector:@selector(objectForKeyedSubscript:)]) {
            id inner = [(NSDictionary *)wrapped objectForKeyedSubscript:@"element"];
            [result addObject:inner ?: wrapped];
        } else {
            [result addObject:wrapped];
        }
    }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyUserTestingSnapshotForElement:options:]
//   imp=0x92280 insns=193
// ---------------------------------------------------------------------------
- (NSDictionary *)copyUserTestingSnapshotForElement:(AXUIElementRef)element options:(NSDictionary *)options {
    if (!element) { return nil; }
    NSDictionary *normalized = PDAXNormalizeSnapshotOptions(options);      // 直调 0x92310
    id snapshot = [self copyXCParameterizedAttributeObject:element
                                              attributeKey:@"userTestingSnapshotParameterized"
                                                 parameter:normalized];
    if (!snapshot) {
        snapshot = [self copyXCAttributeObject:element attributeKey:@"userTestingSnapshot"];
    }
    if (!snapshot) { return nil; }
    NSMutableDictionary *result = [snapshot isKindOfClass:[NSDictionary class]]
                                    ? [snapshot mutableCopy] : [NSMutableDictionary dictionary];
    id attributes = result[@"attributes"];
    if ([attributes isKindOfClass:[NSArray class]]) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (id item in attributes) {
            if (item == [NSNull null]) { continue; }
            if (CFGetTypeID((__bridge CFTypeRef)item) == CFStringGetTypeID()) {
                [filtered addObject:item];
            }
        }
        // 已定案 0x92508: count(filtered) — 0 才 removeObjectForKey:@"attributes"（0x92538），
        //   非 0 走 setObject:forKeyedSubscript:@"attributes"（0x92524）。原稿无条件写入是错的。
        if (filtered.count) { result[@"attributes"] = filtered; }
        else { [result removeObjectForKey:@"attributes"]; }
    }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge probeUserTestingSnapshotForElement:options:]
//   imp=0x92584 insns=337
// [0x92714]  insn#100
// [0x928a4]  insn#200
// [0x92a34]  insn#300
//   返回诊断字典：parameterized / attribute 两条通道各自记录 errorCode / error / 摘要。
// ---------------------------------------------------------------------------
- (NSDictionary *)probeUserTestingSnapshotForElement:(AXUIElementRef)element options:(NSDictionary *)options {
    NSMutableDictionary *probe = [NSMutableDictionary dictionary];
    NSDictionary *normalized = PDAXNormalizeSnapshotOptions(options);       // 直调 0x92310
    probe[@"normalizedOptions"] = normalized ?: @{};
    // ---- 通道 1：参数化 ----
    {
        CFTypeRef value = NULL;
        NSString *mapped = PDAXResolveParameterizedName(@"userTestingSnapshotParameterized");
        AXError err = AXUIElementCopyParameterizedAttributeValue(element,
                          (__bridge CFStringRef)mapped, (__bridge CFTypeRef)normalized, &value);
        probe[@"parameterizedErrorCode"] = @(err);
        probe[@"parameterizedError"] = [self errorStringForAXError:err];
        probe[@"parameterizedValueSummary"] = PDAXDescribeSnapshotValue((__bridge id)value);  // 直调 0x92884
        if (value) {
            probe[@"snapshot"] = (__bridge_transfer id)value;
            probe[@"snapshotSource"] = @"parameterized";
        }
    }
    // ---- 通道 2：直接属性 ----
    {
        CFTypeRef value = NULL;
        NSString *mapped = PDAXResolveXCAttributeName(@"userTestingSnapshot");
        AXError err = AXUIElementCopyAttributeValue(element, (__bridge CFStringRef)mapped, &value);
        probe[@"attributeErrorCode"] = @(err);
        probe[@"attributeError"] = [self errorStringForAXError:err];
        probe[@"attributeValueSummary"] = PDAXDescribeSnapshotValue((__bridge id)value);
        if (value) {
            if (!probe[@"snapshot"]) {
                probe[@"snapshot"] = (__bridge_transfer id)value;
                probe[@"snapshotSource"] = @"userTestingSnapshot";
            } else {
                CFRelease(value);
            }
        }
    }
    // ---- 摘要（class / count / keys / length，文案见下） ----
    id snapshot = probe[@"snapshot"];
    probe[@"class"] = snapshot ? NSStringFromClass([snapshot class]) : @"<unknown>";
    if ([snapshot respondsToSelector:@selector(count)]) {
        probe[@"count"] = @([snapshot count]);
    }
    if ([snapshot isKindOfClass:[NSDictionary class]]) {
        probe[@"keys"] = [((NSDictionary *)snapshot).allKeys subarrayWithRange:
            NSMakeRange(0, MIN(8u, ((NSDictionary *)snapshot).allKeys.count))];
        probe[@"count"] = @(((NSDictionary *)snapshot).allKeys.count);
    }
    if ([snapshot isKindOfClass:[NSString class]]) {
        probe[@"length"] = @(((NSString *)snapshot).length);
    }
    if (!probe[@"snapshot"]) {
        probe[@"snapshot"] = [NSNull null];
        probe[@"snapshotSource"] = snapshot ? probe[@"snapshotSource"] : [NSNull null];
    }
    return probe;
}

#pragma mark - 批量读（有界）

// ---------------------------------------------------------------------------
// -[PDNative_MCPAXAttributeBridge copyBoundedAttributes:attributes:error:]
//   imp=0x8c74c insns=146
//   在后台队列上按批读：先 ensureRuntimeAvailable，再用一次 BLR 批量 API；
//   pid 不符或数量不符时逐项补读。
// ---------------------------------------------------------------------------
- (NSDictionary *)copyBoundedAttributes:(AXUIElementRef)element
                             attributes:(NSArray *)attributes
                                  error:(NSString **)error
{
    if ([NSThread isMainThread] || !element || !attributes.count) {        // [0x8c788] 系列
        if (error) { *error = @"AX batch read unavailable or called on main thread"; }
        return nil;
    }
    if (![self ensureRuntimeAvailable:error]) {                           // [0x8c7a4]
        if (error) { *error = @"Target app AX service unavailable (-25215); no activation or retry attempted"; }
        return nil;
    }
    // 直调 0x8c7d0 / 0x8c7ec：批量读入口（参数为 element, attributes, 0）
    NSArray *values = PDAXBatchCopyAttributeValues(element, attributes);   // 见静态函数
    if (!values) {
        if (error) { *error = @"AX batch read failed (-25200); no retry"; }
        return nil;
    }
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSUInteger n = MIN(attributes.count, values.count);
    for (NSUInteger i = 0; i < n; i++) {
        id key = attributes[i];
        id value = values[i];
        map[key] = (value && value != [NSNull null]) ? value : [NSNull null];
    }
    if (values.count != attributes.count) {
        if (error) {
            *error = [NSString stringWithFormat:@"AX batch read failed (%d); no retry",
                         (int)(attributes.count - values.count)];
        }
        return nil;
    }
    return map;
}

#pragma mark - 内部辅助

// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号），
//    仅用于组织原版内联逻辑；如需严格对齐应合并回调用处。
static NSArray<NSNumber *> * PDRecon_displays(void) {
    // 已定案 0x8dc1c..0x8dc30（原判二选一，既非 A 也非 B —— 是第三个答案：常量表）：
    //   display 候选来自 __NSConstantArray @0x107e88，count@+0x08 = 2，元素缓冲 0x106728，
    //   元素是 __NSConstantIntegerNumber：0x108d90 → 1、0x108d78 → 0
    //   （0x8dc20 `add x0,x0,#0xe88` 取该对象作 NSFastEnumeration 接收者；
    //    0x8dc30 `bl countByEnumeratingWithState:objects:count:`；
    //    0x8dcb0 `bl unsignedIntValue` 得 displayId；0x8dd3c `numberWithUnsignedInt:` 作查询实参）。
    //   · 既不是 A（由 FBSWorkspace.scenes 逐个推导）——同方法内 0x8e96c 起的 workspace 探测
    //     只用于 `workspace_context_probe` 那一段，不参与 displayId 生成；
    //   · 也不是 B（AX 自己的列表现数编号）——表是硬编码且顺序是 1 在前、0 在后。
    //   注意 0x8db30 段还有第二个常量数组 0x107ea0 = {0,1,2}，那是 hit-test 的 option 候选，别混用。
    return @[ @1, @0 ];
}

@end

#pragma mark - 静态函数

// 0x93388 段尾 + 0x93658：把 4 个镜像里的 AX 入口绑到 gAXRuntime
static void PDAXBindRuntimeIfNeeded(void) {
    if (gAXRuntime.bound) { return; }                                       // 0x93520 判定
    static const char *kImages[] = { "hiservices", "applicationservices", "axruntime", "accessibility" };
    for (size_t i = 0; i < 4; i++) {
        void *handle = dlopen(kImages[i], RTLD_NOW /*0xa*/);
        if (!handle) { handle = dlopen(kImages[i], RTLD_LAZY /*0x1a*/); }   // 0x934d0/0x934e0
        if (!handle) { continue; }
        // 0x93658：按名字表逐个 dlsym 并填入槽位
        PDAXBindSymbols(handle, nil);
        if (gAXRuntime.bound) { break; }
    }
    if (!gAXRuntime.bound) {
        // 0x93534 起：第二遍，按名称数组逐个 dlopen + 绑定（0x107f30 为名称表）
        for (NSString *image in @[ @"Accessibility", @"AXRuntime" ]) {
            void *handle = dlopen(image.UTF8String, RTLD_LAZY);
            if (handle && PDAXBindSymbols(handle, image)) { break; }
        }
    }
    if (!gAXRuntime.bound) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(@"[witchan][ios-mcp]%@", @"Direct AX runtime unavailable in SpringBoard");
        }
        return;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(@"[witchan][ios-mcp]%@", [NSString stringWithFormat:
              @"[AXBridge] AX runtime bound from %@%@", @"RTLD_DEFAULT",
              @" using _AXUIElementCreateAppElementWithPid"]);
    }
}

// 0x93658：把 handle 里的符号填进缓存；返回是否已绑定
static BOOL PDAXBindSymbols(void *handle, NSString *imageName) {
    if (!handle) { return NO; }
    // 已定案 0x93688..0x93c84：46 个 dlsym 调用逐条读出，名字与槽偏移见 kPDAXSymbols。
    //   kAXXCAttribute* 系列先 dlsym 到 LHS，再 0x93854 `ldr x8,[x0]` 取值后入槽（槽里存的是 NSString*）。
    gAXHandle = handle;                                                    // [0x93cd4] stp x20, …
    for (size_t i = 0; i < sizeof(kPDAXSymbols) / sizeof(kPDAXSymbols[0]); i++) {
        const char *name = kPDAXSymbols[i].name;
        void *sym = dlsym(handle, name);                                   // [0x93694] bl _dlsym
        if (!sym) { continue; }
        switch (kPDAXSymbols[i].off) {
            case 0x008: gAXValueCreate = sym; break;
            case 0x010: gAXCreateApplication = sym; break;                 // [0x93ca8] csel 兜底 +0x18
            case 0x020: gAXCreateSystemWide = sym; break;
            case 0x028: gAXCopyAttributeValue = sym; break;
            case 0x030: gAXCopyParameterizedAttributeValue = sym; break;
            case 0x038: gAXCopyMultipleAttributeValues = sym; break;
            case 0x068: gAXSetMessagingTimeout = sym; break;
            case 0x070: gAXCopyElementWithParameters = sym; break;
            case 0x078: gAXCopyElementUsingContextIdAtPosition = sym; break;
            case 0x088: gAXGetPid = sym; break;
            case 0x090: gAXAddAssociatedPid = (PDAXAddAssociatedPidFn)sym; break;
            case 0x098: gAXIsPidAssociated = (BOOL (*)(pid_t))sym; break;
            case 0x0a0: gAXIsPidAssociatedWithDisplayType = (BOOL (*)(pid_t, int))sym; break;
            default: break;                                                // kAXXCAttribute* 常量槽
        }
    }
    // 已定案 0x93520/0x93524：已绑定 = [0x11c728](CreateApplication) && [0x11c740](CopyAttributeValue)
    gAXRuntime.bound = (gAXCreateApplication && gAXCopyAttributeValue);
    (void)imageName;
    return gAXRuntime.bound;
}

// 0x917f4：XC 属性名规范化（表见文件头）
static NSString *PDAXResolveXCAttributeName(NSString *name) {
    if (!name.length) { return nil; }
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"children": @"AXChildren", @"AXChildren": @"AXChildren",
                 @"frame": @"AXFrame", @"AXFrame": @"AXFrame",
                 @"identifier": @"AXIdentifier", @"AXIdentifier": @"AXIdentifier",
                 @"label": @"AXLabel", @"AXLabel": @"AXLabel",
                 @"traits": @"AXTraits", @"AXTraits": @"AXTraits",
                 @"value": @"AXValue", @"AXValue": @"AXValue" };
    });
    return map[name] ?: name;
}

// 0x91e2c：直接属性名规范化
static NSString *PDAXResolveDirectAttributeName(NSString *name) {
    if (!name.length) { return nil; }
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"application": @"AXApplication", @"windowContextId": @"AXWindowContextId",
                 @"path": @"AXPath", @"visibleFrame": @"AXVisibleFrame",
                 @"visiblePoint": @"AXVisiblePoint", @"url": @"AXURL",
                 @"centerPoint": @"AXCenterPoint", @"containerType": @"AXContainerType" };
    });
    return map[name] ?: name;
}

// 0x921e8：参数化属性名规范化
static NSString *PDAXResolveParameterizedName(NSString *name) {
    if (!name.length) { return nil; }
    if ([name isEqualToString:@"childrenWithRange"]) {
        return @"AXChildrenWithRange";
    }
    if ([name isEqualToString:@"userTestingSnapshotParameterized"]) {
        return @"AXUserTestingSnapshotParameterized";
    }
    return name;
}

// 0x92310：快照选项规范化
static NSDictionary *PDAXNormalizeSnapshotOptions(NSDictionary *options) {
    if (![options isKindOfClass:[NSDictionary class]]) { return @{}; }
    return options;
}

// 0x92884：快照值摘要
// 已定案（本轮，见 out/notes/residue.md）：全二进制的 CF "<unknown>"（0xff268）只有 **2 处**代码引用——
//   0x8ed88（copyContextChainHitElementAtPoint: 内，`csel x8,x8,x0,eq` 后接 retain）
//   0x9292c（probeUserTestingSnapshotForElement: 内，0x92934 `csel x2,x8,x22,eq` + 0x9293c CF "class"
//            + 0x92944 `setObject:forKeyedSubscript:`，即 probe[@"class"] 的兜底）。
//   两处都是「类名 ?: "<unknown>"」，**没有**一处是 nil 值摘要的兜底。
//   另：本函数用的 @"dict(%lu)" / @"array(%lu)" / @"string(%lu)" 三条格式串在 __cfstring 里都不存在
//   （全段只找到 "AXSnapshotElement" / "userTestingSnapshotSummary" 等），故本函数整体属重构引入。
//   保留行为，但把 nil 分支标注为 Assumed（字面量本身 Observed，落点 Assumed）。
//   验证动作：真机对 userTestingSnapshot 走一次 probe，看 parameterizedValueSummary 在 nil 时到底是
//   空串、@"(null)" 还是 @"<unknown>"。
static NSString *PDAXDescribeSnapshotValue(id value) {
    if (!value) { return @"<unknown>"; }   // Assumed：见上，无静态落点
    if ([value isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"dict(%lu)", (unsigned long)[value count]];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"array(%lu)", (unsigned long)[value count]];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"string(%lu)", (unsigned long)[value length]];
    }
    return NSStringFromClass([value class]);
}

// 0x930f4：子元素包装
static NSDictionary *PDAXWrapElement(id element) {
    if (!element || element == [NSNull null]) { return nil; }
    int pid = 0;
    if (CFGetTypeID((__bridge CFTypeRef)element) == AXUIElementGetTypeID()) {
        pid_t p = 0;
        if (AXUIElementGetPid((AXUIElementRef)element, &p) == kAXErrorSuccess) { pid = (int)p; }
    }
    return @{ @"element": element, @"pid": @(pid) };
}

// 0x8d9e0 / 0x8da54：诊断条目
static NSDictionary *PDAXDiagnostics(NSString *stage, NSDictionary *fields) {
    NSMutableDictionary *entry = [fields mutableCopy] ?: [NSMutableDictionary dictionary];
    if (stage) { entry[@"stage"] = stage; }
    return entry;
}

// 0x92c50 段：已定案——二进制里不存在 attributeId → 属性名 的映射（0x92c70 `mov w3,w3` 后直接
//   把 attributeId 当 attribute 指针交给 copyAttributeObject:），故原 PDAXNameForAttributeId 删除。

// 0x8c7d0 / 0x8c7ec：批量读 —— 已定案走 0x11c750（槽 +0x38 = AXUIElementCopyMultipleAttributeValues）
//   0x8c7b0 ldr x8,[0x11c750] / 0x8c7ec blr x8(element, attributes, 0, &out)；
//   调用前 0x8c7c4/0x8c7d0 用槽 +0x68 设 messaging timeout = 0.08 秒（0xc0b3c）。
static NSArray *PDAXBatchCopyAttributeValues(AXUIElementRef element, NSArray *attributes) {
    if (!element || !attributes.count) { return nil; }
    if (!gAXCopyMultipleAttributeValues) { return nil; }                    // [0x8c7b4] cbz x8
    if (gAXSetMessagingTimeout) {                                          // [0x8c7c0] cbz x9
        ((AXError (*)(AXUIElementRef, float))gAXSetMessagingTimeout)(element, 0.08f); // [0x8c7cc] blr
    }
    CFArrayRef values = NULL;
    AXError err = ((AXError (*)(AXUIElementRef, CFArrayRef, int, CFArrayRef *))gAXCopyMultipleAttributeValues)(
                      element, (__bridge CFArrayRef)attributes, 0, &values); // [0x8c7ec] x2 = 0
    if (err != kAXErrorSuccess || !values) { return nil; }
    return (__bridge_transfer NSArray *)values;
}

#pragma mark - §SELFCHECK
// 括号走查：27 个方法 + 9 个静态函数全部闭合；probeUserTestingSnapshot 两个通道块的
//   CF 所有权成对（CFRelease 只在未接管分支执行）。
// 方法计数：method-table 27 条 → 本文件 27 个方法实现。
// 保真度：Tier-2（调用序列 + 分支骨架 + 全部常量串逐字；参数化 API 的具体实参组合与
//   多屏枚举与参数化实参组合 —— 已定案（本轮，见 out/notes/residue.md）：
// Assumed 汇总（本轮已三选一，见 out/notes/assume-b.md）：
//   · dlsym 名称表 —— 已定案：46 条全部读出（kPDAXSymbols），不再有“未解槽位”。
//   · AX 属性 ID → 名称映射 —— 已定案：二进制里不存在，copyNumericAttributeArray 直传 attributeId。
//   · 参数化 hit-test 的 hitType —— 已定案：不是 0..3，而是常量数组 {0, 2}（0x107f48，count=2）。
//   · displays 的取值 —— 已定案（既非 A 也非 B）：常量数组 @[@1,@0]（__NSConstantArray 0x107e88，
//     count=2，元素 0x108d90→1 / 0x108d78→0），见 PDRecon_displays() 上方注释。
//   · 参数化实参组合 —— 已定案：段 1/段 2 是槽 +0x30 的 **4 参**查询
//     （x1 = 数值属性 ID 0x16573 / 0x16574，Observed；ID 的符号名 Assumed）；
//     段 3 是槽 +0x78 的 **6 参**调用 fn(element, ctxId, &out, option, float x, float y)，
//     option 由常量数组 0x107ea0 = {0,1,2} 提供。原稿三处统一写 5 个平铺形参是错的，已改。
// CALL：0 处（原 4 处全部落到 _AXIsPidAssociated / _AXIsPidAssociatedWithDisplayType / _AXAddAssociatedPid）。
// NOT RUN：未编译/未运行。
