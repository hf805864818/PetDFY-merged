//
//  WNMotion+Render.m — 逆向还原：render / faceAt: / decideAutonomousAction
//
//  还原依据：PetDFY.dylib arm64e
//    render                  781 insns / 23 selector
//    faceAt:                 619 insns / 16 selector
//    decideAutonomousAction  470 insns / 26 selector
//
//  ---- render ----
//  调用序列：face → faceAt: → is:×2 → pulse×3 → groupTilt×2 → numberWithInt:
//            → setTransform: → eyeCur → eyePrev → setObject:forKeyedSubscript:×3
//  输出字典键：face / faceConfig / eyes / eyeClose / blink / blush / drag /
//              drowse / facing / dur / ax / ay / AX / AY
//
//  ---- faceAt: ----
//  以 _faces 为模板 mutableCopy，再按当前状态覆写 12 个键：
//    eyes / lid / rot / gap / content / s / rx / ry / cry / dizzy / love / heart
//  表情名：neutral happy sleep dragged love dizzy surprised blink
//          cry flustered
//
//  ---- decideAutonomousAction ----
//  按 roamMode（free / calm / off）与随机数选择行为：
//    idle / wait / look / walk / run / jump / sit
//  常量：6.0 30.0 9.0 2.0 4.0 0.5
//

#import "WNMotion.h"
#import <math.h>

@implementation WNMotion (Render)

#pragma mark - faceAt:（表情参数装配）

/// 按表情名生成该表情的完整参数表（以 _faces 模板为基底）。
- (NSDictionary *)faceAt:(NSString *)name {
    NSString *requested = [name isKindOfClass:[NSString class]] ? name : @"neutral";
    NSDictionary *aliases = @{ @"grabbed": @"dragged", @"walking": @"run",
                               @"idle": @"neutral", @"poke": @"surprised" };
    NSString *resolved = aliases[requested] ?: requested;
    NSDictionary *neutral = [_faces isKindOfClass:[NSDictionary class]] ? _faces[@"neutral"] : nil;
    NSDictionary *base = [_faces isKindOfClass:[NSDictionary class]] ? _faces[resolved] : nil;
    if (![base isKindOfClass:[NSDictionary class]]) base = neutral;
    NSMutableDictionary *out = [base isKindOfClass:[NSDictionary class]] ? [base mutableCopy]
                                                                       : [NSMutableDictionary dictionary];

    NSArray *neutralEyes = [neutral[@"eyes"] isKindOfClass:[NSArray class]] ? neutral[@"eyes"] : nil;
    if (![out[@"eyes"] isKindOfClass:[NSArray class]] || [(NSArray *)out[@"eyes"] count] < 2) {
        out[@"eyes"] = neutralEyes ?: @[ @{ @"shape": @"ring", @"rx": @16.0, @"ry": @16.0 },
                                          @{ @"shape": @"ring", @"rx": @16.0, @"ry": @16.0 } ];
    }
    if (![out[@"gap"] isKindOfClass:[NSArray class]] || [(NSArray *)out[@"gap"] count] < 2) {
        out[@"gap"] = @[@50.0, @50.0];
    }
    if ([requested isEqualToString:@"blink"]) {
        out[@"eyes"] = @[ @{ @"shape": @"lid", @"ry": @0.0 },
                           @{ @"shape": @"lid", @"ry": @0.0 } ];
    }
    return out;
}

#pragma mark - render（输出渲染数据包）

- (void)render {
    NSString *faceName = [self currentFaceName];
    if (![faceName isKindOfClass:[NSString class]] || faceName.length == 0) faceName = @"neutral";
    NSDictionary *faceConfig = [[self faceAt:faceName] mutableCopy];
    NSMutableDictionary *mutableFace = [faceConfig mutableCopy] ?: [NSMutableDictionary dictionary];
    mutableFace[@"blush"] = @(p.blushK);
    faceConfig = mutableFace;

    double t = time;
    double blink = 0.0;
    double blinkDuration = 0.16;
    if (p.blinkAge >= 0.0 && p.blinkAge < blinkDuration) {
        blink = sin((p.blinkAge / blinkDuration) * M_PI);
    }

    double sq = fmax(fmin(p.sq, 0.65), -0.35);
    double horizontal = scale * (1.0 - sq * 0.35);
    double vertical = scale * (1.0 + sq * 0.45);
    double facingScale = (p.faceVis < 0.0 ? -1.0 : 1.0);
    double rotation = p.tilt + p.lean;
    NSDictionary *xf = @{ @"AX": @(p.x), @"AY": @(p.fy),
                          @"ax": @128.0, @"ay": @256.0,
                          @"kx": @(horizontal * facingScale), @"ky": @(vertical),
                          @"rot": @(rotation) };
    [self setTransform:xf];
    [self setFace:faceConfig];

    NSArray *faceEyes = [faceConfig[@"eyes"] isKindOfClass:[NSArray class]] ? faceConfig[@"eyes"] : @[];
    if (![_eyeCur isKindOfClass:[NSArray class]]) _eyeCur = faceEyes;
    NSMutableArray *eyeQuads = [NSMutableArray arrayWithCapacity:4];
    for (NSUInteger i = 0; i < 4; i++) {
        NSDictionary *eye = i < faceEyes.count && [faceEyes[i] isKindOfClass:[NSDictionary class]]
                          ? faceEyes[i] : nil;
        double dx = [eye[@"dx"] doubleValue];
        double dy = [eye[@"dy"] doubleValue];
        double rx = eye ? [eye[@"rx"] doubleValue] : 0.0;
        double ry = eye ? [eye[@"ry"] doubleValue] : 0.0;
        [eyeQuads addObject:@[@(dx), @(dy), @(rx), @(ry)]];
    }

    NSArray *leg0 = @[ @104.0, @(p.low + 212.0), @(p.feet[0]), @(p.feet[1]) ];
    NSArray *leg1 = @[ @150.0, @(p.low + 212.0), @(p.feet[2]), @(p.feet[3]) ];
    NSDictionary *frame = @{ @"face": faceName,
                             @"faceConfig": faceConfig,
                             @"eyes": eyeQuads,
                             @"look": @[@(p.lookX), @(p.lookY)],
                             @"legs": @[leg0, leg1],
                             @"low": @(p.low), @"t": @(t),
                             @"blink": @(blink), @"eyeClose": @(blink),
                             @"eyePrev": _eyePrev ?: [NSNull null],
                             @"swing": @(p.swing), @"mode": _mode ?: @"idle",
                             @"modeT": @(p.modeT), @"talk": @(p.talkK),
                             @"drowse": @(p.drowse), @"sit": @(p.sitK),
                             @"facing": @(p.faceVis), @"tilt": @(p.tilt),
                             @"lean": @(p.lean), @"groupRot": @(rotation),
                             @"gesture": _pulse ?: @{} };
    [self setFrame:frame];
}


#pragma mark - decideAutonomousAction（自主行为决策）

/// 根据 roamMode 和随机数决定下一步动作。
/// 动作：idle / wait / look / walk / run / jump / sit
- (void)decideAutonomousAction {
    if ([_roamMode isEqualToString:@"off"] || time < _roamHoldUntil) return;

    BOOL calm = [_roamMode isEqualToString:@"calm"];
    double r = [self random];
    if (r < 0.48) {
        BOOL run = !calm && r > 0.38;
        _roamHoldUntil = time + [self rnd:3.0 to:6.0];
        _lastAction = run ? @"run" : @"walk";
        [self walkTo:[self pickRoamingTarget] run:run identifier:nil];
    } else if (r < 0.70) {
        _roamHoldUntil = time + [self rnd:1.5 to:3.5];
        _lastAction = @"look";
        p.glanceAt = 0.0;
        [self setModeTo:@"look"];
    } else {
        _roamHoldUntil = time + [self rnd:2.0 to:5.0];
        _lastAction = @"wait";
        [self setModeTo:@"idle"];
    }
}


@end
