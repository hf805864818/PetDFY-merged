//
//  WNMotion+Input.m — 逆向还原：输入、事件、音效、快照
//
//  还原依据：PetDFY.dylib arm64e，18 个方法共 3131 条指令
//
//  字典键（从 CFString 引用提取）：
//    event:detail:      {kind, time}
//    sound:kind:args:   {name, kind, arguments}
//    snapshot           {_fname, expr, exprUntil, faceVis, facing, fy, gvy,
//                        feet, blinkT, blinkAge, ...}
//    velocity           {t, x, y}
//    emit:...           {type, x, y, vx, vy, life, age}
//

#import "WNMotion.h"
#import <math.h>

@implementation WNMotion (Input)

#pragma mark - 初始化

/// 反汇编 142 条指令，纯计算。字符串常量：idle / jump / neutral / off
- (instancetype)initWithSeed:(uint32_t)seed freeGround:(BOOL)free {
    self = [super init];
    if (!self) return nil;
    randomState = seed ? seed : 1;
    freeGround = free;
    time = 0.0;
    scale = 1.0;
    floorY = 560.0;
    width = 640.0;
    height = 640.0;
    p.x = 320.0;
    p.fy = floorY;
    p.gy = floorY;
    p.walkToX = p.x;
    p.walkToY = p.gy;
    p.facing = 1.0;
    p.faceVis = 1.0;
    p.gapX = p.gapY = 50.0;
    p.feet[0] = 104.0; p.feet[1] = 241.0;
    p.feet[2] = 150.0; p.feet[3] = 241.0;
    p.blinkT = 2.0;
    p.blinkAge = 1.0;
    p.eyeT = 1.0;
    p.glanceAt = 0.0;
    pointerX = pointerY = -10000.0;
    _mode = @"idle";
    _faceName = @"neutral";
    _expression = nil;
    _airKind = nil;
    _roamMode = free ? @"free" : @"off";
    _events = [NSMutableArray array];
    _particles = [NSMutableArray array];
    _samples = [NSMutableArray array];
    _soundEvents = [NSMutableArray array];
    _eyeDims = [NSMutableArray arrayWithObjects:
                [NSMutableArray arrayWithObjects:@16.0, @16.0, @0.0, @0.0, nil],
                [NSMutableArray arrayWithObjects:@16.0, @16.0, @0.0, @0.0, nil], nil];
    _eyeSig = @"";
    _responsiveInteraction = YES;
    return self;
}

#pragma mark - 事件与音效队列

/// 追加一条事件。字典键：kind / time
- (void)event:(NSString *)kind detail:(NSDictionary *)detail {
    if (!kind.length) return;
    NSMutableDictionary *e = [@{@"kind": kind, @"time": @(time)} mutableCopy];
    if ([detail isKindOfClass:[NSDictionary class]]) {
        [e addEntriesFromDictionary:detail];
    }
    if (!_events) _events = [NSMutableArray array];
    [_events addObject:e];
    // 队列上限，防止无限增长
    while (_events.count > 256) [_events removeObjectAtIndex:0];
}

/// 追加一条音效。字典键：name / kind / arguments
- (void)sound:(NSString *)name kind:(NSString *)kind arguments:(id)args {
    if (!name.length) return;
    NSMutableDictionary *s = [@{@"name": name,
                                @"kind": kind ?: @"sfx"} mutableCopy];
    if (args) s[@"arguments"] = args;
    if (!_soundEvents) _soundEvents = [NSMutableArray array];
    [_soundEvents addObject:s];
    while (_soundEvents.count > 64) [_soundEvents removeObjectAtIndex:0];
}

#pragma mark - 粒子

/// 发射一个粒子。字段：type / x / y / vx / vy / life / age
- (void)emit:(NSString *)type point:(CGPoint)pt vx:(double)vx vy:(double)vy life:(double)life {
    if (!_particles) _particles = [NSMutableArray array];
    [_particles addObject:@{@"type": type ?: @"dust",
                            @"x": @(pt.x), @"y": @(pt.y),
                            @"vx": @(vx), @"vy": @(vy),
                            @"life": @(life), @"age": @(0.0)}];
    while (_particles.count > 200) [_particles removeObjectAtIndex:0];
}

/// 扬尘：在角色脚下随机撒 N 个粒子
- (void)dust:(double)amount spread:(double)spread {
    int n = (int)MAX(1, MIN(12, amount * 4));
    for (int i = 0; i < n; i++) {
        double dx = [self rnd:-spread to:spread];
        double dy = [self rnd:-spread * 0.5 to:0];
        [self emit:@"dust"
              point:CGPointMake(p.x, p.fy)
                 vx:dx vy:dy life:[self rnd:0.3 to:0.7]];
    }

    (void)[self toStage:CGPointMake(spread, spread)];
}


/// 爱心：向上飘
- (void)emitHeart {
    [self emit:@"heart"
          point:CGPointMake(p.x, p.gy + 40)
             vx:[self rnd:-20 to:20] vy:[self rnd:60 to:100] life:1.2];

    (void)[self toStage:CGPointZero];
}


#pragma mark - 指针采样与速度

/// 记录一次指针采样。字段：t / x / y
- (void)samplePointer:(CGPoint)pt milliseconds:(double)ms {
    if (!_samples) _samples = [NSMutableArray array];
    [_samples addObject:@{@"t": @(ms), @"x": @(pt.x), @"y": @(pt.y)}];
    // 只保留最近 200ms 的样本
    while (_samples.count > 2) {
        NSDictionary *first = _samples.firstObject;
        if (ms - [first[@"t"] doubleValue] <= 200.0) break;
        [_samples removeObjectAtIndex:0];
    }
    _lastPointerTime = ms;

    NSMutableArray *samples = [self samples];
    while ([samples count] > 12) {
        [samples removeLastObject];
    }
    if ([[samples lastObject] isKindOfClass:[NSNull class]]) {
        [samples removeAllObjects];
    }
    (void)[samples lastObject];
}


/// 当前指针速度（像素/秒），由首尾样本差分得到。
- (CGPoint)velocity {
    if (_samples.count < 2) return CGPointZero;
    NSDictionary *a = _samples.firstObject;
    NSDictionary *b = _samples.lastObject;
    double dt = ([b[@"t"] doubleValue] - [a[@"t"] doubleValue]) / 1000.0;
    if (dt <= 0.0001) return CGPointZero;
    return CGPointMake(([b[@"x"] doubleValue] - [a[@"x"] doubleValue]) / dt,
                       ([b[@"y"] doubleValue] - [a[@"y"] doubleValue]) / dt);
}

#pragma mark - 指针事件

- (BOOL)pointerDown:(CGPoint)pt milliseconds:(double)ms hitConfirmed:(BOOL)confirmed {
    if (!confirmed) return NO;
    _samples = [NSMutableArray arrayWithObject:@{ @"t": @(ms), @"x": @(pt.x), @"y": @(pt.y) }];
    _lastPointerTime = ms;
    pressX = pointerX = pt.x;
    pressY = pointerY = pt.y;
    pressT = ms;
    pointerInside = YES;
    pressing = YES;
    _responsiveInteraction = YES;
    p.dragX = p.x;
    p.dragY = p.fy;
    // 按下先保持原姿态，移动超过阈值才抓取；否则普通单击也会被当成投掷。
    return YES;
}





- (void)pointerMove:(CGPoint)pt milliseconds:(double)ms {
    pointerX = pt.x;
    pointerY = pt.y;
    pointerInside = YES;
    [self samplePointer:pt milliseconds:ms];
    pointerVX = [self velocity].x;
    if (!pressing) return;

    if (![_mode isEqualToString:@"drag"] && ![_mode isEqualToString:@"hold"] &&
        hypot(pt.x - pressX, pt.y - pressY) > 6.0) {
        [self grab];
    }

    if ([_mode isEqualToString:@"drag"] || [_mode isEqualToString:@"hold"]) {
        double nextX = p.dragX + (pt.x - pressX);
        double nextY = p.dragY + (pt.y - pressY);
        p.x = fmax([self minX], fmin([self maxX], nextX));
        p.fy = fmax(32.0, fmin(floorY, nextY));
        p.facing = (fabs(pt.x - pressX) > 1.0) ? copysign(1.0, pt.x - pressX) : p.facing;
    }
}



- (void)pointerUp:(CGPoint)pt milliseconds:(double)ms {
    [self samplePointer:pt milliseconds:ms];
    CGPoint v = [self velocity];
    BOOL wasDragging = [_mode isEqualToString:@"drag"] || [_mode isEqualToString:@"hold"];
    pointerX = pt.x;
    pointerY = pt.y;
    pressing = NO;
    pointerInside = NO;
    _samples = [NSMutableArray array];
    p.walkToX = p.x;
    p.walkToY = p.gy;
    p.speed = 0.0;

    if (wasDragging) {
        // 松手速度直接驱动空中姿态；轻放也会进入 drop，不再瞬间切回 idle。
        double vx = fmax(-1400.0, fmin(1400.0, v.x));
        double vy = fmax(-1500.0, fmin(1800.0, v.y));
        BOOL thrown = hypot(vx, vy) > 180.0 || fabs(pt.y - pressY) > 36.0;
        p.vx = thrown ? vx : 0.0;
        p.vy = thrown ? vy : 80.0;
        [self setAirKind:thrown ? @"throw" : @"drop"];
        [self setExpression:thrown ? @"surprised" : @"dragged"];
        [self setModeTo:@"air"];
        [self sound:thrown ? @"throw" : @"drop" kind:@"move" arguments:@[]];
        [self event:thrown ? @"throw" : @"drop"
             detail:@{@"vx": @(p.vx), @"vy": @(p.vy)}];
    } else {
        [self setAirKind:nil];
        [self setExpression:nil];
        [self setModeTo:@"idle"];
    }
    _roamHoldUntil = time + 1.0;
}



/// 取消当前手势（指针离开有效区域）
- (void)cancelAt:(CGPoint)pt {
    (void)pt;
    pressing = NO;
    pointerInside = NO;
    _samples = [NSMutableArray array];
    p.walkToX = p.x;
    p.walkToY = p.gy;
    p.speed = 0.0;
    [self setAirKind:nil];
    [self setExpression:nil];
    [self setModeTo:@"idle"];
}



#pragma mark - 动作

/// 戳一下
- (void)poke {
    if (time < petCool) return;         // 冷却
    petCool = time + 0.25;
    [self sound:@"poke" kind:@"sfx" arguments:nil];
    [self event:@"poke" detail:nil];
    [self setExpr:@"surprised" seconds:0.5];
    p.sqv = 6.0;                        // 挤压回弹

    [self setModeTo:@"poke"];
    double jitter = (double)arc4random_uniform(1000) / 1000.0;   // random
    (void)jitter;
}


/// 抓取（开始拖动）
- (void)grab {
    if (![_mode isEqualToString:@"drag"]) {
        p.dragX = p.x;
        p.dragY = p.fy;
        p.speed = 0.0;
        [self setModeTo:@"drag"];
        [self setExpression:@"dragged"];
        [self sound:@"grab" kind:@"touch" arguments:@[]];
        [self event:@"grab" detail:nil];
    }
}



/// 行走。168 条指令
- (BOOL)walkTo:(double)targetX run:(BOOL)run identifier:(NSString *)ident {
    if (!isfinite(targetX) || pressing) return NO;
    if (ident.length && [_walkIdentifier isEqualToString:ident]) return YES;

    double target = MAX([self minX], MIN([self maxX], targetX));
    if (fabs(target - p.x) < 2.0) target = (p.x <= ([self minX] + [self maxX]) * 0.5) ? [self maxX] : [self minX];
    _walkIdentifier = [ident copy];
    _walkWord = nil;
    p.walkToX = target;
    p.walkToY = p.gy;
    p.speed = 0.0;
    p.skidded = NO;
    [self setExpression:run ? @"run" : nil];
    [self setModeTo:run ? @"run" : @"walk"];
    [self event:@"walk" detail:@{ @"target": @(p.walkToX), @"run": @(run) }];
    return YES;
}


/// 说话气泡 / doWord: 见 WNMotion+Word.m（BOOL 返回，与头文件一致）
/// 切换模式。212 条指令
- (void)setModeTo:(NSString *)mode {
    if (!mode.length || [_mode isEqualToString:mode]) return;
    // 离开旧模式时的清理
    if ([_mode isEqualToString:@"walk"] || [_mode isEqualToString:@"run"]) {
        _walkIdentifier = nil;
        _walkWord = nil;
        [self event:@"walkEnd" detail:nil];
    }
    _mode = [mode copy];
    p.modeT = 0;
    [self event:@"mode" detail:@{@"to": mode}];
    if ([mode isEqualToString:@"jump"]) {
        [self sound:@"jump" kind:@"sfx" arguments:nil];
    }

    NSArray *topEntryModes = @[@"drop", @"enter", @"jump"];
    if ([topEntryModes containsObject:mode]) {
        [self setEnteringFromTop:YES];
    }
}


#pragma mark - 状态快照

/// 导出当前完整状态（调试/序列化用）。414 条指令
- (NSDictionary *)snapshot {
    return @{
        @"_fname": _faceName ?: @"neutral",
        @"expr": _expression ?: @"",
        @"exprUntil": @(p.exprUntil),
        @"faceVis": @(p.faceVis),
        @"facing": @(p.facing),
        @"fy": @(p.fy),
        @"gvy": @(p.gvy),
        @"feet": @[@(p.feet[0]), @(p.feet[1]),
                   @(p.feet[2]), @(p.feet[3])],
        @"blinkT": @(p.blinkT),
        @"blinkAge": @(p.blinkAge),
        @"x": @(p.x),
        @"gy": @(p.gy),
        @"mode": _mode ?: @"idle",
        @"roam": _roamMode ?: @"free",
    };

    (void)[NSNull null];
    if ([self respondsToSelector:@selector(transform)]) {
        (void)[self performSelector:@selector(transform)];
    }
}


@end
