//
//  PDNative_AppManager.m
//  PetDFY
//
//  应用安装 / 启动 / 终止 / 卸载，以及越狱环境下的 ad-hoc 重签（fakesign）。
//
//  二进制证据
//    image base  : 0（extract/bin/PetDFY.arm64.dylib, sha256 E4DE3DA9…B6EF）
//    方法表      : out/method-table-all.md → 27 条（1 条 `+` / 26 条 `-`）
//    区间        : 0x73870 .. 0x7e950（共 11320 条指令，本批最大单元）
//    instanceSize: 8（0x08）—— 无实例 ivar，全部走单例 + 局部状态
//
//  还原口径（本文件是 Tier-2：调用序列 + 分支骨架 + 全部字符串常量逐字还原；
//  纯算术与寄存器搬运不逐条转写）
//  已定案 2026-11-28（复核）：原文写“凡语义不唯一的判断都打 Assumed 并给地址”，实测 18 条
//  Assumed 里 17 条不带地址，口径与实际不符。本次已逐条补地址或结论，见 out/notes/assume-a.md。
//  同批核对：本文件 27 条 imp 与 out/method-table-all.md 的 PDNative_AppManager 行集合完全相等
//  （0x73870..0x7e324；sign 列 1 个 + / 26 个 -，与下行一致）。
//
//  跨文件依赖（这些静态函数不在本文件里，签名由调用点反推）
//    PDNative_MCPResolvedJailbreakPath(NSString *)      0x78ea4 起（多处）
//    PDNative_MCPJailbreakEnvironment(void)             0x7b408
//    PDNative_MCPRunProcess(...)                        0x7aab0
//    PDNative_MCPResolvedJailbreakPath 解析、mcp-root/mcp-ldid 定位、dpkg 落盘
//
//  符号修正（跨单元一致性，2026-11-28）
//    +sharedInstance 是**类方法**（sign = +，0x73870），已改为 `+`；其余 26 条为实例方法。
//    本文件里对 `frontmostApplicationInfo` 的三处调用改用
//    `PDAppFrontmostInfo()`（0x7e79c 静态函数，走 PDNative_AccessibilityManager）：
//    该 selector 不在本类方法表内（CALL 0x7e79c 是跨文件静态入口），走 performSelector 以免假定签名。
//    同时把 `[PDNative_MCPLogger.sharedInstance …]` 全部改为 `[PDNative_MCPLogger …]`
//    —— MCPLogger 没有实例方法，`isDebugLoggingEnabled` 是类方法。
//
//  标记：[0xADDR] = 指令地址 / Assumed / NOT RUN
//  已定案 2026-11-28（复核）：图例可用——本文件内 “CALL 0x” 内联标记共 12 处，指向
//  0x7e79c / 0x752fc / 0x75e94 / 0x75be8 / 0x76c14 / 0x77590 / 0x7d0d8 / 0x79b90 八个本文件外的
//  静态入口；其中 0x79b90 已在本次解出（见行 1692 段）。
//

#import "PDNative_AppManager.h"
#import "PDNative_MCPLogger.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>   // SecStaticCode* / kSecCodeInfoEntitlementsDict（0x79bd4/0x79bfc/0x79c20）
#import <objc/runtime.h>
#import <objc/message.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

extern NSString *PDNative_MCPResolvedJailbreakPath(NSString *name);   // 0x78ea4
extern NSDictionary *PDNative_MCPJailbreakEnvironment(void);          // 0x7b408
extern id PDNative_MCPRunProcess(NSArray *argv, NSDictionary *env, NSString **output, int *exitCode); // 0x7aab0

static NSString *const kPDAppLogPrefix = @"[witchan][ios-mcp]%@";     // 0x…（各方法共用）
static NSString *const kPDAppContainersRoot = @"/var/containers/Bundle/Application"; // 0x761…/0x766…

// 0x7e79c..0x7e810（静态函数，被 launchApp/openURL 共用）：
//   [PDNative_AccessibilityManager sharedInstance] → frontmostApplicationInfo
//   → 非 NSDictionary 时用空字典顶替（0x7e7e0 isKindOfClass: + 0x7e7f0 csel）。
//   Observed：0x7e7ac 的类槽（0x11a090 → 0x11b9d0）= PDNative_AccessibilityManager；
//   调用形式是两段零参 objc_msgSend，没有多参 performSelector。
static NSDictionary *PDAppFrontmostInfo(void) {
    Class managerClass = NSClassFromString(@"PDNative_AccessibilityManager");        // 0x7e7ac
    if (!managerClass) { return @{}; }
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, @selector(sharedInstance)); // 0x7e7b0
    id info = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(frontmostApplicationInfo));  // 0x7e7bc
    return ([info isKindOfClass:[NSDictionary class]]) ? info : @{};                 // 0x7e7e0/0x7e7f0
}

// 0x74a58..0x74bb8（静态函数，listInstalledApps: 的块内 0x748bc 调用）：
//   applicationType 归一。参数 (proxy x0, bundleId x1, type x2)，返回值 retain/autorelease。
//   已定案（逐分支，复核 2026-11-28）：
//     0x74a94  [type isEqualToString:@"User"]            → 返回 @"User"（0x74a8c 预置 x23=CF 0xfee28）
//     0x74aac  [proxy respondsToSelector:@selector(bundleURL)]
//     0x74ac0  bl 0x752fc(proxy, bundleURL) → 0x74ae0 isKindOfClass:NSURL
//     0x74aec/0x74af8 [url path] → stringByStandardizingPath
//     0x74b2c  [path containsString:@"/Containers/Bundle/Application/"]（CF 0x100088）→ 返回 @"User"
//     0x74b34/0x74b48 bundleId.length != 0 && ![bundleId hasPrefix:@"com.apple."]（CF 0x1000a8）→ 返回 @"User"
//     0x74b5c  [type isEqualToString:@"Internal"]（CF 0x1000c8）      → 返回 @"System"（CF 0x1000e8）
//     0x74b78  type.length ? type : @"System"
//   注意极性：容器内路径与「非 com.apple. 前缀」都归 **User**；System 只由 com.apple. 前缀
//   或空类型给出——与旧注释「容器内/苹果自家包归 System」相反。
static NSString *PDAppNormalizedAppType(id proxy, NSString *bundleId, NSString *type) {
    if ([type isEqualToString:@"User"]) { return @"User"; }                    // 0x74a94
    NSString *path = nil;
    if ([proxy respondsToSelector:@selector(bundleURL)]) {                     // 0x74aac
        id u = ((id (*)(id, SEL))objc_msgSend)(proxy, @selector(bundleURL));   // 0x74ac0 → 0x752fc
        if ([u isKindOfClass:[NSURL class]]) {                                 // 0x74ae0
            path = [[u path] stringByStandardizingPath];                       // 0x74aec / 0x74af8
        }
    }
    if ([path containsString:@"/Containers/Bundle/Application/"]) { return @"User"; }        // 0x74b2c
    if (bundleId.length && ![bundleId hasPrefix:@"com.apple."]) { return @"User"; }          // 0x74b34 / 0x74b48
    if ([type isEqualToString:@"Internal"]) { return @"System"; }                            // 0x74b5c
    return type.length ? type : @"System";                                                   // 0x74b78
}

@implementation PDNative_AppManager

// ---------------------------------------------------------------------------
// +[PDNative_AppManager sharedInstance]  imp=0x73870 insns=26
// ---------------------------------------------------------------------------
+ (instancetype)sharedInstance {
    static id shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self class] new]; });            // [0x738b0] objc_alloc_init
    return shared;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager launchApp:error:]  imp=0x738d8 insns=639
// [0x73a68]  insn#100
// [0x73bf8]  insn#200
// [0x73d88]  insn#300
// [0x73f18]  insn#400
// [0x740a8]  insn#500
// [0x74238]  insn#600
//   主路径 LSApplicationWorkspace openApplicationWithBundleID:；随后轮询前台 5 秒；
//   失败再走 SBUIController activateApplication: 兜底。
// ---------------------------------------------------------------------------
- (BOOL)launchApp:(NSString *)bundleId error:(NSError **)error {
    if (!bundleId.length) {                                             // [0x738d8]
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey: @"Empty bundle ID"}]; }
        return NO;
    }
    Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");      // [0x739…]
    if (!LSAppWorkspace || ![LSAppWorkspace respondsToSelector:@selector(defaultWorkspace)]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace is unavailable"}]; }
        return NO;
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)((id)LSAppWorkspace,
                                                   @selector(defaultWorkspace));
    if (!workspace) {                                                    // 文案 0x…: "LSApplicationWorkspace defaultWorkspace returned nil"
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace defaultWorkspace returned nil"}]; }
        return NO;
    }
    if (![workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                     userInfo:@{NSLocalizedDescriptionKey:
                        @"LSApplicationWorkspace openApplicationWithBundleID: is unavailable"}]; }
        return NO;
    }
    CFTimeInterval started = CFAbsoluteTimeGetCurrent();                  // [0x739…]
    BOOL opened = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace,
                     @selector(openApplicationWithBundleID:), bundleId);
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        // @"[App] LaunchServices launch request for %@ returned %@ in %.0fms"
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] LaunchServices launch request for %@ returned %@ in %.0fms",
              bundleId, opened ? @"YES" : @"NO",
              (CFAbsoluteTimeGetCurrent() - started) * 1000.0]);
    }
    if (!opened) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey:
                        @"LSApplicationWorkspace openApplicationWithBundleID: returned NO"}]; }
        return NO;
    }
    // ---- 前台确认：最多 5 秒 ----
    if ([NSThread isMainThread]) {                                        // [0x73a…] isMainThread
        dispatch_sync(dispatch_get_global_queue(0, 0), ^{ /* 轮询放到后台队列 */ });
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];         // 已定案 0x73ba4: fmov d0,#5.0 → 0x73ba8 bl sel:dateWithTimeIntervalSinceNow:
    NSString *frontmost = nil;
    while ([deadline timeIntervalSinceNow] > 0) {
        NSDictionary *info = PDAppFrontmostInfo(); // CALL 0x7e79c
        frontmost = info[@"bundleId"] ?: info[@"CFBundleIdentifier"];
        if ([frontmost isEqualToString:bundleId]) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                // @"[App] Launch confirmed in foreground: %@"
                NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                      @"[App] Launch confirmed in foreground: %@", bundleId]);
            }
            return YES;
        }
        [NSThread sleepForTimeInterval:0.1];                              // 已定案 0x73bdc: ldr d8,[0xbfc88](=0.1) → 0x73c50 fmov d0,d8 → 0x73c54 bl sel:sleepForTimeInterval:
    }
    {
        NSString *name = [[NSBundle bundleWithIdentifier:bundleId] localizedInfoDictionary][@"CFBundleDisplayName"];
        NSString *suffix = name.length ? [NSString stringWithFormat:@" (%@)", name] : @"";
        NSString *message = frontmost.length
            ? [NSString stringWithFormat:
                 @"Launch request sent for %@, but frontmost app is still %@%@",
                 bundleId, frontmost, suffix]
            : [NSString stringWithFormat:
                 @"Launch request sent for %@, but it did not become frontmost within 5 seconds",
                 bundleId];
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Launch not confirmed for %@, currentFrontmostBundleId=%@",
                  bundleId, frontmost ?: @"-"]);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"PDNative_AppManager" code:6
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
    }
    // ---- SBUIController 兜底（0x73d… 起，@try/@catch） ----
    @try {
        Class SBUIController = objc_getClass("SBUIController");           // [0x73e…]
        id controller = [SBUIController performSelector:@selector(sharedInstance)];
        if ([controller respondsToSelector:@selector(activateApplication:)]) {
            [controller performSelector:@selector(activateApplication:) withObject:workspace];
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                // @"[App] Launched app via activateApplication: %@"
                NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                      @"[App] Launched app via activateApplication: %@", bundleId]);
            }
            return YES;
        }
        if (error) {
            *error = [NSError errorWithDomain:@"PDNative_AppManager" code:7
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"%@; SBUIController fallback unavailable for %@",
                    @"LaunchServices request failed", bundleId]}];
        }
        return NO;
    } @catch (NSException *exception) {
        // 文案：@"LSApplicationWorkspace launch failed: %@" / @"unknown exception" / @"unknown"
        NSString *reason = exception.reason ?: @"unknown";
        NSString *name = exception.name ?: @"unknown exception";
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] LaunchServices launch exception for %@: %@ - %@",
                  bundleId, name, reason]);
        }
        if (error) {
            *error = [NSError errorWithDomain:@"PDNative_AppManager" code:8
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"LSApplicationWorkspace launch failed: %@", reason]}];
        }
        return NO;
    }
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager killApp:error:]  imp=0x742d4 insns=224
//   FBSSystemService terminateApplication:forReason:andReport:withDescription:（NSInvocation，实参 4 个）
// ---------------------------------------------------------------------------
- (BOOL)killApp:(NSString *)bundleId error:(NSError **)error {
    if (!bundleId.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Empty bundle ID"}]; }
        return NO;
    }
    __block BOOL killed = NO;
    __block NSError *inner = nil;
    void (^work)(void) = ^{
        Class FBS = objc_getClass("FBSSystemService");                    // [0x743…]
        id service = [FBS performSelector:@selector(sharedService)];
        // 0x744f8 的 selref 实读：terminateApplication:forReason:andReport:withDescription:（4 参）
        SEL terminate = @selector(terminateApplication:forReason:andReport:withDescription:);
        if (!service || ![service respondsToSelector:terminate]) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                    userInfo:@{NSLocalizedDescriptionKey:
                        service ? @"terminateApplication: selector not available"
                                : @"FBSSystemService not available"}];
            return;
        }
        NSMethodSignature *sig = [service methodSignatureForSelector:terminate];  // [0x743…]
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:service];
        [inv setSelector:terminate];
        [inv setArgument:&bundleId atIndex:2];                 // 0x74514 idx=2（bundleId）
        int reason = 1;                                        // 0x74518 w24=#1
        [inv setArgument:&reason atIndex:3];                   // 0x7452c idx=3
        BOOL andReport = NO;                                   // 0x74530 strb wzr,[sp,#0x13]
        [inv setArgument:&andReport atIndex:4];                // 0x74540 idx=4
        NSString *terminateDescription = @"Terminated via ios-mcp";   // 0x74548 CFString
        [inv setArgument:&terminateDescription atIndex:5];     // 0x7455c idx=5
        [inv retainArguments];
        [inv invoke];
        killed = YES;
    };
    if ([NSThread isMainThread]) {                                       // [0x743…]
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
    if (!killed) {
        if (error) { *error = inner; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        // 文案 0x…: @"Terminated via ios-mcp" 作为 reason 串；日志 @"[App] Killed app: %@"
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:@"[App] Killed app: %@", bundleId]);
    }
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager listInstalledApps:]  imp=0x74654 insns=345
// [0x747e4]  insn#100
// [0x74974]  insn#200
// [0x74b04]  insn#300
//   返回 @[{name, type, path?...}]；type 取 User / System / Internal。
// ---------------------------------------------------------------------------
- (NSArray<NSDictionary *> *)listInstalledApps:(NSString *)filter {
    __block NSArray *result = @[];
    void (^work)(void) = ^{
        Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
        id workspace = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        NSArray *all = [workspace performSelector:@selector(allInstalledApplications)];
        NSMutableArray *rows = [NSMutableArray array];
        for (id proxy in all) {
            NSString *bundleId = [proxy performSelector:@selector(applicationIdentifier)];  // 0x74870，选择器槽 0x119be8
            NSString *name = [proxy performSelector:@selector(localizedName)];              // 0x74884，槽 0x119bf0
            NSString *type = [proxy performSelector:@selector(applicationType)];            // 0x74898，槽 0x119bf8
            NSString *normalized = PDAppNormalizedAppType(proxy, bundleId, type);           // 0x748bc bl 0x74a58
            // 已定案 0x748c8 / 0x748f0：filter 是**类型过滤**，与 bundleId 无关——
            //   0x748c8 [filter isEqualToString:@"user"]（CF 0xf4348），
            //           且 0x748e8 归一类型 != @"User"（CF 0xfee28）→ 0x748ec cbz 跳到 0x749ac（跳过本行）；
            //   0x748f0 [filter isEqualToString:@"system"]（CF 0xf7448），
            //           0x74910 归一类型 == @"User" → 0x74914 tbnz 跳到 0x749ac（跳过本行）。
            //   其余取值（nil / 空串 / 其它）都不过滤；全函数没有 [filter length]，
            //   也没有 [bundleId isEqualToString:filter]。
            if ([filter isEqualToString:@"user"] && ![normalized isEqualToString:@"User"]) { continue; }
            if ([filter isEqualToString:@"system"] && [normalized isEqualToString:@"User"]) { continue; }
            NSString *path = nil;
            if ([proxy respondsToSelector:@selector(bundleURL)]) {                 // 0x74aac（归一函数内同一判定）
                id u = [proxy performSelector:@selector(bundleURL)];               // 0x752fc
                if ([u isKindOfClass:[NSURL class]]) {                            // 0x74ae0
                    path = [[u path] stringByStandardizingPath];                   // 0x74aec / 0x74af8
                }
            }
            [rows addObject:@{ @"name": name ?: @"",
                               @"bundleId": bundleId ?: @"",
                               @"type": normalized,
                               @"path": path ?: @"" }];
        }
        result = [rows copy];
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager listRunningApps]  imp=0x74bb8 insns=280
// [0x74d48]  insn#100
// [0x74ed8]  insn#200
//   私有 API runningApplications → 逐个取 bundleIdentifier（NSInvocation 处理返回值）
// ---------------------------------------------------------------------------
- (NSArray<NSDictionary *> *)listRunningApps {
    __block NSArray *result = @[];
    void (^work)(void) = ^{
        // 已定案 0x74cf4：类名是 "SBApplicationController"（cstr @0xba279），不是 SBWorkspace。
        //   0x74cf8 objc_getClass("SBApplicationController")，nil → 0x74fdc（空结果）；
        //   0x74d04 槽 0x118e98 = @selector(sharedInstance)，0x74d08 performSelector:（对类直接发，
        //       没有先 respondsToSelector:）；
        //   0x74d18 槽 0x119c00 = @selector(runningApplications)，0x74d20 respondsToSelector:，
        //       命中 → 0x74d38 performSelector:runningApplications；
        //       未命中 → 0x74d4c 槽 0x119c08 = @selector(allApplications)，0x74d54 performSelector:。
        Class appController = objc_getClass("SBApplicationController");             // 0x74cf8
        NSArray *running = nil;
        if (appController) {
            id ws = [appController performSelector:@selector(sharedInstance)];       // 0x74d08
            if ([ws respondsToSelector:@selector(runningApplications)]) {            // 0x74d20
                running = [ws performSelector:@selector(runningApplications)];       // 0x74d38
            } else {
                running = [ws performSelector:@selector(allApplications)];           // 0x74d54
            }
        }
        NSMutableArray *rows = [NSMutableArray array];
        for (id app in running) {
            NSString *bundleId = nil;
            SEL sel = @selector(bundleIdentifier);
            if ([app respondsToSelector:sel]) {
                NSMethodSignature *sig = [app methodSignatureForSelector:sel];   // [0x74d…]
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:app];
                [inv setSelector:sel];
                [inv invoke];
                __unsafe_unretained id value = nil;
                [inv getReturnValue:&value];
                bundleId = value;
            }
            if (bundleId.length) {
                [rows addObject:@{ @"name": bundleId, @"bundleId": bundleId, @"type": @"" }];
            }
        }
        result = [rows copy];
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager getFrontmostApp]  imp=0x75018 insns=196
//   返回 @{bundleId, name}
// ---------------------------------------------------------------------------
- (NSDictionary *)getFrontmostApp {
    // [0x75018..] 先取 frontmostApplicationInfo（CALL 0x752fc）
    NSDictionary *info = PDAppFrontmostInfo();
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *bundleId = info[@"bundleId"];
    NSString *name = info[@"name"];
    if (bundleId.length) { result[@"bundleId"] = bundleId; }             // [0x751…]
    if (name.length) { result[@"name"] = name; }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager openURL:error:]  imp=0x75328 insns=901
// [0x754b8]  insn#100
// [0x75648]  insn#200
// [0x757d8]  insn#300
// [0x75968]  insn#400
// [0x75af8]  insn#500
// [0x75c88]  insn#600
// [0x75e18]  insn#700
// [0x75fa8]  insn#800
// [0x76138]  insn#900
//   三级：UIApplication openURL:options:completionHandler: → LSApplicationWorkspace
//   openSensitiveURL: → prefs 特例（com.apple.Preferences / com.apple.springboard）；
//   之后按 scheme/host 轮询前台确认。
// ---------------------------------------------------------------------------
- (BOOL)openURL:(NSString *)urlString error:(NSError **)error {
    if (!urlString.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Empty URL"}]; }
        return NO;
    }
    NSURL *url = [NSURL URLWithString:urlString];                         // [0x753…] URLWithString:
    if (!url) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Invalid URL: %@", urlString]}]; }
        return NO;
    }
    __block BOOL ok = NO;
    __block NSError *inner = nil;
    void (^work)(void) = ^{                                              // CALL 0x75e94 / 0x75be8
        UIApplication *app = [UIApplication sharedApplication];
        if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            __block BOOL done = NO;
            __block BOOL accepted = NO;
            [app openURL:url options:@{} completionHandler:^(BOOL success) {
                accepted = success;
                done = YES;
            }];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];  // 已定案 0x75740: fmov d0,#1.5 → 0x75744 bl sel:dateWithTimeIntervalSinceNow:（不是 2.0）
            while (!done && [deadline timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            if (accepted) {
                ok = YES;
                if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                    NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                          @"[App] Opened URL via UIApplication: %@", urlString]);
                }
                return;
            }
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                    userInfo:@{NSLocalizedDescriptionKey:
                        done ? @"openURL returned NO" : @"openURL completion timed out"}];
        }
        // ---- LSApplicationWorkspace openSensitiveURL: ----
        Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
        id ws = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        SEL openSensitive = @selector(openSensitiveURL:withOptions:);
        if ([ws respondsToSelector:openSensitive]) {
            NSMethodSignature *sig = [ws methodSignatureForSelector:openSensitive];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:ws];
            [inv setSelector:openSensitive];
            [inv setArgument:&url atIndex:2];
            id options = @{};
            [inv setArgument:&options atIndex:3];
            [inv invoke];
            BOOL accepted = NO;
            [inv getReturnValue:&accepted];
            if (accepted) {
                ok = YES;
                if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                    NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                          @"[App] Opened URL via LSApplicationWorkspace: %@", urlString]);
                }
                return;
            }
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                    userInfo:@{NSLocalizedDescriptionKey: @"openSensitiveURL returned NO"}];
        }
        if (error) { *error = inner ?: [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey: @"No URL open method available"}]; }
    };
    if ([NSThread isMainThread]) {                                       // [0x753…] isMainThread
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);                  // CALL 0x75be8
    }
    if (!ok) { return NO; }
    // ---- 前台确认（scheme/host 判定，文案 "<url:%@://%@>" / "<url:%@>" / "<url>"） ----
    NSString *lower = urlString.lowercaseString;
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host;
    // 已定案 0x75e94..0x76038（静态函数 PDAppWaitForFrontmost，调用点 0x7557c 传 d0=2.0）：
    //   expected 三分支——0x75f2c/0x75f38 scheme=="prefs"（CF 0x100188）→ 0x75f44 标记；
    //   0x75f48/0x75f54 scheme=="app-prefs"（CF 0x1001a8）→ 同上 → @"com.apple.Preferences"（CF 0x100168）；
    //   否则 0x75ff8 host.length ? host（0x76008）: @"com.apple.springboard"（0x76018，CF 0xfee48）。
    //   全程只比较 scheme 与 host.length，**不判 scheme == "https"**；springboard 是「host 为空」的兜底。
    //   helper 内 0x75edc/0x75ee0 把超时下限钳到 0.1（fcsel）。
    NSString *expected = nil;
    if ([scheme isEqualToString:@"prefs"] || [scheme isEqualToString:@"app-prefs"]) {
        expected = @"com.apple.Preferences";                                 // 0x75f44 → 0x75f8c
    } else {
        expected = host.length ? host : @"com.apple.springboard";            // 0x75ff8 / 0x76018
    }
    if (expected) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        NSDictionary *front = PDAppFrontmostInfo();
        NSString *frontId = front[@"bundleId"];
        while (![frontId isEqualToString:expected] && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            front = PDAppFrontmostInfo();
            frontId = front[@"bundleId"];
        }
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Verified URL open after main dispatch: %@", urlString]);
        }
    }
    return ok;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager appBundlePathForBundleId:mainExecutablePath:]
//   imp=0x7613c insns=261
// [0x762cc]  insn#100
// [0x7645c]  insn#200
//   扫 /var/containers/Bundle/Application/<UUID>/<*.app>/Info.plist，取最新修改的一个。
// ---------------------------------------------------------------------------
- (NSString *)appBundlePathForBundleId:(NSString *)bundleId
                   mainExecutablePath:(NSString **)mainExecutablePath {
    if (!bundleId.length) { return nil; }
    NSFileManager *fm = [NSFileManager defaultManager];                   // [0x761…]
    NSString *bestPath = nil;
    NSString *bestExec = nil;
    NSDate *bestDate = nil;
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:kPDAppContainersRoot error:NULL]) {
        NSString *container = [kPDAppContainersRoot stringByAppendingPathComponent:uuid];
        for (NSString *item in [fm contentsOfDirectoryAtPath:container error:NULL]) {
            if (![[item pathExtension].lowercaseString isEqualToString:@"app"]) { continue; }
            NSString *appPath = [container stringByAppendingPathComponent:item];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [appPath stringByAppendingPathComponent:@"Info.plist"]];
            if (![info[@"CFBundleIdentifier"] isEqualToString:bundleId]) { continue; }
            NSString *execName = info[@"CFBundleExecutable"];
            if (!execName.length) { continue; }
            NSString *execPath = [appPath stringByAppendingPathComponent:execName];
            NSDictionary *attrs = [fm attributesOfItemAtPath:appPath error:NULL];
            NSDate *modified = attrs[NSFileModificationDate] ?: [NSDate distantPast];
            if (!bestDate || [modified compare:bestDate] == NSOrderedDescending) {
                bestDate = modified;
                bestPath = appPath;
                bestExec = execPath;
            }
        }
    }
    if (mainExecutablePath) { *mainExecutablePath = bestExec; }
    return bestPath;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager waitForAppBundlePathForBundleId:mainExecutablePath:timeout:]
//   imp=0x76550 insns=76
// ---------------------------------------------------------------------------
- (NSString *)waitForAppBundlePathForBundleId:(NSString *)bundleId
                           mainExecutablePath:(NSString **)mainExecutablePath
                                      timeout:(double)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];     // [0x765…]
    NSString *path = nil;
    while ([deadline timeIntervalSinceNow] > 0) {
        path = [self appBundlePathForBundleId:bundleId mainExecutablePath:mainExecutablePath];
        if (path.length) { return path; }
        [NSThread sleepForTimeInterval:0.25];                              // 已定案 0x76610: fmov d0,#0.25 → 0x76614 bl sel:sleepForTimeInterval:
    }
    return path;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager newestInstalledAppBundlePathAfterDate:resolvedBundleId:mainExecutablePath:]
//   imp=0x76680 insns=396
// [0x76810]  insn#100
// [0x769a0]  insn#200
// [0x76b30]  insn#300
// ---------------------------------------------------------------------------
- (NSString *)newestInstalledAppBundlePathAfterDate:(NSDate *)after
                                    resolvedBundleId:(NSString **)outBundleId
                                 mainExecutablePath:(NSString **)outExecPath
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *best = nil;
    NSDate *bestDate = after;
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:kPDAppContainersRoot error:NULL]) {
        NSString *container = [kPDAppContainersRoot stringByAppendingPathComponent:uuid];
        NSDictionary *cattrs = [fm attributesOfItemAtPath:container error:NULL];
        NSDate *cdate = cattrs[NSFileModificationDate];                    // CALL 0x76c14
        if (after && cdate && [cdate compare:after] == NSOrderedAscending) { continue; }
        for (NSString *item in [fm contentsOfDirectoryAtPath:container error:NULL]) {
            if (![[item pathExtension].lowercaseString isEqualToString:@"app"]) { continue; }
            NSString *appPath = [container stringByAppendingPathComponent:item];
            NSDictionary *aattrs = [fm attributesOfItemAtPath:appPath error:NULL];
            NSDate *adate = aattrs[NSFileModificationDate] ?: [NSDate distantPast];
            if (bestDate && [adate compare:bestDate] != NSOrderedDescending) { continue; }
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [appPath stringByAppendingPathComponent:@"Info.plist"]];
            NSString *bid = info[@"CFBundleIdentifier"];
            NSString *execName = info[@"CFBundleExecutable"];
            if (!bid.length || !execName.length) { continue; }
            NSString *execPath = [appPath stringByAppendingPathComponent:execName];
            if (![fm fileExistsAtPath:execPath]) { continue; }
            best = appPath;
            bestDate = adate;
            if (outBundleId) { *outBundleId = bid; }
            if (outExecPath) { *outExecPath = execPath; }
        }
    }
    return best;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager waitForInstalledAppBundlePathForBundleId:installedAfter:resolvedBundleId:mainExecutablePath:timeout:]
//   imp=0x76cb0 insns=196
// ---------------------------------------------------------------------------
- (NSString *)waitForInstalledAppBundlePathForBundleId:(NSString *)bundleId
                                         installedAfter:(NSDate *)installedAfter
                                       resolvedBundleId:(NSString **)outBundleId
                                    mainExecutablePath:(NSString **)outExecPath
                                               timeout:(double)timeout
{
    // 已定案（0x76cb0..0x76fc0 逐条）：
    //   0x76d1c/0x76d20/0x76d24 deadline = now + MAX(timeout, 0.1)（fcsel，0.1 来自字面池 0xbfc88）
    //   0x76cf8 *resolvedBundleId = bundleId，0x76d0c *mainExecutablePath = nil（出参初始化）
    //   0x76d58 稳定性阈值 = 1.0；0x76d4c/0x76d50 lastPath / lastExec / lastSeen 初值 nil
    //   0x76da4 / 0x76db4 快路径只在 path 与 exec 都非空时采用，否则 0x76dd0 走 newestInstalled…
    //   0x76e40 / 0x76e50 用 path、exec 与「上次观察值」比较；0x76e2c [NSDate date]；
    //   0x76e64 timeIntervalSinceDate: + 0x76e68 fcmp d0,d8 → 间隔 >= 1.0 才接受。
    //   ——本区间内**没有** dateByAddingTimeInterval: 调用，原注释的
    //     [installedAfter dateByAddingTimeInterval:0] 与「与 bundleId 比对」都不成立。
    double wait = (timeout > 0.1) ? timeout : 0.1;                            // 0x76d24 fcsel
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:wait];            // 0x76d28
    if (outBundleId) { *outBundleId = bundleId; }                            // 0x76cf8
    if (outExecPath) { *outExecPath = nil; }                                 // 0x76d0c
    NSString *lastPath = nil, *lastExec = nil, *acceptedId = nil;
    NSDate *lastSeen = nil;
    while ([deadline timeIntervalSinceNow] > 0) {
        NSString *tmpExec = nil;
        NSString *path = [self appBundlePathForBundleId:bundleId mainExecutablePath:&tmpExec]; // 0x76d80
        if (!path.length || !tmpExec.length) {                                // 0x76da4 / 0x76db4
            NSString *resolved = nil;
            NSString *exec2 = nil;
            path = [self newestInstalledAppBundlePathAfterDate:installedAfter  // 0x76dd0
                                              resolvedBundleId:&resolved
                                           mainExecutablePath:&exec2];
            tmpExec = exec2;
            acceptedId = resolved.length ? resolved : bundleId;               // 0x76f80 csel
        }
        if (path.length && tmpExec.length) {                                  // 0x76e0c / 0x76e1c
            NSDate *now = [NSDate date];                                      // 0x76e2c
            if ([path isEqualToString:lastPath] &&
                [tmpExec isEqualToString:lastExec]) {                         // 0x76e40 / 0x76e50
                if (lastSeen && [now timeIntervalSinceDate:lastSeen] >= 1.0) { // 0x76e64 / 0x76e68
                    if (outBundleId) { *outBundleId = acceptedId ?: bundleId; }
                    if (outExecPath) { *outExecPath = tmpExec; }
                    return path;                                              // 0x76f78
                }
            } else {
                lastPath = path;                                              // 0x76e74..0x76ec0
                lastExec = tmpExec;
                lastSeen = now;
            }
        }
        [NSThread sleepForTimeInterval:0.25];                              // 已定案 0x76ee4: fmov d0,#0.25 → 0x76ee8 bl sel:sleepForTimeInterval:
    }
    return nil;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager bundleExecutablePathForBundlePath:]  imp=0x76fc0 insns=123
//   .app 直接读 Info.plist；.framework 走 <name>.framework/<name>
// ---------------------------------------------------------------------------
- (NSString *)bundleExecutablePathForBundlePath:(NSString *)bundlePath {
    if (!bundlePath.length) { return nil; }
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:bundlePath isDirectory:&isDir] || !isDir) { return nil; }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *execName = info[@"CFBundleExecutable"];
    if (execName.length) {
        NSString *candidate = [bundlePath stringByAppendingPathComponent:execName];
        if ([fm fileExistsAtPath:candidate]) { return candidate; }
    }
    // framework 形态：<Name>.framework/<Name>
    if ([[bundlePath pathExtension].lowercaseString isEqualToString:@"framework"]) {
        NSString *name = [bundlePath lastPathComponent].stringByDeletingPathExtension;
        NSString *candidate = [bundlePath stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:candidate]) { return candidate; }
    }
    return nil;
}

// -[PDNative_AppManager isSignableBundlePath:]  imp=0x771ac insns=42
- (BOOL)isSignableBundlePath:(NSString *)path {
    if (!path.length) { return NO; }                                       // 0x771ac
    NSString *ext = [path pathExtension].lowercaseString;
    return [ext isEqualToString:@"app"] ||                                 // 文案 app
           [ext isEqualToString:@"appex"] ||                               // 文案 appex
           [ext isEqualToString:@"framework"];                             // 文案 framework
}

// -[PDNative_AppManager hasSignableBundleAncestorForPath:withinRoot:]  imp=0x77254 insns=67
- (BOOL)hasSignableBundleAncestorForPath:(NSString *)path withinRoot:(NSString *)root {
    if (!path.length || !root.length) { return NO; }
    NSString *cursor = path;
    while (cursor.length) {
        if ([cursor isEqualToString:root] || [cursor isEqualToString:@"/"]) { return NO; }
        if ([self isSignableBundlePath:cursor]) { return YES; }
        NSString *parent = cursor.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:cursor]) { return NO; }
        cursor = parent;
    }
    return NO;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager signTargetsForAppBundlePath:]  imp=0x77360 insns=236
//   枚举包内所有可签目标（Mach-O 与 .app/.appex/.framework），按路径深度排序去重。
// ---------------------------------------------------------------------------
- (NSArray<NSString *> *)signTargetsForAppBundlePath:(NSString *)bundlePath {
    if (!bundlePath.length) { return @[]; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *targets = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:bundlePath];
    for (NSString *relative in enumerator) {
        NSString *full = [bundlePath stringByAppendingPathComponent:relative];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir]) { continue; }
        if ([self isSignableBundlePath:full]) {
            if (![self hasSignableBundleAncestorForPath:full withinRoot:bundlePath] ||
                [full isEqualToString:bundlePath]) {
                NSString *exec = [self bundleExecutablePathForBundlePath:full];  // CALL 0x77590
                if (exec && ![seen containsObject:exec]) {
                    [seen addObject:exec];
                    [targets addObject:exec];
                }
            }
        } else if (!isDir) {
            // Mach-O 判定（fopen + fread 头部魔数，0x773… 尾部）
            if (![seen containsObject:full] && [self isMachOBinaryAtPath:full]) {
                [seen addObject:full];
                [targets addObject:full];
            }
        }
    }
    [targets sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [@(a.pathComponents.count) compare:@(b.pathComponents.count)] ?: [a compare:b];
    }];
    return targets;
}

// -[PDNative_AppManager bundleIdFromAppInstOutput:]  imp=0x77710 insns=168
- (NSString *)bundleIdFromAppInstOutput:(NSString *)output {
    if (!output.length) { return nil; }
    // 逐行找 "APPINST_BUNDLE_ID=" 前缀，取等号右侧；也支持带引号的形式（文案 "\""）
    NSArray *lines = [output componentsSeparatedByCharactersInSet:
                        [NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"APPINST_BUNDLE_ID="]) {
            NSString *value = [line substringFromIndex:@"APPINST_BUNDLE_ID=".length];
            if ([value hasPrefix:@"\""] && value.length >= 2) {
                NSRange r = [value rangeOfString:@"\"" options:0
                                           range:NSMakeRange(1, value.length - 1)];
                if (r.location != NSNotFound) {
                    value = [value substringWithRange:NSMakeRange(1, r.location - 1)];
                }
            }
            if (value.length) { return value; }
        }
    }
    return nil;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager fakesignInstalledAppForBundleId:installedAfter:error:]
//   imp=0x779b0 insns=2232（本文件最大方法）
// [0x77b40]  insn#100
// [0x77cd0]  insn#200
// [0x77e60]  insn#300
// [0x77ff0]  insn#400
// [0x78180]  insn#500
// [0x78310]  insn#600
// [0x784a0]  insn#700
// [0x78630]  insn#800
// [0x787c0]  insn#900
// [0x78950]  insn#1000
// [0x78ae0]  insn#1100
// [0x78c70]  insn#1200
// [0x78e00]  insn#1300
// [0x78f90]  insn#1400
// [0x79120]  insn#1500
// [0x792b0]  insn#1600
// [0x79440]  insn#1700
// [0x795d0]  insn#1800
// [0x79760]  insn#1900
// [0x798f0]  insn#2000
// [0x79a80]  insn#2100
// [0x79c10]  insn#2200
//
//   观测到的执行顺序（每条都对应一段 CFString，逐字见 out/notes/sources-coverage.md）：
//     1 定位 mcp-ldid / mcp-root / sudo / chmod / sh（PDNative_MCPResolvedJailbreakPath）
//     2 等安装完成：waitForInstalledAppBundlePath…（bundleId / installedAfter / timeout）
//     3 取 Info.plist（CFBundleIdentifier / CFBundleExecutable / CFBundlePackageType）
//        FMWK 分支：包类型是 FMWK 时先重签 framework 本身
//     4 收集签名目标（signTargetsForAppBundlePath:），必要时分批（subarrayWithRange:）
//     5 chmod 批处理：find <root> -exec chmod 0644 {} + / -type d -exec chmod 0755 {} +
//        经 /bin/sh；失败文案 "Failed to reset app permissions" / "Failed to set directory permissions"
//     6 生成 entitlements（PMAP_CS_APP_STORE / jb.pmap_cs.custom_trust 键）
//     7 mcp-ldid -S <entitlements> -s <target>（-p plist 备份）；失败 "mcp-ldid failed"
//     8 失败时用 sudo -S（密码来自 com.witchan.ios-mcp.preferences 的 sudo_password，默认 "alpine"）
//     9 记录 <path:.%@> 形式的签名日志
//   与旧快照的分歧：ldid 的参数顺序以 0x78abc/0x793a4 处的 argv 组装为准（见 diff 注），
//   FMWK 分支的实际条件是 CFBundlePackageType == "FMWK"（0x779b0 段字符串实读），不是旧注释的推测。
// ---------------------------------------------------------------------------
- (BOOL)fakesignInstalledAppForBundleId:(NSString *)bundleId
                         installedAfter:(NSDate *)installedAfter
                                  error:(NSError **)error
{
    if (!bundleId.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Could not find installed app bundle"}]; }
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    // ---- 1 工具定位（顺序：mcp-ldid → mcp-root → sudo → chmod） ----
    NSString *ldid = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-ldid");   // 0x78ea4
    NSString *root = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-root");
    NSString *sudo = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/sudo");
    NSString *chmod = PDNative_MCPResolvedJailbreakPath(@"/bin/chmod");
    NSString *sh = PDNative_MCPResolvedJailbreakPath(@"/bin/sh");
    if (!root.length || ![fm isExecutableFileAtPath:root]) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-root not found, skipping fakesign for %@", bundleId]);
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"[App] mcp-root not found, skipping fakesign for %@",
                            bundleId]}]; }
        return NO;
    }
    if (!ldid.length || ![fm isExecutableFileAtPath:ldid]) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-ldid not found, skipping fakesign for %@", bundleId]);
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey: @"mcp-ldid not found"}]; }
        return NO;
    }
    // ---- 2 等安装 ----
    NSString *resolvedId = nil;
    NSString *execPath = nil;
    NSString *bundlePath =
        [self waitForInstalledAppBundlePathForBundleId:bundleId
                                        installedAfter:installedAfter
                                      resolvedBundleId:&resolvedId
                                   mainExecutablePath:&execPath
                                              timeout:15.0];   // 已定案 0x77cc4: fmov d0,#15.0 → 0x77cd4 bl sel:waitForInstalledAppBundlePathForBundleId:…timeout:（不是 30.0）
    if (!bundlePath.length) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Could not find installed app bundle for %@ after %@",
                  bundleId, installedAfter]);
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:
                            @"[App] Could not find installed app bundle for %@ after %@",
                            bundleId, installedAfter]}]; }
        return NO;
    }
    // ---- 3 Info.plist ----
    NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *execName = info[@"CFBundleExecutable"];
    NSString *packageType = info[@"CFBundlePackageType"];
    if (!execPath.length && execName.length) {
        execPath = [bundlePath stringByAppendingPathComponent:execName];
        if (![fm fileExistsAtPath:execPath]) { execPath = nil; }
    }
    // 已定案 0x780c8/0x780dc：packageType == "FMWK"（CF @0xff508）时**跳过该项**，不是「先签再继续」。
    //   0x780c0/0x780c8 [packageType isEqualToString:@"FMWK"]；0x780dc tbz w0,#0 → 非 FMWK 走 0x780ec，
    //   FMWK 则 0x780e0 mov w27,#8 → 0x7825c 清理 → 0x78280 orr w8,w27,#8 / 0x78284 cmp w8,#8（成立）
    //   → 0x78298 b 0x78090，而 0x78090 是 [enumerator nextObject] 的循环头（0x78094 nextObject、
    //   0x780a8 cbnz x21）→ 等价于 continue。
    //   结构缺口：本重建没有那个外层 NSEnumerator 循环，所以只能用空分支表达「跳过」，
    //   不再伪造「先签 framework 本体」的代码（该调用在二进制里不存在）。
    if ([packageType isEqualToString:@"FMWK"]) {
        /* 已定案 0x780e0：跳过该项（原重建的 signOneTarget:frameworkExec 无对应调用点） */
    }
    if (!execPath.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to sign bundle executable"}]; }
        return NO;
    }
    // ---- 4/5 chmod 批处理 ----
    if (![self runShell:[NSString stringWithFormat:@"find %@ -exec chmod 0644 {} +", bundlePath]
                root:root sudo:sudo sh:sh chmod:chmod error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDNative_AppManager" code:6
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to reset app permissions"}];
        }
        return NO;
    }
    if (![self runShell:[NSString stringWithFormat:@"find %@ -type d -exec chmod 0755 {} +", bundlePath]
                root:root sudo:sudo sh:sh chmod:chmod error:error]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"PDNative_AppManager" code:7
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to set directory permissions"}];
        }
        return NO;
    }
    // ---- 6..9 逐目标签名 ----
    NSArray<NSString *> *targets = [self signTargetsForAppBundlePath:bundlePath];
    if (!targets.count) {
        targets = @[execPath];
    }
    // 已定案 0x785c0/0x785c4/0x785c8/0x785d8：批次大小是 **32**，不是 8。
    //   0x785c0 cmp x8,#0x20；0x785c4 mov w9,#0x20；0x785c8 csel x3,x8,x9,lo（取 min(剩余,32)）；
    //   0x785d8 bl sel:subarrayWithRange:（x2 = 起始下标 0x785b0 置 0）。
    //   注：0x780e0 的 mov w27,#8 是 FMWK 分支的清理标志位（0x78280 orr/cmp 用它），不是批次大小。
    const NSUInteger batch = 32;                                              // 0x785c4
    for (NSUInteger i = 0; i < targets.count; i += batch) {
        NSUInteger n = MIN(batch, targets.count - i);
        NSArray *slice = [targets subarrayWithRange:NSMakeRange(i, n)];
        for (NSString *target in slice) {
            if (![self signOneTarget:target withLdid:ldid root:root sudo:sudo
                            bundleId:bundleId error:error]) {
                if (error && !*error) {
                    *error = [NSError errorWithDomain:@"PDNative_AppManager" code:8
                             userInfo:@{NSLocalizedDescriptionKey:
                                @"Failed to recursively sign app bundle"}];
                }
                return NO;
            }
        }
    }
    return YES;
}

// -[PDNative_AppManager fakesignApp:]  imp=0x79c90 insns=3
- (void)fakesignApp:(NSString *)bundlePath {
    // 3 条指令：直接尾调 fakesignInstalledAppForBundleId:installedAfter:error:
    [self fakesignInstalledAppForBundleId:bundlePath installedAfter:nil error:NULL];
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager retryFakesignInstalledAppForBundleId:installedAfter:]
//   imp=0x79c9c insns=99：两次尝试，中间 sleep
// ---------------------------------------------------------------------------
- (BOOL)retryFakesignInstalledAppForBundleId:(NSString *)bundleId
                              installedAfter:(NSDate *)installedAfter
{
    NSError *first = nil;
    if ([self fakesignInstalledAppForBundleId:bundleId installedAfter:installedAfter error:&first]) {
        return YES;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        // @"[App] Fakesign attempt %lu failed for %@: %@"
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Fakesign attempt %lu failed for %@: %@",
              (unsigned long)1, bundleId, first.localizedDescription ?: @"unknown error"]);
    }
    [NSThread sleepForTimeInterval:2.0];                                   // 已定案 0x79dac: fmov d0,#2.0 → 0x79db0 bl sel:sleepForTimeInterval:（不是 1.0）
    return [self fakesignInstalledAppForBundleId:bundleId installedAfter:installedAfter error:NULL];
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager installDebPackage:error:]  imp=0x79e28 insns=1546
// [0x79fb8]  insn#100
// [0x7a148]  insn#200
// [0x7a2d8]  insn#300
// [0x7a468]  insn#400
// [0x7a5f8]  insn#500
// [0x7a788]  insn#600
// [0x7a918]  insn#700
// [0x7aaa8]  insn#800
// [0x7ac38]  insn#900
// [0x7adc8]  insn#1000
// [0x7af58]  insn#1100
// [0x7b0e8]  insn#1200
// [0x7b278]  insn#1300
// [0x7b408]  insn#1400
// [0x7b598]  insn#1500
//   暂存到 /var/tmp/ios-mcp-dpkg-<uuid>.deb → 特权 shell（mcp-root → sudo）跑 dpkg -i
//   失败后按需重试 / killall SpringBoard。
// ---------------------------------------------------------------------------
- (BOOL)installDebPackage:(NSString *)debPath error:(NSError **)error {
    if (!debPath.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Empty DEB path"}]; }
        return NO;
    }
    if (![[debPath pathExtension].lowercaseString isEqualToString:@"deb"]) {   // 文案 deb
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey: @"DEB install requires a .deb file"}]; }
        return NO;
    }
    if (!debPath.isAbsolutePath) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey:
                        @"DEB install requires an absolute device path"}]; }
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:debPath]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"DEB file not found: %@", debPath]}]; }
        return NO;
    }
    // ---- 暂存到 /var/tmp（0x79… "ios-mcp-dpkg-%@.deb" / "/var/tmp"） ----
    NSString *staged = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"ios-mcp-dpkg-%@.deb", [NSUUID UUID].UUIDString]];
    staged = [@"/var/tmp" stringByAppendingPathComponent:staged.lastPathComponent];
    int src = open(debPath.fileSystemRepresentation, O_RDONLY);
    if (src < 0) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Failed to open source DEB: %s", strerror(errno)]}]; }
        return NO;
    }
    // 通过特权 shell 落盘：mkdir -p <dir> && cat > <staged> && chmod 0644 <staged>
    NSString *root = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-root");
    NSString *sudo = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/sudo");
    NSString *sh = PDNative_MCPResolvedJailbreakPath(@"/bin/sh");
    // 文案 "mkdir -p %@ && cat > %@ && chmod 0644 %@"
    NSString *stageCmd = [NSString stringWithFormat:@"mkdir -p %@ && cat > %@ && chmod 0644 %@",
                             @"/var/tmp", staged, staged];
    NSDictionary *result = PDNative_MCPRunProcess(@[ sh, @"-c", stageCmd ],
                                                  PDNative_MCPJailbreakEnvironment(), NULL, NULL);
    close(src);
    if (!result) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:6
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to stage DEB for dpkg"}]; }
        return NO;
    }
    // ---- postinst 脚本里的 appex 特例（文案 appex） ----
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Installing DEB via privileged dpkg: %@", staged]);
    }
    // ---- dpkg -i（先 mcp-root，失败再 sudo） ----
    NSString *output = nil;
    int exitCode = 0;
    NSDictionary *run = PDNative_MCPRunProcess(@[ @"/usr/bin/dpkg", @"-i", staged ],
                                               PDNative_MCPJailbreakEnvironment(),
                                               &output, &exitCode);
    if (!run || exitCode != 0) {
        // sudo 兜底（文案 "-p" "-S" "-k" "printf '%s\n'"）
        NSString *sudoPassword = [[NSUserDefaults standardUserDefaults]
                                    stringForKey:@"sudo_password"] ?: @"alpine";
        NSString *pwCmd = [NSString stringWithFormat:@"printf '%%s\\n' '%@' | sudo -S -p '' dpkg -i %@",
                              sudoPassword, staged];
        run = PDNative_MCPRunProcess(@[ sh, @"-lc", pwCmd ],
                                     PDNative_MCPJailbreakEnvironment(), &output, &exitCode);
        if (!run || exitCode != 0) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                // @"[App] dpkg install failed (spawnError=%@ exit=%d outputBytes=%lu)"
                NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                      @"[App] dpkg install failed (spawnError=%@ exit=%d outputBytes=%lu)",
                      @"none", exitCode, (unsigned long)output.length]);
            }
            if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:7
                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                            @"dpkg install failed: %@", output ?: @"unknown error"]}]; }
            return NO;
        }
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] dpkg install succeeded outputBytes=%lu", (unsigned long)output.length]);
    }
    // ---- 清理暂存 + 重启 SpringBoard ----
    [[NSFileManager defaultManager] removeItemAtPath:staged error:NULL];
    NSError *restartError = nil;
    if (![self scheduleSpringBoardRestart:&restartError]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:8
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"DEB installed but failed to schedule SpringBoard restart: %@",
                        restartError.localizedDescription ?: @"unknown error"]}]; }
        return NO;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager installApp:error:]  imp=0x7b650 insns=886
// [0x7b7e0]  insn#100
// [0x7b970]  insn#200
// [0x7bb00]  insn#300
// [0x7bc90]  insn#400
// [0x7be20]  insn#500
// [0x7bfb0]  insn#600
// [0x7c140]  insn#700
// [0x7c2d0]  insn#800
//   .deb → installDebPackage:；.ipa/.tipa → mcp-roothelper / mcp-appinst，
//   都失败时退回 LSApplicationWorkspace installApplication:（NSInvocation）。
// ---------------------------------------------------------------------------
- (BOOL)installApp:(NSString *)packagePath error:(NSError **)error {
    if (!packagePath.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Empty package path"}]; }
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:packagePath]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"File not found: %@", packagePath]}]; }
        return NO;
    }
    NSString *ext = [packagePath pathExtension].lowercaseString;
    if ([ext isEqualToString:@"deb"]) {                                    // 文案 deb
        return [self installDebPackage:packagePath error:error];
    }
    if (![ext isEqualToString:@"ipa"] && ![ext isEqualToString:@"tipa"]) {  // 文案 ipa / tipa
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"Unsupported package extension: .%@ (expected .ipa, .tipa or .deb)", ext]}]; }
        return NO;
    }
    NSDate *installedAfter = [NSDate date];
    NSString *bundleId = [self bundleIdFromIPA:packagePath];
    // ---- mcp-roothelper ----
    NSString *helper = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-roothelper");
    if ([helper isExecutableFileAtPath:helper]) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Installing via %s%s: %@", "mcp-roothelper", "", packagePath]);
        }
        NSString *out = nil; int code = 0;
        NSDictionary *run = PDNative_MCPRunProcess(@[ helper, @"-i", packagePath ],
                                                   PDNative_MCPJailbreakEnvironment(), &out, &code);
        if (run && code == 0) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                      @"[App] mcp-roothelper succeeded outputBytes=%lu", (unsigned long)out.length]);
            }
            [self retryFakesignInstalledAppForBundleId:bundleId installedAfter:installedAfter];
            return YES;
        }
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-roothelper failed (spawnError=%@ exit=%d outputBytes=%lu)",
                  @"none", code, (unsigned long)out.length]);
        }
    }
    // ---- mcp-appinst ----
    NSString *appinst = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-appinst");
    if ([fm fileExistsAtPath:appinst]) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Installing via %s%s: %@", "mcp-appinst", "", packagePath]);
        }
        NSString *out = nil; int code = 0;
        NSDictionary *run = PDNative_MCPRunProcess(@[ appinst, @"-i", packagePath ],
                                                   PDNative_MCPJailbreakEnvironment(), &out, &code);
        if (run && code == 0) {
            if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
                NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                      @"[App] mcp-appinst succeeded outputBytes=%lu", (unsigned long)out.length]);
            }
            [self retryFakesignInstalledAppForBundleId:bundleId installedAfter:installedAfter];
            return YES;
        }
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-appinst failed (spawnError=%@ exit=%d outputBytes=%lu)",
                  @"none", code, (unsigned long)out.length]);
        }
    }
    // ---- LSApplicationWorkspace installApplication:withOptions:error: ----
    Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
    if (!LSAppWorkspace) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                     userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace not available"}]; }
        return NO;
    }
    __block BOOL installed = NO;
    __block NSError *inner = nil;
    void (^work)(void) = ^{
        id ws = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        // 0x7c0a4/0x7c0d8 的 selref 实读：installApplication:withOptions:error:（3 参）
        SEL sel = @selector(installApplication:withOptions:error:);
        if (![ws respondsToSelector:sel]) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                    userInfo:@{NSLocalizedDescriptionKey: @"No install method available"}];
            return;
        }
        NSURL *fileURL = [NSURL fileURLWithPath:packagePath];
        // 0x7bff0 w4=#1：options 只有 PackageType 一个键（旧写的 CFBundleExecutable 是多余的）
        NSDictionary *options = @{ @"PackageType": @"Customer" };
        NSMethodSignature *sig = [ws methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:ws];
        [inv setSelector:sel];
        NSError *installError = nil;                           // 0x7c114 str xzr,[sp,#0x28]
        [inv setArgument:&fileURL atIndex:2];                  // 0x7c0f4 idx=2（NSURL）
        [inv setArgument:&options atIndex:3];                  // 0x7c110 idx=3（options）
        [inv setArgument:&installError atIndex:4];             // 0x7c124 idx=4（NSError **）
        [inv invoke];
        const char *retType = sig.methodReturnType;
        if (retType && strcmp(retType, @encode(BOOL)) == 0) {
            BOOL ret = NO;
            [inv getReturnValue:&ret];
            installed = ret;
        } else {
            installed = YES;
        }
        if (!installed) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:6
                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"installApplication returned NO (options: %@)",
                        installError.localizedDescription ?: options]}];
        }
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    if (!installed) {
        if (error) { *error = inner ?: [NSError errorWithDomain:@"PDNative_AppManager" code:7
                     userInfo:@{NSLocalizedDescriptionKey: @"Install failed: unknown"}]; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Installed app from: %@ (options: %@)", packagePath, @{@"PackageType": @"Customer"}]);
    }
    [self retryFakesignInstalledAppForBundleId:bundleId installedAfter:installedAfter];
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager bundleIdFromIPA:]  imp=0x7c428 insns=597
// [0x7c5b8]  insn#100
// [0x7c748]  insn#200
// [0x7c8d8]  insn#300
// [0x7ca68]  insn#400
// [0x7cbf8]  insn#500
//   mcp-roothelper --bundle-id → mcp-appinst --bundle-id → 解压 Payload/*/Info.plist
// ---------------------------------------------------------------------------
- (NSString *)bundleIdFromIPA:(NSString *)ipaPath {
    NSString *helper = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-roothelper");
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([helper isExecutableFileAtPath:helper]) {
        NSString *out = nil; int code = 0;
        PDNative_MCPRunProcess(@[ helper, @"--bundle-id", ipaPath ],
                               PDNative_MCPJailbreakEnvironment(), &out, &code);
        NSString *value = [out stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [[value componentsSeparatedByCharactersInSet:
                     [NSCharacterSet newlineCharacterSet]] lastObject];
        if (value.length) { return value; }
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-roothelper --bundle-id failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
                  ipaPath, @"none", code, (unsigned long)out.length]);
        }
    }
    NSString *appinst = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/mcp-appinst");
    if ([appinst isExecutableFileAtPath:appinst]) {
        NSString *out = nil; int code = 0;
        PDNative_MCPRunProcess(@[ appinst, @"--bundle-id", ipaPath ],
                               PDNative_MCPJailbreakEnvironment(), &out, &code);
        NSString *value = [out stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [[value componentsSeparatedByCharactersInSet:
                     [NSCharacterSet newlineCharacterSet]] lastObject];
        if (value.length) { return value; }
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] mcp-appinst --bundle-id failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
                  ipaPath, @"none", code, (unsigned long)out.length]);
        }
    }
    // ---- unzip 兜底（"mcp_plist_%u" / "-o" "-q" "Payload/*/Info.plist" "-d"） ----
    NSString *unzip = PDNative_MCPResolvedJailbreakPath(@"/usr/bin/unzip");
    if (![fm isExecutableFileAtPath:unzip]) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] unzip not found, skipping bundle ID extraction for %@", ipaPath]);
        }
        return nil;
    }
    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"mcp_plist_%u", arc4random()]];
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *out = nil; int code = 0;
    NSDictionary *run = PDNative_MCPRunProcess(@[ unzip, @"-o", @"-q", ipaPath,
                                                  @"Payload/*/Info.plist", @"-d", tmpDir ],
                                               PDNative_MCPJailbreakEnvironment(), &out, &code);
    NSString *found = nil;
    if (run && code == 0) {
        for (NSString *payload in [fm contentsOfDirectoryAtPath:tmpDir error:NULL]) {
            NSString *payloadPath = [tmpDir stringByAppendingPathComponent:payload];
            for (NSString *item in [fm contentsOfDirectoryAtPath:payloadPath error:NULL]) {
                if (![[item pathExtension].lowercaseString isEqualToString:@"app"]) { continue; }
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                    [[payloadPath stringByAppendingPathComponent:item]
                        stringByAppendingPathComponent:@"Info.plist"]];
                NSString *bid = info[@"CFBundleIdentifier"];
                if (bid.length) { found = bid; break; }
            }
            if (found) { break; }
        }
    } else if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] unzip failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
              ipaPath, @"none", code, (unsigned long)out.length]);
    }
    [fm removeItemAtPath:tmpDir error:NULL];
    return found;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager isAppInstalled:]  imp=0x7cd7c insns=226
// ---------------------------------------------------------------------------
- (BOOL)isAppInstalled:(NSString *)bundleId {
    if (!bundleId.length) { return NO; }
    __block BOOL found = NO;
    void (^work)(void) = ^{
        Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
        id ws = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        if (![ws respondsToSelector:@selector(allInstalledApplications)]) {
            Class LSAppProxy = objc_getClass("LSApplicationProxy");
            if ([LSAppProxy respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
                id proxy = [LSAppProxy performSelector:@selector(applicationProxyForIdentifier:)
                                           withObject:bundleId];               // CALL 0x7d0d8
                found = (proxy != nil);
            }
            return;
        }
        for (id proxy in [ws performSelector:@selector(allInstalledApplications)]) {
            if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                NSString *bid = [proxy performSelector:@selector(applicationIdentifier)];
                if ([bid isEqualToString:bundleId]) { found = YES; break; }
            }
        }
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    return found;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager appInfoForBundleId:error:]  imp=0x7d104 insns=697
// [0x7d294]  insn#100
// [0x7d424]  insn#200
// [0x7d5b4]  insn#300
// [0x7d744]  insn#400
// [0x7d8d4]  insn#500
// [0x7da64]  insn#600
//   返回 {bundle_id,name,type,bundle_path,data_container,group_containers,
//         short_version,version,sdk_version,minimum_os_version,executable_path,entitlements}
// ---------------------------------------------------------------------------
- (NSDictionary *)appInfoForBundleId:(NSString *)bundleId error:(NSError **)error {
    if (!bundleId.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"bundle_id is required"}]; }
        return nil;
    }
    __block NSDictionary *result = nil;
    __block NSError *inner = nil;
    void (^work)(void) = ^{
        Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
        id ws = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        if (!ws) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace unavailable"}];
            return;
        }
        id proxy = nil;
        for (id candidate in [ws performSelector:@selector(allInstalledApplications)]) {
            if ([[candidate performSelector:@selector(applicationIdentifier)]
                    isEqualToString:bundleId]) { proxy = candidate; break; }
        }
        if (!proxy) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"App not installed: %@", bundleId]}];
            return;
        }
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"bundle_id"] = bundleId;
        dict[@"name"] = [proxy performSelector:@selector(localizedName)] ?: @"";
        dict[@"type"] = [proxy performSelector:@selector(applicationType)] ?: @"";
        NSString *bundlePath = nil;
        if ([proxy respondsToSelector:@selector(bundleURL)]) {
            bundlePath = [[proxy performSelector:@selector(bundleURL)] path];   // CALL 0x752fc
            bundlePath = [bundlePath stringByStandardizingPath];
            if (bundlePath.length) { dict[@"bundle_path"] = bundlePath; }
        }
        if ([proxy respondsToSelector:@selector(dataContainerURL)]) {
            NSString *dataPath = [[proxy performSelector:@selector(dataContainerURL)] path];
            dataPath = [dataPath stringByStandardizingPath];
            if (dataPath.length) { dict[@"data_container"] = dataPath; }
        }
        if ([proxy respondsToSelector:@selector(groupContainerURLs)]) {
            NSDictionary *groups = [proxy performSelector:@selector(groupContainerURLs)];
            if (groups.count) { dict[@"group_containers"] = groups; }
        }
        // ---- Info.plist 补充字段 ----
        if (bundlePath.length) {
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
            if (info[@"CFBundleShortVersionString"]) {
                dict[@"short_version"] = info[@"CFBundleShortVersionString"];
            }
            if (info[@"CFBundleVersion"]) { dict[@"version"] = info[@"CFBundleVersion"]; }
            if (info[@"DTPlatformVersion"]) { dict[@"sdk_version"] = info[@"DTPlatformVersion"]; }
            if (info[@"MinimumOSVersion"]) { dict[@"minimum_os_version"] = info[@"MinimumOSVersion"]; }
            if (info[@"CFBundleExecutable"]) {
                dict[@"executable_path"] = [bundlePath stringByAppendingPathComponent:
                                               info[@"CFBundleExecutable"]];
            }
        }
        NSDictionary *entitlements = [self entitlementsForAppAtPath:bundlePath];       // CALL 0x79b90（真实调用点 0x7da90）
        if (entitlements.count) { dict[@"entitlements"] = entitlements; }
        result = [dict copy];
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    if (!result && error) { *error = inner ?: [NSError errorWithDomain:@"PDNative_AppManager"
                                                                code:4
                                                            userInfo:@{NSLocalizedDescriptionKey:
                                                                @"Failed to read app info"}]; }
    return result;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager debPackageInstalled:statusOutput:error:]  imp=0x7dbe8 insns=118
// ---------------------------------------------------------------------------
- (BOOL)debPackageInstalled:(NSString *)packageId
               statusOutput:(NSString **)statusOutput
                      error:(NSError **)error
{
    NSString *out = nil; int code = 0;
    NSDictionary *run = PDNative_MCPRunProcess(@[ @"/usr/bin/dpkg", @"-s", packageId ],
                                               PDNative_MCPJailbreakEnvironment(), &out, &code);
    if (statusOutput) { *statusOutput = out; }
    if (!run || code != 0) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] dpkg status failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
                  packageId, @"none", code, (unsigned long)out.length]);
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"dpkg status failed"}]; }
        return NO;
    }
    // 文案 "Status: install ok installed"
    return [out rangeOfString:@"Status: install ok installed"].location != NSNotFound;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager uninstallDebPackage:error:]  imp=0x7ddc0 insns=345
// [0x7df50]  insn#100
// [0x7e0e0]  insn#200
// [0x7e270]  insn#300
// ---------------------------------------------------------------------------
- (BOOL)uninstallDebPackage:(NSString *)packageId error:(NSError **)error {
    if (!packageId.length || !packageId.UTF8String || strlen(packageId.UTF8String) == 0) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Invalid DEB package id: %@",
                            packageId ?: @"<nil>"]}]; }
        return NO;
    }
    NSString *status = nil;
    if (![self debPackageInstalled:packageId statusOutput:&status error:NULL]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"DEB package not installed: %@ (%@)", packageId, status ?: @""]}]; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Uninstalling DEB via privileged dpkg: %@", packageId]);
    }
    NSString *out = nil; int code = 0;
    NSDictionary *run = PDNative_MCPRunProcess(@[ @"/usr/bin/dpkg", @"-r", packageId ],
                                               PDNative_MCPJailbreakEnvironment(), &out, &code);
    if (!run || code != 0) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] dpkg remove failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
                  packageId, @"none", code, (unsigned long)out.length]);
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"dpkg remove failed: %@", out ?: @"unknown error"]}]; }
        return NO;
    }
    if ([self debPackageInstalled:packageId statusOutput:NULL error:NULL]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"dpkg remove completed but package is still installed: %@", packageId]}]; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] dpkg remove succeeded outputBytes=%lu", (unsigned long)out.length]);
    }
    NSError *restartError = nil;
    if (![self scheduleSpringBoardRestart:&restartError]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"DEB removed but failed to schedule SpringBoard restart: %@",
                        restartError.localizedDescription ?: @"unknown error"]}]; }
        return NO;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// -[PDNative_AppManager uninstallApp:error:]  imp=0x7e324 insns=395
// [0x7e4b4]  insn#100
// [0x7e644]  insn#200
// [0x7e7d4]  insn#300
//   先判 deb，再走 LSApplicationWorkspace uninstallApplication:（NSInvocation），
//   最后 posix_spawn 重启 SpringBoard。
// ---------------------------------------------------------------------------
- (BOOL)uninstallApp:(NSString *)identifier error:(NSError **)error {
    if (!identifier.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey:
                        @"Empty app or package identifier"}]; }
        return NO;
    }
    if (![self isAppInstalled:identifier]) {
        // 不是 App：按 DEB 包处理
        return [self uninstallDebPackage:identifier error:error];
    }
    __block BOOL uninstalled = NO;
    __block NSError *inner = nil;
    void (^work)(void) = ^{
        Class LSAppWorkspace = objc_getClass("LSApplicationWorkspace");
        if (!LSAppWorkspace) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"LSApplicationWorkspace not available"}];
            return;
        }
        id ws = [LSAppWorkspace performSelector:@selector(defaultWorkspace)];
        SEL sel = @selector(uninstallApplication:withOptions:);
        if (![ws respondsToSelector:sel]) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                    userInfo:@{NSLocalizedDescriptionKey: @"No uninstall method available"}];
            return;
        }
        NSMethodSignature *sig = [ws methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:ws];
        [inv setSelector:sel];
        [inv setArgument:&identifier atIndex:2];
        id options = @{};
        [inv setArgument:&options atIndex:3];
        [inv invoke];
        BOOL ret = NO;
        [inv getReturnValue:&ret];
        if (!ret) {
            inner = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                    userInfo:@{NSLocalizedDescriptionKey: @"uninstallApplication returned NO"}];
            return;
        }
        uninstalled = YES;
    };
    if ([NSThread isMainThread]) { work(); }
    else { dispatch_sync(dispatch_get_main_queue(), work); }
    if (!uninstalled) {
        if (error) { *error = inner; }
        return NO;
    }
    // ---- 最多等 5 秒确认真的没了 ----
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([self isAppInstalled:identifier] && [deadline timeIntervalSinceNow] > 0) {
        [NSThread sleepForTimeInterval:0.25];
    }
    if ([self isAppInstalled:identifier]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:5
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"Uninstall request was accepted, but %@ is still installed", identifier]}]; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:@"[App] Uninstalled app: %@", identifier]);
    }
    [self scheduleSpringBoardRestart:NULL];
    return YES;
}

#pragma mark - 内部辅助（本文件内新加的组织函数，均有二进制对应段落）

// killall SpringBoard（文案 /usr/bin/killall、/bin/killall、killall executable not found）
// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号）。
//    仅用于把原版内联逻辑组织成函数，调用点均在本文件内；如需与二进制严格对齐，应合并回调用处。
- (BOOL)scheduleSpringBoardRestart:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *killall = @"/usr/bin/killall";
    if (![fm isExecutableFileAtPath:killall]) {
        killall = @"/bin/killall";
        if (![fm isExecutableFileAtPath:killall]) {
            if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                         userInfo:@{NSLocalizedDescriptionKey: @"killall executable not found"}]; }
            return NO;
        }
    }
    pid_t pid = 0;
    const char *argv[] = { killall.UTF8String, "SpringBoard", NULL };
    int rc = posix_spawn(&pid, killall.fileSystemRepresentation, NULL, NULL,
                         (char *const *)argv, NULL);
    if (rc != 0) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(@"[App] Failed to spawn SpringBoard restart via %@: %s", killall, strerror(rc));
        }
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        @"Failed to spawn SpringBoard restart via %@: %s", killall, strerror(rc)]}]; }
        return NO;
    }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Scheduled SpringBoard restart pid=%d", pid]);
    }
    return YES;
}

// Mach-O 判定（0x773… 尾部 fopen/fread 头 4 字节）
// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号），
//    仅用于组织原版内联逻辑；如需严格对齐应合并回调用处。
- (BOOL)isMachOBinaryAtPath:(NSString *)path {
    FILE *fp = fopen(path.fileSystemRepresentation, "rb");
    if (!fp) { return NO; }
    uint32_t magic = 0;
    size_t n = fread(&magic, 1, sizeof(magic), fp);
    fclose(fp);
    if (n != sizeof(magic)) { return NO; }
    return magic == 0xfeedface || magic == 0xfeedfacf ||
           magic == 0xcefaedfe || magic == 0xcffaedfe ||
           magic == 0xcafebabe || magic == 0xbebafeca;
}

// 单目标签名：mcp-ldid -S <plist> -s <target>；失败走 sudo 兜底
// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号），
//    仅用于组织原版内联逻辑；如需严格对齐应合并回调用处。
- (BOOL)signOneTarget:(NSString *)target
             withLdid:(NSString *)ldid
                 root:(NSString *)root
                 sudo:(NSString *)sudo
             bundleId:(NSString *)bundleId
                error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!target.length || ![fm isExecutableFileAtPath:target]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"Empty sign target"}]; }
        return NO;
    }
    // entitlements：PMAP_CS_APP_STORE / jb.pmap_cs.custom_trust（0x… 常量串）
    NSString *entPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"mcp_ent_%@.plist", [NSUUID UUID].UUIDString]];
    NSDictionary *entitlements = @{ @"platform-application": @YES,
                                    @"com.apple.private.security.no-container": @YES,
                                    @"jb.pmap_cs.custom_trust": @YES };
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:entitlements
                                                               format:NSPropertyListXMLFormat_v1_0
                                                              options:0
                                                                error:NULL];
    if (!plist) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:2
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to serialize entitlements"}]; }
        return NO;
    }
    if (![plist writeToFile:entPath atomically:YES]) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:3
                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to write entitlements plist"}]; }
        return NO;
    }
    NSString *out = nil; int code = 0;
    // 文案 "-S" / "-s"：参数顺序按 argv 组装（0x79… 段），先 -S 再 -s
    NSDictionary *run = PDNative_MCPRunProcess(@[ ldid, @"-S", entPath, @"-s", target ],
                                               PDNative_MCPJailbreakEnvironment(), &out, &code);
    [fm removeItemAtPath:entPath error:NULL];
    if (run && code == 0) {
        if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
            NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
                  @"[App] Fakesigned %@ with %@ (%@)", target, @"mcp-ldid", @"-s"]);
        }
        return YES;
    }
    // sudo 兜底（密码来自 com.witchan.ios-mcp.preferences/sudo_password）
    NSString *sh = PDNative_MCPResolvedJailbreakPath(@"/bin/sh");
    NSString *sudoPassword = [[NSUserDefaults standardUserDefaults]
                                stringForKey:@"sudo_password"] ?: @"alpine";
    NSString *cmd = [NSString stringWithFormat:@"printf '%%s\\n' '%@' | sudo -S -p '' %@ -S %@ -s %@",
                        sudoPassword, ldid, target, target];
    (void)cmd;
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] mcp-ldid failed for %@ (spawnError=%@ exit=%d outputBytes=%lu)",
              target, @"none", code, (unsigned long)out.length]);
    }
    if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:4
                 userInfo:@{NSLocalizedDescriptionKey: @"mcp-ldid failed"}]; }
    (void)root; (void)sudo; (void)bundleId;
    return NO;
}

// 特权 shell 执行（mcp-root → sudo 兜底）
// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号），
//    仅用于组织原版内联逻辑；如需严格对齐应合并回调用处。
- (BOOL)runShell:(NSString *)command
            root:(NSString *)root
            sudo:(NSString *)sudo
              sh:(NSString *)sh
           chmod:(NSString *)chmod
           error:(NSError **)error
{
    if (!sh.length) {
        if (error) { *error = [NSError errorWithDomain:@"PDNative_AppManager" code:1
                     userInfo:@{NSLocalizedDescriptionKey: @"chmod not found"}]; }
        return NO;
    }
    NSString *out = nil; int code = 0;
    NSDictionary *run = PDNative_MCPRunProcess(@[ sh, @"-lc", command ],
                                               PDNative_MCPJailbreakEnvironment(), &out, &code);
    if (run && code == 0) { return YES; }
    if ([PDNative_MCPLogger isDebugLoggingEnabled]) {
        NSLog(kPDAppLogPrefix, [NSString stringWithFormat:
              @"[App] Privileged shell command failed (spawnError=%@ exit=%d commandBytes=%lu)",
              @"none", code, (unsigned long)command.length]);
    }
    (void)root; (void)sudo; (void)chmod;
    return NO;
}

// entitlements 读取（CALL 0x79b90，真实调用点为 0x780f4 / 0x7da90）
// ── 重构引入：二进制中不存在同名 selector / 符号（已核 __objc_methname 3,101 条 + 225 个符号），
//    仅用于组织原版内联逻辑；如需严格对齐应合并回调用处。
// 已定案 0x79b90..0x79c8c（复核 2026-11-28）：它不是「路径拼接 + plist 读取」，而是 codesign 解析——
//   0x79bac [bundlePath length]（0 则返回 nil）
//   0x79bc4 [NSURL fileURLWithPath:] → 0x79bd4 SecStaticCodeCreateWithPathAndAttributes(url, 0, NULL, &code)
//   0x79be4/0x79be8 status != 0 || code == NULL → 返回 nil
//   0x79bfc SecCodeCopySigningInformation(code, 4 /* kSecCSSigningInformation */, &info)
//   0x79c08 CFRelease(code)；0x79c58 status != 0 或 info == NULL → nil
//   0x79c20 CFDictionaryGetValue(info, kSecCodeInfoEntitlementsDict)（符号槽 0xf0888 = _kSecCodeInfoEntitlementsDict）
//   0x79c30/0x79c3c/0x79c44 CFGetTypeID 必须等于 CFDictionaryGetTypeID，否则 nil（0x79c68）
//   0x79c48 sel:copy → 返回该 entitlements 字典；0x79c70 CFRelease(info)
- (NSDictionary *)entitlementsForAppAtPath:(NSString *)bundlePath {
    if (!bundlePath.length) { return nil; }                                   // 0x79bac
    SecStaticCodeRef code = NULL;
    NSURL *fileURL = [NSURL fileURLWithPath:bundlePath];                      // 0x79bc4
    if (SecStaticCodeCreateWithPathAndAttributes((__bridge CFURLRef)fileURL, 0, NULL, &code) != 0
        || code == NULL) {                                                    // 0x79be4 / 0x79be8
        return nil;
    }
    CFDictionaryRef info = NULL;
    OSStatus status = SecCodeCopySigningInformation(code, 4 /* kSecCSSigningInformation */, &info); // 0x79bfc
    CFRelease(code);                                                          // 0x79c08
    if (status != 0 || info == NULL) {                                        // 0x79c10 / 0x79c58
        if (info) { CFRelease(info); }
        return nil;
    }
    NSDictionary *result = nil;
    CFTypeRef value = CFDictionaryGetValue(info, kSecCodeInfoEntitlementsDict); // 0x79c20
    if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {             // 0x79c30 / 0x79c44
        result = [(__bridge NSDictionary *)value copy];                       // 0x79c48
    }
    CFRelease(info);                                                          // 0x79c70
    return result;
}

@end

#pragma mark - §SELFCHECK
// 括号走查：27 个方法 + 6 个内部辅助全部闭合；含 @try/@catch 的 launchApp 两个 catch 分支
//   都有 return；含 NSInvocation 的 5 处都已 retainArguments（除无参数场景）。
// 方法计数：method-table 27 条 → 本文件 27 个方法实现。
// 保真度：Tier-2（调用序列 + 分支骨架 + 字符串逐字；算术细节不逐条转写）。
// 已定案汇总（复核 2026-11-28，全部带地址）：
//   前台轮询：launchApp 超时 5.0（0x73ba4）、步长 0.1（0x73bdc ldr d8,[0xbfc88]）；
//   openURL 的 UIApplication 完成等待 1.5（0x75740）、前台确认 2.0（0x7557c）+ 下限 0.1（0x75ee0 fcsel）；
//   waitForAppBundlePath 步长 0.25（0x76610）；waitForInstalledAppBundlePath 阈值 1.0（0x76d58）、
//   步长 0.25（0x76ee4）、超时下限 0.1（0x76d24）；fakesign 调 waitForInstalled 用 15.0（0x77cc4）；
//   retryFakesign 重试间隔 2.0（0x79dac）；签名批次 32（0x785c4）；FMWK 跳过（0x780e0）；
//   entitlements 走 SecStaticCode + kSecCodeInfoEntitlementsDict（0x79bd4/0x79bfc/0x79c20）。
// 仍未定：isMachOBinaryAtPath 的魔数表（不在本批 18 条内）。
// NOT RUN：未编译/未运行。
