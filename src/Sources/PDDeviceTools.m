//
//  PDDeviceTools.m
//  PetDFY
//
//  原生“设备工具”派发器：一次只跑一个工具，带代数（generation）作废机制。
//
//  二进制证据
//    image base  : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表      : out/method-table-all.md → 14 条（全 `-`）
//    区间        : 0x6b02c .. 0x6babc
//    instanceSize: 48（0x30）
//    ivar（__objc_ivar 实读）
//      _inFlight +0x08 B   _prepareHandler +0x10 @?   _queue +0x18
//      _executor +0x20     _generation +0x28 Q
//    区间内的静态实体（方法表按“下一个方法起点”截断，故算进 -.cxx_destruct）
//      0x6b318  PDDeviceToolsFailureFromError(id)        154 insns，信封三键
//      0x6b3d0  prepareHandler 回调块 invoke              68 insns
//      0x6b4c8  执行队列块 invoke                         166 insns
//      0x6b760  回主线程块 invoke                         41 insns
//      0x6b874  PDDeviceToolDoubleParameter(...)          96 insns，@"Missing required parameter: %@"
//                                                              / @"Invalid parameter %@: expected number"
//      0x6b9e8  PDDeviceToolBoolParameter(...)            53 insns，objectForKeyedSubscript + boolValue
//    外部依赖（不在本文件）
//      0x6180c  PDIsDeviceTool(NSString *)       0x61bac  PDDeviceToolPermissionError(id, id)
//      0x61f2c  PDDeviceToolResult(id)
//
//  与旧快照的关键分歧（详见 out/notes/sources-diff.md）
//    · 队列 label 二进制是 "com.susudear.petdfy.device-tools"（0x6b070 CFString）；
//      旧快照的注释对、代码写成 "petdfy.deviceTools"。
//    · -init 里 _objc_opt_new 的目标是 PDDeviceNativeExecutor（0x119000+0xc0），
//      不是 NSMutableDictionary；ivar 表里也没有 _tools。
//    · -init 会调 -[PDDeviceAXScope recoverInterruptedScope]（0x6b068）。
//    · prepareHandler 不是“只判空”，0x6b2f0 真的用 blr 调用它，且带一个完成块参数。
//
//  标记：[0xADDR] = 指令地址 / <CALL 0xADDR> = 未解析调用 / Assumed
//  已定案 2026-11-28（复核）：图例中的 “CALL 0xADDR（本文件 0 处）” 成立——
//    本文件里 “CALL 0x” 字样只出现在本行图例自身，正文 0 处；区间内 11 处 bl 全部解析为
//    objc 运行时桩（_objc_retain/_objc_release/dispatch_* 等）或方法表内地址。
//  编译状态：NOT RUN
//

#import "PDDeviceTools.h"
#import "PDDeviceAXScope.h"
#import "PDDeviceNativeExecutor.h"
#import <Foundation/Foundation.h>

static NSString *const kPDDeviceToolsQueueLabel = @"com.susudear.petdfy.device-tools"; // [0x6b070]

// 信封三键（0x6b1a8/0x6b1dc/0x6b1e8 与 0x6b6dc/0x6b6f0 两组同构）
//   键：receipt / failed / images（CF 0xf6128 / 0xf6148 / 0xf6108）
//   值：文案、@YES、空集合常量
//   已定案 0x6b364/0x6b6fc：images 的常量槽是 0xf0638，绑定符号 ___NSArray0__struct
//     → 空数组单例（@[]）。两组信封都用同一槽，所以旧快照的 @[] 是对的；
//     原注释「isa 实测为 NSConstantDictionary」与槽绑定不符，已改回 @[]。
//   已定案 0x6b350/0x6b6e4：failed 的值来自槽 0xf0660 = ___kCFBooleanTrue（@YES）。
static NSDictionary *PDDeviceToolsEnvelope(NSString *receipt) {
    return @{ @"receipt": receipt ?: @"",
              @"failed":  @YES,
              @"images":  @[] };
}

// 前向声明（定义在文件末尾，调用点在前）
static NSDictionary *PDDeviceToolsFailureFromError(id error);

@implementation PDDeviceTools

// ---------------------------------------------------------------------------
// -[PDDeviceTools init]  imp=0x6b02c insns=34
// ---------------------------------------------------------------------------
- (instancetype)init {
    // [0x6b054] objc_msgSendSuper2(sel=init)
    if ((self = [super init])) {
        // [0x6b064] 类槽 0x11a0b8 → rebase _OBJC_CLASS_$_PDDeviceAXScope（是**类**，不是实例）
        // [0x6b068] 直接 bl sel:recoverInterruptedScope，x0 仍是类对象，中间没有 alloc/new
        //   → 调的是类方法 +[PDDeviceAXScope recoverInterruptedScope]（method-table sign = +）
        // 已定案 0x6b064/0x6b068：接收者是类；原写法 [[PDDeviceAXScope new] …] 多了一次实例化，已改。
        [PDDeviceAXScope recoverInterruptedScope];
        // [0x6b078] dispatch_queue_create(label, NULL) → +0x18
        _queue = dispatch_queue_create(kPDDeviceToolsQueueLabel.UTF8String, NULL);
        // [0x6b090] _objc_opt_new(PDDeviceNativeExecutor) → +0x20
        _executor = [PDDeviceNativeExecutor new];
    }
    return self;                                           // [0x6b0a0]
}

// ---------------------------------------------------------------------------
// -[PDDeviceTools cancel]  imp=0x6b0b4 insns=10
//   只把代数 +1：在途回调各自比对代数自行作废。
// ---------------------------------------------------------------------------
- (void)cancel {
    self.generation = self.generation + 1;                 // [0x6b0c4] generation → [0x6b0d8] setGeneration:
}

// ---------------------------------------------------------------------------
// -[PDDeviceTools execute:arguments:completion:]  imp=0x6b0dc insns=449
//   三道前置门 + prepare 回调 + 执行队列 + 回主线程。
// ---------------------------------------------------------------------------
- (void)execute:(NSString *)name
      arguments:(NSDictionary *)arguments
     completion:(void (^)(NSDictionary *))completion {
    // [0x6b0f8] x21=completion x20=arguments x23=self x19=name
    id permissionError = PDDeviceToolPermissionError(name, arguments);  // [0x6b134]
    if (permissionError) {                                             // [0x6b140] cbz x0
        completion(PDDeviceToolsFailureFromError(permissionError));    // [0x6b148] bl 0x6b318
        // [0x6b224] blr：completion(dict)
        return;
    }
    // [0x6b158] PDIsDeviceTool(name)
    if (!PDIsDeviceTool(name) ||
        ![arguments isKindOfClass:[NSDictionary class]]) {             // [0x6b174] isKindOfClass:
        // [0x6b1bc] 两条文案由 inFlight 选（0x6b1cc csel）
        completion(PDDeviceToolsEnvelope(self.inFlight
                    ? @"上一项原生设备操作尚未返回，请稍后重试。"
                    : @"设备操作不可用或参数无效。"));
        return;
    }
    if (!self.prepareHandler) {                                        // [0x6b188] cbz x0
        completion(PDDeviceToolsEnvelope(self.inFlight
                    ? @"上一项原生设备操作尚未返回，请稍后重试。"
                    : @"设备操作不可用或参数无效。"));
        return;
    }
    if (self.inFlight) {                                               // [0x6b1a0] cbz w25
        completion(PDDeviceToolsEnvelope(@"上一项原生设备操作尚未返回，请稍后重试。"));
        return;
    }
    unsigned long long generation = self.generation;                    // [0x6b274]
    self.inFlight = YES;                                                // [0x6b284]
    void (^prepare)(void (^)(BOOL)) = self.prepareHandler;               // [0x6b28c]
    // [0x6b2f0] blr：prepare(^(BOOL ok){ … })，块体 0x6b3d0
    prepare(^(BOOL ok) {
        if (!ok || self.generation != generation) {                     // [0x6b3e4]/[0x6b3f8]
            self.inFlight = NO;                                         // [0x6b4a4]
            completion(@{});                                            // [0x6b4c4] 空结果（@{}）
            return;
        }
        dispatch_async(self.queue, ^{                                   // [0x6b46c]，块体 0x6b4c8
            @autoreleasepool {                                          // [0x6b4f8]
                NSDictionary *result = nil;
                id err = PDDeviceToolPermissionError(name, arguments);   // [0x6b504]
                if (err) {                                              // [0x6b510]
                    result = PDDeviceToolsFailureFromError(err);         // [0x6b518]
                } else if (self.generation != generation) {               // [0x6b534]
                    result = @{};                                       // [0x6b578]
                } else {
                    // [0x6b550] executor execute:arguments: → [0x6b55c] PDDeviceToolResult
                    result = PDDeviceToolResult([self.executor execute:name arguments:arguments]);
                }
                dispatch_async(dispatch_get_main_queue(), ^{             // [0x6b5f0]，块体 0x6b760
                    self.inFlight = NO;                                  // [0x6b77c]
                    id finishErr = PDDeviceToolPermissionError(name, arguments); // [0x6b784]
                    if (finishErr) {
                        completion(PDDeviceToolsFailureFromError(finishErr));   // [0x6b798]
                    } else {
                        completion(result);                             // [0x6b7b0] blr
                    }
                });
            }
        });
    });
}

#pragma mark - 访问器

// -[PDDeviceTools prepareHandler]  imp=0x6b7e0 insns=2
- (void (^)(void))prepareHandler { return _prepareHandler; }                 // [0x6b7e0]
// -[PDDeviceTools setPrepareHandler:]  imp=0x6b7e8 insns=2
- (void)setPrepareHandler:(void (^)(void))prepareHandler {
    _prepareHandler = [prepareHandler copy];                                // [0x6b7ec] objc_setProperty…copy 0x10
}
// -[PDDeviceTools queue]  imp=0x6b7f0 insns=2
- (id)queue { return _queue; }                                              // [0x6b7f0]
// -[PDDeviceTools setQueue:]  imp=0x6b7f8 insns=3
- (void)setQueue:(id)queue { _queue = queue; }                              // [0x6b800] storeStrong 0x18
// -[PDDeviceTools executor]  imp=0x6b804 insns=2
- (id)executor { return _executor; }                                        // [0x6b804]
// -[PDDeviceTools setExecutor:]  imp=0x6b80c insns=3
- (void)setExecutor:(id)executor { _executor = executor; }                  // [0x6b814] storeStrong 0x20
// -[PDDeviceTools generation]  imp=0x6b818 insns=2
- (unsigned long long)generation { return _generation; }                    // [0x6b818]
// -[PDDeviceTools setGeneration:]  imp=0x6b820 insns=2
- (void)setGeneration:(unsigned long long)generation { _generation = generation; } // [0x6b820] str 0x28
// -[PDDeviceTools inFlight]  imp=0x6b828 insns=2
- (BOOL)inFlight { return _inFlight; }                                      // [0x6b828] ldrb 0x08
// -[PDDeviceTools setInFlight:]  imp=0x6b830 insns=2
- (void)setInFlight:(BOOL)inFlight { _inFlight = inFlight; }                // [0x6b830] strb 0x08

// ---------------------------------------------------------------------------
// -[PDDeviceTools .cxx_destruct]  imp=0x6b838 insns=161
//   前 12 条是析构（+0x20 / +0x18 / +0x10），其后 0x6b874 起是本文件的参数解析静态函数。
// ---------------------------------------------------------------------------
- (void).cxx_destruct {
    _executor = nil;                                                       // [0x6b850] +0x20
    _queue = nil;                                                          // [0x6b85c] +0x18
    _prepareHandler = nil;                                                 // [0x6b870] +0x10
}

@end

#pragma mark - 区间内静态函数

// 0x6b318..0x6b3d0（46 insns，(0x6b3d0-0x6b318)/4；文件头原写 154 insns 与区间不符）
//   已定案（复核 2026-11-28）：不取 localisedDescription，也不判类型——
//     0x6b354 stp x0, x8,[sp,#0x20]：x0 就是入参本身，直接当 receipt 的值；
//     0x6b378 bl _objc_retain（retain 入参）→ 0x6b37c mov x20, x0；
//     0x6b39c bl _objc_release_x20（释放同一寄存器）；
//     区间内唯一的消息发送是 0x6b390 sel:dictionaryWithObjects:forKeys:count:
//     （x0 = NSDictionary 类槽 0x119ce8），没有任何 localizedDescription / isKindOfClass: /
//     stringWithFormat: 调用。三键：receipt(CF 0xf6128) / failed(CF 0xf6148) / images(CF 0xf6108)。
static NSDictionary *PDDeviceToolsFailureFromError(id error) {
    // 0x6b354：error 本体就是 receipt 的值（不改写成字符串，不做类型分支）
    return PDDeviceToolsEnvelope((NSString *)error);
}

// 0x6b874..0x6b9e8（96 insns）：从参数字典取 double。
//   x0 = 值  x1 = 参数名  x2 = double *out  x3 = NSString **error
//   文档串：0x6b914 @"Missing required parameter: %@"（值为 nil）
//           0x6b994 @"Invalid parameter %@: expected number"（类型/解析失败）
static BOOL PDDeviceToolDoubleParameter(id value, NSString *name, double *outValue,
                                        NSString **outError) {
    if (!value) {                                                          // [0x6b8a8]
        if (outError) { *outError = [NSString stringWithFormat:@"Missing required parameter: %@", name]; }
        return NO;
    }
    if (value == (id)[NSNull null]) {                                     // [0x6b8c4] b.eq
        if (outError) { *outError = [NSString stringWithFormat:@"Missing required parameter: %@", name]; }
        return NO;                                                        // [0x6b900]
    }
    if ([value isKindOfClass:[NSNumber class]]) {                          // [0x6b8e0]
        if (outValue) { *outValue = [value doubleValue]; }                  // [0x6b8f0]
        return YES;                                                        // [0x6b8f8]
    }
    if ([value isKindOfClass:[NSString class]]) {                          // [0x6b930]
        NSScanner *scanner = [NSScanner scannerWithString:value];           // [0x6b944]
        double parsed = 0;
        if ([scanner scanDouble:&parsed] && [scanner isAtEnd]) {            // [0x6b958]/[0x6b964]
            if (outValue) { *outValue = parsed; }                           // [0x6b974]
            return YES;
        }
    }
    if (outError) {                                                        // [0x6b984]
        *outError = [NSString stringWithFormat:@"Invalid parameter %@: expected number", name];
    }
    return NO;
}

// 0x6b9e8..0x6babc（53 insns）：从参数字典取 BOOL。
//   x0 = arguments  x1 = key  x2 = BOOL *out
//   路径：isKindOfClass:NSDictionary → objectForKeyedSubscript: → 非 nil/非 NSNull
//        → respondsToSelector:@selector(boolValue) → *out = boolValue
static BOOL PDDeviceToolBoolParameter(id arguments, NSString *key, BOOL *outValue) {
    if (![arguments isKindOfClass:[NSDictionary class]]) {                  // [0x6b9e8]/[0x6ba18]
        return NO;
    }
    id value = [arguments objectForKeyedSubscript:key];                     // [0x6ba28]
    if (!value || value == [NSNull null]) {                                 // [0x6ba34]/[0x6ba4c]
        return NO;
    }
    if (outValue && [value respondsToSelector:@selector(boolValue)]) {      // [0x6ba60]
        *outValue = [value boolValue];                                      // [0x6ba78]
        return YES;
    }
    return NO;                                                              // [0x6ba9c]
}

#pragma mark - §SELFCHECK
// 括号走查：14 个方法全闭合；execute 内 3 层块（prepare 回调 / 队列块 / 主线程块）逐层闭合；
//   两个参数解析函数各 4 个出口，均 return。
// 方法计数：method-table 14 条 → 本文件 14 个方法（含 10 个访问器）。
// 已定案汇总（复核 2026-11-28）：
//   PDDeviceToolsFailureFromError 不取 localizedDescription —— 直接把入参当 receipt（0x6b354/0x6b378/0x6b39c）；
//   信封 images 的空常量是 @[]（槽 0xf0638 = ___NSArray0__struct，0x6b364 与 0x6b6fc 两处同槽），
//     failed 是 @YES（槽 0xf0660 = ___kCFBooleanTrue）；-init 里 AXScope 的接收者是**类**（0x6b064/0x6b068）。
// NOT RUN：未编译/未运行。
