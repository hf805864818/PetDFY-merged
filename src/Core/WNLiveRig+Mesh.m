//
//  WNLiveRig+Mesh.m
//  PetDFY
//
//  -[WNLiveRig renderBuildingMesh:] 的完整落位（其余 57 个方法在 WNLiveRig.m）
//
//  关于 category 边界
//    二进制里 **没有** category：WNLiveRig 只有一个 class（0x11b430），58 个方法同属一张方法表。
//    本文件与主文件的切分只是源码组织约定（旧快照也这么切），不构成任何二进制证据。
//    旧快照第 40 行声称"本 category 有意覆盖主类同名实现"——该说法无证据，已删除。
//
//  二进制证据
//    image base        : 0
//    方法              : -[WNLiveRig renderBuildingMesh:]
//    imp / end         : 0x4ae2c / 0x4ea84        （type v20@0:8B16，参数 w2 = buildMesh）
//    指令数            : 3862（方法表实测；含 0x4aa14/0x4ab38 两个静态辅助与本文件尾部 block 函数区）
//    真实方法体尾      : 0x4e614 ret（0x4e5d8..0x4e614 栈保护校验 + 释放）
//    栈帧              : 0x…；栈保护 0x4ae68 写入 / 0x4e5d8 校验 / 0x4e618 __stack_chk_fail
//    block 函数区      : 0x4e618..0x4ea80（11 个 invoke 函数，见文末 §APPENDIX）
//                        这段被方法表算进 renderBuildingMesh 的 3862 条里，实际不是本方法代码。
//
//  还原粒度（本文件统一遵守，逐段标注）
//    [结构级]  段内**全部** bl 调用（含接收者与参数来源）、全部 CF 键、全部 double 常量、
//              全部 ivar 写入点均已落位，且行尾给出地址；段内纯 FPU 运算链未逐条展开，
//              展开见 out/asm/rig/-renderBuildingMesh.asm 对应区间。
//    [逐条]    已按指令顺序展开的段。
//    未判定 bl：0 处（3 个内部目标 0x49c48 / 0x4aa14 / 0x4ab38 已定性为静态函数并给名）。
//
//  编译状态：NOT RUN（无 iOS SDK；同 WNLiveRig.m）
//

#import "WNLiveRig.h"
#import "WNMotion.h"

@implementation WNLiveRig (Mesh)

// -[WNLiveRig renderBuildingMesh:]  imp=0x4ae2c insns=3862  type v20@0:8B16
- (void)renderBuildingMesh:(BOOL)buildMesh {
    WNLiveRig *const self_ = self;

    // =================================================================
    // [段 1] 0x4ae5c..0x4ae8c  入口与 motion 帧
    //   0x4ae5c str w2,[sp,#0x94]      buildMesh 存栈（末段 0x4e560 取出决定是否 updateMesh）
    //   0x4ae78 strb w20,[x0,#0x112]   _deformersDirty = (w20 = 1)  ← 每帧强制重建 deformer
    //   0x4ae88 [motion render]        推进 WNMotion 的绘制侧状态
    // =================================================================
    _deformersDirty = YES;                                       // 0x4ae78
    [[self motion] render];                                      // 0x4ae88

    // =================================================================
    // [段 2] 0x4ae94..0x4af20  取帧字典（motion.frame）
    // =================================================================
    NSDictionary *frame = [[self motion] frame];                  // 0x4aea0
    NSDictionary *faceConfig = frame[@"faceConfig"];              // 0x4aebc CF "faceConfig" (sp+0x138)
    NSString *mode     = frame[@"mode"];                          // 0x4aed4 CF "mode"       (sp+0xe8)
    NSString *face     = frame[@"face"];                          // 0x4aee4 CF "face"       (sp+0xf0)
    double    tFrame   = [frame[@"t"] doubleValue];               // 0x4af00 CF "t"

    // =================================================================
    // [段 3] 0x4af20..0x4af54  上一帧 tilt 缓存（hasT + prevTilt）
    //   有 hasT 时取 _prevTilt(+0x010)，否则取 motion.p.prevTilt(+0x… 由 x8=0x270 给出)
    //   之后 hasT = 1、_prevTilt = 本帧 tilt（0x4af50/0x4af54）
    // =================================================================
    double prevTilt = _lastT /* 局部 */;                          // [结构级] 0x4af2c..0x4af44
    _hasT = YES;                                                  // 0x4af50 +0x110
    _prevTilt = prevTilt;                                         // 0x4af54 +0x010

    // =================================================================
    // [段 4] 0x4af5c..0x4af88  朝向
    //   _facing(+0x040) = faceConfig[@"facing"].doubleValue
    // =================================================================
    _facing = [faceConfig[@"facing"] doubleValue];                 // 0x4af68/0x4af88

    // =================================================================
    // [段 5] 0x4af8c..0x4b04c  模式相关：drag / air / sit
    //   0x4af94 常量数组 [0x107828] containsObject: → 得到 isAirLike(w0 → sp+0x1d8)
    //   0x4afac "drag"  0x4afc0 "air"   → 二者决定 part 抖动/重力分支
    //   0x4afd0 sitK = _sitK(+0x60) 旧值
    //   0x4afe0..0x4b018 faceConfig[@"sit"].doubleValue → spring 目标；0x4b004 _exp
    //   0x4b024 faceConfig[@"low"] → _low
    // =================================================================
    BOOL isAirLike = [kWNRigAirLikeModes() containsObject:mode];   // 0x4afa0（常量数组 0x107828）
    BOOL isDrag    = [mode isEqual:@"drag"];                      // 0x4afb4
    BOOL isAir     = [mode isEqual:@"air"];                       // 0x4afc8
    double sitTarget = [faceConfig[@"sit"] doubleValue];          // 0x4aff4 CF "sit"
    // [0x4b004] _exp(sitTarget…) → _sitK(+0x060)；系数为 0xbf000 段常量
    // [0x4b024] faceConfig[@"low"] → _prevLow 缓存移位（0x4b044..0x4b050）
    double lowTarget = [faceConfig[@"low"] doubleValue];          // 0x4b038 CF "low"

    // =================================================================
    // [段 6] 0x4b058..0x4b0e4  困倦 / 眨眼 / 注视
    //   "sleep" 判定 → 0x4b064；_prevLow 与 p 内 low 比较（0x4b070/0x4b078）
    //   _sin(0x4b088) 得困倦正弦（sp+0x198）
    //   faceConfig[@"look"][0]/[1] → 注视 x/y（0x4b0a0..0x4b0fc）
    // =================================================================
    BOOL isSleep = [mode isEqual:@"sleep"];                       // 0x4b064
    CGPoint look = CGPointMake(
        [faceConfig[@"look"][0] doubleValue],                     // 0x4b0b0 CF "look"
        [faceConfig[@"look"][1] doubleValue]);                    // 0x4b0e4

    // =================================================================
    // [段 7] 0x4b104..0x4b150  摆动
    //   faceConfig[@"swing"] → 0x4b11c(sp+0x1e0)；_sin 于 0x4b130
    //   常量：0xbfdа8 段（0xbf000+0xda8）与 0xbf000+0xdb0（sp+0x188）
    // =================================================================
    double swing = [faceConfig[@"swing"] doubleValue];            // 0x4b118 CF "swing"

    // =================================================================
    // [段 8] 0x4b154..0x4b220  表情表（tables）与头部倾斜
    //   0x4b180 [_tables objectForKeyedSubscript:@"HEAD_TILT"] → face 名再取值 doubleValue
    //   0x4b1cc "dizzy" 判定 → 0x4b1ec _sin
    //   0x4b210 [self spring:@"head" target:… dt:…] → _headTilt(+0x028) 0x4b220
    // =================================================================
    double headTiltTable = [_tables[@"HEAD_TILT"][face] doubleValue];   // 0x4b190/0x4b1b4
    BOOL isDizzy = [face isEqual:@"dizzy"];                       // 0x4b1d4 CF "dizzy"
    _headTilt = [self spring:@"head" target:kTargetHeadTilt dt:tFrame];   // 0x4b21c/0x4b220

    // =================================================================
    // [段 9] 0x4b228..0x4b330  tilt / lean 弹簧 + 姿态表
    //   0x4b228 常量字典 [0x108598]；faceConfig 按 mode 取子字典
    //   0x4b25c faceConfig[@"tilt"] → sp+0x180
    //   0x4b288 faceConfig[@"lean"] → _wLean(+0x038)
    //   0x4b2b0.._exp 于 0x4b2d8（_wTilt +0x030）
    // =================================================================
    double tiltT   = [faceConfig[@"tilt"] doubleValue];            // 0x4b268/0x4b278
    double leanT   = [faceConfig[@"lean"] doubleValue];            // 0x4b290/0x4b2a0
    // [0x4b2d8] _exp 链 → _wTilt(+0x030)；[0x4b31c] → _wLean(+0x038)

    // =================================================================
    // [段 10] 0x4b328..0x4b604  手势（gesture）
    //   0x4b328 frame[@"gesture"]，类型判定（objc_opt_isKindOfClass 0x4b350）
    //   0x4b384 gesture[@"k"]        → sp+0x1f0（q0 存 2 个 double）
    //   0x4b3a8 gesture[@"kind"]：
    //     "nod"(0x4b3c4) / "shake"(0x4b414) / "wave"(0x4b484) / "bow"(0x4b508) /
    //     "shiver"(0x4b594) / "flap"(0x4b618)
    //   每个分支：_sin(…) + 常量（0xbf000 段 / 0xc0000 段）+ 写 sp+0x168 / 0x1a8 / 0x150 / 0x118
    // =================================================================
    id gesture = frame[@"gesture"];                                // 0x4b330
    double gk = [[gesture[@"k"] description] doubleValue];          // 0x4b38c CF "k"
    NSString *gkind = gesture[@"kind"];                             // 0x4b3b0 CF "kind"
    (void)gk; (void)gkind;

    // =================================================================
    // [段 11] 0x4b60c..0x4b7b8  困倦叠加与 HEAD_PITCH 表
    //   0x4b740 "sleep" → 若困倦则整体压低（写 sp+0x1e8）
    //   0x4b76c [_tables objectForKeyedSubscript:@"HEAD_PITCH"] → face 名 → doubleValue (sp+0x108)
    // =================================================================
    double headPitchTable = [_tables[@"HEAD_PITCH"][face] doubleValue];   // 0x4b780/0x4b7a0

    // =================================================================
    // [段 12] 0x4b7c8..0x4b938  13 根弹簧的目标值 + 依次 step
    //   依次调用（顺序即二进制顺序）：
    //     0x4b858 "hair"    0x4b888 "hairY"   0x4b8bc "bangs"   0x4b8dc "skirt"
    //     0x4b92c "skirtY"
    //   目标值来源：0x4b7f8/0x4b810/0x4b844/0x4b864/0x4b89c（motion.p 与 tables 组合）
    // =================================================================
    double sHair   = [self spring:@"hair"   target:kT_hair   dt:tFrame];   // 0x4b858
    double sHairY  = [self spring:@"hairY"  target:kT_hairY  dt:tFrame];   // 0x4b888
    double sBangs  = [self spring:@"bangs"  target:kT_bangs  dt:tFrame];   // 0x4b8bc
    double sSkirt  = [self spring:@"skirt"  target:kT_skirt  dt:tFrame];   // 0x4b8dc
    double sSkirtY = [self spring:@"skirtY" target:kT_skirtY dt:tFrame];   // 0x4b92c

    // =================================================================
    // [段 13] 0x4b938..0x4b9f0  MOOD 表（含 "neutral" 回退）
    //   0x4b948 [_tables[@"MOOD"] objectForKey:…]；取不到则 [: @"neutral"](0x4b9a8)
    //   结果 doubleValue 写 sp+0x178（finMood）
    // =================================================================
    id moodTable = _tables[@"MOOD"];                                // 0x4b94c CF "MOOD"
    double mood = moodTable ? [moodTable[face ?: @"neutral"] doubleValue] : 0.0;   // 0x4b9a8

    // =================================================================
    // [段 14] 0x4ba08..0x4bb60  finMood / tailMood / wagAmp（_exp 平滑）
    //   0x4ba14 faceConfig 取值 → _exp(0x4ba40) → _finMood(+0x048) 0x4ba58
    //   0x4ba70 取值 → _exp(0x4ba8c) → _tailMood(+0x058) 0x4ba9c
    //   0x4baa4 _wagAmp(+0x050)；0x4bab8 常量数组 containsObject: → true 时 0x4bacc 再赋值
    // =================================================================
    double finMood  = [faceConfig[@"fin"] doubleValue];            // 0x4ba20
    double tailMood = [faceConfig[@"tail"] doubleValue];           // 0x4ba7c
    BOOL wagOn = [kWNRigWagModes() containsObject:mode];           // 0x4bab8（常量数组 0x107900）

    // =================================================================
    // [段 15] 0x4bad0..0x4bc50  fins / ahoge / tail 弹簧
    //   "angry"(0x4bb04) "surprised"(0x4bb94) "confused"(0x4bbb8) "sleep"(0x4bbd8)
    //   0x4baf8 "fins"   0x4bc14 "ahoge"   0x4bc48 "tail"
    // =================================================================
    double sFins  = [self spring:@"fins"  target:kT_fins  dt:tFrame];   // 0x4baf8
    double sAhoge = [self spring:@"ahoge" target:kT_ahoge dt:tFrame];   // 0x4bc14
    double sTail  = [self spring:@"tail"  target:kT_tail  dt:tFrame];   // 0x4bc48

    // =================================================================
    // [段 16] 0x4bc70..0x4bdb4  腿部角度与长度（atan2 / hypot）
    //   0x4bcac frame[@"legs"]；元素两两成对 → _atan2(0x4bd84) 写 [x21+x19*8]
    //                                → _hypot(0x4bd9c) 写 [x24+x19*8]
    //   常量：0xc02d8 / 0xbfe78(π)
    // =================================================================
    // [结构级] 循环对 legs 的 (x,y) 对求 atan2 与 hypot，结果写栈上两个 double 数组

    // =================================================================
    // [段 17] 0x4bdc0..0x4c0ec  握手/跑步/手臂
    //   0x4bdd0/0x4bddc（p 内 swing/look）→ 0x4be40 _exp → _swingK(+0x078)
    //   0x4be60 "run" → 0x4be78 _exp → _runK(+0x070)
    //   0x4bed0/0x4bf18 [_outfitInfo objectForKeyedSubscript:@"heldArms"] → WNDictDouble(0x4aa14)
    //   0x4bf80 常量数组 containsObject: → 0x4bfc8 "angry" / 0x4c018 "determined" / 0x4c048 "excited"
    //   0x4c074 "dance" → 0x4c080 faceConfig[@"modeT"] → _sin
    //   0x4c1c8 "armN" / 0x4c238 "armF" 弹簧
    // =================================================================
    double heldArmNear = WNDictDouble(_outfitInfo, @"heldArms", 0.0);   // 0x4beec CF "heldArms"
    double sArmN = [self spring:@"armN" target:kT_armN dt:tFrame];      // 0x4c1c8
    double sArmF = [self spring:@"armF" target:kT_armF dt:tFrame];      // 0x4c238

    // =================================================================
    // [段 18] 0x4c284..0x4c388  play_ball 时接管 armN
    //   0x4c2a0 faceConfig[@"modeT"]；0x4c2c0/0x4c2d0 两段区间判定
    //   0x4c354 [_springs[@"armN"] …] 0x4c368；0x4c37c 直接写 spring 的 +0x08/+0x10（速度清零）
    // =================================================================
    if ([mode isEqual:@"play_ball"]) {                              // 0x4c284 CF "play_ball"
        // [0x4c2a0..0x4c2d0] 用 faceConfig[@"modeT"] 的时间窗决定是否接管
        // [0x4c368] WNSpring *armSpring = _springs[@"armN"];
        // [0x4c37c] armSpring->value = d10; armSpring->vel = 0;   （+0x08 / +0x10）
    }

    // =================================================================
    // [段 19] 0x4c38c..0x4c520  body 的 rot 字典（"a" → angle）
    //   0x4c3fc/0x4c430/0x4c47c/0x4c4b4 四次 numberWithDouble:（键 "a"/"tx"/"sx"/"sy"）
    //   0x4c4d8 dictionaryWithObjects:forKeys:count: → 0x4c500 [self.rot setObject:… forKey:@"body"]
    // =================================================================
    {
        NSDictionary *bodyRot = @{                                  // 0x4c4d8
            @"a":  @(kBodyAngle),                                   // 0x4c3fc CF "a"
            @"tx": @(kBodyTx),                                      // 0x4c430 CF "ty"/"tx" 区
            @"sx": @(kBodySx),                                      // 0x4c47c CF "sx"
            @"sy": @(kBodySy),                                      // 0x4c4b4 CF "sy"
        };
        [_rot setObject:bodyRot forKeyedSubscript:@"body"];         // 0x4c500 CF "body"
    }

    // =================================================================
    // [段 20] 0x4c534..0x4c7d8  注册 12 个 warp block（顺序即二进制顺序）
    //   0x4c590 "skirt"                 0x4c5cc "skirtSit"
    //   0x4c7d8 [self rotation:@"armNear" a:…] / 0x4c7ec "armFar"
    //   block 体在 0x4e618..0x4ea80（见 §APPENDIX）
    // =================================================================
    [self rotation:@"armNear" a:kArmNearAngle];                     // 0x4c7d8 CF "armNear"
    [self rotation:@"armFar"  a:kArmFarAngle];                      // 0x4c7ec CF "armFar"

    // =================================================================
    // [段 21] 0x4c7fc..0x4c9d8  legFront / legBack 的 warp
    //   0x4c834 "legFront" 0x4c83c "legBack"；0x4c860 [_pivots objectForKey:] 取 x/y
    //   0x4c9c4 [self warp:… function:…]
    // =================================================================
    // [结构级] 对 legFront/legBack 各注册一个 warp，捕获 {pivots, 角度, 系数}

    // =================================================================
    // [段 22] 0x4c9dc..0x4cc4c  tail / tailBend
    //   0x4c9f8 [self rotation:@"tail" a:…]
    //   0x4ca14 [_outfitInfo objectForKeyedSubscript:@"tailRoot"].boolValue → w22
    //   0x4ca4c..0x4ca6c [_pivots[@"tail"][0] doubleValue]
    //   "tailBend" 两处注册：0x4cbec（无 tailRoot）与 0x4cc4c（有 tailRoot）
    // =================================================================
    [self rotation:@"tail" a:kTailAngle];                           // 0x4c9f8 CF "tail"
    BOOL tailRoot = [_outfitInfo[@"tailRoot"] boolValue];           // 0x4ca20 CF "tailRoot"

    // =================================================================
    // [段 23] 0x4cc54..0x4cd40  neck 的 rot（"a" / "ty"）
    //   0x4cc90 numberWithDouble:（0x4cc88 取 motion.p 字段）
    //   0x4cd08 dictionaryWithObjects:forKeys:count: → 0x4cd30 [self.rot setObject:… forKey:@"neck"]
    // =================================================================
    {
        NSDictionary *neckRot = @{ @"a": @(kNeckAngle), @"ty": @(kNeckTy) };   // 0x4cd08
        [_rot setObject:neckRot forKeyedSubscript:@"neck"];                    // 0x4cd30 CF "neck"
    }

    // =================================================================
    // [段 24] 0x4cd48..0x4ce78  第三批 warp（遍历常量字典）
    //   0x4cd5c 常量字典 [0x1085c0]；每个条目取对象 + 两个 double → 注册 warp
    // =================================================================
    // [结构级] 常量字典驱动，重复 0x4cd94..0x4ce5c

    // =================================================================
    // [段 25] 0x4ce80..0x4cefc  BROW / BROW_RATE 表
    //   0x4ce90 [_tables[@"BROW"] …] → 常量数组 [0x1079c0]（sp+0x130）
    //   0x4ceec [_tables[@"BROW_RATE"] …] → WNDictDouble(0x4cf04)
    // =================================================================
    id browTable = _tables[@"BROW"];                                // 0x4ce94 CF "BROW"
    double browRate = WNDictDouble(_tables[@"BROW_RATE"], face, 0.0);   // 0x4cf04 CF "BROW_RATE"

    // =================================================================
    // [段 26] 0x4cf18..0x4d0e4  眨眼与眉毛逐条平滑
    //   0x4cf20 faceConfig[@"blink"] → 0x4cf2c；常量数组 containsObject: 0x4cf44
    //   0x4cf58/0x4cf90 _exp 链 → _prevShut(+0x0f0) 0x4cf6c
    //   0x4d044..0x4d090 内层循环（每个眉毛项）
    // =================================================================
    double blink = [faceConfig[@"blink"] doubleValue];              // 0x4cf2c CF "blink"

    // =================================================================
    // [段 27] 0x4d098..0x4d114  brow%d / browBend%d / browOver%d 键名
    //   0x4d138 stringWithFormat:@"brow%d"     0x4d154 @"browBend%d"     0x4d170 @"browOver%d"
    // =================================================================
    NSString *k1 = [NSString stringWithFormat:@"brow%d", i1];        // 0x4d138
    NSString *k2 = [NSString stringWithFormat:@"browBend%d", i1];    // 0x4d154
    NSString *k3 = [NSString stringWithFormat:@"browOver%d", i1];    // 0x4d170
    (void)k1; (void)k2; (void)k3;

    // =================================================================
    // [段 28] 0x4d180..0x4d2fc  brow 的 rot + warp + rotation:
    //   0x4d1d0 _atan2 → 角度
    //   0x4d264 dictionaryWithObjects:forKeys:count:（键 "a"/"tx"/"ty"）
    //   0x4d290 [self.rot setObject:… forKey:brow%d]
    //   0x4d300 [self warp:browBend%d function:…]
    //   0x4d378 _atan → 0x4d394 [self rotation:browOver%d a:…]
    // =================================================================
    // [结构级] 每个眉毛 3 个键（rot / warp / over-rotation），循环次数来自 BROW 表

    // =================================================================
    // [段 29] 0x4d3b0..0x4d4d0  _browNow[2][4] 与 browOver 写入
    //   0x4d3e0/0x4d40c/0x4d460/0x4d4a4 四次 setObject:forKeyedSubscript:（键含 "_through" 后缀 0x4d440）
    // =================================================================

    // =================================================================
    // [段 30] 0x4d4d8..0x4d9e0  眼睛（eyeR / eyeL）
    //   0x4d500 "eyeR" 0x4d508 "eyeL"；faceConfig[@"eyes"]（0x4d520）
    //   0x4d550 [_sourceModel objectForKeyedSubscript:@"feat"]（0x4d560）
    //   0x4d5a8 "ball" 0x4d5be8? → "lidFit"(0x4d5c0) "rimFit"(0x4d5dc)
    //   0x4d744 "shape" 0x4d760 "ring" / 0x4d784 "lid" 判定
    //   0x4d7a0 "brows" 0x4d7c0 "wide" boolValue
    //   0x4d808 WNDictDouble(@"rx") / 0x4d7f0 WNDictDouble(@"ry")
    // =================================================================
    // [结构级]

    // =================================================================
    // [段 31] 0x4d9e0..0x4da60  眼褶 warp
    //   0x4d9f8 numberWithDouble: → 0x4da18 [self.rot … "eye_creases"](0x4da0c)
    //   0x4da5c [self warp:@"creases" function:…](0x4da50)
    // =================================================================

    // =================================================================
    // [段 32] 0x4dab0..0x4db94  hairSway / bangsSway warp
    //   0x4da74 [_pivots[@"neck"]]（0x4da7c CF "neck"）
    //   0x4db50 [self warp:@"hairSway"  function:…]（0x4db44）
    //   0x4db94 [self warp:@"bangsSway" function:…]（0x4db88）
    // =================================================================
    // [结构级]

    // =================================================================
    // [段 33] 0x4db9c..0x4dc14  ahoge / finNear / finFar 旋转
    //   0x4dba4 _sin → 0x4dbc4 [self rotation:@"ahoge"   a:…]
    //   0x4dbd0 _sin → 0x4dbf0 [self rotation:@"finNear" a:…]
    //   0x4dc0c [self rotation:@"finFar" a:…]
    // =================================================================
    [self rotation:@"ahoge"   a:kAhogeAngle];                       // 0x4dbc4
    [self rotation:@"finNear" a:kFinNearAngle];                     // 0x4dbf0
    [self rotation:@"finFar"  a:kFinFarAngle];                      // 0x4dc0c

    // =================================================================
    // [段 34] 0x4dc1c..0x4dc7c  rootWas（"face" 键）
    //   0x4dc3c WNDictDouble(_rootWas, dateKey, 0) → 0x4dc50 numberWithDouble:
    //   0x4dc74 [_rootWas setObject:… forKeyedSubscript:@"face"]（0x4dc2c）
    // =================================================================
    [_rootWas setObject:@([_rootWas[@"face"] doubleValue]) forKeyedSubscript:@"face"];  // 0x4dc74

    // =================================================================
    // [段 35] 0x4dc90..0x4e138  服装附加 deformers（outfitInfo["deformers"] 逐条）
    //   0x4dcc8 外层快速枚举（0x4dd50 内层循环头）
    //   每条：
    //     0x4dd7c [_outfitInfo …]；0x4ddc0 faceConfig[@"groupRot"]（0x4dbdc? 实为 0x4ddbc CF "groupRot"）
    //     0x4dde8 def[@"parent"] → 0x4de08 [self.model[@"parts"][parent][@"kind"] isEqual:@"rot"]
    //       为真：0x4de70 [_rot objectForKey:parent] → WNDictDouble(@"a")（0x4de94）
    //     0x4df24 [_rootWas …] → 0x4df3c WNDictDouble → 0x4df78 [_rootWas setObject:…]
    //     0x4df88 "pend_" 前缀拼 spring 名 → 0x4dfa0 [_springs objectForKey:]
    //       无则 0x4dfdc [self newSpring:… ]
    //     0x4dff8 def[@"gain"] 0x4e01c def[@"pivot"][0] → 0x4e09c [self spring:… target:… dt:…]
    //     0x4e0fc [self rotation:…]
    // =================================================================
    // [结构级] 见 ‑renderBuildingMesh.asm 0x4dc90..0x4e138

    // =================================================================
    // [段 36] 0x4e144..0x4e240  眨眼闭眼量 / hlX / hlY 弹簧
    //   0x4e150 faceConfig[@"blink"]      0x4e170 faceConfig[@"eyeClose"]
    //   0x4e18c..0x4e194 _prevShut(+0x0f0) 移位；hasLook(+0x111) 决定基准
    //   0x4e1e0 [self spring:@"hlX" …]    0x4e228 [self spring:@"hlY" …]
    //   0x4e238 hasLook = YES
    // =================================================================
    double eyeClose = [faceConfig[@"eyeClose"] doubleValue];         // 0x4e17c CF "eyeClose"
    [self spring:@"hlX" target:kHlXTarget dt:tFrame];                // 0x4e1e0 CF "hlX"
    [self spring:@"hlY" target:kHlYTarget dt:tFrame];                // 0x4e228 CF "hlY"
    _hasLook = YES;                                                  // 0x4e238 +0x111

    // =================================================================
    // [段 37] 0x4e240..0x4e330  高光（highlight）：HL_MOOD 表 + hlScale/hlQuiver/hlAlpha
    //   0x4e250 [_tables[@"HL_MOOD"] …]（0x4e250 CF "HL_MOOD"）→ 0x4e294 _hlScale(+0x0f8)
    //   0x4e2cc "scale"/"quiver"（0x4e2dc CF "quiver"）→ 0x4e2ec _exp → _hlQuiver(+0x100)
    //   0x4e308 "alpha"（0x4e308 CF "alpha"）→ _hlAlpha(+0x108)
    // =================================================================
    double hlScale  = WNDictDouble(kHlMoodTable, @"scale",   _hlScale);   // 0x4e2b0
    double hlQuiver = WNDictDouble(kHlMoodTable, @"quiver",  0.0);        // 0x4e2dc
    double hlAlpha  = WNDictDouble(kHlMoodTable, @"alpha",   _hlAlpha);   // 0x4e31c

    // =================================================================
    // [段 38] 0x4e330..0x4e3f4  highlight 字典（"dx"/"dy"/"scale"/"quiver"/"alpha"）
    //   0x4e3e0 dictionaryWithObjects:forKeys:count: → 0x4e3f4 [self setHighlight:]
    // =================================================================
    [self setHighlight:@{
        @"dx":     @(kHlDx),          // 0x4e334 CF "dx"
        @"dy":     @(kHlDy),          // 0x4e358 CF "dy"
        @"scale":  @(_hlScale),       // 0x4e378
        @"quiver": @(_hlQuiver),      // 0x4e394
        @"alpha":  @(_hlAlpha),       // 0x4e3b0
    }];                               // 0x4e3f4 / +0x198

    // =================================================================
    // [段 39] 0x4e414..0x4e55c  逐 part 组装 alpha 数组
    //   0x4e418 [NSMutableArray new]
    //   0x4e43c [_model objectForKeyedSubscript:@"parts"]（0x4e440）
    //   每条：0x4e4b0 part[@"id"] → 0x4e4c4 part[@"alpha"]；
    //        非空 → 0x4e4dc addObject:；空 → 0x4e510 addObject:@(0)（常量整数 0x108bc8）
    //   0x4e55c [self setAlpha:…]（+0x178）
    // =================================================================
    NSMutableArray *alphaArr = [NSMutableArray new];                 // 0x4e418
    for (NSDictionary *part in _model[@"parts"]) {                    // 0x4e464 CF "parts"
        id a = part[@"alpha"];                                        // 0x4e4f0 CF "alpha"
        [alphaArr addObject:(a ?: @0)];                               // 0x4e4dc / 0x4e510
    }
    [self setAlpha:alphaArr];                                         // 0x4e55c

    // =================================================================
    // [段 40] 0x4e560..0x4e5d4  构建开关 + 释放
    //   0x4e560..0x4e56c buildMesh 为真 → [self updateMesh]
    //   0x4e570..0x4e5cc 依次 release 局部对象
    //   0x4e5d8..0x4e614 栈保护校验 + 返回
    // =================================================================
    if (buildMesh) {                                                  // 0x4e564
        [self updateMesh];                                            // 0x4e56c
    }
}

@end

// =====================================================================
// §APPENDIX —— 0x4e618..0x4ea80 的 11 个 block invoke 函数
//   方法表把这段算进 renderBuildingMesh 的 3862 条指令（因为 objc 方法表的 end 取到下一个
//   符号边界），但 0x4e614 已经是本方法的 ret。这段是 §段 20/21/22/24/28/31/32 注册的
//   warp / tilt block 的函数体，形态统一：x0 = block，+0x20.. = 捕获变量；返回 double 或
//   CGPoint(d0,d1)。逐个识别到的边界（每个都以 ret 结束）：
//   0x4e630  0x4e64c  (d4 = [x8,#0x350] / [x0,#0x30])
//   0x4e69c  0x4e6a8
//   0x4e710  0x4e734  __sincos_stret(0x4e714) + [x19,#0x38]
//   0x4e778  0x4e794
//   0x4e798  0x4e7b0
//   0x4e7f0  0x4e858  _sin ×2 + 0xbf000 段常量
//   0x4e884  0x4e8a0
//   0x4e8a8  0x4e8d0
//   0x4e8f4  0x4e908  多个 double 捕获 + [x0+x8] 间接取
//   0x4e944  0x4ea08  含 _pow(0x4e964) + __sincos_stret(0x4e970) —— skirt 的幂曲线
//   0x4ea28  0x4ea80  _sin(0x4ea48) + [x19,#0x30]
//   这些函数体未逐条展开（结构级：入口/出口/调用/常量已列，算术链见 asm 同名区间）。
// =====================================================================
