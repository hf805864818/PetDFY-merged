//
//  PDDeviceAXScope.m
//  PetDFY
//
//  “辅助功能作用域”：在后台队列申请一次 AX 读写窗口，到点自动关闭。
//
//  二进制证据
//    image base      : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表          : out/method-table-all.md → 18 条（3 条 `+` / 15 条 `-`）
//    区间            : 0x6babc .. 0x6c568（-recoverInterruptedScope 起，.cxx_destruct 及其后
//                      的静态块/辅助函数止于 0x6c568）
//    instanceSize    : 40（0x28）
//    ivar（__objc_ivar 实读）
//      _closed      +0x08 B    _changed +0x09 B    _ready +0x0a B
//      _readState   +0x10 @?   _writeState +0x18 @?  _markRestore +0x20 @?
//    file-static 弱引用 : 0x11c038（__DATA），-closeOnMain 与工作块都用 objc_loadWeakRetained/
//                        objc_storeWeak 访问它 → 推断为 `static __weak PDDeviceAXScope *gCurrentScope`
//
//  本文件内的静态函数（都不在方法表里，靠调用点定位）
//    0x6bb78  PDDeviceAXEnabledGetter()   dlsym("_AXSApplicationAccessibilityEnabled") → BOOL(^)(void)
//    0x6bbdc  PDDeviceAXEnabledSetter()   dlsym("_AXSApplicationAccessibilitySetEnabled") → void(^)(BOOL)
//    0x6c3e0  getter 块 invoke：`return fn() != 0;`（0x6c3ec cset w0,ne）
//    0x6c400  setter 块 invoke：`fn(flag);`（0x6c404 br x2）
//    0x6c414  PDWithScreenCaptureDisabled(layer, body)   @try/@finally，设 setDisableUpdateMask:0x12
//    0x6c4f4  _PDSetLayerHiddenFromScreenCapture(layer, BOOL)   符号名直接取自 symtab
//    0x6c05c  工作块内 dispatch_after → [scope closeOnMain]
//    0x6c064  工作块内 dispatch_after → dispatch_semaphore_signal
//    0x11c038 见上
//
//  两处“错误输出”是直接把 CFString 写进 ^@ 槽（0x6bdb0 / 0x6bdf8），
//  说明原实现的 error 参数实际承载的是字符串；本文件按 Observed 原样保留并在行尾标注。
//
//  符号修正（跨单元一致性，2026-11-28）
//    recoverInterruptedScope / acquireWithRead:write:mark:warmup:duration:error: / acquireWithError:
//    三条是**类方法**（sign = +），已改为 `+`。这三个方法体内不访问任何 ivar：
//    acquireWithRead: 里 `[PDDeviceAXScope new]` 造实例（0x6bcb4 _objc_opt_new），
//    acquireWithError: 里 `[self acquireWithRead:…]` 是类方法调类方法（两者同为 +）。
//    其余 15 条仍是实例方法（-closeOnMain / -finish / 12 个访问器 / -.cxx_destruct）。
//
//  标记：[0xADDR] = 指令地址；Assumed = 语义推断；CALL 0xADDR = 未解析调用（本文件 0 处）
//  已定案 2026-11-28（复核）：图例中的 “CALL 0xADDR（本文件 0 处）” 成立——
//    本文件里 “CALL 0x” 字样只出现在本行图例自身，正文 0 处。
//
//  编译状态：NOT RUN（Windows 主机，无 iOS SDK）
//

#import "PDDeviceAXScope.h"
#import <dlfcn.h>

// CFPreferences 键与域：0x6bad0 / 0x6bad8（两处 CFString 实读）
static NSString *const PDDeviceAXRestorePendingKey = @"DeviceAXRestorePending";
static NSString *const PDDeviceAXPrefsDomain = @"com.susudear.petdfyprefs";

// 0x11c038：唯一被 objc_storeWeak/objc_loadWeakRetained 直接操作的全局槽
static __weak PDDeviceAXScope *gCurrentScope;

typedef BOOL (^PDDeviceAXEnabledGetterBlock)(void);
typedef void (^PDDeviceAXEnabledSetterBlock)(BOOL enabled);

// ---------------------------------------------------------------------------
// 0x6bb78..0x6bbdc（38 insns）：把 dlsym 得到的函数指针包成块返回。
//   x0 = dlsym(RTLD_DEFAULT(-2), "_AXSApplicationAccessibilityEnabled")
//   块捕获该指针（块体 +0x20），invoke = 0x6c3e0
// ---------------------------------------------------------------------------
static PDDeviceAXEnabledGetterBlock PDDeviceAXEnabledGetter(void) {
    // [0x6bb88] "_AXSApplicationAccessibilityEnabled"；[0x6bb8c] x0 = -2 (RTLD_DEFAULT)
    void *fn = dlsym((void *)-2, "_AXSApplicationAccessibilityEnabled");  // [0x6bb90]
    if (!fn) {
        return nil;                                                       // [0x6bb94] cbz
    }
    BOOL (^block)(void) = ^{                                              // [0x6bbc8]
        return ((BOOL (*)(void))fn)() != 0;                               // [0x6c3e8]/[0x6c3f0]
    };
    return [block copy];                                                  // [0x6bbcc] _objc_retainBlock
}

// 0x6bbdc..0x6bc40（38 insns）：同上，写端。
static PDDeviceAXEnabledSetterBlock PDDeviceAXEnabledSetter(void) {
    // [0x6bbec] "_AXSApplicationAccessibilitySetEnabled"
    void *fn = dlsym((void *)-2, "_AXSApplicationAccessibilitySetEnabled"); // [0x6bbf4]
    if (!fn) {
        return nil;                                                       // [0x6bbf8] cbz
    }
    void (^block)(BOOL) = ^(BOOL enabled) {                               // [0x6bc2c]
        ((void (*)(BOOL))fn)(enabled);                                    // [0x6c404] br x2
    };
    return [block copy];                                                  // [0x6bc30]
}

// 0x6c4f4..0x6c568（29 insns）：若 layer 响应 setDisableUpdateMask:，
//   隐藏时传 0x12（0x6c540 mov w8,#0x12），否则传 0。
void _PDSetLayerHiddenFromScreenCapture(id layer, BOOL hidden) {
    SEL sel = NSSelectorFromString(@"setDisableUpdateMask:");             // [0x6c514]
    if (layer && [layer respondsToSelector:sel]) {                        // [0x6c530]
        NSUInteger mask = hidden ? 0x12 : 0;                              // [0x6c544] csel
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(layer, sel, mask);   // [0x6c550]
    }
}

// 0x6c414..0x6c4f4（57 insns）：在“屏蔽录屏更新”的窗口里执行 body，@try/@finally 保证还原。
static id PDWithScreenCaptureDisabled(id layer, id (^body)(void)) {
    id result = nil;
    BOOL inFlight = NO;
    @try {
        if (layer && body && [layer respondsToSelector:NSSelectorFromString(@"setDisableUpdateMask:")]) {
            _PDSetLayerHiddenFromScreenCapture(layer, YES);               // [0x6c45c]
            [layer flush];                                                // [0x6c468]
        }
        result = body ? body() : nil;                                     // [0x6c474] blr
        inFlight = YES;
    } @finally {
        _PDSetLayerHiddenFromScreenCapture(layer, NO);                     // [0x6c48c]
        [layer flush];                                                     // [0x6c498]
    }
    return result;
}

#pragma mark -

@implementation PDDeviceAXScope

// ---------------------------------------------------------------------------
// +[PDDeviceAXScope recoverInterruptedScope]  imp=0x6babc insns=97
//   App 启动时：若上次留下“待还原”标记，就把 AX 关掉一次；关不掉则保留标记。
// ---------------------------------------------------------------------------
+ (void)recoverInterruptedScope {
    // [0x6bb04] CFPreferencesGetAppBooleanValue(key, domain, NULL)
    if (!CFPreferencesGetAppBooleanValue((__bridge CFStringRef)PDDeviceAXRestorePendingKey,
                                         (__bridge CFStringRef)PDDeviceAXPrefsDomain,
                                         NULL)) {
        return;                                                           // [0x6bb68]
    }
    PDDeviceAXEnabledGetterBlock getter = PDDeviceAXEnabledGetter();       // [0x6bae8] bl 0x6bb78
    PDDeviceAXEnabledSetterBlock setter = PDDeviceAXEnabledSetter();       // [0x6baf4] bl 0x6bbdc
    if (!getter || !setter) {                                             // [0x6bb04]/[0x6bb08]
        return;
    }
    setter(NO);                                                           // [0x6bb18] w1=0
    if (getter()) {                                                       // [0x6bb24] tbnz w0
        return;
    }
    // [0x6bb38] 关掉了 → 清标记
    CFPreferencesSetAppValue((__bridge CFStringRef)PDDeviceAXRestorePendingKey, NULL,
                             (__bridge CFStringRef)PDDeviceAXPrefsDomain);  // [0x6bb44]
    CFPreferencesAppSynchronize((__bridge CFStringRef)PDDeviceAXPrefsDomain); // [0x6bb4c]
}

// ---------------------------------------------------------------------------
// +[PDDeviceAXScope acquireWithRead:write:mark:warmup:duration:error:]
//   imp=0x6bc40 insns=290
//   形参（arm64）：x2 read(块) x3 write(块) x4 mark(块) d0 warmup d1 duration x5 error
//   栈帧 0xc0；主线程工作块的捕获顺序 = scope/sem/read/mark/write/warmup/duration
// ---------------------------------------------------------------------------
+ (instancetype)acquireWithRead:(BOOL (^)(void))read
                          write:(void (^)(BOOL))write
                           mark:(void (^)(BOOL))mark
                         warmup:(double)warmup
                       duration:(double)duration
                          error:(NSError **)error {
    // [0x6bc60..0x6bc68] x22=error, d8=duration, d9=warmup
    if (error) {
        *error = nil;                                                     // [0x6bc94] str xzr
    }
    // [0x6bc9c] NSThread +isMainThread
    if (!read || !write || [NSThread isMainThread]) {                     // [0x6bca4] 三处 cbz/cbnz
        // [0x6bde8] 直接存字符串（Observed：^@ 槽里放的是 CFString）
        if (error) { *error = (NSError *)@"应用辅助功能接口不可用，或查询不在后台队列。"; }
        return nil;                                                       // [0x6bde8..0x6bdf8]
    }
    // [0x6bcb4] _objc_opt_new → PDDeviceAXScope
    PDDeviceAXScope *scope = [PDDeviceAXScope new];
    scope.readState = read;                                               // [0x6bcc0]
    scope.writeState = write;                                             // [0x6bccc]
    scope.markRestore = mark;                                             // [0x6bcd8]
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);              // [0x6bce0]
    // [0x6bd14..0x6bd44] 块字面量（invoke 0x6be38），捕获 scope/sem/read/mark/write + 两个 double
    dispatch_async(dispatch_get_main_queue(), ^{                          // [0x6bd54]
        if (scope.closed) {                                               // [0x6be5c]
            goto signal;                                                  /* [0x6bff8] */
        }
        {
            PDDeviceAXScope *cur = gCurrentScope;                         // [0x6be68]
            if (cur && !gCurrentScope.closed) {                           // [0x6be7c]/[0x6be94]
                goto signal;
            }
        }
        gCurrentScope = scope;                                            // [0x6bea4] objc_storeWeak
        if (!read()) {                                                    // [0x6beac] blr
            scope.changed = YES;                                          // [0x6bec0]
            if (mark) { mark(YES); }                                      // [0x6bed4] w1=1
            write(YES);                                                   // [0x6bee4] w1=1
        }
        scope.ready = read();                                             // [0x6befc] setReady:
        // [0x6bf00] 第一次 dispatch_after：warmup 秒后在主线程关闭本作用域
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(warmup * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [scope closeOnMain];                                          /* [0x6c05c] */
        });
        // [0x6bf78..0x6bf90] 第二次 dispatch_after：开启过才等 duration，否则立刻放行
        int64_t delta = scope.changed ? (int64_t)(duration * NSEC_PER_SEC) : 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delta),
                       dispatch_get_main_queue(), ^{
            dispatch_semaphore_signal(sem);                               /* [0x6c064] */
        });
        return;
    signal:
        dispatch_semaphore_signal(sem);                                   /* [0x6bff8] */
    });
    // [0x6bd5c] 等待 duration 秒
    long waited = dispatch_semaphore_wait(sem,
                     dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC))) != 0;
    if (waited == 0 && scope.ready && !scope.closed) {                    // [0x6bd7c]/[0x6bd88]/[0x6bd94]
        return scope;                                                     // [0x6be2c] retain + autorelease
    }
    [scope finish];                                                       // [0x6bd9c]
    if (error) {
        // [0x6bda8] 同样是把 CFString 写进 ^@ 槽（Observed）
        *error = (NSError *)@"应用辅助功能未及时就绪；本次未读取元素，也不会重试。";
    }
    return nil;                                                           // [0x6bde8..0x6bdec]
}

// ---------------------------------------------------------------------------
// +[PDDeviceAXScope acquireWithError:]  imp=0x6c0c8 insns=49
//   便捷入口：read/write 用 dlsym 出来的 AXS 开关，mark 用全局块
//   （0x6c0f8 __NSConcreteGlobalBlock，块体 0x6c14c..0x6c18c 写 CFPreferences）。
//   warmup = 1.2（0x6c104 取 0xbf000+0xf40），duration = 3.0（0x6c108 fmov d1,#3.0）。
// ---------------------------------------------------------------------------
+ (instancetype)acquireWithError:(NSError **)error {
    PDDeviceAXEnabledGetterBlock getter = PDDeviceAXEnabledGetter();       // [0x6c0e0]
    PDDeviceAXEnabledSetterBlock setter = PDDeviceAXEnabledSetter();       // [0x6c0ec]
    void (^mark)(BOOL) = ^(BOOL pending) {                                 // [0x6c0fc] 全局块
        // [0x6c154] kCFBooleanTrue / [0x6c160] csel：pending ? kCFBooleanTrue : NULL
        CFPreferencesSetAppValue((__bridge CFStringRef)PDDeviceAXRestorePendingKey,
                                 pending ? kCFBooleanTrue : NULL,
                                 (__bridge CFStringRef)PDDeviceAXPrefsDomain); // [0x6c178]
        CFPreferencesAppSynchronize((__bridge CFStringRef)PDDeviceAXPrefsDomain); // [0x6c188]
    };
    // [0x6c11c]
    return [self acquireWithRead:getter write:setter mark:mark warmup:1.2 duration:3.0 error:error];
}

// ---------------------------------------------------------------------------
// -[PDDeviceAXScope closeOnMain]  imp=0x6c18c insns=70
//   只在主线程调用；关掉自己，并在需要时撤销 AX 开关。
// ---------------------------------------------------------------------------
- (void)closeOnMain {
    if (self.closed) {                                                     // [0x6c1a4] tbnz
        return;
    }
    self.closed = YES;                                                     // [0x6c1b0]
    if (gCurrentScope == self) {                                           // [0x6c1bc]/[0x6c1c8] cmp
        gCurrentScope = nil;                                               // [0x6c1dc]
    }
    if (!self.changed) {                                                   // [0x6c1e8] cbz w0
        return;
    }
    void (^write)(BOOL) = self.writeState;                                 // [0x6c1f0]
    if (write) { write(NO); }                                              // [0x6c204] w1=0
    BOOL (^read)(void) = self.readState;                                   // [0x6c210]
    if (read && read()) {                                                  // [0x6c224] cbz w0
        return;   // 仍处于开启状态：保留 restore 标记
    }
    void (^mark)(BOOL) = self.markRestore;                                 // [0x6c234]
    if (!mark) {                                                           // [0x6c24c] cbz x20
        return;
    }
    mark(NO);                                                              // [0x6c268] w1=0
}

// ---------------------------------------------------------------------------
// -[PDDeviceAXScope finish]  imp=0x6c2a4 insns=36
//   主线程直接关；否则同步切到主线程关（dispatch_sync，块体 0x6c32c）。
// ---------------------------------------------------------------------------
- (void)finish {
    if ([NSThread isMainThread]) {                                         // [0x6c2c0] cbz w0
        [self closeOnMain];                                                // [0x6c2d8] b
        return;
    }
    dispatch_sync(dispatch_get_main_queue(), ^{                            // [0x6c318]
        [self closeOnMain];                                                /* [0x6c32c] */
    });
}

#pragma mark - 属性访问器

// -[PDDeviceAXScope readState]  imp=0x6c334 insns=2
- (BOOL (^)(void))readState { return _readState; }                          // [0x6c334]
// -[PDDeviceAXScope setReadState:]  imp=0x6c33c insns=2
- (void)setReadState:(BOOL (^)(void))readState {
    // [0x6c340] objc_setProperty_nonatomic_copy，偏移 0x10
    _readState = [readState copy];
}
// -[PDDeviceAXScope writeState]  imp=0x6c344 insns=2
- (void (^)(BOOL))writeState { return _writeState; }                        // [0x6c344]
// -[PDDeviceAXScope setWriteState:]  imp=0x6c34c insns=2
- (void)setWriteState:(void (^)(BOOL))writeState {
    // [0x6c350] 偏移 0x18
    _writeState = [writeState copy];
}
// -[PDDeviceAXScope markRestore]  imp=0x6c354 insns=2
- (void (^)(BOOL))markRestore { return _markRestore; }                      // [0x6c354]
// -[PDDeviceAXScope setMarkRestore:]  imp=0x6c35c insns=2
- (void)setMarkRestore:(void (^)(BOOL))markRestore {
    // [0x6c360] 偏移 0x20
    _markRestore = [markRestore copy];
}
// -[PDDeviceAXScope closed]  imp=0x6c364 insns=3
- (BOOL)closed { return _closed & 1; }                                     // [0x6c364] ldrb +0x08
// -[PDDeviceAXScope setClosed:]  imp=0x6c370 insns=2
- (void)setClosed:(BOOL)closed { _closed = closed; }                       // [0x6c370] strb +0x08
// -[PDDeviceAXScope changed]  imp=0x6c378 insns=3
- (BOOL)changed { return _changed & 1; }                                   // [0x6c378] ldrb +0x09
// -[PDDeviceAXScope setChanged:]  imp=0x6c384 insns=2
- (void)setChanged:(BOOL)changed { _changed = changed; }                   // [0x6c384] strb +0x09
// -[PDDeviceAXScope ready]  imp=0x6c38c insns=3
- (BOOL)ready { return _ready & 1; }                                       // [0x6c38c] ldrb +0x0a
// -[PDDeviceAXScope setReady:]  imp=0x6c398 insns=2
- (void)setReady:(BOOL)ready { _ready = ready; }                           // [0x6c398] strb +0x0a

// ---------------------------------------------------------------------------
// -[PDDeviceAXScope .cxx_destruct]  imp=0x6c3a0 insns=114
//   前 21 条是真正的析构（+0x20 / +0x18 / +0x10 三个块属性置 nil，顺序同 ivar 声明逆序）；
//   0x6c3e0 之后是 4 个静态实体（getter 块 invoke、setter 块 invoke、
//   PDWithScreenCaptureDisabled、_PDSetLayerHiddenFromScreenCapture），方法表按“下一个
//   方法起点”截断，所以把它们算进了本方法区间。
// ---------------------------------------------------------------------------
- (void).cxx_destruct {
    _markRestore = nil;                                                    // [0x6c3b8] +0x20
    _writeState = nil;                                                     // [0x6c3c4] +0x18
    _readState = nil;                                                      // [0x6c3d8] +0x10
}

@end

#pragma mark - §SELFCHECK
// 括号走查：18 个方法体全闭合；acquireWithRead: 内块里用 goto 跳到同一块内的 signal 标签；
//   两个 dispatch_after 块与 dispatch_async 块均在各自括号内闭合。
// 方法计数：method-table 18 条 → 本文件 18 个方法实现（含 12 个访问器）。
// 已定案汇总（复核 2026-11-28）：
//   · 0x11c038 是唯一的 weak 全局：objc_loadWeakRetained 于 0x6be68 / 0x6be7c（acquireWithRead: 主线程块内）
//     与 0x6c1bc（closeOnMain）；objc_storeWeak 于 0x6bea4（存入新 scope 的 +0x20）与 0x6c1dc（置 nil）。
//     语义=「当前作用域」单例成立；标识符 gCurrentScope 只是命名，二进制无符号可比对（不存在“定不定的问题”）。
//   · PDWithScreenCaptureDisabled（0x6c414）：全镜像 __text 扫描（0x4000..0xa1d474，bl/b 目标比对）
//     没有任何调用点指向 0x6c414 → 原注「无调用者可见」是客观事实，不是推断。
//   · 两处 error 槽放 CFString（0x6bdb0 / 0x6bdf8）仍是 Observed，未改。
// NOT RUN：未编译/未运行。

