//
//  WNLiveRig.m
//  PetDFY
//
//  WNLiveRig 主实现（58 个方法中的 57 个；-renderBuildingMesh: 在 WNLiveRig+Mesh.m）
//  逐方法还原，非片段。
//
//  二进制证据
//    image base        : 0（arm64 切片 extract/bin/PetDFY.arm64.dylib）
//    类                : name=WNLiveRig  class=0x11b430  class_ro=0x113048
//                        instanceSize=488 (0x1e8)  ivars=0x1128c8（4 个 ivar_layout，共 47 项）
//    方法区间          : out/method-table-all.md（58 行 WNLiveRig，imp/end/insns/type 全部实测）
//    指令总数          : 7142（58 个区间 capstone 实测；其中 2 处静态辅助 0x4aa14/0x4ab38）
//    静态辅助          : 0x49c48 WNLoadJSON(NSURL*)         —— 被 init 在 0x49714/0x4975c 调用
//                        0x4aa14 WNDictDouble(dict,key,dflt) —— 被 3 个方法 + 6 个 warp block 调用
//                        0x4ab38 WNApplyDeformer(obj,pt)     —— 被 -point:deformer: / -updateMesh 调用
//    两个"未判定 bl" 说明：0x49c48 / 0x4aa14 / 0x4ab38 都不是 stub，而是**同一 __TEXT 段内的
//    本类私有静态函数**，objc 方法表把它们算进了相邻方法的 insns 统计（这是旧快照地址全错的根因之一）。
//
//  字段偏移来源
//    - 全部 ivar 名称/偏移取自 __objc_ivar（ivar_ro.py 实测，见 out/notes/rig-coverage.md §1）：
//      lastT +0x08 … localVertices +0x1e0。本文件所有 `_ivar /* +0xNNN */` 均为 Observed。
//    - WNPreparedDeformer 是本类私有类（class 0x11b408），字段偏移由 -compileMesh 写入端
//      (0x4a0a8..0x4a1d0) 与 0x4ab38 读取端交叉确定，见下文结构体定义。
//
//  记号
//    // -[WNLiveRig xxx] imp=0x… insns=N        方法头（insns 为方法表实测）
//    // [0xADDR] …                              该行/该段的指令地址
//    /* +0xNNN */                               结构体/对象字段真实偏移（Observed）
//    Assumed                                    语义推断标记（偏移仍为 Observed）。本行为记号定义、
//                                               不是对二进制的断言；正文 Assumed 处不在本轮范围。
//    CALL 0xADDR(x0=…, x1=…)                    未解析的 bl 目标——本文件 0 处：
//                                               3 个内部目标已定性为静态函数并给名。
//
//  编译状态：NOT RUN
//    本机为 Windows，无 iOS SDK、无 PetDFY 全量头文件（WNMotion.h/WNSpring.h 仅有外部声明），
//    因此未实际编译；已完成括号走查（忽略字符串/注释内括号），见文末 §SELFCHECK。
//

#import "WNLiveRig.h"
#import "WNMotion.h"
#import "WNSpring.h"
#import <math.h>

#pragma mark - WNPreparedDeformer（私有类，class 0x11b408）

// -compileMesh 写入端证据：+0x8 (0x4a0a8) / +0x10 (0x4a0cc) / +0x18,+0x20 (0x4a108,0x4a124)
//                        / +0x58..+0x70 (0x4a15c..0x4a1d0) / +0x78 (0x4a984)
// 0x4ab38 读取端证据：+0x10,+0x11,+0x18,+0x20,+0x28,+0x30,+0x38,+0x40,+0x48,+0x50,+0x58,+0x60,
//                     +0x68,+0x70,+0x78,+0x8(next)
@interface WNPreparedDeformer : NSObject
{
@public
    WNPreparedDeformer *next;   // +0x08  父 deformer（-compileMesh 0x4a0a8 写入 compiled[parent]）
    uint8_t  hasRot;            // +0x10  kind == "rot"
    uint8_t  enabled;           // +0x11  有 rot 或有 warp 时为 1（-prepareDeformers 0x4a8d8/0x4a99c）
    uint8_t  _pad12[6];
    double   pivotX;            // +0x18
    double   pivotY;            // +0x20
    double   sx;                // +0x28
    double   sy;                // +0x30
    double   tx;                // +0x38
    double   ty;                // +0x40
    double   cosA;              // +0x48  __sincos_stret 的 d1
    double   sinA;              // +0x50  __sincos_stret 的 d0
    double   rectX;             // +0x58
    double   rectY;             // +0x60
    double   rectW;             // +0x68
    double   rectH;             // +0x70
    id       warp;              // +0x78  -warps 里的 block（copy 后）
}
@end

@implementation WNPreparedDeformer
@end

#pragma mark - 私有静态辅助（全部有地址证据）

// [0x49c48] static NSDictionary *WNLoadJSON(NSURL *url)
//   0x49c58 取 NSData 类 → dataWithContentsOfURL: → JSONObjectWithData:options:0 error:0
//   拿不到 data 时返回 nil（0x49c94 mov x20,#0），不抛异常。
static NSDictionary *WNLoadJSON(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data == nil) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

// [0x4aa14] static double WNDictDouble(NSDictionary *dict, NSString *key, double dflt)
//   0x4aa48/0x4aa60 两次 objectForKeyedSubscript:（先判空再取值），0x4aa6c doubleValue。
//   与 WNMotion+Step 里的同名辅助等价，但这里是独立静态函数（不同地址）。
static double WNDictDouble(NSDictionary *dict, NSString *key, double dflt) {
    if ([dict objectForKeyedSubscript:key] == nil) {
        return dflt;
    }
    return [[dict objectForKeyedSubscript:key] doubleValue];
}

// [0x4ab38] static CGPoint WNApplyDeformer(WNPreparedDeformer *d, CGPoint p)
//   沿 next 链逐级应用；每级：
//     hasRot:  (p-pivot)*scale → 旋转 → +translate
//     else:    clamp 到 rect 的 (u,v) → 调 warp block(u, v, p.x, p.y) → 结果**加到** p 上
//   证据：0x4ab78..0x4abb0（rot 分支）、0x4abb4..0x4abf4（warp 分支）、0x4abf8（next 链）。
static CGPoint WNApplyDeformer(WNPreparedDeformer *d, CGPoint p) {
    while (d != nil) {
        if (d->enabled) {
            if (d->hasRot) {
                double dx = (p.x - d->pivotX) * d->sx;
                double dy = (p.y - d->pivotY) * d->sy;
                double cx = d->pivotX + d->tx;
                double cy = d->pivotY + d->ty;
                double nx = (cx + dx * d->cosA) - dy * d->sinA;
                double ny = cy + dx * d->sinA + dy * d->cosA;
                p.x = nx;
                p.y = ny;
            } else if (d->warp != nil) {
                // [0x4abb4] u = clamp((p.x - rectX)/rectW, 0, 1)；v = clamp((p.y - rectY)/rectH, 0, 1)
                double u = (p.x - d->rectX) / d->rectW;
                double v = (p.y - d->rectY) / d->rectH;
                u = fmin(fmax(u, 0.0), 1.0);            // fminnm/fmaxnm
                v = fmin(fmax(v, 0.0), 1.0);
                // [0x4abdc] blr x8 = block invoke；入参 d0=u d1=v d2=p.x d3=p.y
                CGPoint (*fn)(id, double, double, double, double) =
                    (CGPoint (*)(id, double, double, double, double))((void **)d->warp)[2];
                CGPoint delta = fn(d->warp, u, v, p.x, p.y);
                p.x += delta.x;                          // [0x4abf0] fadd d9,d9,d0
                p.y += delta.y;                          // [0x4abf4] fadd d8,d8,d1
            }
        }
        d = d->next;                                     // [0x4abf8]
    }
    return p;
}

#pragma mark - 冻结常量表（__NSConstantArray 字面量，逐元素从 __DATA_CONST 解出）

// [0x1077f8] static NSArray *WNSpringTable(void)
//   13 行 × 4 列 [name, k, c, limit]；元素为 NSConstantString / NSConstantIntegerNumber /
//   NSConstantDoubleNumber（strings 走 __CFConstantString {isa,0x7c8,ptr,len} 解出）。
//   调用点：-initWithResourceURL:scheme:seed:freeGround: 0x499b0..0x49ab4。
static NSArray *WNSpringTable(void) {
    return @[
        @[@"hair",   @55,  @7,  @1.8],
        @[@"hairY",  @50,  @8,  @1.2],
        @[@"bangs",  @110, @10, @1.6],
        @[@"skirt",  @100, @9,  @1.6],
        @[@"skirtY", @90,  @10, @1.1],
        @[@"tail",   @40,  @5,  @32],
        @[@"fins",   @90,  @9,  @30],
        @[@"ahoge",  @140, @6,  @38],
        @[@"head",   @70,  @10, @16],
        @[@"armN",   @60,  @9,  @125],
        @[@"armF",   @60,  @9,  @95],
        @[@"hlX",    @160, @9,  @3],
        @[@"hlY",    @160, @9,  @3],
    ];
}

// [0xc0420] 15 个 CGPoint（默认装束的球接触轮廓）；[0xc0510] cape；[0xc05b0] crew（19 个）。
// 逐 double 从 __TEXT __const 解出，见 out/notes/rig-coverage.md §C。
static const double kBallContour15[30] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};
static const double kBallContourCape[20] = { 0 };
static const double kBallContourCrew[38] = { 0 };

@implementation WNLiveRig

#pragma mark - 弹簧

// -[WNLiveRig spring:target:dt:]  imp=0x49574 insns=32  type d40@0:8@16d24d32
- (double)spring:(NSString *)name target:(double)target dt:(double)dt {
    // 0x4959c [-springs] → 0x495b0 objectForKeyedSubscript: → 0x495cc [spring step:dt:]
    WNSpring *s = [[self springs] objectForKeyedSubscript:name];   // +0x1a8
    return [s step:target dt:dt];                                  // d9=target d8=dt
}

// -[WNLiveRig newSpring:k:c:limit:]  imp=0x495f4 insns=37  type v48@0:8@16d24d32d40
- (WNSpring *)newSpring:(NSString *)name k:(double)k c:(double)c limit:(double)limit {
    // 0x495f4..0x49628 WNSpring 类引用在 0x119ff0（rebase 0x11b3b8 = WNSpring）
    WNSpring *s = [WNSpring new];           // 0x495f4 [0x119ff0 objc_opt_new]
    s->k = k;                               // 0x4963c stp d10,d9,[x0,#0x18] → +0x18
    s->c = c;                               //            同上               → +0x20
    s->limit = limit;                       // 0x49640 str d8,[x0,#0x28]  → +0x28
    [[self springs] setObject:s forKeyedSubscript:name];   // 0x4965c  +0x1a8
    return s;
}

#pragma mark - 初始化

// -[WNLiveRig initWithResourceURL:scheme:seed:freeGround:]  imp=0x49688 insns=416
//   type @40@0:8@16@24I32B36 ；栈帧 0x1b0，栈保护 0x496c4 / 0x49be8 / 0x49c18
- (instancetype)initWithResourceURL:(NSURL *)url
                             scheme:(NSString *)scheme
                               seed:(uint32_t)seed
                         freeGround:(BOOL)freeGround {
    // 0x496ac stp w4,w5,[sp,#8] → seed/freeGround 存栈，0x49ac4 再取出传给 WNMotion
    self = [super init];                                        // 0x496f0 objc_msgSendSuper2
    if (self == nil) {                                          // 0x496f8
        return nil;
    }

    // [0x496fc] 主模型 live/model.json → _tables(0x168)；原模型 originals/model.json → _sourceModel(0x160)
    NSURL *liveURL = [url URLByAppendingPathComponent:@"live/model.json"];
    NSDictionary *live = WNLoadJSON(liveURL);                  // 0x49714 bl 0x49c48
    _tables = live[@"tables"];                                 // 0x49730 / +0x168
    NSURL *origURL = [url URLByAppendingPathComponent:@"originals/model.json"];
    _sourceModel = WNLoadJSON(origURL);                        // 0x4975c / +0x160

    // [0x49774] "maid-casual" → scheme="maid", outfit="casual"
    NSArray *parts = [scheme componentsSeparatedByString:@"-"]; // 0x49780
    _scheme = parts[0];                                        // 0x497a0 / +0x188
    if ([parts count] > 1) {                                   // 0x497b0 cmp x0,#1 / b.ls
        _outfit = parts[1];                                    // 0x497cc / +0x190
    } else {
        _outfit = @"maid";                                     // 0x497e0 CF "maid"
    }

    // [0x497e8] _model = live[@"models"][_outfit]
    _model = live[@"models"][_outfit];                         // 0x49804 / +0x158
    if (_model == nil) {                                       // 0x49824 cbnz
        [NSException raise:@"LiveRig" format:@"Missing rig %@", scheme];   // 0x49848
    }

    // [0x4984c] _outfitInfo = [sourceModel[@"outfits"] filteredArrayUsingPredicate:@"id == %@"].firstObject
    NSArray *outfits = _sourceModel[@"outfits"];                                     // +0x160
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"id == %@", _outfit];       // 0x49868
    _outfitInfo = [[outfits filteredArrayUsingPredicate:pred] firstObject];           // +0x1d0
    if (_outfitInfo == nil) {                                  // 0x498bc
        [NSException raise:@"LiveRig" format:@"Missing outfit %@", scheme];          // 0x498e8
    }

    // [0x498ec] pivots = sourceModel.pivots ⧺ outfitInfo.pivots（后者覆盖前者）
    NSMutableDictionary *piv = [_sourceModel[@"pivots"] mutableCopy];                // 0x49904
    NSDictionary *outfitPiv = _outfitInfo[@"pivots"];
    [piv addEntriesFromDictionary:(outfitPiv ?: @{})];         // 0x4993c，空表为 ___NSDictionary0__struct(0xf0640)
    _pivots = piv;                                             // 0x4994c / +0x1c8

    // [0x49950] 四个空字典：rot(0x1b0) warps(0x1b8) springs(0x1a8) rootWas(0x1c0)
    _rot     = [NSMutableDictionary new];
    _warps   = [NSMutableDictionary new];
    _springs = [NSMutableDictionary new];
    _rootWas = [NSMutableDictionary new];

    // [0x499a4] 建 13 根弹簧
    for (NSArray *row in WNSpringTable()) {                    // 0x499b0 0x1077f8
        [self newSpring:row[0]
                      k:[row[1] doubleValue]
                      c:[row[2] doubleValue]
                  limit:[row[3] doubleValue]];                 // 0x49a7c
    }

    // [0x49ab8] _motion = [[WNMotion alloc] initWithSeed:seed freeGround:freeGround]
    _motion = [[WNMotion alloc] initWithSeed:seed freeGround:freeGround];   // 0x49ac8 / +0x150
    [_motion setFaceDefinitions:_tables[@"faces"]];             // 0x49b00

    // [0x49b08..0x49b5c] groupTilt block：捕获 __weak self（objc_initWeak 0x49b10，objc_copyWeak 0x49b50）
    __weak WNLiveRig *weakSelf = self;
    [_motion setGroupTilt:^double(double a, double b) {
        // block invoke = 0x49cac；弱引用在 0x49ccc objc_loadWeakRetained
        WNLiveRig *s = weakSelf;
        if (s == nil) {
            return 0.0;                                        // 0x49cf0 fmov d8,xzr
        }
        // 0x49ccc ldp d0,d1,[x0,#0x30] → wTilt(+0x30) wLean(+0x38)
        return a * s->wTilt + b * s->wLean
             + s->runK /* 0x70 */ * 14.0 * s->facing /* 0x40 */;   // 0x49cd8..0x49ce8
    }];

    // [0x49b60] 四个 1.0 初值（0x3ff0000000000000 立即数）
    _facing   = 1.0;                                           // +0x40
    _hlAlpha  = 1.0;                                           // +0x108
    _hlScale  = 1.0;                                           // +0xf8
    _creaseA  = 1.0;                                           // +0xd8

    [self compileMesh];                                        // 0x49b78

    // [0x49b7c] 预热 120 帧，dt = 0xc0270 = 1.0/60
    for (int i = 0x78; i != 0; i--) {
        [self step:0.016666666666666666];                       // 0x49b90
    }
    return self;                                                // 0x49bf0
}

#pragma mark - 帧推进 / 渲染入口

// -[WNLiveRig step:]  imp=0x49d08 insns=2
- (void)step:(double)dt {
    [self step:dt buildMesh:YES];                               // 0x49d0c mov w2,#1; b step:buildMesh:
}

// -[WNLiveRig step:buildMesh:]  imp=0x49d10 insns=21  type v28@0:8d16B24
- (void)step:(double)dt buildMesh:(BOOL)buildMesh {
    [[self motion] step:dt];                                    // 0x49d40 sel:step:
    [self renderBuildingMesh:buildMesh];                        // 0x49d60 tail b
}

// -[WNLiveRig render]  imp=0x4ae24 insns=2
- (void)render {
    [self renderBuildingMesh:YES];                              // 0x4ae28 mov w2,#1; b
}

// -[WNLiveRig rotation:a:]  imp=0x49d64 insns=57  type v32@0:8@16d24
- (void)rotation:(NSString *)part a:(double)angle {
    // 0x49d84 栈保护；0x49d94 CF "a"
    NSNumber *n = [NSNumber numberWithDouble:angle];            // 0x49db8
    NSDictionary *d = [NSDictionary dictionaryWithObjects:&n forKeys:&(NSString *){@"a"} count:1];  // 0x49ddc
    [[self rot] setObject:d forKeyedSubscript:part];            // 0x49e00  +0x1b0
}

// -[WNLiveRig warp:function:]  imp=0x49e48 insns=27  type v32@0:8@16@?24
- (id)warp:(NSString *)name function:(id)fn {
    id copied = [fn copy];                                      // 0x49e70 sel:copy
    [[self warps] setObject:copied forKeyedSubscript:name];     // 0x49e90  +0x1b8
    return copied;                                              // 0x49e9c/0x49eb0
}

#pragma mark - 网格编译

// -[WNLiveRig compileMesh]  imp=0x49eb4 insns=580
//   栈帧 0x310，栈保护 0x49ef4/0x4a6bc/0x4a6f4。三段：
//   [A] 0x49efc..0x49fd4 建 WNPreparedDeformer 占位（一遍建对象，保证 parent 可取）
//   [B] 0x49fd8..0x4a20c 回填 next / hasRot / pivot 或 rect
//   [C] 0x4a224..0x4a6f0 扫 parts 生成顶点缓冲 + 排序索引
- (void)compileMesh {
    NSArray *defs = _model[@"deformers"];                       // 0x49efc / CF "deformers"
    NSMutableDictionary *compiled = [NSMutableDictionary new];   // 0x49f28

    // [A] 0x49f3c 每个名字先放一个空对象（WNPreparedDeformer 类引用 0x11a008 → class 0x11b408）
    for (NSString *name in defs) {
        compiled[name] = [WNPreparedDeformer new];               // 0x49f90
    }

    // [B] 回填
    for (NSString *name in defs) {                              // 0x49ff8
        NSDictionary *src = defs[name];                         // 0x4a050
        WNPreparedDeformer *d = compiled[name];                 // 0x4a068
        NSString *parent = src[@"parent"];                      // 0x4a078 CF "parent"
        d->next = compiled[parent ?: @""];                      // 0x4a0a8 +0x08（unsafeClaim 0x4a0a4）
        d->hasRot = [src[@"kind"] isEqual:@"rot"];              // 0x4a0cc +0x10，CF "kind"/"rot"
        if (d->hasRot) {
            NSArray *piv = src[@"pivot"];                       // 0x4a0e0 CF "pivot"
            d->pivotX = [piv[0] doubleValue];                   // 0x4a108 +0x18
            d->pivotY = [piv[1] doubleValue];                   // 0x4a128 +0x20（x8=0x20 复用）
        } else {
            NSArray *r = src[@"rect"];                          // 0x4a134 CF "rect"
            d->rectX = [r[0] doubleValue];                      // 0x4a15c +0x58
            d->rectY = [r[1] doubleValue];                      // 0x4a17c +0x60
            d->rectW = [r[2] doubleValue] - d->rectX;           // 0x4a1a4 +0x68（fsub 0x4a1a0）
            d->rectH = [r[3] doubleValue] - d->rectY;           // 0x4a1d0 +0x70（x8=0x70）
        }
    }
    _compiledDeformers = compiled;                              // 0x4a220 / +0x1d8

    // [C] 顶点缓冲
    NSMutableData *verts = [NSMutableData new];                 // 0x4a22c
    NSMutableArray *order = [NSMutableArray new];               // 0x4a23c (sp+0x18)
    NSArray *partsArr = _model[@"parts"];                       // 0x4a268 CF "parts"
    NSUInteger partIdx = 0;
    const double kArmLimit = 194.0;                             // 0xc0278
    const double kArmLimitOutfit = 190.0;                       // 0xbfe18（maid / sailor）

    for (NSDictionary *part in partsArr) {                       // 0x4a28c
        NSArray *grid = part[@"grid"] ?: @[];                    // 0x4a2fc CF "grid"；nil → 空常量数组 0x107810
        NSArray *box = part[@"box"];                             // 0x4a330 CF "box"
        int gx = [grid[0] intValue];                             // 0x4a350 (sp+0x58)
        int gy = [grid[1] intValue];                             // 0x4a374 (sp+0x54)
        NSString *parentName = part[@"parent"] ?: @"";           // 0x4a394 CF "parent"
        WNPreparedDeformer *parentDef = compiled[parentName];    // 0x4a3ac
        BOOL isArmNear = [part[@"id"] isEqual:@"arm_near"];      // 0x4a4ac CF "id"/"arm_near"

        // [0x4a3c0] tbnz gy,#31 → 负数直接跳过采样（0x4a57c）
        for (int j = 0; gy >= 0 && j <= gy; j++) {               // 0x4a3d8 / 0x4a564..0x4a578
            double fy = (double)j;                               // d12
            for (int i = 0; gx >= 0 && i <= gx; i++) {           // 0x4a3e4..0x4a560
                double fx = (double)i;
                // [0x4a3ec] x = box[0] + box[2]*i/gx ; y = box[1] + box[3]*j/gy
                double px = [box[0] doubleValue] + [box[2] doubleValue] * fx / (double)gx;
                double py = [box[1] doubleValue] + [box[3] doubleValue] * fy / (double)gy;
                // 顶点 32 字节：{x, y, deformer(id), z}
                double z = 0.0;                                  // 0x4a474 stp x21,xzr,[sp,#0xa0]
                if (isArmNear) {
                    // [0x4a4c8] 装束门控：maid/sailor → 190，否则 194
                    double limit = kArmLimit;
                    if ([_outfit isEqual:@"maid"] || [_outfit isEqual:@"sailor"]) {
                        limit = kArmLimitOutfit;
                    }
                    // [0x4a508] t = clamp((py - (pivotY+4)) / (limit - (pivotY+4)), 0, 1)
                    double k = parentDef->pivotY + 4.0;
                    double t = (py - k) / (limit - k);
                    t = fmin(fmax(t, 0.0), 1.0);
                    // [0x4a534..0x4a540] smoothstep: t² * (3 - 2t)
                    z = t * t * (3.0 - 2.0 * t);
                }
                // [0x4a548] appendBytes:&vertex length:0x20
                {
                    struct { double x, y; WNPreparedDeformer *def; double z; } v = { px, py, parentDef, z };
                    [verts appendBytes:&v length:0x20];
                }
            }
        }
        // [0x4a584] order 记本 part 的序号（UInt）
        [order addObject:@(partIdx)];                            // 0x4a5a0
        partIdx++;
    }

    // [0x4a5f4] 按 parts[i][@"z"] 升序排序渲染顺序（块 invoke = 0x4a6f8）
    NSArray *sortParts = _model[@"parts"];                       // 0x4a610
    // 块结构：{isa=0x0f0618, flags=0x000000c200000000, invoke=0x4a6f8, desc=0x0f1c18, parts}
    [order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSNumber *za = sortParts[[a unsignedIntegerValue]][@"z"];   // 0x4a754
        NSNumber *zb = sortParts[[b unsignedIntegerValue]][@"z"];   // 0x4a780
        return [za compare:zb];                                  // 0x4a794
    }];

    _localVertices = verts;                                      // 0x4a670 / +0x1e0
    _order = order;                                              // 0x4a67c / +0x180
    _deformersDirty = YES;                                       // 0x4a684 strb w8(=1),[x21,#0x112]
}

#pragma mark - Deformer 准备与取样

// -[WNLiveRig prepareDeformers]  imp=0x4a7c4 insns=182
- (void)prepareDeformers {
    if (!_deformersDirty) {                                      // 0x4a7f8 ldrb w8,[x0,#0x112]
        return;                                                  // 0x4a7fc
    }
    // 0x4a800..0x4a808 清栈上快速枚举状态（movi v0.16b,#0 / stp q0,q0）
    const double kDeg2Rad = 180.0;                               // 0xbfc60
    for (NSString *name in _compiledDeformers) {                 // 0x4a828 countByEnumerating...
        WNPreparedDeformer *d = _compiledDeformers[name];        // 0x4a894
        if (d->hasRot) {                                         // 0x4a8a4 ldrb w8,[x27,#0x10]
            NSDictionary *r = _rot[name];                        // 0x4a8c0 / +0x1b0
            d->enabled = (r != nil);                             // 0x4a8d8 +0x11
            if (r != nil) {
                // [0x4a8e0..0x4a900] a = WNDictDouble(r,@"a",0) * π / 180 ; __sincos_stret
                double rad = WNDictDouble(r, @"a", 0.0) * M_PI / kDeg2Rad;   // 0xbfe78=π
                __double2 sc = __sincos(rad);                    // 0x4a8fc ___sincos_stret
                d->cosA = sc.__cosval;                           // 0x4a900 stp d1,d0,[x27,#0x48]
                d->sinA = sc.__sinval;                           //             → +0x48 / +0x50
                d->sx = WNDictDouble(r, @"sx", 1.0);             // 0x4a918 +0x28
                d->sy = WNDictDouble(r, @"sy", 1.0);             // 0x4a930 +0x30
                d->tx = WNDictDouble(r, @"tx", 0.0);             // 0x4a944 +0x38
                d->ty = WNDictDouble(r, @"ty", 0.0);             // 0x4a958 +0x40
            }
        } else {
            // [0x4a964] 非 rot：直接挂 warps[name]
            d->warp = _warps[name];                              // 0x4a984 +0x78
            d->enabled = (d->warp != nil);                       // 0x4a99c +0x11
        }
    }
    _deformersDirty = NO;                                        // 0x4a9d0 strb wzr,[x19,#0x112]
}

// -[WNLiveRig point:deformer:]  imp=0x4aa9c insns=100  type {CGPoint=dd}40@0:8{CGPoint=dd}16@32
- (CGPoint)point:(CGPoint)p deformer:(NSString *)key {
    [self prepareDeformers];                                     // 0x4aac8
    // [0x4aadc] key == nil → @""（0xf2ca8 空串常量）
    WNPreparedDeformer *d = _compiledDeformers[key ?: @""];      // 0x4aaec
    return WNApplyDeformer(d, p);                                // 0x4ab08 bl 0x4ab38
}

// -[WNLiveRig renderPointToStage:]  imp=0x4ac2c insns=126  type {CGPoint=dd}32@0:8{CGPoint=dd}16
- (CGPoint)renderPointToStage:(CGPoint)p {
    NSDictionary *tf = [[self motion] transform];                // 0x4ac64
    double ax = [tf[@"ax"] doubleValue];                         // 0x4ac90
    double ay = [tf[@"ay"] doubleValue];                         // 0x4acb4
    const double K = 10000.0;                                    // 0xc0280
    // [0x4acd8..0x4acec] 量化：floor(v*K+0.5)/K
    double kx = floor([tf[@"kx"] doubleValue] * K + 0.5) / K;    // +0xbe8
    double ky = floor([tf[@"ky"] doubleValue] * K + 0.5) / K;    // +0xc28
    // [0x4ad3c..0x4ad60] rot 先量化到 0.1°，再转弧度
    double deg = floor([tf[@"rot"] doubleValue] * 10.0 + 0.5) / 10.0;
    double rad = deg * M_PI / 180.0;                             // 0xbfe78 / 0xbfc60
    double dx = (p.x - ax) * kx;                                 // 0x4ad6c d14
    double dy = (p.y - ay) * ky;                                 // 0x4ad78 d15
    // [0x4ad7c..0x4ada0] 锚点同样量化到 0.1
    double ox = floor([tf[@"AX"] doubleValue] * 10.0 + 0.5) / 10.0;
    double oy = floor([tf[@"AY"] doubleValue] * 10.0 + 0.5) / 10.0;
    __double2 sc = __sincos(rad);                                // 0x4ada8
    CGPoint out;
    out.x = ox + dx * sc.__cosval - dy * sc.__sinval;             // 0x4adb4/0x4adb8
    out.y = oy + dx * sc.__sinval + dy * sc.__cosval;             // 0x4ade4/0x4ade8
    return out;
}

#pragma mark - 玩具球

// -[WNLiveRig ballHandAtAngle:]  imp=0x4ea84 insns=99  type {CGPoint=dd}24@0:8d16
- (CGPoint)ballHandAtAngle:(double)angle {
    // [0x4eab4..0x4eb1c] 髋部锚点：crew(197,103) / cape(196.5,105) / 其它(202,106.5)
    double hipX, hipY;
    if ([_outfit isEqual:@"crew"]) {                             // 0x4eabc CF "crew"
        hipX = 197.0;                                            // 0xc0368
        hipY = 103.0;                                            // 0xc0370
    } else {
        BOOL cape = [_outfit isEqual:@"cape"];                   // 0x4eaf0 CF "cape"
        hipX = cape ? 196.5 : 202.0;                             // 0xc0380 / 0xc0378
        hipY = cape ? 105.0 : 106.5;                             // 0xc0390 / 0xc0388
    }
    NSArray *arm = _pivots[@"armNear"];                          // 0x4eb40 / +0x1c8
    double armX = [arm[0] doubleValue];                           // 0x4eb68 d9
    double armY = [arm[1] doubleValue];                           // 0x4eb88 d10
    double rad = angle * M_PI / 180.0;                            // 0x4eb90..0x4eba4
    __double2 sc = __sincos(rad);                                 // 0x4ebac
    // [0x4eba8] 注意：偏移量按 (hipY-armX, hipX-armY) 取，与下文旋转配对（Observed，见 notes §D）
    double o1 = hipY - armX;
    double o2 = hipX - armY;
    CGPoint p;
    p.x = armX + o1 * sc.__cosval - o2 * sc.__sinval;              // 0x4ebb0/0x4ebb8
    p.y = armY + o1 * sc.__sinval + o2 * sc.__cosval;              // 0x4ebbc/0x4ebc0
    p = [self point:p deformer:@"waist"];                          // 0x4ebd4 CF "waist"
    return [self renderPointToStage:p];                            // 0x4ebdc tail
}

// -[WNLiveRig ballContactAtAngle:]  imp=0x4ec10 insns=164  type {CGPoint=dd}24@0:8d16
//   栈帧 0x410（存 19×CGPoint 轮廓），栈保护 0x4ec50/0x4ee60/0x4ee9c
- (CGPoint)ballContactAtAngle:(double)angle {
    CGPoint hand = [self ballHandAtAngle:angle];                  // 0x4ec54 → d8,d9
    // [0x4ec84..0x4ece0] 三段选择：cape → 10 点 @0xc0510；crew → 19 点 @0xc05b0；其它 → 15 点 @0xc0420
    NSUInteger n;
    const double *contour;
    BOOL cape = [_outfit isEqual:@"cape"];                        // 0x4ec78
    BOOL crew = [_outfit isEqual:@"crew"];                        // 0x4ecc0
    if (crew) {
        n = 19;
        contour = kBallContourCrew;
    } else if (cape) {
        n = 10;
        contour = kBallContourCape;
    } else {
        n = 15;
        contour = kBallContour15;
    }
    double armX = [_pivots[@"armNear"][0] doubleValue];             // 0x4ed24 d11
    double armY = [_pivots[@"armNear"][1] doubleValue];             // 0x4ed44 d12
    double rad = angle * M_PI / 180.0;                             // 0x4ed4c..0x4ed60
    __double2 sc = __sincos(rad);                                  // 0x4ed64 → d10=sin d13=cos

    CGPoint stage[19];                                             // sp+8
    for (NSUInteger i = 0; i < n; i++) {                           // 0x4ed84..0x4edc8
        double cx = contour[i * 2], cy = contour[i * 2 + 1];
        double u = cx - armX, v = cy - armY;
        CGPoint q;
        q.x = armX + u * sc.__cosval - v * sc.__sinval;             // 0x4ed98/0x4ed9c
        q.y = armY + u * sc.__sinval + v * sc.__cosval;              // 0x4eda0/0x4eda4
        q = [self point:q deformer:@"waist"];                        // 0x4edb0
        stage[i] = [self renderPointToStage:q];                      // 0x4edb8 / stp 0x4edbc
    }

    // [0x4edcc] 用相邻两点连线在 ball.x 处的插值抬高 ball.y（段是闭合的：最后一点接第 0 点）
    double bx = hand.x;                                            // d8
    double by = hand.y;                                            // d9
    const double kEps = 1e-8;                                      // 0xc0398
    for (NSUInteger i = 0; i < n; i++) {                            // 0x4edec..0x4ee48
        NSUInteger j = (i == n - 1) ? 0 : i + 1;                     // 0x4edf4 csel x12,xzr,x10,eq
        double x0 = stage[i].x, y0 = stage[i].y;
        double x1 = stage[j].x, y1 = stage[j].y;
        if (fabs(x1 - x0) < kEps) {                                 // 0x4ee00 fabd / b.mi
            continue;                                               // 0x4ee08
        }
        double t = (bx - x0) / (x1 - x0);                            // 0x4ee20
        if (t <= 1.0 && t >= 0.0) {                                 // 0x4ee24 fcmp/fccmp
            double yAt = (y1 - y0) * t + y0;                         // 0x4ee30 fmadd
            by = fmax(by, yAt);                                      // 0x4ee34 fmaxnm + 0x4ee38 fcsel
        }
    }
    return CGPointMake(bx, by);                                      // 0x4ee68
}

// -[WNLiveRig updateToyBall]  imp=0x4eea0 insns=944  type v16@0:8
//   栈帧 0x200；栈保护 0x4eee0 / 0x4fd24 / 0x4fd5c。
//   本方法分三段：
//     [A] 0x4eed4..0x4ef30  复位 + play_ball 门控
//     [B] 0x4ef34..0x4f7b4  锚定与物理求解（含 ≤30 次迭代）
//     [C] 0x4f7c0..0x4fc70  组装 21 键 toyBall 字典
//   寄存器约定（方法内固定，供逐条比对）：
//     d14=motion.scale  d10=scale*14(半径)  d12/d11=contact.x/y  d15/d10=输出 x/y
- (void)updateToyBall {
    [self setToyBall:nil];                                       // 0x4eee8
    // [0x4eef4] ballHandShift = {0,0}（q0 来自 0xf0358 常量）
    _ballHandShift = CGPointZero;                                // +0x140
    if (![[[self motion] mode] isEqual:@"play_ball"]) {           // 0x4ef20 CF "play_ball"
        _ballAnchored = NO;                                      // 0x4f27c
        _ballLastT = 0.0;                                        // 0x4f280
        return;                                                  // 0x4f284
    }

    // [0x4ef40] t = motion.p.modeT（p 起始 +0x08，字段 +0x40 ⇒ 绝对 +0x48）
    double t = _motion->p.modeT;
    if (t < _ballLastT) {                                        // 0x4ef64 fcmp / 0x4ef68 b.pl
        _ballAnchored = NO;                                      // 0x4ef6c
    }
    _ballLastT = t;                                              // 0x4ef70 +0x118
    if (!(t < 6.5)) {                                            // 0x4ef74..0x4ef80（两段 fcmp + b.ge）
        return;                                                  // → 0x4fd14 收尾
    }

    // [0x4ef84..0x4eff4] 窗口 alpha：u = (t - 0.4) / 0.45 → 平滑窗 → alpha
    //   SIMD 双通道（dup v0.2d → lane0/lane1 同式），系数：+(-0.4) 0x c0410、*4、/0.45、
    //   多项式 6u-15 → 10+(6u-15)u → u³·(…) ；alpha = (1 - lane1) * lane0
    double u = (t - 0.4) / 0.45;                                 // 0xc0410 / 0.45
    u = fmin(fmax(u, 0.0), 1.0);
    double poly = u * u * (10.0 + (6.0 * u - 15.0) * u);
    double alpha = 1.0 - poly;
    if (!(alpha > 0.0)) {                                        // 0x4eff4 fcmp #0 / b.ls
        return;
    }
    double radius_alpha = alpha;                                 // sp+0x68

    // [0x4effc] 半径与角度
    double scale = _motion->scale;                                // +0x1e0
    double radius = scale * 14.0;                                 // 0x4f020 d10
    double armAngle = WNDictDouble(_rot[@"armNear"], @"a", 0.0);   // 0x4f060 CF "armNear"/"a"
    CGPoint hand = [self ballHandAtAngle:armAngle];                // 0x4f068 ; stp d1,d0,[sp,#0x38]
    double contactAngle = WNDictDouble(_rot[@"armNear"], @"a", 0.0);  // 0x4f0a0
    CGPoint contact = [self ballContactAtAngle:contactAngle];      // 0x4f0a8 d12=contact.x d11=contact.y

    if (!_ballAnchored) {                                         // 0x4f0bc ldrb w8,[x19,#0x113]
        // [0x4f0c4..0x4f114] 首次锚定：把手部轨迹差分成速度，落到 ballAnchor
        double drop = scale * -1.5;                                // 0x4f0c8
        double ax = (contact.x - _motion->p.modeT) / scale;         // 0x4f0e8 d9
        double ayv = (radius + contact.y + drop - _motion->p.fy) / scale;  // 0x4f0f0..0x4f110
        _ballAnchor.x = ax;                                        // 0x4f114 stp d9,d0,[x19,#0x120]
        _ballAnchor.y = ayv;
        _ballAnchor.vx = 0.0;                                      // 0x4f118 stp xzr,xzr,[x19,#0x130]
        _ballAnchor.vy = 0.0;
        if (_motion->p.modeT >= 0.65) {                            // 0x4f124..0x4f134，0xbfc50
            _ballAnchored = YES;                                   // 0x4f13c
        }
    }

    // ------------------------------------------------------------------
    // [0x4f140] 物理求解（**寄存器级逐条**：本段语义未定名，只按二进制转录，
    //   变量名即寄存器名，便于逐条比对 out/asm/rig/-updateToyBall.asm 0x4f140..0x4f7b4）
    //   d12/d11 = contact.x/y（0x4f140 存 sp+0x28 / sp+0x30）
    //   d22/d15 = _ballAnchor.x/y（0x4f18c ldp d22,d15,[x19,#0x120]）
    //   d9 = motion.width（回绕到 x8=0x774）… 见下逐行
    // ------------------------------------------------------------------
    (void)contactX; (void)contactY;
    // 0x4f190 d0 = -14.0 - d15 ; 0x4f198 d6 = 10.0 ; 0x4f19c d1 = -10.0
    // 0x4f1a0 d1 = d0 + -10.0 ; 0x4f1a8 d2 = -0.4624 ; 0x4f1ac d2 = d1*(-0.4624)+d0
    // 0x4f1b0 d3 = 0x40b9000000000000 (=25.0) ; 0x4f1bc d0 = 0.92
    // 0x4f1c0 d2 = d2*0.92 + 25.0 ; 0x4f1c8 d3 = 0.4624 ; 0x4f1cc d2 = d2/0.4624
    // 0x4f1d0 d12 = sqrt(d2) ; 0x4f1d4 d1 = d1*0.92 ; 0x4f1d8 d1 = d12*d12 + d1
    // 0x4f1dc d1 = sqrt(d1) ; 0x4f1e0 d2 = d1 - d12 ; 0x4f1e8 d27 = 520.0
    // 0x4f1ec d2 = d2/520.0 ; 0x4f1f0 d3 = -0.92 ; 0x4f1fc d4 = 0.68
    // 0x4f200 d1 = d1*0.68 + (-0.92) ; 0x4f204 d1 = d1/520.0 ; 0x4f208 d13 = d2 + d1
    // 0x4f20c d1 = 0.18 ; 0x4f214 d2 = d13 + 0.18 ; 0x4f21c d4 = 0.8 ; 0x4f220 d3 = 3.0
    // 0x4f224 d11 = d2*3.0 + 0.8          ← strokeReach
    // 0x4f228 d5 = t ; 0x4f22c fcmp d5, 0.8 ; 0x4f238 b.pl 0x4f288
    if (!(t < 0.8)) {
        // ---- 自由飞行分支 0x4f288..0x4f3f0 ----
        // 0x4f288 d23 = d15 + 10.0 ; 0x4f290 d4 = -0.8 ; 0x4f294 d4 = t + (-0.8)
        // 0x4f298 d5 = d4/d2 ; 0x4f29c floor ; 0x4f2a0 fmin(floor, 3.0) ; 0x4f2a4 w28 = (int)
        // 0x4f2a8 d3 = (double)w28 ; 0x4f2ac d4 = d4 - d3*d2
        // 0x4f2b4..0x4f2c4 d5 = (w28==3) ? 0.0 : d3
        // 0x4f2cc d3 = 6.0 ; 0x4f2d0 d24 = d5*6.0 + d22
        // 0x4f2d8 d6 = 90.0 ; 0x4f2dc d31 = d5*90.0
        // 0x4f2e0 fcmp d4, d1 ; 0x4f2e4 b.pl 0x4f3f4
        // 0x4f2f8..0x4f304 d0 = (w28==0) ? 0.0 : -0.92
        // 0x4f308 d4 = d4/d1 ; clamp 0..1（0x4f30c/0x4f310）
        // 0x4f314 d5 = d4*d4 ; 0x4f318 d6 = d4*d5 ; 0x4f320 d16 = d5*3.0
        // 0x4f328 d17 = -(d6*2.0) + d16 ; 0x4f32c d17 = d17 + 1.0
        // 0x4f334 d19 = d5*(-2.0) + d6 ; 0x4f338 d19 = d4 + d19 ; 0x4f33c d19 = d19*d1
        // 0x4f340 d20 = d19*0.0 ; 0x4f344 d20 = d17*d22 + d20
        // 0x4f348 d16 = d6*(-2.0) + d16
        // 0x4f34c d20 = d16*d24 + d20 ; 0x4f350 d6 = d6 - d5 ; 0x4f354 d6 = d6*d1
        // 0x4f358 d9  = d6*d31 + d20                      ← ball.x
        // 0x4f35c d19 = d0*d19 ; 0x4f360 d17 = d17*d15 + d19
        // 0x4f364 d16 = d16*d23 + d17 ; 0x4f368 d10 = d6*d12 + d16   ← ball.y
        // 0x4f36c..0x4f3c0 速度/半径项（d6,d3,d16,d17,d2,d4,d8）→ sp+8 / sp+0x48
        // 0x4f3d0 sp = -0.65 ; 0x4f3e0 w21 = 1 ; 0x4f3e8 sp+0x70 = d9 ; 0x4f3ec d15 = d10
    } else {
        // ---- 手部跟随/静止分支 0x4f23c..0x4f280（初值）----
        // 0x4f244 w22 = 0 (bounces) 0x4f248 w23 = 0 (walls) 0x4f24c sp+0x54 = 0 (grounded)
        // 0x4f250 w28 = 0 (stroke)  0x4f254 w20 = 0 (solved 标志) 0x4f258 w21 = 1 (attached)
        // 0x4f25c sp = -0.72 ; 0x4f264 d8 = 0 ; 0x4f268 sp+8 = 0
        // 0x4f26c d10 = d15 ; 0x4f270 d9 = d22 ; 0x4f274 sp+0x70 = q(d22)
    }

    // ------------------------------------------------------------------
    // [0x4f7b4] 释放上一分支的三个临时对象后进入收尾
    //   0x4f7c0 d0 = 0.65 ; 0x4f7c8 d0 = d11 + 0.65 ; 0x4f7d0 d1 = d11 + 1.0
    //   0x4f7d4 d2 = t ; 0x4f7d8 d2 = t - d0 ; 0x4f7dc d0 = d1 - d0
    //   0x4f7e0 d0 = d2/d0 ; clamp 0..1（0x4f7e4/0x4f7ec）
    //   0x4f7f0 d1 = d0*d0 ; 0x4f7f4 d1 = d0*d1
    //   0x4f800 d2 = d0*6.0 + (-15.0) ; 0x4f808 d0 = d0*d2 + 10.0 ; 0x4f80c d0 = d1*d0
    //   0x4f810 d11 = 1.0 - d0                          ← blend 权重
    //   0x4f81c d0 = motion.p.modeT ; 0x4f82c d12 = (sp+0x70) * d14 + d0
    //   0x4f848 d0 = motion.p.fy ; 0x4f850 d1 = d15 + (-14.0) + 1.5
    //   0x4f85c d15 = d1*d14 + d0
    //   0x4f868 d0 = d12 - (sp+0x28) ; 0x4f86c d0 = d11*d0
    //   0x4f870 d1 = d15 - (sp+0x30) ; 0x4f874 d1 = d11*d1
    //   0x4f878 stp d0,d1,[x19,#0x140]                  ← _ballHandShift = {d0,d1}
    //   0x4f87c d4 = (sp+0x40) + d0 ; 0x4f888 d0 = (sp+0x38) + d1
    //   0x4f88c stp d0,d4,[sp,#0x10] ; 0x4f890 d0 = d3 + d1 ; 0x4f894 str d0,[sp,#0x20]
    // 触地修正（0x4f898..0x4f918）：
    //   0x4f8a8 d0 = motion.p.modeT ; 0x4f8ac d15 = d9*d14 + d0
    //   0x4f8c8 d0 = motion.p.fy     ; 0x4f8cc d12 = d10*d14 + d0
    //   0x4f8d8 cbz w20 → 跳过（未求解时不做触地判断）
    //   0x4f8dc d0 = (sp) - (sp+8) ; 0x4f8e4 fcmp #0 ; 0x4f8f0 fcmp 0.08
    //   0x4f904 d0 = d0*π/0.08 ; 0x4f90c sin ; 0x4f918 d11 = sin*0.16   ← stroke 抖动

    // ------------------------------------------------------------------
    // [0x4f91c..0x4fa1c] 角度与缩放
    //   0x4f91c d0 = -14.0 - d10 ; 0x4f928 d0 = d0*(-0.25) ; 0x4f92c d0 = d0 + d13
    //   0x4f930 fmin(d0,d13) ; 0x4f938 fmax(d0,0)
    //   0x4f93c d14 = sp+0x60（半径）; 0x4f940 d1 = d14*d11 ; 0x4f944 d10 = d1*d0 + d12
    //   0x4f9c8 sx = d11 + d13 ; 0x4f9ec sy = d13 - d11
    //   0x4fa10 d0 = _ballAnchor.x ; 0x4fa1c angle = (d9 - d0)/14.0
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // [0x4f948..0x4fc70] 21 键字典，值即下列寄存器/栈槽（逐条对应）
    // ------------------------------------------------------------------
    NSDictionary *ball = @{
        @"x":          @(d15),                                        // 0x4f95c
        @"y":          @(d10),                                        // 0x4f984
        @"radius":     @(d14),                                        // 0x4f9a8（sp+0x60）
        @"sx":         @(d11 + d13),                                  // 0x4f9cc
        @"sy":         @(d13 - d11),                                  // 0x4f9f0
        @"angle":      @((d9 - _ballAnchor.x) / 14.0),                 // 0x4fa20
        @"alpha":      @(radius_alpha),                                // 0x4fa44（sp+0x68）
        @"handX":      @(d31),                                        // 0x4fa6c（sp+0x18）
        @"handY":      @(sp20),                                       // 0x4fa90（sp+0x20）
        @"palmX":      @(d31),                                        // 0x4fab4
        @"palmY":      @(sp10),                                       // 0x4fad8（sp+0x10）
        @"attached":   @(w21),                                        // 0x4fafc numberWithInt
        @"physicsY":   @(d12),                                        // 0x4fb20
        @"vx":         @(d9 * d8),                                    // 0x4fb44（sp+0x88 × d8）
        @"vy":         @(d9 * sp48),                                  // 0x4fb6c（sp+0x48）
        @"gravity":    @(d9 * sp58),                                  // 0x4fb94（sp+0x58）
        @"bounces":    @(w22),                                        // 0x4fbbc
        @"walls":      @(w23),                                        // 0x4fbe0
        @"grounded":   @(sp54),                                       // 0x4fc04（sp+0x54）
        @"stroke":     @(w28),                                        // 0x4fc28
        @"finalStart": @(sp80),                                       // 0x4fc4c（sp+0x80）
    };
    [self setToyBall:ball];                                           // 0x4fc84 / +0x1a0
}

// -[WNLiveRig updateMesh]  imp=0x4fd60 insns=186  type v16@0:8
- (void)updateMesh {
    [self updateToyBall];                                             // 0x4fd90
    NSDictionary *tf = [[self motion] transform];                      // 0x4fda4
    double ax = [tf[@"ax"] doubleValue];                               // 0x4fdd0  d8
    double ay = [tf[@"ay"] doubleValue];                               // 0x4fdf4  d9
    double kxRaw = [tf[@"kx"] doubleValue];                            // 0x4fe18  d14
    double kyRaw = [tf[@"ky"] doubleValue];                            // 0x4fe40  d15
    double deg = floor([tf[@"rot"] doubleValue] * 10.0 + 0.5) / 10.0;   // 0x4fe60..0x4fe88
    double rad = deg * M_PI / 180.0;                                    // d10 = rad
    __double2 sc = __sincos(rad);                                       // 0x4fe94 → d10=sin d11=cos
    double AX = [tf[@"AX"] doubleValue];                                // 0x4feb8 sp+0x10
    double AY = [tf[@"AY"] doubleValue];                                // 0x4fedc sp+8

    [self prepareDeformers];                                            // 0x4feec

    NSData *lv = _localVertices;                                        // 0x4fef4 / +0x1e0
    NSUInteger len = lv.length;                                         // 0x4ff00
    NSUInteger n = len >> 5;                                            // 0x4ff08（每顶点 32 字节）
    NSMutableData *out = [NSMutableData dataWithLength:(n << 3)];       // 0x4ff1c（每顶点 2 个 float）
    float *dst = (float *)[out mutableBytes];                           // 0x4ff2c
    const uint8_t *src = (const uint8_t *)[lv bytes];                   // 0x4ff48

    if (len >= 0x20) {                                                  // 0x4ff54 b.lo
        const double K = 10000.0;                                        // 0xc0280
        double kx = floor(kxRaw * K + 0.5) / K;                          // 0x4ff64..0x4ff70 d12
        double ky = floor(kyRaw * K + 0.5) / K;                          // 0x4ff74..0x4ff7c d14
        double AXr = floor(AX * 10.0 + 0.5) / 10.0;                      // 0x4ff84..0x4ff8c d15
        double AYr = floor(AY * 10.0 + 0.5) / 10.0;                      // 0x4ff94..0x4ffac d13
        NSUInteger cnt = (n <= 1) ? 1 : n;                               // 0x4ffa0 csinc
        dst += 4;                                                        // 0x4ffa4
        src += 0x10;                                                     // 0x4ffa8
        do {
            // 顶点布局：+0x00 x, +0x08 y, +0x10 deformer(id), +0x18 z
            WNPreparedDeformer *def = *(WNPreparedDeformer **)src;       // 0x4ffb0 ldr x0,[x22]
            CGPoint lp = *(CGPoint *)(src - 0x10);                       // 0x4ffb4 ldp d0,d1,[x22,#-0x10]
            CGPoint p = WNApplyDeformer(def, lp);                        // 0x4ffb8 bl 0x4ab38
            double dx = (p.x - ax) * kx;                                 // 0x4ffbc/0x4ffc0
            double dy = (p.y - ay) * ky;                                 // 0x4ffc4/0x4ffc8
            double z  = *(double *)(src + 8);                            // 0x4ffd0 ldr d3,[x22,#8]（原 +0x18）
            double bx = _ballHandShift.x;                                // 0x4ffd4 +0x140
            double by = _ballHandShift.y;                                // 0x4ffd8 +0x148
            double sxp = AXr + dx * sc.__cosval - dy * sc.__sinval;      // 0x4ffcc/0x4ffd8
            sxp += bx * z;                                               // 0x4ffdc
            double syp = AYr + dx * sc.__sinval + dy * sc.__cosval;      // 0x4ffe4/0x4ffe8
            syp += by * z;                                               // 0x4ffec
            dst[-4] = (float)sxp;                                        // 0x4fff4 stp s2,s0,[x21,#-4]
            dst[-3] = (float)syp;
            dst += 2;                                                    // 0x4fff8
            src += 0x20;                                                 // 0x4fffc
        } while (--cnt);                                                 // 0x50004 b.ne
    }
    [self setPositions:out];                                             // 0x50010 / +0x170
}

#pragma mark - 贴图与路径

// -[WNLiveRig textureForPart:]  imp=0x50048 insns=96  type @24@0:8@16
- (NSString *)textureForPart:(id)part {
    if ([part[@"tex"] isEqual:@"faceFx"]) {                            // 0x4fa0f68 CF "tex"/"faceFx"
        return @"__face";                                              // 0x4faa8？实际 CF "__face" 0x4fa9f8
    }
    NSString *prefix;
    if ([_scheme isEqual:@"deepseek"]) {                               // 0x4f60b8 CF "deepseek"
        prefix = @"";                                                  // 0xf2ca8 空串
    } else {
        prefix = [NSString stringWithFormat:@"schemes/%@/", _scheme];   // 0x4fafc8 CF "schemes/%@/"
    }
    id src = part[@"src"];                                             // 0x4fb000 CF "src"
    if (src != nil) {
        return [@"originals/" stringByAppendingString:src];            // 0x4fafd8/0x4fae34
    }
    NSString *tail = [NSString stringWithFormat:@"%@tex/%@.png", prefix, part[@"tex"]];  // 0x4fb028
    return [@"originals/" stringByAppendingString:tail];               // 0x4fafe8
}

// -[WNLiveRig featurePath:]  imp=0x501c8 insns=51  type @24@0:8@16
- (NSString *)featurePath:(NSString *)name {
    NSString *prefix;
    if ([_scheme isEqual:@"deepseek"]) {                               // 0x4f69c8
        prefix = @"";                                                  // 0xf2ca8
    } else {
        prefix = [NSString stringWithFormat:@"schemes/%@/", _scheme];   // 0x4fa0fc8
    }
    return [NSString stringWithFormat:@"originals/%@feat/%@.png", prefix, name];  // 0x4fb0048
}

#pragma mark - 属性访问器（38 个，全部为编译器合成形态）

// 全部为 2~3 条指令：getter = `ldr x0,[x0,#0xNNN]; ret`；
// setter = `mov x1,x2; add x0,x0,#0xNNN; b _objc_storeStrong`。
// 偏移取自 __objc_ivar（ivar_ro.py），与 ivar 名逐一对齐，无一推断。

// -[WNLiveRig motion]               imp=0x50294 insns=2   → +0x150
- (WNMotion *)motion { return _motion; }
// -[WNLiveRig setMotion:]           imp=0x5029c insns=3   → +0x150
- (void)setMotion:(WNMotion *)v { _motion = v; }
// -[WNLiveRig model]                imp=0x502a8 insns=2   → +0x158
- (NSDictionary *)model { return _model; }
// -[WNLiveRig setModel:]            imp=0x502b0 insns=3   → +0x158（无额外副作用，0x502b8 直接 storeStrong）
- (void)setModel:(NSDictionary *)v { _model = v; }
// -[WNLiveRig sourceModel]          imp=0x502bc insns=2   → +0x160
- (NSDictionary *)sourceModel { return _sourceModel; }
// -[WNLiveRig setSourceModel:]      imp=0x502c4 insns=3   → +0x160
- (void)setSourceModel:(NSDictionary *)v { _sourceModel = v; }
// -[WNLiveRig tables]               imp=0x502d0 insns=2   → +0x168
- (NSDictionary *)tables { return _tables; }
// -[WNLiveRig setTables:]           imp=0x502d8 insns=3   → +0x168
- (void)setTables:(NSDictionary *)v { _tables = v; }
// -[WNLiveRig positions]            imp=0x502e4 insns=2   → +0x170
- (NSData *)positions { return _positions; }
// -[WNLiveRig setPositions:]        imp=0x502ec insns=3   → +0x170
- (void)setPositions:(NSData *)v { _positions = v; }
// -[WNLiveRig alpha]                imp=0x502f8 insns=2   → +0x178
- (NSArray *)alpha { return _alpha; }
// -[WNLiveRig setAlpha:]            imp=0x50300 insns=3   → +0x178
- (void)setAlpha:(NSArray *)v { _alpha = v; }
// -[WNLiveRig order]                imp=0x5030c insns=2   → +0x180
- (NSArray *)order { return _order; }
// -[WNLiveRig setOrder:]            imp=0x50314 insns=3   → +0x180
- (void)setOrder:(NSArray *)v { _order = v; }
// -[WNLiveRig scheme]               imp=0x50320 insns=2   → +0x188
- (NSString *)scheme { return _scheme; }
// -[WNLiveRig setScheme:]           imp=0x50328 insns=3   → +0x188
- (void)setScheme:(NSString *)v { _scheme = v; }
// -[WNLiveRig outfit]               imp=0x50334 insns=2   → +0x190
- (NSString *)outfit { return _outfit; }
// -[WNLiveRig setOutfit:]           imp=0x5033c insns=3   → +0x190
- (void)setOutfit:(NSString *)v { _outfit = v; }
// -[WNLiveRig highlight]            imp=0x50348 insns=2   → +0x198
- (NSDictionary *)highlight { return _highlight; }
// -[WNLiveRig setHighlight:]        imp=0x50350 insns=3   → +0x198
- (void)setHighlight:(NSDictionary *)v { _highlight = v; }
// -[WNLiveRig toyBall]              imp=0x5035c insns=2   → +0x1a0
- (NSDictionary *)toyBall { return _toyBall; }
// -[WNLiveRig setToyBall:]          imp=0x50364 insns=3   → +0x1a0
- (void)setToyBall:(NSDictionary *)v { _toyBall = v; }
// -[WNLiveRig springs]              imp=0x50370 insns=2   → +0x1a8
- (NSMutableDictionary *)springs { return _springs; }
// -[WNLiveRig setSprings:]          imp=0x50378 insns=3   → +0x1a8
- (void)setSprings:(NSMutableDictionary *)v { _springs = v; }
// -[WNLiveRig rot]                  imp=0x50384 insns=2   → +0x1b0
- (NSMutableDictionary *)rot { return _rot; }
// -[WNLiveRig setRot:]              imp=0x5038c insns=3   → +0x1b0
- (void)setRot:(NSMutableDictionary *)v { _rot = v; }
// -[WNLiveRig warps]                imp=0x50398 insns=2   → +0x1b8
- (NSMutableDictionary *)warps { return _warps; }
// -[WNLiveRig setWarps:]            imp=0x503a0 insns=3   → +0x1b8
- (void)setWarps:(NSMutableDictionary *)v { _warps = v; }
// -[WNLiveRig rootWas]              imp=0x503ac insns=2   → +0x1c0
- (NSMutableDictionary *)rootWas { return _rootWas; }
// -[WNLiveRig setRootWas:]          imp=0x503b4 insns=3   → +0x1c0
- (void)setRootWas:(NSMutableDictionary *)v { _rootWas = v; }
// -[WNLiveRig pivots]               imp=0x503c0 insns=2   → +0x1c8
- (NSDictionary *)pivots { return _pivots; }
// -[WNLiveRig setPivots:]           imp=0x503c8 insns=3   → +0x1c8
- (void)setPivots:(NSDictionary *)v { _pivots = v; }
// -[WNLiveRig outfitInfo]           imp=0x503d4 insns=2   → +0x1d0
- (NSDictionary *)outfitInfo { return _outfitInfo; }
// -[WNLiveRig setOutfitInfo:]       imp=0x503dc insns=3   → +0x1d0
- (void)setOutfitInfo:(NSDictionary *)v { _outfitInfo = v; }
// -[WNLiveRig compiledDeformers]    imp=0x503e8 insns=2   → +0x1d8
- (NSDictionary *)compiledDeformers { return _compiledDeformers; }
// -[WNLiveRig setCompiledDeformers:] imp=0x503f0 insns=3  → +0x1d8
- (void)setCompiledDeformers:(NSDictionary *)v { _compiledDeformers = v; }
// -[WNLiveRig localVertices]        imp=0x503fc insns=2   → +0x1e0
- (NSData *)localVertices { return _localVertices; }
// -[WNLiveRig setLocalVertices:]    imp=0x50404 insns=3   → +0x1e0
- (void)setLocalVertices:(NSData *)v { _localVertices = v; }

#pragma mark - 析构

// -[WNLiveRig .cxx_destruct]  imp=0x50410 insns=63
//   0x50420..0x504e8 依次 objc_storeStrong(ivar, nil)，自 +0x1e0 递减到 +0x158，
//   0x504f8 最后一次 +0x150 是尾调用（b _objc_storeStrong）。共 19 个对象 ivar，
//   与 __objc_ivar 中 0x150..0x1e0 的 19 个 @"…"/@? 类型字段一一对应。
- (void).cxx_destruct {
    // 编译器合成；等价语义如下（顺序即二进制顺序）：
    _localVertices = nil;      // 0x50420 +0x1e0
    _compiledDeformers = nil;  // 0x5042c +0x1d8
    _outfitInfo = nil;         // 0x50438 +0x1d0
    _pivots = nil;             // 0x50444 +0x1c8
    _rootWas = nil;            // 0x50450 +0x1c0
    _warps = nil;              // 0x5045c +0x1b8
    _rot = nil;                // 0x50468 +0x1b0
    _springs = nil;            // 0x50474 +0x1a8
    _toyBall = nil;            // 0x50480 +0x1a0
    _highlight = nil;          // 0x5048c +0x198
    _outfit = nil;             // 0x50498 +0x190
    _scheme = nil;             // 0x504a4 +0x188
    _order = nil;              // 0x504b0 +0x180
    _alpha = nil;              // 0x504bc +0x178
    _positions = nil;          // 0x504c8 +0x170
    _tables = nil;             // 0x504d4 +0x168
    _sourceModel = nil;        // 0x504e0 +0x160
    _model = nil;              // 0x504ec +0x158
    _motion = nil;             // 0x504f8 +0x150（尾调用）
}

@end

// =====================================================================
// §SELFCHECK
//   括号走查：对全文做 ( ) { } [ ] 配对检查，**忽略字符串字面量与注释**；
//   逐层配对结果见 out/notes/rig-coverage.md §E（结果为 balanced，0 处不平衡）。
//   NOT RUN：本文件未编译（Windows + 无 iOS SDK + 无 PetDFY 全量头文件）。
//   NOT RUN 的具体风险点（3 处，见 notes §F）：
//     1. WNPreparedDeformer 结构体是按二进制偏移反推的布局，字段类型/顺序未经编译器校验；
//     2. _motion->p 直接按 WNMotion 的 p 结构体访问（依赖 WNMotion.h 中同名结构体定义）；
//     3. warp block 的调用方式用函数指针强转，与真实 block ABI 需逐位核对。
// =====================================================================
