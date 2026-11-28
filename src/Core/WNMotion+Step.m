//
//  WNMotion+Step.m
//  PetDFY
//
//  -[WNMotion step:] 逐帧推进（方法体完整还原，非片段）
//
//  二进制证据
//    image base          : 0（arm64 切片 extract/bin/PetDFY.arm64.dylib）
//    方法范围            : 0x43ee8（序言 stp d15,d14,[sp,#-0xa0]!）→ 0x46b5c
//    指令数              : 2880（0x43ee8..0x46be4 含静态辅助）
//    真实方法尾          : 0x45a34 ret（冷分支区 0x45a38..0x46b5c 之后再无其它入口）
//    静态辅助            : 0x46b60..0x46be4 = WNGetDouble(dict, key, dflt)，已被本方法
//                          在 0x44a38/0x44a64/0x44a90/0x44ac0/0x44c74/0x44d74/0x46xxx 调用
//    栈帧                : 0x43f14 sub sp,sp,#0x1e0；sp+0x20..sp+0x90 是姿态目标槽
//    栈保护              : 0x43f64 写入 / 0x459f0 校验 / 0x46b5c __stack_chk_fail
//
//  字段偏移来源
//    - 实例变量名与偏移：__objc_ivar（已解析，见 out/notes/step-coverage.md §1），
//      例如 _mode +0x250、pointerX +0x210、time +0x1d8。
//    - p（匿名结构，+0x08 起，464 字节）：字段名由 -snapshot（0x48b64..0x491c8）
//      的字典键顺序 + 本方法用法交叉确定；键序为
//      x,fy,gy,gvy,vx,vy,facing,faceVis,modeT,sq,sqv,tilt,tiltV,lean,sitK,
//      stretch,low,look,swing,swingV,velX,feet,blinkAge,blinkT,exprUntil。
//      键序与偏移不完全单调，故每个访问点都在行尾标注真实字节偏移。
//
//  记号
//    [0xADDR]  —— 该行对应的指令地址
//    /* +0xNNN */ —— 结构体/对象字段的真实偏移（Observed）
//    Assumed  —— 语义推断标记（偏移仍为 Observed）；本文件 16 个 p 字段已逐条对二进制定案，
//                正文改标「已定案 0xADDR: 证据」；未定案处继续用 Assumed，见 step-coverage.md §4
//    CALL 0xADDR —— 未解析的 bl 目标（本方法内 0 处：472 条 bl 全部解析为 sel:/符号）
//
//  编译状态：NOT RUN（本机为 Windows + 无 iOS SDK / 无 PetDFY 头文件全量声明，
//  未能实际编译；已完成括号走查，见文末 §SELFCHECK）
//

#import "WNMotion.h"
#import <math.h>
#import <float.h>

#pragma mark - p（WNMotion 的姿态结构，偏移以 self 为基准）

// instanceSize 792，p 位于 +0x08，长 464（= 0x1d8 - 0x08）。
// 下列 double 字段的排列与二进制逐一对应，行尾为绝对偏移。
// B 方案：姿态结构已并入 PetDFY.h 的 WNMotionState（字段名与本文件一致），
// 不再在此重复定义。


// [0x46b60] 静态辅助：从字典取 double，取不到时返回默认值。
// 二进制里 objectForKeyedSubscript 被调用了两次（0x46b94 判定存在性 / 0x46bac 取值），
// 语义等价于下面这一版。
static double WNGetDouble(NSDictionary *dict, NSString *key, double dflt) {
    id v = [dict objectForKeyedSubscript:key];
    if (v == nil) {
        return dflt;
    }
    return [v doubleValue];
}

// 0x107618 / 0x107660 / 0x107678 / 0x107630 / 0x107648 为 __NSConstantArray 字面量，
// 元素已从 __DATA_CONST 解出（见 step-coverage.md §2）。
static NSArray *WNLookModes(void)    { return @[@"idle", @"sit"]; }              // 0x107618
static NSArray *WNRingShapes(void)   { return @[@"ring", @"lid"]; }              // 0x107630
static NSArray *WNEyeKeys(void)      { return @[@"rx", @"ry", @"dx", @"dy"]; }   // 0x107648
static NSArray *WNGaitModes(void)    { return @[@"walk", @"run", @"dance"]; }    // 0x107660
static NSArray *WNAirModes(void)     { return @[@"drag", @"air"]; }              // 0x107678


@implementation WNMotion (Step)

- (void)step:(double)dt {
    // =====================================================================
    // [0x43ee8] 序言与 dt 合法性守卫
    //   0x43f18 fmov d8,d0 … 0x43f80 tbnz w8,#0 → 0x459f0（直接返回）
    //   判定：dt 必须 > 0 且有限；否则跳到 0x459f0 走收尾。
    // =====================================================================
    if (!(dt > 0.0) || !isfinite(dt)) {
        return;                                          // [0x43f80] -> 0x459f0
    }

    WNMotionState *pp = &p;

    // [0x43f88] time += dt
    time += dt;                                          // +0x1d8
    // [0x43f94] p.modeT += dt
    pp->modeT /* +0x48 */ += dt;                                     // +0x48

    NSString *mode = self.mode /* +0x250 */;                          // +0x250（x20）
    double modeT = pp->modeT /* +0x48 */;                            // d13

    // [0x43fac] 自主行为总开关：roamMode == "off" 时关闭，否则看 time 是否越过 roamHoldUntil
    BOOL autonomous;
    if ([self.roamMode /* +0x2d0 */ isEqualToString:@"off"]) {        // +0x2d0 / CF "off" 0xf30e8
        autonomous = NO;                                 // [0x43fd0]
    } else {
        autonomous = (time > self.roamHoldUntil /* +0x2d8 */);        // [0x43fd8..0x43fe8] +0x2d8
    }

    // =====================================================================
    // [0x43ff0] 眨眼计时
    // =====================================================================
    pp->blinkT /* +0x118 */ -= dt;                                    // +0x118
    pp->blinkAge /* +0x120 */ += dt;                                  // +0x120
    if (pp->blinkT /* +0x118 */ <= 0.0) {                             // [0x44000] b.hi 跳过
        pp->blinkAge /* +0x120 */ = 0.0;                              // [0x4400c]
        if ([self random] < 0.2) {                       // [0x44018] 0xbfd28 = 0.2
            pp->blinkT /* +0x118 */ = 0.28;                           // [0x44028] 0xbfe20 = 0.28
        } else {
            pp->blinkT /* +0x118 */ = [self rnd:2.2 to:5.2];          // [0x44034] 0xc0070 / 0xc0078
        }
    }

    // =====================================================================
    // [0x4404c] 指针相对舞台锚点的偏移
    //   0x44050 d0=146.05(0xc0080) 0x44058 d1=128.13(0xc0088) → -toStage:
    // =====================================================================
    CGPoint anchor = [self toStage:CGPointMake(146.05, 128.13)];
    double px = pointerX - anchor.x;                // [0x44064] d10, +0x210
    double py = pointerY - anchor.y;                // [0x44070] d11, +0x218
    double dist = hypot(px, py);                         // [0x4407c] d12
    if (dist == 0.0) {                                   // [0x44080..0x44088]
        dist = 1.0;                                      // fcsel d12,d0,d1,ne
    }

    // =====================================================================
    // [0x4408c] 注视目标 lookX/lookY
    //   仅 {"idle","sit"} 跟随指针；"wake" 在 modeT>1.2 后也跟随；
    //   其余模式 look 恒为 0。
    // =====================================================================
    double lpLookX = 0.0;                                // d14
    double lpLookY = 0.0;                                // d15
    BOOL trackPointer;
    if ([WNLookModes() containsObject:mode]) {           // [0x44090] 0x107618
        trackPointer = YES;
    } else if ([mode isEqualToString:@"wake"]) {         // [0x440a4] CF "wake" 0xf9948
        trackPointer = (modeT > 1.2);                    // [0x440bc] 0xbff40 = 1.2
    } else {
        trackPointer = NO;                               // [0x440b8] -> 0x44148
    }
    if (trackPointer) {
        if (pointerInside) {                        // [0x440d0] +0x241
            double k = fmin(dist / 120.0, 1.0);          // [0x440d8..0x440e8] 120.0
            lpLookX = k * ((px * pp->facing /* +0x38 */) / dist) * 5.0;   // [0x440ec..0x44100] +0x38
            lpLookY = k * ((py / dist) * 4.0);           // [0x44104..0x44110]
        } else {
            // [0x44118] 指针在外：随机瞟视，0.45 概率归零
            if (time > pp->glanceAt /* +0x188 */) {                   // +0x188
                if ([self random] < 0.45) {              // [0x44130] 0xbfc08 = 0.45
                    pp->glanceX /* +0x178 */ = 0.0;                   // [0x4413c] +0x178
                    pp->glanceY /* +0x180 */ = 0.0;                   // [0x44144] -> 0x44174, +0x180
                } else {
                    pp->glanceX /* +0x178 */ = [self rnd:-3.0 to:5.0];     // [0x44150..0x4415c]
                    pp->glanceY /* +0x180 */ = [self rnd:-3.0 to:3.0];     // [0x44164..0x44170]
                }
                pp->glanceAt /* +0x188 */ = time + [self rnd:1.2 to:3.0];  // [0x44178..0x44190] 0xbff40
            }
            lpLookX = pp->glanceX /* +0x178 */;                       // [0x44198]
            lpLookY = pp->glanceY /* +0x180 */;
        }
    }

    // =====================================================================
    // [0x4419c] 模式分派：只负责写入姿态目标槽
    //   sp+0x20 tBob  sp+0x28 tLift  sp+0x30 tLean  sp+0x38 tSitK
    //   sp+0x58 tSway sp+0x80 kTilt  sp+0x88 cTilt  sp+0x90 tDrowse
    //   d11 = 基础倾斜（最终写入 tilt 弹簧目标）  d14/d15 = lookX/lookY
    // =====================================================================
    double tBob = 0.0, tLift = 0.0, tLean = 0.0, tSitK = 0.0, tSway = 0.0;
    double kTilt = 160.0, cTilt = 12.0, tDrowse = 0.0;   // 0x4424c/0x441fc 的默认组合
    double tiltBias = 0.0;                               // d11（最终 tilt 目标）
    double squashBias = 0.0;                             // d13（最终 sq 目标）
    BOOL usePointerVX = NO;                              // w19
    double swingVel = 0.0;                               // d9
    double lookX = lpLookX;                              // d14
    double lookY = lpLookY;                              // d15

    if ([mode isEqualToString:@"idle"]) {                // [0x441a4] CF "idle" 0xf38a8
        // ---- 背对指针判定（0x441c0..0x441f0）----
        BOOL behind = NO;
        if (pointerInside && !pressing) {      // +0x241 / +0x240
            // 0x441e4 x8 = -0x3fb7000000000000  ⇒ 位型 0xC049000000000000 = -50.0
            behind = (dist < 600.0) && ((px * pp->facing /* +0x38 */) < -50.0);   // 0x441d8 = 600.0
        }
        if (behind) {
            // [0x45c5c] 背对：累计滞留计时，> 0.9s 翻面并清零
            pp->stallT /* +0x140 */ += dt;                            // +0x140
            if (pp->stallT /* +0x140 */ > 0.9) {                      // [0x45c68] 0xbfda8 = 0.9
                pp->facing /* +0x38 */ = -pp->facing /* +0x38 */;                // [0x45c7c] +0x38
                pp->stallT /* +0x140 */ = 0.0;                        // [0x45c84] -> 0x441f8
            }
        } else {
            pp->stallT /* +0x140 */ = 0.0;                            // [0x441f8] +0x140
        }
        // [0x441fc] 倾斜刚体 160/12，困倦 0
        cTilt = 12.0;                                    // [0x441fc] sp+0x88
        tDrowse = 0.0;                                   // [0x44204] sp+0x90

        // [0x44208] 自主行为门控
        if (autonomous) {
            BOOL suppressed = NO;
            if (time > pp->nextAt /* +0x130 */) {                     // [0x4420c] +0x130
                if ([self expression] != nil) {          // [0x4421c] +0x258
                    if (time < pp->exprUntil /* +0x128 */) {          // [0x44238] +0x128
                        suppressed = YES;
                    }
                }
            }
            if (!suppressed) {
                [self decideAutonomousAction];           // [0x44240]
            }
        }
        tBob = 0.0;                                      // [0x44248/0x4424c/0x44250]
        goto label_zero_targets;                        // -> 0x44254 -> 0x442e0                           // -> 0x442e0 -> 0x446f4

    } else if ([mode isEqualToString:@"walk"] ||
               [mode isEqualToString:@"run"]) {          // [0x4425c..0x44280]
        // =================================================================
        // [0x44284] 行走 / 奔跑
        // =================================================================
        BOOL isRun = [mode isEqualToString:@"run"];      // [0x44290] CF "run" 0xf90c8

        double baseX = pp->x /* +0x08 */;                            // [0x44298] +0x08
        double dx = pp->walkToX /* +0x58 */ - baseX;                 // [0x442a4] +0x58
        double baseY = pp->gy /* +0x18 */;                           // [0x442a8] +0x18
        double dy = pp->walkToY /* +0x60 */ - baseY;                 // [0x442b0] +0x60
        double wdist = hypot(dx, dy);                    // [0x442bc] d10

        // 朝向：dx != 0 取符号，否则保持
        double dir;
        if (dx != 0.0) {                                 // [0x442c4]
            dir = (dx > 0.0) ? 1.0 : -1.0;               // [0x442f4..0x442fc]
        } else {
            dir = pp->facing /* +0x38 */;                            // [0x442cc]
        }
        // 落地状态要求 |dx| > 2 才允许转向；自由悬浮时无条件转
        if (fabs(dx) > 2.0 || !freeGround) {        // [0x44304..0x44318] +0x242
            pp->facing /* +0x38 */ = dir;                            // [0x4431c]
        }

        double cap  = isRun ? 250.0 : 78.0;              // [0x44320..0x44334] 0xbfc30/0xc0130
        double want = isRun ? (wdist * 4.0 + 20.0) : (wdist * 3.0 + 14.0);
        want = fmin(cap, want);                          // [0x44354] d1

        // 步态幅度基准：bob 17/10，lift 15/8；sway 7/3
        double gBob  = isRun ? 17.0 : 10.0;              // [0x44370] sp+0x90
        double gLift = isRun ? 15.0 : 8.0;               // [0x44370] sp+0x88
        double gSway = isRun ? 7.0  : 3.0;               // [0x4437c] sp+0x58

        // 前倾：走 4；跑 11；跑且 dist<50 且 speed>120 → -6
        int leanK;
        double ease, dampK;
        if (!isRun) {
            leanK = 4;                                   // [0x443c0]
            ease  = 0.25;                                // [0x443c4]
            dampK = 9.0;                                 // [0x443c8]
        } else {
            leanK = 11;                                  // [0x44384]
            ease  = 0.35;                                // [0x44390] 0xbfdb8
            dampK = 6.0;                                 // [0x44388]
            if (wdist < 50.0) {                          // [0x44394..0x443a0] 50.0
                if (pp->speed /* +0x68 */ > 120.0) {                 // [0x443a4..0x443b8] 120.0
                    leanK = -6;
                }
            }
        }

        // 模式内加速进度 + smoothstep
        double tAcc = pp->modeT /* +0x48 */ / ease;                  // [0x443cc] d6 = modeT
        tAcc = fmin(tAcc, 1.0);                          // [0x443d4]
        double smooth = tAcc * tAcc * (3.0 - 2.0 * tAcc);// [0x443dc..0x443ec]
        double goal = want * smooth;                     // [0x443ec] d9

        // 指数平滑逼近目标速度
        double cur  = pp->speed /* +0x68 */;                         // [0x443d8] +0x68
        double damp = 1.0 - exp(-dampK * dt);            // [0x443f0..0x443f8]
        double next = cur + (goal - cur) * damp;         // [0x443fc..0x44400]
        pp->speed /* +0x68 */ = next;                                // [0x44404] +0x68

        // 沿目标方向推进，不越过目标
        if (wdist > 0.0) {                               // [0x44408]
            double move = fmin(wdist, next * dt);        // [0x44410..0x44414]
            double ux = dx / wdist;                      // [0x44418]
            double uy = dy / wdist;                      // [0x4441c]
            double ny = baseY + uy * move;               // [0x44420..0x44424]
            pp->fy /* +0x10 */ = ny;                                 // [0x44428] +0x10
            pp->gy /* +0x18 */ = ny;                                 // [0x44428] +0x18
            pp->x /* +0x08 */  = baseX + ux * move;                  // [0x4442c..0x44434] +0x08
        }

        // 速度比 → 步态幅度；相位每 π 一次落脚
        double ratio = fmax(fmin(next / cap, 1.0), 0.0); // [0x44438..0x44444]
        double gait  = 0.4 + 0.6 * ratio;                // [0x44448..0x44458] d9
        double cyclePrev = floor(pp->phase /* +0x88 */ / M_PI);      // [0x4445c..0x44468] +0x88
        double inc = (isRun ? 27.646015351590183          // [0x4446c..0x4447c] 0xc0140
                            : 13.194689145077131) * dt;   //                     0xc0138
        pp->phase /* +0x88 */ += inc * fmax(ratio, 0.35);            // [0x44488..0x44498] 0xbfdb8

        if (floor(pp->phase /* +0x88 */ / M_PI) != cyclePrev) {      // [0x444a8..0x444b4]
            // 落脚音效：@[@(isRun), @(foot)]
            int foot = ((int)floor(pp->phase /* +0x88 */ / M_PI)) & 1;   // [0x444dc..0x444e0]
            [self sound:@"step" kind:@"move"
            arguments:@[ @(isRun), @(foot) ]];           // [0x444b8..0x44528] 0xf3ac8/0xf97a8
            if (isRun && pp->speed /* +0x68 */ > 120.0) {            // [0x44538..0x4454c]
                // csinc w2,w8(3),wzr,mi ⇒ 近处 3 团 / 远处 1 团
                int n = (wdist < 50.0) ? 3 : 1;          // [0x44550..0x44560]
                [self dust:n spread:20.0];               // [0x44564..0x4456c]
            }
        }
        // 奔跑接近目标仍有余速 → 打滑音效，一次进入只触发一次
        if (isRun && wdist < 50.0 && pp->speed /* +0x68 */ > 120.0 && !pp->skidded /* +0x1d4 */) {
            [self sound:@"skid" kind:@"move" arguments:@[]];  // [0x445a4..0x445c0]
            pp->skidded /* +0x1d4 */ = 1;                             // [0x445c4..0x445c8] +0x1d4
        }

        // 目标槽（public 段读取）
        tBob  = gBob  * gait;                            // [0x445d0..0x445d8]
        tLift = gLift * gait;                            // [0x445dc..0x445e4]
        tLean = (double)leanK;                           // [0x445cc] / [0x445e4]
        cTilt = 12.0;                                    // [0x445f4] sp+0x88
        tDrowse = 0.0;                                   // [0x445f4] sp+0x90
        kTilt = 160.0;                                   // [0x446e0] sp+0x80
        tSway = gSway;                                   // [0x4437c] sp+0x58
        tiltBias = 0.0;                                  // [0x446e8] d11

        // ---- 到达判定 [0x445f8] ----
        if (wdist < 1.5) {                               // b.pl 跳过
            pp->speed /* +0x68 */ = 0.0;                             // [0x44604] +0x68
            if (self.walkIdentifier /* +0x300 */ != nil) {            // [0x44608] +0x300
                [self event:@"arrived"
                     detail:@{ @"walkId": self.walkIdentifier /* +0x300 */,   // [0x44674] 0xf8ac8
                               @"x": @(pp->x /* +0x08 */) }];                //              0xf89a8
                self.walkIdentifier /* +0x300 */ = nil;               // [0x446a0..0x446a8]
            }
            [self setModeTo:@"idle"];                    // [0x446ac..0x446b8]
            pp->nextAt /* +0x130 */ = time + [self rnd:1.2 to:3.2];   // [0x446bc..0x446dc]
        }
        goto label_pose_begin;                           // -> 0x446f4

    } else if ([mode isEqualToString:@"look"]) {         // [0x45af0] CF "look" 0xf3ca8
        // =================================================================
        // look：按 modeT 分四段（0.9 / 1.8 / 2.6），只改注视角与 tilt 刚体
        // =================================================================
        tDrowse = 0.0;                                   // [0x45b04] sp+0x90
        if (modeT < 0.9) {                               // [0x45b0c] 0xbfda8
            cTilt = 12.0;                                // [0x45b1c]
            lookX = 4.0;                                 // [0x45b24] d14
            lookY = -4.0;                                // [0x45b24] d15
            kTilt = 160.0;                               // [0x45ea0]
            tiltBias = 0.0;                              // [0x45ea8] d11
            goto label_zero_targets;                     // -> 0x44254
        }
        if (modeT < 1.8) {                               // [0x45c88] 0xbfea0
            cTilt = 12.0;                                // [0x45c98]
            lookX = 5.0;                                 // [0x45ca4] d14（d15 仍为 -4）
            if (!pp->flipOnce /* +0x1d1 */) {                          // [0x45ca0] +0x1d1
                pp->facing /* +0x38 */ = -pp->facing /* +0x38 */;                 // [0x45cac..0x45cc0]
                pp->flipOnce /* +0x1d1 */ = 1;                         // [0x45cb8]
            }
            kTilt = 160.0;                               // 0x4424c
            tiltBias = 0.0;                              // 0x44248
            goto label_zero_targets;                     // -> 0x44254
        }
        if (modeT < 2.6) {                               // [0x45e88] 0xc0068
            cTilt = 12.0;                                // [0x45e80]
            lookX = 1.0;                                 // [0x45e98] d14
            lookY = 4.0;                                 // [0x45e98] d15
            kTilt = 160.0;                               // [0x45ea0]
            tiltBias = 0.0;                              // [0x45ea8]
            goto label_zero_targets;                     // -> 0x44254
        }
        [self setModeTo:@"idle"];                        // [0x45f74..0x45f80]
        pp->nextAt /* +0x130 */ = time + [self rnd:1.0 to:2.5];       // [0x45f84..0x45f98]
        tiltBias = 0.0;                                  // [0x45f9c]
        kTilt = 160.0;                                   // 0x4424c
        goto label_zero_targets;                         // -> 0x44254

    } else if ([mode isEqualToString:@"sit"]) {          // [0x45bfc] CF "sit" 0xf38c8
        // =================================================================
        // sit：低头犯困 → 累加 drowse → 到点转 sleep（或醒回 idle）
        // =================================================================
        double drowse = pp->drowse /* +0xd0 */;                      // [0x45c10] +0xd0
        BOOL canSleep = (pp->sitSeen /* +0x1d3 */ != 0) && autonomous;   // [0x45c18..0x45c24]
        tDrowse = canSleep
                 ? fmax(fmin((modeT - (pp->dwell /* +0x50 */ - 1.6)) / 1.2, 1.0), 0.0)  // 0x45c2c..0x45c54
                 : 0.15;                                 // [0x45dbc] 0xbfd90
        double awake = 1.0 - drowse;                     // [0x45dc8] d9
        // 呼吸前倾：drowse > 0.5 时 drowse*7*pow(max(sin(time*1.3),0),6)
        double breath;
        if (drowse > 0.5) {                              // [0x45dd0..0x45ddc]
            breath = drowse * 7.0 *
                     pow(fmax(sin(time * 1.3), 0.0), 6.0);   // 0x45de0..0x45e08
        } else {
            breath = 0.0;
        }
        lookX *= awake;                                  // [0x45e10] d14
        lookY *= awake;                                  // [0x45e14] d15
        tLean = breath;                                  // [0x45e1c] sp+0x30
        tSitK = 1.0;                                     // [0x45e1c] sp+0x38
        if (autonomous && modeT > pp->dwell /* +0x50 */) {            // [0x45e20..0x45e2c]
            if (pp->sitSeen /* +0x1d3 */ == 0) {
                // [0x461a4] 没真正睡着：回 idle，身体弹一下
                cTilt = 12.0;                            // [0x461a4]
                [self setModeTo:@"idle"];                // [0x461ac]
                pp->sqv /* +0xb0 */ -= 1.2;                          // [0x461b8..0x461cc] 0xc00e8
                pp->nextAt /* +0x130 */ = time + [self rnd:1.5 to:3.0];  // [0x461d4..0x461e8]
            } else {
                [self setModeTo:@"sleep"];               // [0x45e34]
                cTilt = 12.0;                            // [0x45e44]
                pp->dwell /* +0x50 */ = [self rnd:8.0 to:12.0];      // [0x45e4c..0x45e5c]
            }
        } else {
            cTilt = 12.0;                                // [0x45e64]
        }
        kTilt = 160.0;                                   // [0x45e6c]
        tSway = 0.0;                                     // [0x45e74]
        goto label_zero_lean_bob;                        // -> 0x442ec

    } else if ([mode isEqualToString:@"sleep"]) {        // [0x45cc8] CF "sleep" 0xf38e8
        // =================================================================
        // sleep：鼾声节拍 + 强困倦姿态
        // =================================================================
        if (time >= pp->snoreAt /* +0x190 */) {                       // [0x45cdc..0x45ce8] +0x190
            double snore = [self snoreSeconds];          // [0x45cec] +0x2e0
            if (snore <= 0.0 || modeT < snore) {         // [0x45cf4..0x45d08]
                [self sound:@"snore" kind:@"snore"
                arguments:@[ @(modeT) ]];            // [0x45d0c..0x45d54] 0xf3ce8
                pp->snoreAt /* +0x190 */ = time + [self rnd:4.5 to:6.5];  // [0x45d60..0x45d78]
            }
        }
        tiltBias = 0.0;                                  // [0x45d7c]
        tDrowse = 1.0;                                   // [0x45d80] sp+0x90
        tLean = 5.0;                                     // [0x45d88..0x45d90]
        cTilt = 12.0;                                    // [0x45d94]
        if (autonomous && modeT > pp->dwell /* +0x50 */) {            // [0x45d9c..0x45da4]
            [self setModeTo:@"wake"];                    // [0x45da8]
        }
        kTilt = 160.0;                                   // [0x45f54]
        tSway = 0.0;                                     // [0x45f5c]
        tSitK = 1.0;                                     // [0x45f64]
        goto label_zero_lean_bob;                        // -> 0x442ec

    } else if ([mode isEqualToString:@"wake"]) {         // [0x45eb0] CF "wake" 0xf9948
        // =================================================================
        // wake：先醒身（wokeNow），未醒时按 modeT 做伸展 + 打哈欠
        // =================================================================
        if (pp->wokeNow /* +0x1d2 */) {                               // [0x45ec4] +0x1d2
            lookY = -2.0;                                // [0x45ecc] d15
            cTilt = 12.0;                                // [0x45ed0] sp+0x88
            tDrowse = 0.0;                               // [0x45ed8] sp+0x90
            if (modeT > 0.9) {                           // [0x45edc] 0xbfda8
                [self setModeTo:@"idle"];                // [0x45eec]
                pp->nextAt /* +0x130 */ = time + [self rnd:1.5 to:3.0];   // [0x45f00..0x45f98]
            }
            lookX = 3.0;                                 // [0x45f00] / [0x462ec] d14
            tiltBias = 0.0;                              // [0x45f9c]
            kTilt = 160.0;                               // 0x4424c / 0x462ec
            goto label_zero_targets;                     // -> 0x44254
        }
        // 打哈欠音效：跨过 modeT == 0.5 的那一帧
        if (modeT > 0.5 && (modeT - dt) <= 0.5) {        // [0x461f0..0x46204]
            [self sound:@"yawn" kind:@"face" arguments:@YES];   // 0xf3cc8/0xf9908
        }
        tSitK = (modeT < 1.1) ? 1.0 : 0.0;               // [0x46228..0x46240] 0xc0118
        // 伸展挤压：0.5<modeT<1.3 时 sq 目标 -0.1
        squashBias = (modeT > 0.5 && modeT < 1.3) ? -0.1 : 0.0;   // [0x46260] d13
        // 前倾：<0.5 → 5；0.5..1.2 → -5；>=1.2 → 0
        if (modeT < 0.5) {
            tLean = 5.0;                                 // [0x46280..0x46288]
        } else if (modeT < 1.2) {
            tLean = -5.0;                                // [0x46264..0x4627c] 0xbff40
        } else {
            tLean = 0.0;
        }
        tDrowse = 0.0;                                   // [0x46270] sp+0x90
        cTilt = 12.0;                                    // [0x46290]
        if (modeT >= 1.8) {                              // [0x46298] 0xbfea0
            [self setModeTo:@"idle"];                    // [0x462a8]
            pp->nextAt /* +0x130 */ = time + [self rnd:1.0 to:2.0];   // [0x462b8..0x462cc]
        }
        kTilt = 160.0;                                   // [0x462d4]
        tiltBias = 0.0;                                  // [0x462dc]
        tSway = 0.0;                                     // [0x462e4]
        goto label_zero_bob_lift_keep_squash;            // -> 0x46800（tLean 保留）

    } else if ([mode isEqualToString:@"crouch"]) {       // [0x45fa8] CF "crouch" 0xf88e8
        // =================================================================
        // crouch：墩身蓄力，0.16s 后弹射进入 air
        // =================================================================
        cTilt = 12.0;                                    // [0x45fc0] sp+0x88
        tDrowse = 0.0;                                   // [0x45fc0] sp+0x90
        squashBias = 0.24;                               // [0x45fcc] 0xbfe48
        tSitK = 0.3;                                     // [0x45fd4] 0xbfcf8
        if (modeT > 0.16) {                              // [0x45fe0] 0xbfd30
            pp->vx /* +0x28 */ = pp->launchX /* +0x160 */;                        // [0x45ff0..0x45ff8] +0x160
            pp->vy /* +0x30 */ = -pp->launchY /* +0x158 */;                       // [0x45ff0..0x45ff8] +0x158
            [self setAirKind:@"jump"];                   // [0x45ffc..0x4600c]
            pp->sqv /* +0xb0 */ -= 2.6;                              // [0x46010..0x46020] 0xc0110
            [self sound:@"jump" kind:@"move" arguments:@YES];   // 0xf3b68/0xf97a8
            [self setModeTo:@"air"];                     // [0x46040]
        }
        kTilt = 160.0;                                   // [0x46050]
        tiltBias = 0.0;                                  // [0x46058]
        tSway = 0.0;                                     // [0x46060]
        goto label_zero_lean_keep_squash;                // -> 0x467fc

    } else if ([mode isEqualToString:@"air"]) {          // [0x46068] CF "air" 0xf3588
        // =================================================================
        // air：重力积分 + 自由悬浮二段速度 + 上下边界反弹 + 落地判定
        // =================================================================
        double grav = 2300.0;                            // [0x46088] 0xc00d8
        if (self.responsiveInteraction /* +0x249 */ &&                // [0x4607c..0x46098] +0x249
            !self.enteringFromTop /* +0x248 */ &&                     // +0x248
            ![self.airKind /* +0x2c8 */ isEqualToString:@"jump"]) {   // [0x4609c..0x460c8] +0x2c8
            grav = 3200.0;                               // 0x40a9000000000000
        }
        pp->vy /* +0x30 */ += grav * dt;                             // [0x460d0..0x460d8] +0x30
        pp->vx /* +0x28 */ *= exp(-0.4 * dt);                        // [0x460dc..0x460f4] 0xc00e0
        pp->x /* +0x08 */  += pp->vx /* +0x28 */ * dt;                           // [0x460fc..0x46104]
        pp->fy /* +0x10 */ += pp->vy /* +0x30 */ * dt;

        if (freeGround && pp->gvy /* +0x20 */ != 0.0) {         // [0x46108..0x46118] +0x242
            pp->gvy /* +0x20 */ *= exp(-1.2 * dt);                   // [0x4611c..0x46130] 0xc00e8
            double gy2 = pp->gy /* +0x18 */ + pp->gvy /* +0x20 */ * dt;          // [0x46134..0x4613c]
            pp->fy /* +0x10 */ += pp->gvy /* +0x20 */ * dt;                      // [0x46140] stp d0,d10
            pp->gy /* +0x18 */  = gy2;
            if (pp->gy /* +0x18 */ < [self minY]) {                  // [0x46144..0x46150]
                double top = [self minY];                // [0x46154]
                pp->fy /* +0x10 */ += top - pp->gy /* +0x18 */;                  // [0x4615c..0x46168]
                pp->gy /* +0x18 */  = top;                           // [0x46188] stp
                pp->gvy /* +0x20 */ = fabs(pp->gvy /* +0x20 */) * 0.55;          // [0x4616c..0x46188] 0xbfc00
                pp->sqv /* +0xb0 */ += 0.6;                          // [0x4618c..0x4619c]
            }
        }
        // 地面
        if (pp->gy /* +0x18 */ > floorY) {                      // [0x46644..0x46650] +0x1e8
            pp->fy /* +0x10 */ -= (pp->gy /* +0x18 */ - floorY);            // [0x46654..0x46660]
            pp->gy /* +0x18 */  = floorY;
            pp->gvy /* +0x20 */ = -0.55 * fabs(pp->gvy /* +0x20 */);             // [0x46664..0x4667c] 0xc00f0
            pp->sqv /* +0xb0 */ += 0.6;                              // [0x4667c..0x4668c]
        }
        // 左右墙（按 x 判定，撞击后水平速度反向、挤压）
        double xNow = pp->x /* +0x08 */;                             // [0x46690]
        if (xNow < [self minX]) {                        // [0x46698]
            pp->x /* +0x08 */ = [self minX];                         // [0x466a4..0x466b0]
            pp->vx /* +0x28 */ = 0.55 * fabs(pp->vx /* +0x28 */);                // [0x466b4..0x466c8]
            pp->sqv /* +0xb0 */ += 0.6;                              // [0x466cc..0x466dc]
        } else {
            xNow = pp->x /* +0x08 */;                                // [0x466e4]
            if (xNow > [self maxX]) {                    // [0x466e8..0x466f4]
                pp->x /* +0x08 */ = [self maxX];                     // [0x466f8]
                pp->vx /* +0x28 */ = -0.55 * fabs(pp->vx /* +0x28 */);           // [0x46704..0x46718]
                pp->sqv /* +0xb0 */ += 0.6;                          // [0x4671c..0x4672c]
            }
        }
        // 天花板（y - 250*scale < 0 且向上运动）
        double ceiling = pp->fy /* +0x10 */ + scale * -250.0;   // [0x46730..0x46740] 0xc00f8
        if (ceiling < 0.0 && pp->vy /* +0x30 */ < 0.0) {             // [0x46748..0x46754]
            pp->fy /* +0x10 */ = scale * 250.0;                 // [0x46758..0x46764] 0xbfc30
            pp->vy /* +0x30 */ = fabs(pp->vy /* +0x30 */) * 0.3;                 // [0x46768..0x46778] 0xbfcf8
        }
        squashBias = -fmin(fabs(pp->vy /* +0x30 */) / 6000.0, 0.12);   // [0x4677c..0x46798] 0xc0100/0xbfc90
        tiltBias = fmax(fmin(pp->sqv /* +0xb0 */ * 0.025, 30.0), -30.0);  // [0x4679c..0x467b8] 0xc0108
        cTilt = 8.0;                                     // [0x467c0] sp+0x88
        tDrowse = 0.0;                                   // [0x467c0] sp+0x90
        kTilt = 70.0;                                    // [0x467d0] 0xc0060
        if (pp->fy /* +0x10 */ >= pp->gy /* +0x18 */ && pp->vy /* +0x30 */ > 0.0) {           // [0x467d8..0x467e4]
            [self land];                                 // [0x467e8]
        }
        tSway = 0.0;                                     // [0x467f0]
        tSitK = 0.0;                                     // [0x467f4]
        goto label_zero_lean_keep_squash;                // -> 0x467fc -> 0x46800

    } else if ([mode isEqualToString:@"land"]) {         // [0x462fc] CF "land" 0xf3ba8
        // =================================================================
        // land：0.35s 内把 sitK 从 0.35 缓降到 0，0.4s 后回 idle
        // =================================================================
        double t = fmin(fmax(modeT / 0.35, 0.0), 1.0);   // [0x46310..0x46330] 0xbfdb8
        double smooth = t * t * (3.0 - 2.0 * t);         // [0x46334..0x46344]
        tSitK = 0.35 * (1.0 - smooth);                   // [0x46348..0x46350]
        tDrowse = 0.0;                                   // [0x46324] sp+0x90
        lookX = 2.0;                                     // [0x46380] d14
        lookY = 2.0;                                     // [0x46354] d15
        cTilt = 12.0;                                    // [0x46358]
        if (modeT > 0.4) {                               // [0x46360] 0xbfe28
            [self setModeTo:@"idle"];                    // [0x46370]
        }
        kTilt = 160.0;                                   // [0x46384]
        tiltBias = 0.0;                                  // [0x4638c]
        tSway = 0.0;                                     // [0x469e4]
        goto label_zero_lean_bob;                        // -> 0x442e8

    } else if ([mode isEqualToString:@"dizzy"]) {        // [0x46398] CF "dizzy" 0xf97c8
        // =================================================================
        // dizzy：2.4s 前摇头晃脑，2.4~3.0 收尾，3.0 后回 idle
        // =================================================================
        double t = modeT;                                // [0x463a8] d13
        tSitK = (t < 2.6) ? 1.0 : 0.0;                   // [0x463b0..0x463c8] 0xc0068
        if (t < 2.4 && time > pp->voiceCool /* +0x1c0 */) {            // [0x463cc..0x463dc] 0xc0020
            [self sound:@"chirps" kind:@"move" arguments:@YES];  // 0xf3c48/0xf97a8
            pp->voiceCool /* +0x1c0 */ = time + 0.9;                   // [0x4640c] 0xbfda8
        }
        if (t >= 2.4 && pp->nextNoteAt /* +0x1c8 */ == 0.0) {          // [0x46420..0x46430] +0x1c8
            [self sound:@"shake" kind:@"move" arguments:@YES];   // 0xf3c68
            pp->nextNoteAt /* +0x1c8 */ = DBL_MAX;                     // [0x46454..0x46458]
        }
        if (t < 2.4) {
            tiltBias = 8.0 * sin(time * 4.5) * fmin(2.0 * t, 1.0);   // [0x46464..0x46488]
            cTilt = 12.0;                                 // [0x4648c]
            tDrowse = 0.0;                                // [0x46858]
            kTilt = 160.0;                                // [0x4685c]
            tSway = 0.0;                                   // [0x469e4]
            goto label_zero_lean_bob;                     // -> 0x442e8
        }
        if (t < 3.0) {
            double ramp = (t - 2.4) / -0.6;              // [0x46814..0x46828] 0xc00c8/0xc00d0
            tiltBias = 12.0 * sin(t * 34.0) * (1.0 + ramp);   // [0x4682c..0x46854]
            cTilt = 12.0;                                 // [0x4683c]
            tDrowse = 0.0;                                // [0x46858]
            kTilt = 160.0;                                // [0x4685c]
            tSway = 0.0;                                   // [0x469e4]
            goto label_zero_lean_bob;                     // -> 0x442e8
        }
        [self setModeTo:@"idle"];                         // [0x46990]
        pp->sqv /* +0xb0 */ -= 1.0;                                   // [0x469a0..0x469ac]
        pp->nextAt /* +0x130 */ = time + [self rnd:1.5 to:3.0];        // [0x469b0..0x469c8]
        cTilt = 12.0;                                     // [0x469d0]
        tDrowse = 0.0;                                    // [0x469d0]
        kTilt = 160.0;                                    // [0x469d8]
        tiltBias = 0.0;                                   // [0x469e0]
        tSway = 0.0;                                      // [0x469e4]
        goto label_zero_lean_bob;                         // -> 0x442e8

    } else if ([mode isEqualToString:@"dance"]) {         // [0x46498] CF "dance" 0xf3d88
        // =================================================================
        // dance：相位以 6.91 rad/s 推进，每跨 π 一次落脚；顺手扔音符粒子
        // =================================================================
        double cycPrev = floor(pp->phase /* +0x88 */ / M_PI);        // [0x464ac..0x464b8] +0x88
        pp->phase /* +0x88 */ += 6.9115038378975457 * dt;            // [0x464bc..0x464c8] 0xc00b8
        if (floor(pp->phase /* +0x88 */ / M_PI) != cycPrev) {         // [0x464cc..0x464d8]
            int foot = ((int)floor(pp->phase /* +0x88 */ / M_PI)) & 1;   // [0x464e8..0x464f0]
            [self sound:@"step" kind:@"move"
            arguments:@[ @NO, @(foot) ]];                // [0x464dc..0x46538] kCFBooleanFalse
        }
        double s = sin(pp->phase /* +0x88 */);                        // [0x46544..0x4654c] d10
        if (time > pp->nextNoteAt /* +0x1c8 */) {                      // [0x46554..0x4655c] +0x1c8
            CGPoint p0 = [self toStage:CGPointMake(196.0, pp->low /* +0xc8 */ + 44.0)];  // 0xc00c0/0x46568
            double vx = pp->facing /* +0x38 */ * [self rnd:10.0 to:30.0];    // [0x4658c..0x465a0]
            [self emit:@"note" point:p0
                     vx:vx
                     vy:-34.0                                 // x8 = -0x3fbf000000000000
                   life:1.8];                                 // [0x465b8] 0xbfea0
            pp->nextNoteAt /* +0x1c8 */ = time + 0.6;                  // [0x465d0..0x465d8] 0xbfff0
        }
        tiltBias = 7.0 * s;                               // [0x465e4] d11
        tBob = 5.0;                                       // [0x465f4] sp+0x20
        tLift = 10.0;                                     // [0x465f4] sp+0x28
        lookY = -2.0;                                     // [0x465f8] d15
        cTilt = 12.0;                                     // [0x465fc] sp+0x88
        tDrowse = 0.0;                                    // [0x465fc] sp+0x90
        if (modeT > pp->dwell /* +0x50 */) {                          // [0x46608] +0x50
            [self setModeTo:@"idle"];                     // [0x46610]
            pp->nextAt /* +0x130 */ = time + [self rnd:1.5 to:3.0];    // [0x46620..0x46638]
        }
        lookX = 3.0;                                      // [0x46620] / [0x46970] d14
        kTilt = 160.0;                                    // [0x46974]
        tSway = 3.0;                                      // [0x4697c]
        tLean = 0.0;                                      // [0x46984]
        tSitK = 0.0;                                      // [0x46984]
        goto label_pose_begin;                            // -> 0x446f4

    } else if ([mode isEqualToString:@"play_ball"]) {     // [0x4686c] CF "play_ball" 0xf6588
        // =================================================================
        // play_ball：两段三次 smoothstep 组成的视线轨迹；6.5s 后回 idle 并上报 done
        // =================================================================
        double u = fmin(fmax((modeT - 5.1) / 0.6, 0.0), 1.0);        // 0xc0098/0xc00a0
        double pu = u * u * u * (u * (6.0 * u - 15.0) + 10.0);       // [0x468a8..0x468c4]
        double q = 1.0 - pu;                                          // [0x468c8]
        double v = fmin(fmax((modeT - 2.7) / 0.9, 0.0), 1.0);        // 0xc00a8/0xc00b0
        double pv = v * v * v * (v * (6.0 * v - 15.0) + 10.0);       // [0x468f4..0x46904]
        tDrowse = 0.0;                                                // [0x468e8]
        lookX = (-2.0 * pv - 3.0) * q;                                // [0x46908..0x46914]
        lookY = 3.0 * q;                                              // [0x46918]
        cTilt = 12.0;                                                 // [0x46920]
        if (modeT >= 6.5) {                                           // [0x46928]
            [self setModeTo:@"idle"];                                 // [0x46934]
            pp->nextAt /* +0x130 */ = time + 2.0;                                  // [0x46944..0x46950]
            [self event:@"done" detail:@{}];                          // [0x46954..0x46968]
        }
        // 两段分支都落到 0x44248/0x46974：目标全零
        tiltBias = 0.0;                                               // 0x44248
        kTilt = 160.0;
        tSway = 0.0;
        tSitK = 0.0;
        tLean = 0.0;
        goto label_zero_targets;                        // -> 0x44248 -> 0x44254

    } else if ([mode isEqualToString:@"drag"]) {         // [0x469ec] CF "drag" 0xf3848
        // =================================================================
        // drag：被拎起时身体跟随指针（有阻尼），并产生倾斜与吱声
        // =================================================================
        tDrowse = 0.0;                                    // [0x46a00] sp+0x90
        if (!responsiveInteraction) {                     // [0x46a0c]
            cTilt = 12.0;                                 // [0x46a30]
            kTilt = 160.0;                                // [0x462f0]
            tiltBias = 0.0;                               // [0x462f4]
            goto label_zero_targets;                      // -> 0x44250 -> 0x44254
        }
        [self syncDragPointer];                           // [0x46a18]
        {
            double soft = 1.0 - exp(-28.0 * dt);          // [0x46a48..0x46a58]
            double tx = pp->dragX /* +0x148 */ + (pointerX - pp->dragX /* +0x148 */) * soft;   // +0x148/+0x210
            double tyTarget = fmin(pointerY,                      // +0x218
                                   floorY + scale * -245.0);  // 0xc0090
            double ty = pp->dragY /* +0x150 */ + (tyTarget - pp->dragY /* +0x150 */) * soft;     // +0x150
            pp->dragX /* +0x148 */ = tx;
            pp->dragY /* +0x150 */ = ty;
        }
        cTilt = 5.0;                                      // [0x46a8c] sp+0x88
        kTilt = 90.0;                                     // [0x46a94..0x46a9c] 0xbffb0
        tiltBias = fmax(fmin(pointerVX * 0.035, 40.0), -40.0);   // 0xbfda0
        if (fabs(pointerVX) > 500.0 &&               // [0x46acc..0x46ad8] 0xbfe30
            time > pp->voiceCool /* +0x1c0 */) {                       // [0x46ae0..0x46af0]
            [self sound:@"squeak" kind:@"touch" arguments:@YES];   // 0xf3c08/0xf9d28
            pp->voiceCool /* +0x1c0 */ = time + [self rnd:0.4 to:0.7]; // [0x46b18..0x46b38]
        }
        tSway = 0.0;                                      // [0x46b44]
        tSitK = 0.0;                                      // [0x46b48]
        tLean = 0.0;                                      // [0x46b48]
        tBob = 0.0;                                       // [0x46b4c]
        tLift = 0.0;
        goto label_pose_spine;                            // -> 0x446f8（保留 squash）

    } else {
        // 未命中任何模式：等效 idle 的静态零目标（0x46a30 → 0x462f0 → 0x44250）
        cTilt = 12.0;
        kTilt = 160.0;
        tiltBias = 0.0;
        goto label_zero_targets;
    }

    // =====================================================================
    // 汇合点：二进制里各模式分支用 b 跳回 0x44248/0x4424c/0x44250/0x44254/
    // 0x442e0/0x442e4/0x442e8/0x442ec/0x446f4/0x446f8/0x467fc/0x46800。
    // 这里用标签复刻同样的落点语义。
    // =====================================================================
label_zero_targets:;                                     // 0x44254 → 0x442e0
    tSway = 0.0;                                         // 0x442e0
    tSitK = 0.0;                                         // 0x442e4
    /* fallthrough */
label_zero_lean_bob:;                                    // 0x442e8 / 0x442ec
    tLean = 0.0;                                         // 0x442e8
    tBob = 0.0;                                          // 0x442ec
    tLift = 0.0;
    goto label_pose_begin;

label_zero_lean_keep_squash:;                            // 0x467fc
    tLean = 0.0;
    /* fallthrough */
label_zero_bob_lift_keep_squash:;                        // 0x46800
    tBob = 0.0;
    tLift = 0.0;
    goto label_pose_spine;

label_pose_begin:;                                       // 0x446f4
    squashBias = 0.0;                                    // fmov d13, xzr
label_pose_spine:;                                       // 0x446f8
    {
        // =================================================================
        // [0x446f8] pulse 叠加：flap 累加 tilt/squash，spin 处理翻面
        // =================================================================
        NSDictionary *pulse = self.pulse /* +0x280 */;                // +0x280
        if (pulse != nil) {
            double u = (time - [pulse[@"t0"] doubleValue]) /
                       [pulse[@"dur"] doubleValue];      // [0x44710..0x44768] 0xf97e8/0xf3f68
            NSString *kind = pulse[@"kind"];             // [0x44778..0x447a0] 0xf2f08
            if (u >= 1.0) {                               // [0x447a4..0x447ac]
                [self setPulse:nil];                     // [0x44818]
            } else if ([kind isEqualToString:@"shiver"]) {    // 0xf3d68
                // 抖动只由 public 段消费，这里不改任何累加量
            } else if ([kind isEqualToString:@"flap"]) {      // 0xf99e8
                double s = sin(u * M_PI * 8.0);           // [0x447d8..0x447e8]
                tiltBias   += (s * 7.0) * (1.0 - u);      // [0x447ec..0x447fc] d11
                squashBias += (fabs(s) * -0.06) * (1.0 - u);  // [0x44800..0x44810] 0xc0148
            } else if ([kind isEqualToString:@"spin"]) {       // 0xf3dc8 @ 0x45b30
                NSMutableDictionary *mut = [pulse mutableCopy];   // [0x45b44..0x45b5c]
                BOOL flipped;
                if (u > 0.5) {                            // [0x45b60..0x45b68]
                    flipped = [mut[@"flipped"] boolValue];    // 0xf9d48
                    if (!flipped) {
                        mut[@"flipped"] = @YES;            // [0x45f10..0x45f24]
                        pp->facing /* +0x38 */ = -pp->facing /* +0x38 */;          // [0x45f28..0x45f30]
                    }
                } else {
                    if (![mut[@"first"] boolValue]) {     // [0x45b9c..0x45bcc] 0xf9d68
                        mut[@"first"] = @YES;              // [0x45bc4..0x45bd8]
                        pp->facing /* +0x38 */ = -pp->facing /* +0x38 */;          // [0x45bdc..0x45be4]
                        pp->sqv /* +0xb0 */ -= 1.0;                    // [0x45be8..0x45bf4]
                    }
                }
                [self setPulse:mut];                       // [0x45f34..0x45f3c]
            }
        }

        // =================================================================
        // [0x44828] 取当前表情帧；thinking 时打上 think 标记
        // =================================================================
        NSString *faceName = self.currentFaceName;         // +0x260
        NSDictionary *frame = [self faceAt:faceName];      // [0x44838..0x44844]
        if (self.thinking /* +0x24a */ && self.thoughtShown /* +0x24b */ &&          // +0x24a / +0x24b
            [faceName isEqualToString:@"thinking"]) {      // 0xf4cc8
            NSMutableDictionary *mf = [frame mutableCopy]; // [0x4487c..0x44880]
            mf[@"think"] = @YES;                           // [0x44888..0x44898] 0xf9d88
            frame = mf;                                    // [0x4489c..0x448ac]
        }

        // ---- 注视目标锁定（lookLock / sleep / drag / lookAt）----
        double eyeLookX = 0.0;                             // d9
        double eyeLookY = 0.0;                             // d10
        if (![frame[@"lookLock"] boolValue]) {             // [0x448b0..0x448c8] 0xf9da8
            if (![self is:@"sleep"] && ![self is:@"drag"]) {     // [0x448d4..0x45a54]
                eyeLookX = lookX;                          // [0x45a78] d9 = d14
                eyeLookY = lookY;                          // [0x45a74] d10 = d15
                id lookAt = frame[@"lookAt"];               // [0x45a58..0x45a70] 0xf9dc8
                if (lookAt != nil) {
                    eyeLookX = [lookAt[0] doubleValue];    // [0x45a80..0x45ab0]
                    eyeLookY = [lookAt[1] doubleValue];    // [0x45abc..0x45ae4]
                }
            }
        }

        // =================================================================
        // [0x448f0] 眼睛求解：eyeSig 变化时按 eyeDims 做指数收敛
        // =================================================================
        NSArray *eyes = frame[@"eyes"];                    // +0x28, 0xf9aa8
        NSArray *shapePair = @[ eyes[0][@"shape"], eyes[1][@"shape"] ];  // 0xf9ac8
        NSString *sig = [NSString stringWithFormat:@"%@,%@",
                         shapePair[0], shapePair[1]];      // [0x44914..0x44970] 0xf9de8
        if (![sig isEqualToString:self.eyeSig /* +0x2c0 */]) {          // [0x449a0] +0x2c0
            if (self.eyeCur /* +0x2a8 */ != nil) {                      // [0x449c0..0x449d4] +0x2a8
                self.eyePrev /* +0x2b0 */ = self.eyeCur /* +0x2a8 */;                // [0x449d8..0x449f0] +0x2b0
                pp->eyeT /* +0x170 */ = 0.0;                            // [0x449f8] +0x170
            }
            self.eyeSig /* +0x2c0 */ = sig;                             // [0x449fc..0x44a04]
            // eyeDims[i] = @[rx, ry, dx, dy]，缺省 16/16/0/0
            for (int i = 0; i < 2; i++) {                  // [0x44a08..0x44b3c]
                id e = eyes[i];
                self.eyeDims /* +0x2b8 */[i] = @[ @(WNGetDouble(e, @"rx", 16.0)),   // 0xf9e08
                                     @(WNGetDouble(e, @"ry", 16.0)),   // 0xf9b48
                                     @(WNGetDouble(e, @"dx", 0.0)),    // 0xf9e28
                                     @(WNGetDouble(e, @"dy", 0.0)) ];  // 0xf9e48
            }
        }

        // [0x44b40] 交接：lookX/lookY → 眼睛段；tiltBias → tilt 弹簧目标
        double eyeTargetX = eyeLookX;                      // d10
        double eyeTargetY = eyeLookY;                      // sp+0x60
        double tiltTarget  = tiltBias;                     // d9
        pp->eyeT /* +0x170 */ += dt;                                    // [0x44b4c] +0x170

        double eyeSoft = 1.0 - exp(-16.0 * dt);            // [0x44b68..0x44b7c] d14
        NSMutableArray *newEyeCur = [NSMutableArray new];  // [0x44b58..0x44b64]
        for (int i = 0; i < 2; i++) {                      // [0x44ba8..0x44d48]
            NSMutableDictionary *eye = [eyes[i] mutableCopy];
            if ([WNRingShapes() containsObject:eye[@"shape"]]) {   // [0x44be8] 0x107630
                NSMutableArray *dims = [self.eyeDims /* +0x2b8 */[i] mutableCopy];   // +0x2b8
                for (int j = 0; j < 4; j++) {              // [0x44c30..0x44cf8]
                    NSString *key = WNEyeKeys()[j];        // [0x44c50..0x44c5c] 0x107648
                    double cur = [dims[j] doubleValue];
                    double dflt = (j < 2) ? 16.0 : 0.0;    // [0x44c64..0x44c68]
                    double tgt = WNGetDouble(eye, key, dflt);   // [0x44c74]
                    cur += (tgt - cur) * eyeSoft;          // [0x44c78..0x44c7c]
                    dims[j] = @(cur);                      // [0x44c88..0x44ca8]
                    eye[key] = @(cur);                     // [0x44cb0..0x44ce4]
                }
                self.eyeDims /* +0x2b8 */[i] = dims;                    // [0x44cfc..0x44d14]
            }
            [newEyeCur addObject:eye];                     // [0x44d30..0x44d38]
        }
        self.eyeCur /* +0x2a8 */ = newEyeCur;                           // [0x44d4c..0x44d58]

        // =================================================================
        // [0x44d5c]  blush / 挤压弹簧 / tilt 弹簧 / lean / sitK / drowse /
        //            stretch / bob / lift / sway / look / gap / faceVis
        // =================================================================
        double blushT = WNGetDouble(frame, @"blush", 0.0); // [0x44d60..0x44d78] 0xf9e88
        double soft6  = 1.0 - exp(-6.0 * dt);              // [0x44d7c..0x44dac] d13
        pp->blushK /* +0x168 */ += (blushT - pp->blushK /* +0x168 */) * soft6;       // [0x44db0..0x44db8] +0x168

        // sq 弹簧：目标 = squashBias，k = 280，c = 14，夹在 [-0.35, 0.45]
        double sqAcc = (squashBias - pp->sq /* +0xa8 */) * 280.0        // [0x44d8c..0x44da4] 0xc0150
                       - 14.0 * pp->sqv /* +0xb0 */;
        pp->sqv /* +0xb0 */ += sqAcc * dt;                             // [0x44dbc]
        pp->sq /* +0xa8 */  += pp->sqv /* +0xb0 */ * dt;                           // [0x44dc0]
        pp->sq /* +0xa8 */ = fmax(fmin(pp->sq /* +0xa8 */, 0.45), -0.35);          // [0x44dd0..0x44ddc] 0xbfc08/0xc0158

        // tilt 弹簧：目标 = tiltTarget，k/c 由模式给定
        {
            double acc = (tiltTarget - pp->tilt /* +0x98 */) * kTilt    // [0x44de8..0x44df4]
                         - pp->tiltV /* +0xa0 */ * cTilt;
            pp->tiltV /* +0xa0 */ += acc * dt;                         // [0x44df8]
            pp->tilt /* +0x98 */  += pp->tiltV /* +0xa0 */ * dt;                   // [0x44dfc]
        }

        // lean：1 - exp(-7·dt)
        pp->lean /* +0x90 */ += (tLean - pp->lean /* +0x90 */) * (1.0 - exp(-7.0 * dt));      // [0x44e04..0x44e20]

        // sitK：land 用 18，其它 6
        {
            double k = [mode isEqualToString:@"land"] ? 18.0 : 6.0;    // [0x44e28..0x44e48]
            pp->sitK /* +0xb8 */ += (tSitK - pp->sitK /* +0xb8 */) * (1.0 - exp(-k * dt));      // [0x44e50..0x44e64]
        }
        // drowse：sleep 1.5，sit 4，其它 6
        {
            double k;
            if ([mode isEqualToString:@"sleep"]) {                     // [0x44e6c..0x44e80]
                k = 1.5;
            } else if ([mode isEqualToString:@"sit"]) {                // [0x44e84..0x44e9c]
                k = 4.0;
            } else {
                k = 6.0;
            }
            pp->drowse /* +0xd0 */ += (tDrowse - pp->drowse /* +0xd0 */) * (1.0 - exp(-k * dt));  // [0x44ea0..0x44eb8]
        }
        // stretch：drag = 1，其它 0
        {
            double soft8 = 1.0 - exp(-8.0 * dt);                       // [0x44ed4..0x44ee0]
            double tgt = [mode isEqualToString:@"drag"] ? 1.0 : 0.0;    // [0x44ec0..0x44ed0]
            pp->stretch /* +0xc0 */ += (tgt - pp->stretch /* +0xc0 */) * soft8;                 // [0x44ee4..0x44eec]
        }
        // bob / lift / sway：1 - exp(-10·dt)
        {
            double soft10 = 1.0 - exp(-10.0 * dt);                     // [0x44ef4..0x44f00]
            pp->bob /* +0x70 */  += (tBob  - pp->bob /* +0x70 */)  * soft10;                   // [0x44f04..0x44f1c]
            pp->lift /* +0x78 */ += (tLift - pp->lift /* +0x78 */) * soft10;
            pp->sway /* +0x80 */ += (tSway - pp->sway /* +0x80 */) * soft10;                   // [0x44f20..0x44f2c]
        }
        // look：1 - exp(-9·dt)
        {
            double soft9 = 1.0 - exp(-9.0 * dt);                       // [0x44f34..0x44f40]
            pp->lookX /* +0xe8 */ += (eyeTargetX - pp->lookX /* +0xe8 */) * soft9;             // [0x44f44..0x44f5c]
            pp->lookY /* +0xf0 */ += (eyeTargetY - pp->lookY /* +0xf0 */) * soft9;
        }
        // gap：1 - exp(-8·dt)，来源 frame[@"gap"]（0xf9a88）
        {
            double soft8 = 1.0 - exp(-8.0 * dt);                       // [0x44ee0] 复用
            NSArray *gap = frame[@"gap"];
            pp->gapX /* +0xd8 */ += ([gap[0] doubleValue] - pp->gapX /* +0xd8 */) * soft8;      // [0x44f6c..0x44f9c]
            pp->gapY /* +0xe0 */ += ([gap[1] doubleValue] - pp->gapY /* +0xe0 */) * soft8;      // [0x44fac..0x44fdc]
        }
        // faceVis：1 - exp(-15·dt) 追 facing
        pp->faceVis /* +0x40 */ += (pp->facing /* +0x38 */ - pp->faceVis /* +0x40 */) * (1.0 - exp(-15.0 * dt));   // [0x44fe8..0x45004]

        // =================================================================
        // [0x45008] 非步态模式：相位向最近的 π 倍数吸附
        // =================================================================
        if (![WNGaitModes() containsObject:mode]) {        // [0x45008..0x4501c] 0x107660
            double cyc = floor(pp->phase /* +0x88 */ / M_PI + 0.5);    // [0x45020..0x45034]
            pp->phase /* +0x88 */ += (cyc * M_PI - pp->phase /* +0x88 */) * soft6; // [0x45038..0x45044]
        }

        // =================================================================
        // [0x45048] 指针速度 / velX（拖拽与普通分开取）
        // =================================================================
        {
            double kd = self.responsiveInteraction /* +0x249 */ ? 22.0 : 6.0;       // [0x45048..0x4505c]
            pointerVX *= exp(-kd * dt);                            // [0x45060..0x45070] +0x220
            BOOL isDragMode = [self is:@"drag"];                        // [0x45074..0x45080]
            double xForVel = isDragMode ? pp->dragX /* +0x148 */ : pp->x /* +0x08 */;             // [0x45088..0x45094]
            if (pp->hasPrev /* +0x1d0 */) {                                          // [0x45098..0x450a4]
                double inst = (xForVel - pp->prevX /* +0x1a8 */) / dt;               // [0x450a8..0x450b0]
                pp->velX /* +0x1b0 */ += (inst - pp->velX /* +0x1b0 */) * 0.25;                   // [0x450b4..0x450c0]
            }
            if (!isfinite(pp->velX /* +0x1b0 */)) {                                  // [0x450c4..0x450d8]
                pp->velX /* +0x1b0 */ = 0.0;                                         // [0x450dc]
            }
            pp->prevX /* +0x1a8 */ = xForVel;                                        // [0x450e0] +0x1a8
            pp->hasPrev /* +0x1d0 */ = 1;                                            // [0x450e4] +0x1d0
            // 响应式交互且拖拽时改用 pointerVX
            usePointerVX = self.responsiveInteraction /* +0x249 */ && isDragMode;     // [0x450ec..0x45114]
            swingVel = usePointerVX ? pointerVX : pp->velX /* +0x1b0 */;        // [0x45120] d9
        }

        // =================================================================
        // [0x45124] swing 弹簧（身体前后摆）
        // =================================================================
        {
            double base = [mode isEqualToString:@"dance"] ? pp->lean /* +0x90 */ * 0.22 : 0.0;  // 0xbfdf8
            double plus  = base + swingVel * 0.06;                      // [0x45154] 0xbfca0
            double minus = base - swingVel * 0.06;                      // [0x45158]
            double tgt = (pp->tilt /* +0x98 */ >= 0.0) ? minus : plus;              // [0x4515c..0x45164]
            tgt = fmax(fmin(tgt, 28.0), -28.0);                         // [0x45168..0x45174]
            double k = usePointerVX ? 0.35 : 110.0;                     // [0x45180] 0xbfdc8/0xc0160
            double c = usePointerVX ? 26.0 : 7.0;                       // [0x45198] 0xc0168?（0xbf... 见注）
            double acc = (tgt - pp->swing /* +0x198 */) * k - pp->swingV /* +0x1a0 */ * c;        // [0x451a4..0x451a8]
            pp->swingV /* +0x1a0 */ += acc * dt;                                     // [0x451ac]
            pp->swing /* +0x198 */  += pp->swingV /* +0x1a0 */ * dt;                              // [0x451b0]
            pp->swing /* +0x198 */ = fmax(fmin(pp->swing /* +0x198 */, 40.0), -40.0);             // [0x451b4..0x451c8]
        }

        // [0x451d0] low = 29·sitK + sway·|sin(phase)|
        pp->low /* +0xc8 */ = 29.0 * pp->sitK /* +0xb8 */ + pp->sway /* +0x80 */ * fabs(sin(pp->phase /* +0x88 */));    // +0xc8

        // =================================================================
        // [0x451f4] 两只脚的落点
        // =================================================================
        {
            BOOL isAirMode = [WNAirModes() containsObject:mode];        // 0x107678 @ 0x45338
            BOOL inAirSet  = isAirMode;                                 // drag 或 air
            double kFeet = inAirSet ? 14.0 : 104.0;                     // [0x4534c..0x45360]
            double softFeet = 1.0 - exp(-kFeet * dt);                   // [0x45360..0x4536c]
            for (int i = 0; i < 2; i++) {
                double baseX = (i == 0) ? 104.0 : 150.0;                // [0x45204..0x45274]
                double fx, fy;
                if ([mode isEqualToString:@"drag"]) {                   // [0x45288..0x45294]
                    fx = baseX + sin(time * 11.0 + i * 2.2) * 7.0;      // [0x45298..0x452b8]
                    fy = pp->sway /* +0x80 */ + 212.0 + 37.0;                       // [0x45280..0x452c4]
                } else if ([mode isEqualToString:@"air"]) {             // [0x452c8..0x452d4]
                    fx = (i == 0) ? 95.0 : 159.0;                       // [0x452d8..0x452e0] 0xbfd10/0xc0180
                    fy = pp->sway /* +0x80 */ + 212.0 + 33.0;                       // [0x452e4..0x452e8] 0xbff68
                } else {
                    double ph = pp->phase /* +0x88 */ + i * M_PI;                   // [0x452f0..0x45304]
                    double s = sin(ph), c = cos(ph);
                    double x0 = baseX + pp->bob /* +0x70 */ * s;                    // [0x45308]
                    fx = x0 + (baseX + 26.0 - x0) * pp->sitK /* +0xb8 */;           // [0x4530c..0x4531c]
                    double L = pp->lift /* +0x78 */ * fmax(c, 0.0);                 // [0x45320..0x45328]
                    fy = (241.0 - L) + L * pp->sitK /* +0xb8 */;                    // [0x4532c..0x45334]
                }
                pp->feet /* +0xf8 */[2 * i]     += (fx - pp->feet /* +0xf8 */[2 * i]) * softFeet;      // [0x45370..0x45384]
                pp->feet /* +0xf8 */[2 * i + 1] += (fy - pp->feet /* +0xf8 */[2 * i + 1]) * softFeet;
            }
        }

        // =================================================================
        // [0x45390] frame[@"emit"]：一次性粒子（heart / z / tear / tears）
        // =================================================================
        {
            NSString *emit = frame[@"emit"];                 // 0xf9ea8
            if (emit != nil && time > pp->fxCool /* +0x138 */) {          // [0x453a8..0x453b8] +0x138
                if ([emit isEqualToString:@"heart"]) {       // [0x453c0] 0xf9ae8
                    [self emitHeart];                        // [0x453d4]
                    pp->fxCool /* +0x138 */ = time + 0.45;                // [0x453e0] sp+0x18 = 0.45
                } else if ([emit isEqualToString:@"z"]) {    // [0x453e8] 0xf9ec8
                    CGPoint pz = [self toStage:CGPointMake(196.0, pp->low /* +0xc8 */ + 44.0)];
                    [self emit:@"z" point:pz
                             vx:pp->facing /* +0x38 */ * 16.0            // [0x45420]
                             vy:-26.0                        // [0x45438]
                           life:2.4];                        // [0x45434] 0xc0020
                    pp->fxCool /* +0x138 */ = time + 1.3;                 // [0x45444..0x45450] 0xbff88
                } else if ([emit isEqualToString:@"tear"]) { // [0x4545c] 0xf9ee8
                    CGPoint pt = [self toStage:CGPointMake(126.1 + pp->lookX /* +0xe8 */,
                                                           139.91 + pp->low /* +0xc8 */)];
                    [self emit:@"drop" point:pt                // [0x454b4] 0xf87e8
                             vx:pp->facing /* +0x38 */ * [self rnd:10.0 to:30.0]
                             vy:-20.0                          // [0x454bc]
                           life:3.0];                          // [0x454c0]
                    pp->fxCool /* +0x138 */ = time + 0.8;                   // [0x454d4..0x454dc] 0xbfe60
                } else if ([emit isEqualToString:@"tears"]) { // [0x454e8] 0xf9f08
                    int n = self.tearNumber /* +0x24c */;                   // +0x24c
                    self.tearNumber /* +0x24c */ = n + 1;                   // [0x45508..0x45510]
                    int idx = ((n & 1) == 0) ? 1 : 0;          // [0x45514..0x45518] cset eq
                    double xb = (idx == 0) ? 166.38 : 128.76;  // [0x4551c..0x45524] 0xc0210
                    double yb = (idx == 0) ? 139.53 : 139.91;  // [0x45578..0x45580] 0xc0220
                    CGPoint pt = [self toStage:CGPointMake(
                                        xb + pp->lookX /* +0xe8 */ + [self rnd:-6.0 to:6.0],
                                        yb + pp->low /* +0xc8 */)];    // [0x45528..0x45594]
                    [self emit:@"drop" point:pt
                             vx:pp->facing /* +0x38 */ * [self rnd:-20.0 to:50.0]   // [0x45544..0x4555c]
                             vy:[self rnd:-60.0 to:-20.0]               // [0x45554..0x45570]
                           life:3.0];                        // [0x455a0]
                    pp->fxCool /* +0x138 */ = time + 0.22;                  // [0x455b4..0x455c0] 0xbfdf8
                }
            }
        }

        // =================================================================
        // [0x455c8] 计时衰减 + 粒子推进
        // =================================================================
        strokeAcc *= exp(-1.5 * dt);                   // [0x455cc] +0x200
        petCool   -= dt;                               // [0x455e4] +0x208

        {
            NSArray *snapshot = [[self particles] copy];   // [0x455fc..0x455610] +0x290
            double vyDamp = exp(-4.0 * dt);                // [0x455f0..0x45650] 0xbf... 
            for (id obj in snapshot) {                     // countByEnumeratingWithState
                NSMutableDictionary *item = (NSMutableDictionary *)obj;
                double age  = [item[@"age"] doubleValue] + dt;      // [0x456b0..0x456c4] 0xf9cc8
                double ix   = [item[@"x"] doubleValue];             // 0xf89a8
                double ivx  = [item[@"vx"] doubleValue];            // 0xf9c88
                double nx   = ix + ivx * dt;                        // [0x456fc..0x45704]
                double iy   = [item[@"y"] doubleValue];             // 0xf89c8
                double ivy  = [item[@"vy"] doubleValue];            // 0xf9ca8
                double ny   = iy + ivy * dt;                        // [0x4573c..0x45744]
                item[@"age"] = @(age);                              // [0x45750..0x45774]
                item[@"x"]   = @(nx);                               // [0x4577c..0x4579c]
                item[@"y"]   = @(ny);                               // [0x457a4..0x457c4]
                double life = 0.0;
                if ([item[@"type"] isEqualToString:@"drop"]) {       // 0xf2de8 @ 0x457cc
                    item[@"vy"] = @([item[@"vy"] doubleValue] + dt * 900.0);   // 0xbfd98
                    double floorOrGy = freeGround ? pp->gy /* +0x18 */ : floorY; // 0x45844..0x45858
                    if (ny > floorOrGy) {                            // [0x4585c]
                        life = [item[@"life"] doubleValue];          // [0x45864..0x45884]
                    }
                }
                if ([item[@"type"] isEqualToString:@"dust"]) {       // [0xf9d08 @ 0x45888
                    item[@"vx"] = @([item[@"vx"] doubleValue] * vyDamp);  // [0x458b4..0x458fc]
                }
                double lifeNow = [item[@"life"] doubleValue];        // [0x45908..0x45928] 0xf9ce8
                if (!(life < lifeNow)) {                             // [0x4592c..0x45934] b.lt 保留
                    [[self particles] removeObject:item];            // [0x45934..0x4594c]
                }
            }
        }

        // =================================================================
        // [0x4597c] 收尾：talkK 衰减，回写 face / faceName
        // =================================================================
        pp->talkK /* +0x1b8 */ *= exp(-12.0 * dt);                      // [0x45984..0x4599c] +0x1b8
        self.face /* +0x268 */ = frame;                                 // [0x459a0..0x459ac] +0x268
        self.faceName /* +0x260 */ = faceName;                          // [0x459b0..0x459bc] +0x260
    }

    // [0x459f0] 栈保护校验 -> [0x45a08] 收尾
    return;
}
