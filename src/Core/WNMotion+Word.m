//
//  WNMotion+Word.m
//  PetDFY
//
//  -[WNMotion doWord:] 指令词入口 + walk 指令面（方法体完整还原，非片段）
//
//  二进制证据
//    image base          : 0（arm64 切片 extract/bin/PetDFY.arm64.dylib）
//    doWord:             : 0x42294（序言 stp d11,d10,[sp,#-0x50]!）→ 0x428fc；411 条指令
//    真实方法尾          : 0x424e0 ret（0x424e4 起为本方法内的冷分支区，非独立函数）
//    栈帧                : 0x42294 帧长 0x50；无栈保护
//    walkTo:run:id:      : 0x41f38 → 0x421cc（166 条）；帧长 0xd0；栈保护 GOT 0xf0680 = ___stack_chk_guard
//    stopWalk:           : 0x421d0 → 0x42290（49 条）；帧长 0x40；无栈保护
//    walkWord 等访问器   : 0x49380..0x493cc（各 2 条，setter 为尾调用 _objc_setProperty_nonatomic_copy）
//
//  容器（词库）
//    本文件引用 5 个 __DATA_CONST 常量对象，全部逐项解出，明细见 out/notes/word-containers.md。
//      @0x1075b8  __objc_arrayobj  count=16  → 手势/动作词表（第 1 道闸门）
//      @0x1075d0  __objc_arrayobj  count=5   → 模式词表（直接 setModeTo: + dur）
//      @0x1075e8  __objc_arrayobj  count=2   → 短脉冲词表
//      @0x1075a0  __objc_arrayobj  count=2   → walk 模式表（stopWalk: 复位用）
//      @0x1084a8  __objc_dictobj   count=5   → 词 → 音效名
//    注意：0x107000 处另有一个 count=0xA 的常量数组（元素 pet.user/pet.vocab/…），
//    本文件 **不引用**；0x424e4/0x42728/0x427f8 的 adrp/add 落点是 +0x5b8/+0x5d0/+0x5e8，
//    即 0x1075b8/0x1075d0/0x1075e8（见 word-containers.md §7）。
//    交叉验证：全 __text（161053 条指令）内 adrp+add 配对解出 3809 个目标，
//    其中 0x107000 出现 0 次；本文件这 5 个容器各只被引用 1 次（引用点见下）。
//
//  字段偏移来源
//    - 实例变量：WNMotion.h（取自 __objc_ivar）。本文件用到 time +0x1d8、width +0x1f0、
//      floorY +0x1e8、freeGround +0x242、faces +0x2f0、mode +0x250、
//      _walkWord +0x2f8、_walkIdentifier +0x300、_lastAction +0x310。
//    - p（匿名结构，self+0x08 起）：字段名以 WNTypes.h §WNMotionState 为准（权威）。
//      该清单在 `feet` 之后与实际字节偏移错位（声明 double[2]、实测 4 个 double），
//      故 **偏移未定案**；本文件只写 `p.<字段名>`，不写死偏移，逐处标
//      `// 偏移待定（WNTypes.h §布局校验）`。A/B 两套候选见 out/notes/word-containers.md §5。
//
//  记号
//    [0xADDR]   —— 该行对应的指令地址
//    CF 0xNNNN  —— __DATA_CONST,__cfstring 里的常量字符串地址
//    0xNNNN.N   —— __TEXT,__const 里的 double 字面量地址（0xbfxxx / 0xc00xx）
//    Assumed    —— 语义推断标记（字节与地址仍为 Observed）。本行为记号定义、不是对二进制的断言；
//                  本文件正文的 Assumed 处仍待逐条复验（不在本轮 25 条范围内）。
//    CALL       —— 本方法内 0 处：全部 bl 已解析为 sel:/符号
//
//  编译状态：NOT RUN（Windows 环境，无 iOS SDK / 无 PetDFY 全量头声明，未实际编译；
//  已完成括号走查，见文末 §SELFCHECK）
//

#import "WNMotion.h"

#import <math.h>
#import <float.h>
#import <objc/runtime.h>

#pragma mark - 词库容器（__DATA_CONST，逐项已解）

// 段布局（Observed）
//   __DATA_CONST,__objc_arraydata  0x104b40..0x106f10   元素指针池（chained fixup 槽）
//   __DATA_CONST,__objc_arrayobj   0x106f10..0x108200   常量数组，步长 0x18（实测 202 个对象）
//        { isa=_OBJC_CLASS_$_NSConstantArray, count(u64), elements(chained fixup) }
//   __DATA_CONST,__objc_dictobj    0x108200..0x108778   常量字典，步长 0x28（实测 35 个对象）
//        { isa=_OBJC_CLASS_$_NSConstantDictionary, 0x1(u64), count(u64), keys, values }
//   校验方式：整数常量逐字节比对 count 与后继 isa 的间距（见 word-containers.md §1）。

// ── 手势/动作词表 ────────────────────────────────────────────────────────
// 对象 @0x1075b8（count=16，elements @0x105860）
// 引用点：[0x424e4] containsObject: 的第 1 道闸门（整个后半段的入口）
static NSArray *const kWNWordsGesture = @[
    @"stand",   // [ 0] elem slot 0x105860 → CF 0xf88c8
    @"jump",    // [ 1] elem slot 0x105868 → CF 0xf3b68
    @"hop",     // [ 2] elem slot 0x105870 → CF 0xf9968
    @"look",    // [ 3] elem slot 0x105878 → CF 0xf3ca8
    @"turn",    // [ 4] elem slot 0x105880 → CF 0xf9988
    @"nod",     // [ 5] elem slot 0x105888 → CF 0xf3da8
    @"shake",   // [ 6] elem slot 0x105890 → CF 0xf3c68
    @"spin",    // [ 7] elem slot 0x105898 → CF 0xf3dc8
    @"sit",     // [ 8] elem slot 0x1058a0 → CF 0xf38c8
    @"sleep",   // [ 9] elem slot 0x1058a8 → CF 0xf38e8
    @"dizzy",   // [10] elem slot 0x1058b0 → CF 0xf97c8
    @"wave",    // [11] elem slot 0x1058b8 → CF 0xf99a8
    @"bow",     // [12] elem slot 0x1058c0 → CF 0xf99c8
    @"shiver",  // [13] elem slot 0x1058c8 → CF 0xf3d68
    @"flap",    // [14] elem slot 0x1058d0 → CF 0xf99e8
    @"dance",   // [15] elem slot 0x1058d8 → CF 0xf3d88
];

// ── 模式词表 ──────────────────────────────────────────────────────────────
// 对象 @0x1075d0（count=5，elements @0x1058e0）
// 引用点：[0x42728] 命中后 setModeTo:word 并写 p.dwell（dance=3.2，其余 1e9）
static NSArray *const kWNWordsMode = @[
    @"look",    // [0] elem slot 0x1058e0 → CF 0xf3ca8
    @"dizzy",   // [1] elem slot 0x1058e8 → CF 0xf97c8
    @"sit",     // [2] elem slot 0x1058f0 → CF 0xf38c8
    @"sleep",   // [3] elem slot 0x1058f8 → CF 0xf38e8
    @"dance",   // [4] elem slot 0x105900 → CF 0xf3d88
];

// ── 短脉冲词表 ────────────────────────────────────────────────────────────
// 对象 @0x1075e8（count=2，elements @0x105908）
// 引用点：[0x427f8] 命中则 pulse 时长 0.7
static NSArray *const kWNWordsShortPulse = @[
    @"nod",     // [0] elem slot 0x105908 → CF 0xf3da8
    @"shake",   // [1] elem slot 0x105910 → CF 0xf3c68
];

// ── walk 模式表 ───────────────────────────────────────────────────────────
// 对象 @0x1075a0（count=2，elements @0x105850）
// 引用点：[0x42224] stopWalk: 命中当前 mode 时把 mode 复位成 idle
static NSArray *const kWNModesWalk = @[
    @"walk",    // [0] elem slot 0x105850 → CF 0xf9708
    @"run",     // [1] elem slot 0x105858 → CF 0xf90c8
];

// ── 词 → 音效名 ───────────────────────────────────────────────────────────
// 对象 @0x1084a8（count=5，keys @0x105918，values @0x105940）
// 引用点：[0x4286c] objectForKeyedSubscript:，命中即 sound:kind:@"move" arguments:@[]
static NSDictionary *const kWNWordSounds = @{
    @"bow":    @"tick",     // key slot 0x105918 → CF 0xf99c8 | val slot 0x105940 → CF 0xf3ec8
    @"nod":    @"nod",      // key slot 0x105920 → CF 0xf3da8 | val slot 0x105948 → CF 0xf3da8
    @"shake":  @"shake",    // key slot 0x105928 → CF 0xf3c68 | val slot 0x105950 → CF 0xf3c68
    @"shiver": @"shiver",   // key slot 0x105930 → CF 0xf3d68 | val slot 0x105958 → CF 0xf3d68
    @"spin":   @"spin",     // key slot 0x105938 → CF 0xf3dc8 | val slot 0x105960 → CF 0xf3dc8
};

// ── 空数组单例 ────────────────────────────────────────────────────────────
// 所有 sound:kind:arguments: 的 arguments 实参都是同一 GOT 槽：
//   0xf0638  → ___NSArray0__struct（源码写作 @[]）
// 出现点：0x42714 / 0x42894（doWord:）。


@implementation WNMotion (Word)

#pragma mark - doWord:

// -[WNMotion doWord:] imp=0x42294 insns=411
// 语义：把一句自然语言指令词翻译成「模式 / 表情 / 音效 / 一次脉冲」。
//       返回 YES = 词被消费；NO = 未识别，或 busy 闸门拦下。
// 词库优先级链（与二进制控制流一一对应）：
//   neutral → busy 闸门 → play_ball → walk/run → 手势词表(16) →（否则）表情字典直通
//                                                    手势词表内：stand → turn → jump族 →
//                                                    模式词表(5) → spin/bow 复位 → 脉冲时长 → 音效 → wave/bow 表情
- (BOOL)doWord:(NSString *)word {
    // =====================================================================
    // [0x42294] 序言 + neutral 直通
    //   0x422ac mov x20,x0（self）/ 0x422b0 x19 = retain(word)
    //   neutral 分支在 busy 闸门 **之前**，忙时也能把表情压回 neutral。
    // =====================================================================
    if ([word isEqual:@"neutral"]) {                            // CF 0xf8948
        if ([self is:@"play_ball"]) {                           // CF 0xf6588
            [self setModeTo:@"idle"];                           // CF 0xf38a8
        }
        [self setExpr:word seconds:0.1];                        // 0.1 @0xbfc88；x2 = word
        return YES;                                             // [0x42300] b 0x424c0 → w20=1
    }

    // =====================================================================
    // [0x42304] busy 闸门
    //   0x42308 bl -[WNMotion busy]；0x4230c tbz w0,#0 → 继续
    // =====================================================================
    if ([self busy]) {                                          // [0x42304]
        return NO;                                             // 0x42310 mov w20,#0 → 0x424c4
    }

    // =====================================================================
    // [0x42318] play_ball 优先分支：清脉冲 + 清表情 + 定长驻留
    // =====================================================================
    if ([word isEqual:@"play_ball"]) {                          // CF 0xf6588
        [self setPulse:nil];                                    // [0x4232c] x2 = 0
        [self setExpression:nil];                               // [0x42338] x2 = 0
        [self setModeTo:@"play_ball"];                          // [0x42344]
        p.dwell = 6.5;                                            // [0x42354] 0x401a000000000000 → str [x20,#0x50]
                                                                //   偏移待定（WNTypes.h §布局校验）
        p.nextAt = self.time + 6.5 + 2.0;                       // [0x4235c..0x42370] time +0x1d8 → str [x20,#0x130]
                                                                //   偏移待定（WNTypes.h §布局校验）
        return YES;                                             // [0x42374] b 0x424c0
    }

    // =====================================================================
    // [0x42378] sitting = (mode=="sit") || (mode=="sleep")
    //   0x42388 tbz w0,#0 → 0x42394 再试 sleep；命中 sit 时 0x4238c mov w21,#1
    // =====================================================================
    BOOL sitting = [self is:@"sit"];                            // CF 0xf38c8
    if (!sitting) {
        sitting = [self is:@"sleep"];                           // [0x42394] CF 0xf38e8
    }

    // =====================================================================
    // [0x423a8] walk / run：随机落点 + 可选唤醒
    // =====================================================================
    if ([word isEqual:@"walk"] || [word isEqual:@"run"]) {      // CF 0xf9708 / 0xf90c8
        // [0x423d0] 取左右半区权重
        //   d8 = p.x（ldr [x20,#8]）；d9 = self.width（ldr [x20,#0x1f0]）；d10 = width*0.5
        double px    = p.x;                                     // [0x423d0] 偏移待定（WNTypes.h §布局校验）
        double halfW = self.width * 0.5;                        // [0x423d4..0x423dc]
        double r     = [self random];                           // [0x423e0] bl -[WNMotion random]
        double kL    = r * 0.35 + 0.55;                         // [0x423f8] fmadd d1；0.35 @0xbfdb8 / 0.55 @0xbfc00
        double kR    = r * 0.35 + 0.1;                          // [0x42404] fmadd d0；0.1 @0xbfc88
        double k     = (px < halfW) ? kL : kR;                  // [0x42408] fcmp d8,d10 + 0x4240c fcsel mi
        // 注释：左半区走 0.55~0.90，右半区走 0.10~0.45（两段都是 0.35 宽，不相交）

        double gy;
        if (self.freeGround) {                                  // [0x42410] ldrb [x20,#0x242]
            gy = [self rnd:[self minY] to:self.floorY];         // [0x42418..0x42428] floorY +0x1e8
        } else {
            gy = p.gy;                                          // [0x42434] ldr d8,[x20,#0x18]
                                                                //   偏移待定（WNTypes.h §布局校验）
        }
        double tx = halfW * k;                                  // [0x42438] fmul d10,d9,d10

        // [0x4243c] 睡着/坐着被叫去走 → 先惊醒
        if ([self is:@"sleep"] || [self is:@"sit"]) {           // CF 0xf38e8 / 0xf38c8
            [self setModeTo:@"wake"];                            // [0x42464] CF 0xf9948
            p.wokeNow = YES;                                     // [0x42478] strb 1,[x20,#0x1d2]
                                                                //   偏移待定（WNTypes.h §布局校验）
        }

        // [0x4247c] 清表情，落点夹到 [minX, maxX]
        [self setExpression:nil];
        double mn = [self minX];                                // [0x42488] bl -[WNMotion minX]
        double mx = [self maxX];                                // [0x42494] bl -[WNMotion maxX]
        p.walkToX  = fmax(mn, fmin(mx, tx));                     // [0x4249c] fminnm d0,d0,d10
                                                                // [0x424a0] fmaxnm d0,d9,d0
                                                                //   偏移待定（WNTypes.h §布局校验）
        p.walkToY = gy;                                         // [0x424a4] stp d0,d8,[x20,#0x58]
                                                                //   偏移待定（WNTypes.h §布局校验）
        // 注释：min/max 两侧是 fminnm/fmaxnm（NaN 传播语义），源码写作 fmin/fmax。

        [self setModeTo:word];                                  // [0x424a8] 模式即词本身（"walk"/"run"）
        [self setWalkWord:word];                                // [0x424b4] _walkWord = word
        return YES;                                             // [0x424c0] w20=1
    }

    // =====================================================================
    // [0x424e4] 手势闸门：word 是否在 16 项常量数组（@0x1075b8）里
    //   命中 → 继续下面的手势分支；未命中 → 0x42568 走表情直通
    // =====================================================================
    if ([kWNWordsGesture containsObject:word]) {                // [0x424e4] x0 = 0x1075b8

        // [0x424f8] 任何手势词都把 play_ball 收回 idle
        if ([self is:@"play_ball"]) {                           // CF 0xf6588
            [self setModeTo:@"idle"];                           // CF 0xf38a8
        }
        [self setExpression:nil];                               // [0x4251c]

        // -----------------------------------------------------------------
        // [0x42528] stand：坐下/睡着时 stand 等于 wake
        // -----------------------------------------------------------------
        if ([word isEqual:@"stand"]) {                          // CF 0xf88c8
            // 0x4253c..0x42550 csel x2,="wake", ="idle", ne（w21!=0 时取 wake）
            [self setModeTo:(sitting ? @"wake" : @"idle")];      // CF 0xf9948 / 0xf38a8
            p.nextAt = self.time + 3.0;                          // [0x4255c] ldr d0,[x20,#0x1d8]
                                                                 // [0x42560] fmov d1,#3.0
                                                                 // [0x42564] b 0x4236c → fadd d0,d0,d1 → str [x20,#0x130]
                                                                 // 注意：跳转落在 0x42368 之后，**跳过**了那条 fmov 2.0，
                                                                 //       所以是 time+3.0，不是 time+5.0（与 play_ball 的 6.5+2.0 不同）
                                                                 //   偏移待定（WNTypes.h §布局校验）
            return YES;                                          // [0x424c0]
        }

        // -----------------------------------------------------------------
        // [0x425c0] turn：翻转朝向 + tick 音效
        // -----------------------------------------------------------------
        if ([word isEqual:@"turn"]) {                           // CF 0xf9988
            if (!sitting) {                                      // [0x425d4] tbnz w21,#0
                [self setModeTo:@"idle"];                        // CF 0xf38a8
            }
            p.facing = -p.facing;                                // [0x425e8..0x425f0] ldr/fneg/str [x20,#0x38]
                                                                 //   偏移待定（WNTypes.h §布局校验）
            [self sound:@"tick" kind:@"move" arguments:@[]];     // [0x425f4] CF 0xf3ec8 / 0xf97a8
                                                                 // 实参 @[] = ___NSArray0__struct @0xf0638
                                                                 // → [0x4270c] 与 flap/dance 共用该调用点
            return YES;                                          // [0x424c0]
        }

        // -----------------------------------------------------------------
        // [0x42600] jump / hop / flap 起飞族：先蹲，再给起跳初速
        // -----------------------------------------------------------------
        if ([word isEqual:@"jump"] || [word isEqual:@"hop"] || [word isEqual:@"flap"]) {
                                                                // CF 0xf3b68 / 0xf9968 / 0xf99e8
            [self setModeTo:@"crouch"];                          // [0x4263c] CF 0xf88e8

            // [0x4264c] 纵向初速三档
            if ([word isEqual:@"jump"]) {
                p.launchY = 720.0;                                 // [0x42660] 0xbfca8 → [x20,#0x158]
                                                                //   偏移待定（WNTypes.h §布局校验）
            } else if ([word isEqual:@"hop"]) {
                p.launchY = 480.0;                                 // [0x42680..0x42690] fcsel ne，480.0 立即数
                                                                //   偏移待定（WNTypes.h §布局校验）
            } else {
                p.launchY = 540.0;                                 // [0x42688] 0xc0018（hop 不成立时的 else 支）
                                                                //   偏移待定（WNTypes.h §布局校验）
            }

            // [0x42698] 横向初速：只有 jump 带朝向分量
            //   0x426a8 fmov d0,xzr（=0）；0x426ac cbz 跳过；0x426b0 ldr facing；0x426bc *40.0
            p.launchX = [word isEqual:@"jump"] ? (p.facing * 40.0) : 0.0;
                                                                // 40.0 @0x4044000000000000 → [x20,#0x160]
                                                                //   偏移待定（WNTypes.h §布局校验）

            // [0x426c4] flap 另有脉冲 + 表情 + 音效
            if ([word isEqual:@"flap"]) {                        // [0x426d4] cbz → 直接返回
                [self pulse:word duration:1.4];                  // [0x426d8] 1.4 @0xbfde8
                [self holdFace:@"happy" seconds:1.6];            // [0x426ec] CF 0xf3de8 / 1.6 @0xbff28
                [self sound:@"chirps" kind:@"move" arguments:@[]];// [0x42704] CF 0xf3c48 / @[] @0xf0638
            }
            return YES;                                          // [0x424c0]
        }

        // -----------------------------------------------------------------
        // [0x42728] 模式词闸门：5 项常量数组（@0x1075d0）
        //   命中就 setModeTo:word，并写驻留时长（dance 3.2s，其余 1e9s ≈ 永久）
        // -----------------------------------------------------------------
        if ([kWNWordsMode containsObject:word]) {                // [0x42728] x0 = 0x1075d0
            [self setModeTo:word];                               // [0x4273c]
            // [0x4275c] cmp + fcsel d0：dance → 3.2 @0xbfff8，否则 1e9 @0xbfc68
            p.dwell = [word isEqual:@"dance"] ? 3.2 : 1e9;         // [0x42774] str [x20,#0x50]
                                                                //   偏移待定（WNTypes.h §布局校验）
            p.sitSeen = NO;                                    // [0x42778] strb wzr,[x20,#0x1d3]
                                                                //   偏移待定（WNTypes.h §布局校验）
            if ([word isEqual:@"dance"]) {                       // CF 0xf3d88
                [self holdFace:@"happy" seconds:3.4];            // [0x4278c] CF 0xf3de8 / 3.4 @0xc0010
                [self sound:@"dance" kind:@"move" arguments:@[]];// [0x427a4] → [0x4270c]
            }
            return YES;                                          // [0x424c0]
        }

        // -----------------------------------------------------------------
        // [0x427b0] spin / bow 需要坐姿；没坐就先回 idle
        //   spin：0x427c4 tbz w21（未坐→0x427e8 复位）
        //   bow ：0x427dc eor w8,w0,#1 / 0x427e0 orr w8,w8,w21 / tbnz → 跳过
        //   ⇒ 仅当（命中 spin 或 bow）且 !sitting 时复位
        // -----------------------------------------------------------------
        if (([word isEqual:@"spin"] || [word isEqual:@"bow"]) && !sitting) {
                                                                // CF 0xf3dc8 / 0xf99c8
            [self setModeTo:@"idle"];                            // [0x427e8] CF 0xf38a8
        }

        // -----------------------------------------------------------------
        // [0x427f8] 脉冲时长四档
        //   短脉冲表(2) → 0.7；spin → 0.6；shiver → 1.6；其余 → 1.8
        //   注：旧快照把 shiver 记成 0.7、缺 1.6 档，与二进制不符（0x42854 fcsel ne）
        // -----------------------------------------------------------------
        double dur;
        if ([kWNWordsShortPulse containsObject:word]) {          // [0x427f8] x0 = 0x1075e8
            dur = 0.7;                                           // [0x42808] 0xbfdb0
        } else if ([word isEqual:@"spin"]) {                     // [0x42818] CF 0xf3dc8
            dur = 0.6;                                           // [0x4282c] 0xbfff0
        } else {
            dur = [word isEqual:@"shiver"] ? 1.6 : 1.8;          // [0x42838] CF 0xf3d68
                                                                // [0x42854] fcsel d0：ne → 1.6 @0xbff28，
                                                                // 否则 1.8 @0xbfea0
        }
        [self pulse:word duration:dur];                          // [0x42860] bl -[WNMotion pulse:duration:]

        // -----------------------------------------------------------------
        // [0x4286c] 词 → 音效名（字典 @0x1084a8）
        //   x0 = 0x1084a8；objectForKeyedSubscript: → claim → cbz
        // -----------------------------------------------------------------
        NSString *sfx = kWNWordSounds[word];                     // [0x4286c] x0 恒为 @0x1084a8
        if (sfx) {                                               // [0x42884] cbz x0 → 跳过
            [self sound:sfx kind:@"move" arguments:@[]];         // [0x42888..0x428a0] CF 0xf97a8
                                                                // 实参 @[] @0xf0638
        }

        // [0x428a4] wave → happy 1.8s
        if ([word isEqual:@"wave"]) {                            // CF 0xf99a8
            [self holdFace:@"happy" seconds:1.8];                // [0x428b8] CF 0xf3de8 / 1.8 @0xbfea0
        }
        // [0x428d0] bow → bowing 1.5s
        if ([word isEqual:@"bow"]) {                             // CF 0xf99c8
            [self holdFace:@"bowing" seconds:1.5];               // [0x428e4] CF 0xfa08→0xf9a08 / fmov 1.5
        }

        return YES;                                              // [0x428fc] b 0x424c0
    }

    // =====================================================================
    // [0x42568] 非手势词 → 当作表情名直通 faces 字典
    //   0x42568 bl -[WNMotion faces]（+0x2f0）→ claim → objectForKeyedSubscript:
    //   0x42590 cbz x22 → 0x42310（返回 NO）
    // =====================================================================
    if ([self faces][word] == nil) {                             // [0x42568..0x42590]
        return NO;                                               // 0x42310 mov w20,#0 → 0x424c4
    }

    // [0x42594] 表情路径同样先收 play_ball
    if ([self is:@"play_ball"]) {                                // CF 0xf6588
        [self setModeTo:@"idle"];                                // [0x425a8] CF 0xf38a8
    }
    [self setExpr:word seconds:0.0];                             // [0x425b8] fmov d0,xzr → 0x422f4
    return YES;                                                  // [0x42300] b 0x424c0
}


#pragma mark - walk 指令面

// -[WNMotion walkTo:run:identifier:] imp=0x41f38 insns=166
// 语义：把漫游目标设为 x（夹到 [minX,maxX]），可选 run 模式；对外发
//       "interrupted"（旧目标被顶替）/ "arrived"（已在落点 2pt 内）两个事件。
// 参数寄存器（Apple arm64：double→d0，BOOL→w2，id→x3）
//   0x41f5c mov x21,x2（run）/ 0x41f60 fmov d8,d0（x）/ 0x41f78 retain(x3)→x19（identifier）
- (BOOL)walkTo:(double)x run:(BOOL)run identifier:(NSString *)identifier {
    // [0x41f68] 栈保护：GOT 0xf0680 → ___stack_chk_guard（失败跳 0x421cc __stack_chk_fail）
    // [0x41f80] busy + !isfinite(x) 合并成一个闸门（w25 = w8 | w0）
    //   0x41f88 fabs / 0x41f8c INF / 0x41f98 cset eq / 0x41f9c csinc vc / 0x41fa0 orr
    //   csinc 在 unordered（NaN）时取 1 ⇒ 判定为 !isfinite(x) || [self busy]
    if (!isfinite(x) || [self busy]) {                            // [0x41f80..0x41fa4]
        return NO;                                               // 0x421a4 eor w0,w25,#1 → 0
    }

    // [0x41fa8] 旧 walk 标识存在 → 发 "interrupted"（detail 里回带当前 p.x 与 by=replaced）
    NSString *prevIdentifier = [self walkIdentifier];             // [0x41fa8] _walkIdentifier +0x300
    if (prevIdentifier != nil) {                                 // [0x41fd4] cbz x22
        // dictionaryWithObjects:forKeys:count: = 3
        //   keys    @sp+0x28：@"walkId" 0xf8ac8 / @"x" 0xf89a8 / @"by" 0xf8b68
        //   objects @sp+0x40：walkIdentifier / @(p.x) / @"replaced" 0xf9928
        [self event:@"interrupted" detail:@{                     // [0x42044] CF 0xf8b08
            @"walkId": [self walkIdentifier],
            @"x":      @(p.x),                                   // [0x41ff8] ldr d0,[x20,#8]
            @"by":     @"replaced",
        }];                                                      // NSDictionary classref 0x119ce8
        [self setWalkIdentifier:nil];                            // [0x42074]
    }

    // [0x42080] 睡着/坐着被叫去走 → 先惊醒（与 doWord: 的 walk 分支同形）
    if ([self is:@"sleep"] || [self is:@"sit"]) {                 // CF 0xf38e8 / 0xf38c8
        [self setModeTo:@"wake"];                                // [0x420a8] CF 0xf9948
        p.wokeNow = YES;                                         // [0x420b8] strb 1,[x20,#0x1d2]
                                                                 //   偏移待定（WNTypes.h §布局校验）
    }
    [self setExpression:nil];                                    // [0x420c0]

    // [0x420cc] 落点夹取：fmax(minX, fmin(maxX, x)) → d8
    double mn = [self minX];                                     // [0x420d0]
    double mx = [self maxX];                                     // [0x420dc]
    double tx = fmax(mn, fmin(mx, x));                           // [0x420e0] fminnm / [0x420e4] fmaxnm

    // [0x420e8] 已在落点 2pt 内 → 直接算到达
    //   0x420e8 ldr p.x；0x420ec fabd d1,d8,d0；0x420f0 fmov 2.0；0x420f8 b.pl 0x42154
    //   （fabd 非负，pl 表示 |Δ|>=2.0 跳过；即 |Δ|<2.0 走到达分支）
    if (fabs(tx - p.x) < 2.0) {                                  // 偏移待定（WNTypes.h §布局校验）
        // dictionaryWithObjects:forKeys:count: = 2
        //   objects @sp+0x18：identifier / @(x)；keys @sp+0x8：@"walkId" / @"x"
        [self event:@"arrived" detail:@{                         // [0x42138] CF 0xf8ae8
            @"walkId": identifier,
            @"x":      @(x),                                     // numberWithDouble:，NSNumber ref 0x119d10
        }];
        return YES;                                              // [0x42150] b 0x42188 公共出口，w25==0 ⇒ YES
    }

    // [0x42154] 提交漫游：模式 csel（run ? "run" : "walk"）
    [self setModeTo:(run ? @"run" : @"walk")];                   // CF 0xf90c8 / 0xf9708
    p.walkToX  = tx;                                              // [0x42178] stp d8,d0,[x20,#0x58]
                                                                 //   偏移待定（WNTypes.h §布局校验）
    p.walkToY = p.gy;                                            // [0x42178] 取 ldr d0,[x20,#0x18]
                                                                 //   偏移待定（WNTypes.h §布局校验）
    [self setWalkIdentifier:identifier];                         // [0x42180] x19 = identifier
    return YES;                                                  // [0x421a4] eor w0,w25,#1 → 1
}

// -[WNMotion stopWalk:] imp=0x421d0 insns=49
// 语义：仅当传入标识与当前 _walkIdentifier 相同，且当前 mode 属于 {walk,run} 时复位到 idle。
- (void)stopWalk:(NSString *)identifier {
    // 0x421e4 mov x19,x0（self）/ 0x421e8 retain(x2)→x20（identifier）
    // 0x421f0 取 _walkIdentifier（+0x300）→ sp+8；0x42200 isEqual:（receiver = 当前标识）
    if ([[self walkIdentifier] isEqual:identifier]) {            // [0x42204]
        // 0x42214 bl -[WNMotion mode]；0x42224 x0 = 0x1075a0（2 项常量数组）
        if ([kWNModesWalk containsObject:[self mode]]) {         // [0x42230]
            [self setModeTo:@"idle"];                            // [0x42248] 尾调用 b 0xad020
                                                                 // CF 0xf38a8
        }
        // 0x42244 cbz w21 → 0x42280（不复位，直接返回）
    }
    // 0x42268 / 0x42280 两条收尾路径都只做 release，无其它副作用
}


#pragma mark - 词/走 状态访问器（编译器合成，2 条）

// -[WNMotion walkWord] imp=0x49380 insns=2     0x49380 ldr x0,[x0,#0x2f8] ; ret
- (NSString *)walkWord {
    return _walkWord;                       // _walkWord +0x2f8
}

// -[WNMotion setWalkWord:] imp=0x49388 insns=2
//   0x49388 mov w3,#0x2f8 ; 0x4938c b _objc_setProperty_nonatomic_copy（尾调用，copy 语义）
- (void)setWalkWord:(NSString *)walkWord {
    objc_setProperty_nonatomic_copy(self, _cmd, walkWord, 0x2f8);
}

// -[WNMotion walkIdentifier] imp=0x49390 insns=2  0x49390 ldr x0,[x0,#0x300] ; ret
- (NSString *)walkIdentifier {
    return _walkIdentifier;                 // _walkIdentifier +0x300
}

// -[WNMotion setWalkIdentifier:] imp=0x49398 insns=2
//   0x49398 mov w3,#0x300 ; 0x4939c b _objc_setProperty_nonatomic_copy
- (void)setWalkIdentifier:(NSString *)walkIdentifier {
    objc_setProperty_nonatomic_copy(self, _cmd, walkIdentifier, 0x300);
}

// -[WNMotion lastAction] imp=0x493c0 insns=2      0x493c0 ldr x0,[x0,#0x310] ; ret
- (NSString *)lastAction {
    return _lastAction;                     // _lastAction +0x310
}

// -[WNMotion setLastAction:] imp=0x493c8 insns=2
//   0x493c8 mov w3,#0x310 ; 0x493cc b _objc_setProperty_nonatomic_copy
- (void)setLastAction:(NSString *)lastAction {
    objc_setProperty_nonatomic_copy(self, _cmd, lastAction, 0x310);
}

@end


// =========================================================================
// §SELFCHECK
// -------------------------------------------------------------------------
// 1. 方法落位：本文件 9 个方法，覆盖方法表 106 条中的 9 条、638/8933 条指令
//    （若排除 WNMotion+Step.m 已承担的 -step: 2880 条，则 638/6053 = 10.5%）。
//    逐方法表见 out/notes/word-coverage.md §2。
// 2. 容器：5/5 全部解出，元素 16+5+2+2+5 = 30 项，无 unknown 占位
//    （word-containers.md §2–§4）。已定案 2026-11-28（复核，实读 4 个 __NSConstantArray 的 count@+0x08）：
//      @0x1075b8 = 16 项、@0x1075d0 = 5 项、@0x1075e8 = 2 项、@0x1084a8 = 1 项
//      （0x1084a8 是 __NSConstantDictionary，只在 keys+values 两个缓冲上取，故按 2+5 分记）。
//      元素对象全是 __NSConstantIntegerNumber / CFString 指针，无 `?` 占位、无未具名槽。
// 3. 括号走查：doWord: 内 27 个 `if`（含 2 个 `else if` + 3 个裸 `else`）、11 个 `return`、
//    4 处由 fcsel 降成的三元（0x4240c / 0x42690 / 0x42770 / 0x4285c），
//    每个分支目标已逐一核对（word-coverage.md §4）；@[ ]/@{ } 字面量 5+1 组，逗号结尾一致。
// 4. bl 解析：638 条指令内所有 bl 均解析为 sel:/符号，无 CALL 占位。
// 5. NOT RUN：未编译（Windows，无 iOS SDK）；p 字段偏移未定案（WNTypes.h §布局校验），
//    因此"能编过"与"偏移正确"两件事都未验证。
// 6. 未决 2 处：
//    a. p.launchY/p.launchX/nextAt/startle/willSleep 的字节偏移与 WNTypes.h 清单错位
//       （feet 声明 double[2]，实测 4 个 double ⇒ 其后整体前移 0x10）。
//       验证动作：按 WNTypes.h 加 static_assert 编一次，报错那组即错。
//    b. walkTo: / stopWalk: 是否属于本文件而非 WNMotion+Walk 模块，仅由调用关系
//       （doWord: 的 walk 分支 → setWalkWord:）推定，无二进制侧证据。
// =========================================================================
