//
//  PDPreferences.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  还原来源：out/prefs_asm/000236e8_PDPreferences_init.asm … 00023bfc_PDPreferences__cxx_destruct.asm
//  实例变量布局（__objc_ivar_list，instsize=88）：
//      +0x08 BOOL _enabled                      +0x30 NSString *_scheme
//      +0x09 BOOL _interactive                  +0x38 NSString *_outfit
//      +0x0a BOOL _responsive                   +0x40 NSString *_roam
//      +0x0b BOOL _soundEnabled                 +0x48 NSString *_doubleTapAction
//      +0x0c BOOL _stroking                    +0x50 NSString *_longPressAction
//      +0x10 double _size
//      +0x18 double _bottomInset
//      +0x20 double _keyboardAvoidanceExtra
//      +0x28 NSInteger _framesPerSecond
//
#import "PDPreferences.h"
#import "PDSupport.h"

// 偏好域（imp 0x23750 / 0x23c70 引用的 CF 常量 "com.susudear.petdfyprefs"）
// 统一用 PDSupport.m 里的全局定义（0x004cc00），不再本地复制一份

#pragma mark - 私有取值助手（imp 0x23c50 / 0x23998 / 0x23ac0 / 0x23a24）

// imp 0x23c50  id PDValue(NSString *key, id def)
//   CFPreferencesCopyAppValue(key, "com.susudear.petdfyprefs") ?: def
static id PDValue(NSString *key, id def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    PDPreferencesDomainRef());
    return v ? CFBridgingRelease(v) : def;
}

// imp 0x23998  BOOL PDBoolValue(NSString *key)
//   id v = PDValue(key, @YES);
//   return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES;
static BOOL PDBoolValue(NSString *key) {
    id v = PDValue(key, [NSNumber numberWithBool:YES]);
    BOOL result = YES;
    if ([v respondsToSelector:@selector(boolValue)]) {
        result = [v boolValue];
    }
    return result;
}

// imp 0x23ac0  double PDClampedDouble(NSString *key, double def, double min, double max)
//   id v = PDValue(key, @(def));
//   double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
//   if (isinf(d) || isnan(d)) return def;
//   return MAX(min, MIN(max, d));          // fminnm/fmaxnm
static double PDClampedDouble(NSString *key, double def, double min, double max) {
    id v = PDValue(key, [NSNumber numberWithDouble:def]);
    double d = def;
    if ([v respondsToSelector:@selector(doubleValue)]) {
        d = [v doubleValue];
    }
    if (isinf(d) || isnan(d)) {
        return def;
    }
    return MAX(min, MIN(max, d));
}

// imp 0x23a24  id PDValueIn(NSString *key, NSArray *allowed, id def)
//   id v = PDValue(key, def);
//   return ([v isKindOfClass:[NSString class]] && [allowed containsObject:v]) ? v : def;
static id PDValueIn(NSString *key, NSArray *allowed, id def) {
    id v = PDValue(key, def);
    if ([v isKindOfClass:[NSString class]] && [allowed containsObject:v]) {
        return v;
    }
    return def;
}

#pragma mark -

@interface PDPreferences () {
    BOOL _enabled;                    // +0x08
    BOOL _interactive;                // +0x09
    BOOL _responsive;                 // +0x0a
    BOOL _soundEnabled;               // +0x0b
    BOOL _stroking;                   // +0x0c
    double _size;                     // +0x10
    double _bottomInset;              // +0x18
    double _keyboardAvoidanceExtra;   // +0x20
    NSInteger _framesPerSecond;       // +0x28
    NSString *_scheme;                // +0x30
    NSString *_outfit;                // +0x38
    NSString *_roam;                  // +0x40
    NSString *_doubleTapAction;       // +0x48
    NSString *_longPressAction;       // +0x50
    BOOL _keyboardAvoidanceEnabled;   // +0x0d
}
@end

@implementation PDPreferences

// imp 0x0236e8  types @16@0:8
- (id)init {
    self = [super init];
    if (self) {
        [self reload];
    }
    return self;
}

// imp 0x023738  types v16@0:8
- (void)reload {
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());

    _enabled      = PDBoolValue(@"Enabled");        // 0x23764 strb w0,[x19,#8]
    _interactive  = PDBoolValue(@"Interactive");    // 0x23774 strb w0,[x19,#9]
    _responsive   = PDBoolValue(@"Responsive");     // 0x23784 strb w0,[x19,#0xa]
    _soundEnabled = PDBoolValue(@"Sound");          // 0x23794 strb w0,[x19,#0xb]

    // 0x23798: CF "InputMode" ∈ {grab, stroke}，默认 "grab"；stroking = (value == "stroke")
    NSString *inputMode = PDValueIn(@"InputMode", @[@"grab", @"stroke"], @"grab");
    _stroking = [inputMode isEqualToString:@"stroke"];   // 0x237c8 strb w0,[x19,#0xc]

    _doubleTapAction = PDValueIn(@"DoubleTapAction", @[@"none", @"voice", @"chat"], @"none");
    _longPressAction = PDValueIn(@"LongPressAction", @[@"menu", @"voice", @"chat", @"none"], @"menu");
    _scheme          = PDValueIn(@"Scheme",
                                 @[@"deepseek", @"harness", @"chatgpt", @"claude",
                                   @"gemini", @"qwen", @"kimi", @"minimax"],
                                 @"deepseek");
    _outfit          = PDValueIn(@"Outfit", @[@"maid", @"cape", @"crew", @"sailor"], @"maid");
    _roam            = PDValueIn(@"Roam", @[@"free", @"calm", @"off"], @"free");

    // 0x238ac: Size 默认 128.0，范围 [72.0, 220.0]（常量 0x4060…/0x4052…/__const 0x2b780）
    double rawSize = PDClampedDouble(@"Size", 128.0, 72.0, 220.0);
    // 0x238d4: PetScale 默认 1.0，范围 [0.5, 10.0]
    double petScale = PDClampedDouble(@"PetScale", 1.0, 0.5, 10.0);
    _size = rawSize * petScale;                     // 0x238f0 str d0,[x19,#0x10]

    _bottomInset = PDClampedDouble(@"BottomInset", 12.0, 0.0, 200.0);   // +0x18

    // 0x23918: FPS 默认 60.0，范围 [30.0, 120.0]，再量化到 30 / 60 / 120
    double fps = PDClampedDouble(@"FPS", 60.0, 30.0, 120.0);
    NSInteger fpsInt = (NSInteger)fps;              // fcvtzs：向零截断
    if (fpsInt > 44) {
        _framesPerSecond = (fpsInt > 99) ? 120 : 60;
    } else {
        _framesPerSecond = 30;
    }

    _keyboardAvoidanceEnabled = PDBoolValue(@"KeyboardAvoidanceEnabled");  // +0xd
    _keyboardAvoidanceExtra = PDClampedDouble(@"KeyboardAvoidanceExtra", 0.0, 0.0, 200.0); // +0x20
}

#pragma mark - 只读属性（逐条对应 2 条指令的 getter）

// imp 0x023b84  types B16@0:8
- (BOOL)enabled { return _enabled; }

// imp 0x023b8c  types B16@0:8
- (BOOL)interactive { return _interactive; }

// imp 0x023b94  types B16@0:8
- (BOOL)responsive { return _responsive; }

// imp 0x023b9c  types B16@0:8
- (BOOL)soundEnabled { return _soundEnabled; }

// imp 0x023ba4  types B16@0:8
- (BOOL)stroking { return _stroking; }

// imp 0x023bac  types d16@0:8
- (double)size { return _size; }

// imp 0x023bb4  types d16@0:8
- (double)bottomInset { return _bottomInset; }

// imp 0x023bbc  types B16@0:8
- (BOOL)keyboardAvoidanceEnabled { return _keyboardAvoidanceEnabled; }

// imp 0x023bc4  types d16@0:8
- (double)keyboardAvoidanceExtra { return _keyboardAvoidanceExtra; }

// imp 0x023bcc  types q16@0:8
- (NSInteger)framesPerSecond { return _framesPerSecond; }

// imp 0x023bd4  types @16@0:8
- (id)scheme { return _scheme; }

// imp 0x023bdc  types @16@0:8
- (id)outfit { return _outfit; }

// imp 0x023be4  types @16@0:8
- (id)roam { return _roam; }

// imp 0x023bec  types @16@0:8
- (id)doubleTapAction { return _doubleTapAction; }

// imp 0x023bf4  types @16@0:8
- (id)longPressAction { return _longPressAction; }

// imp 0x023bfc  types v16@0:8  —— objc_storeStrong(&_longPressAction … &_scheme, nil)
- (void)dealloc {
    // ARC 下无需手写；_cxx_destruct 由编译器生成（5 个 strong 对象 +0x30…+0x50）
}

@end
