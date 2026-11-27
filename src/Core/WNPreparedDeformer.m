//
//  WNPreparedDeformer.m — 逆向还原实现
//
//  还原依据：
//    · ivar_list 完整（instanceSize=128，16 个字段，偏移与类型精确）
//    · RENDER_ANALYSIS.md 中对 fcn.0004d934 的指令序列分析
//
//  重要说明：字段布局 100% 真实；transformPoint: 的数学是**基于反汇编
//  推断的等价实现**，不是逐寄存器追踪的精确还原。fcn.0004d934 用
//  fmadd/fmsub 做四角双线性混合，比"旋转+缩放+平移"更复杂，
//  当前实现保留了核心语义（局部归一化 → 绕轴心旋转 → 缩放 → 平移）。
//
//  ivar 布局：
//    +8   WNPreparedDeformer * parent   父变形器（骨骼链）
//    +16  BOOL rotation                 是否启用旋转
//    +17  BOOL active                   是否激活
//    +24  double px, py                 轴心（旋转/缩放中心）
//    +40  double sx, sy                 缩放
//    +56  double tx, ty                 平移
//    +72  double cosine, sine           预存三角值
//    +88  double x0, y0                 影响区域左上角
//    +104 double width, height          影响区域尺寸
//    +120 block  warp                   自定义扭曲函数
//

#import "WNPreparedDeformer.h"
#import <math.h>

@implementation WNPreparedDeformer

/// 预计算三角值（prepareDeformers 阶段调用一次，渲染时零三角函数）
/// [非二进制] 该类在二进制只有 .cxx_destruct（零方法）；ivar 布局完整（16 字段，
/// 偏移 0x08..0x78 与 fcn.0004d934 的 `[x19,#0x10]`/`[x19,#0x18]` 逐字段对齐）。
/// 以下三个方法是该 C 函数的 OO 封装，数学为等价推断。
- (void)prepareWithAngle:(double)angle {
    cosine = cos(angle);
    sine = sin(angle);
}

/// 顶点变形：世界坐标 → 局部归一化 → 绕轴心旋转 → 缩放 → 平移 → 回世界坐标
/// [非二进制] fcn.0004d934 的 OO 封装，见上方 prepareWithAngle: 说明。
- (CGPoint)transformPoint:(CGPoint)p {
    if (!active) return p;

    if (rotation) {
        double dx = (p.x - px) * sx;
        double dy = (p.y - py) * sy;
        return CGPointMake(px + dx * cosine - dy * sine + tx,
                           py + dx * sine + dy * cosine + ty);
    }

    if (warp && width > 0.0 && height > 0.0) {
        typedef struct { double x, y; } PDWarpVec2;
        PDWarpVec2 (^fn)(double, double, double, double) = (PDWarpVec2 (^)(double, double, double, double))warp;
        double u = fmax(0.0, fmin(1.0, (p.x - x0) / width));
        double v = fmax(0.0, fmin(1.0, (p.y - y0) / height));
        PDWarpVec2 delta = fn(u, v, p.x, p.y);
        if (isfinite(delta.x) && isfinite(delta.y)) {
            return CGPointMake(p.x + delta.x, p.y + delta.y);
        }
    }
    return p;
}

/// 沿骨骼链自顶向下累积变形
/// [非二进制] 同上；全树零调用。
- (CGPoint)transformPointThroughChain:(CGPoint)p {
    NSMutableArray<WNPreparedDeformer *> *chain = [NSMutableArray array];
    WNPreparedDeformer *node = parent;
    while (node && chain.count < 64) {   // 断链保护
        [chain addObject:node];
        node = node->parent;
    }
    CGPoint q = p;
    for (WNPreparedDeformer *d in [chain reverseObjectEnumerator]) {
        q = [d transformPoint:q];
    }
    return [self transformPoint:q];
}

@end
