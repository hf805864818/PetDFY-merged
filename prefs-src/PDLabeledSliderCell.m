//
//  PDLabeledSliderCell.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  参照：out/prefs_asm/0000{8f64,9074,90d8,9120,9168,9698,97c4}_PDLabeledSliderCell_*.asm
//  父类 PSSliderTableCell（ivar 全部继承，本类无自有 ivar，@0x58368 类对象 instanceSize=8）。
//
#import "PDLabeledSliderCell.h"
#import <math.h>
#import <objc/runtime.h>

// _PDLocalizedString @0x23cac：dylib 内部全局函数，签名 (NSString *key) -> NSString *
// NOT-DEFINED-IN-THIS-TU：重建工程需在别处提供实现，详见 out/notes/prefs-cells.md。
extern NSString *PDLocalizedString(NSString *key);

// UIView 私有方法（二进制 0x25700 处调用；本类与 PDSwitchWithInfoCell 共用同一套弹窗定位逻辑）
@interface UIView (PDViewControllerLookup)
- (UIViewController *)_viewControllerForAncestor;
@end

// 0x58b28 处的静态变量地址被用作关联对象键（objc_getAssociatedObject / objc_setAssociatedObject）
static char kPDValueLabelTapKey;

// 0x955c：递归收集 view 树中的 UILabel，父视图先入数组再递归子视图（先序）
static void PDCollectLabels(UIView *view, NSMutableArray *labels) {
    if ([view isKindOfClass:[UILabel class]]) {   // 0x959c: [UILabel class] @0x581b8
        [labels addObject:view];                 // 0x95b8
    }
    for (UIView *subview in [view subviews]) {    // 0x95d0
        PDCollectLabels(subview, labels);        // 0x9628
    }
}

@implementation PDLabeledSliderCell

// imp 0x008f64  types v24@0:8@16
- (void) controlChanged:(id)a1 {
    // 0x8f8c: [[self specifier] propertyForKey:@"pdIntegerValue"] -> boolValue（@0x4df38）
    if ([[[self specifier] propertyForKey:@"pdIntegerValue"] boolValue]) {
        // 0x8fb8: objc_opt_class(UISlider @0x58260) + isKindOfClass
        if ([a1 isKindOfClass:[UISlider class]]) {
            UISlider *slider = (UISlider *)a1;
            // 0x8fe8 先取 maximumValue、0x8ff4 再取 minimumValue（保持源码顺序）
            float maxValue = slider.maximumValue;
            float minValue = slider.minimumValue;
            float value = roundf(slider.value);   // 0x9004 frinta s0,s0（四舍五入，非截断）
            value = MAX(value, minValue);         // 0x9008 fcmp/fcsel mi
            value = MIN(value, maxValue);         // 0x9010 fcmp/fcsel mi
            [slider setValue:value];              // 0x9018
        }
    }
    [super controlChanged:a1];                    // 0x9030..0x9048 msgSendSuper2（sel @0x580d8）
    [self setNeedsLayout];                        // 0x904c
}

// imp 0x009074  types v16@0:8
- (void)layoutSubviews {
    [super layoutSubviews];                       // 0x9088..0x90a0（sel @0x580e0）
    [[self contentView] setClipsToBounds:NO];      // 0x90a8..0x90b8（w2 = #0）
    [self pd_enableValueLabelInput];              // 0x90c4
}

// imp 0x0090d8  types v24@0:8@16
- (void) refreshCellContentsWithSpecifier:(id)a1 {
    [super refreshCellContentsWithSpecifier:a1];  // 0x90f8..0x9104（sel @0x57788）
    [self setNeedsLayout];                        // 0x910c
}

// imp 0x009120  types v16@0:8
- (void)prepareForReuse {
    [super prepareForReuse];                      // 0x9140..0x914c（sel @0x580e8）
    [self setNeedsLayout];                        // 0x9154
}

// imp 0x009168  types v16@0:8
- (void)pd_enableValueLabelInput {
    // 0x91a8: [NSMutableArray array]（@0x58180）
    NSMutableArray *labels = [NSMutableArray array];
    PDCollectLabels([self contentView], labels);  // 0x91c0 contentView → 0x91d0 bl 0x955c

    UILabel *valueLabel = nil;                    // sp+0x10
    CGFloat bestMaxX = -DBL_MAX;                  // 0x9218 fmov d12,#0xFFEFFFFFFFFFFFFF（= -DBL_MAX）
    for (UILabel *label in labels) {
        NSString *text = [label text];                                                    // 0x9254
        // 0x9260: [NSCharacterSet whitespaceAndNewlineCharacterSet]（@0x58168）
        // 0x9290: 逗号 → 点号（@0x4dff8 "," → @0x4cd98 "."）
        NSString *normalized = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                                   stringByReplacingOccurrencesOfString:@"," withString:@"."];
        if ([normalized length] == 0) {           // 0x92a8 cbz
            continue;
        }
        NSScanner *scanner = [NSScanner scannerWithString:normalized];   // 0x92b0（@0x58270）
        double scanned = 0;
        if (![scanner scanDouble:&scanned]) {     // 0x92d0
            continue;
        }
        if (![scanner isAtEnd]) {                 // 0x92dc
            continue;
        }
        // 0x92e8 fabs + 0x9300 fcmp vs +INF，b.eq / b.vs 命中即跳过（NaN 同路径）
        if (fabs(scanned) == INFINITY) {
            continue;
        }
        // 0x930c: 以 label.superview 为祖先坐标系，把 frame 换算到 contentView 坐标系
        CGRect converted = [[label superview] convertRect:[label frame] toView:[self contentView]];
        CGFloat maxX = CGRectGetMaxX(converted);  // 0x9360
        if (maxX > bestMaxX) {                    // 0x9370 fcmp d8,d12 / b.le
            bestMaxX = maxX;
            valueLabel = label;                   // 0x9378..0x9384（retain 后存 sp+0x10）
        }
    }
    if (!valueLabel) {                            // 0x93cc cbz x25
        return;
    }
    // 0x93d4..0x93fc: [[self specifier] propertyForKey:@"pdIntegerValue"] -> boolValue
    if ([[[self specifier] propertyForKey:@"pdIntegerValue"] boolValue]) {
        // 0x9400..0x9428: [[self control] isKindOfClass:[UISlider class]]
        if ([[self control] isKindOfClass:[UISlider class]]) {
            // 0x9444..0x9480: [NSString stringWithFormat:@"%.0f", (double)control.value]（@0x4df58）
            [valueLabel setText:[NSString stringWithFormat:@"%.0f",
                                 (double)[(UISlider *)[self control] value]]];
        }
    }
    // 0x948c: objc_getAssociatedObject(valueLabel, &kPDValueLabelTapKey)
    id existing = objc_getAssociatedObject(valueLabel, &kPDValueLabelTapKey);
    [self pd_preventValueLabelClipping:valueLabel];   // 0x94b0
    if (existing) {                                   // 0x94b4 cbnz x20
        return;
    }
    [valueLabel setUserInteractionEnabled:YES];       // 0x94b8（w2 = #1）
    // 0x94c4..0x94dc: [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pd_promptForSliderValue)]（@0x58268 / sel @0x580f0）
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(pd_promptForSliderValue)];
    [valueLabel addGestureRecognizer:tap];            // 0x94e4
    // 0x94f0: objc_setAssociatedObject(..., w3 = #1 = OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    objc_setAssociatedObject(valueLabel, &kPDValueLabelTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// imp 0x009698  types v24@0:8@16
- (void) pd_preventValueLabelClipping:(id)a1 {
    UILabel *label = (UILabel *)a1;
    [label setNumberOfLines:1];                                    // 0x96bc
    [label setAdjustsFontSizeToFitWidth:YES];                       // 0x96c4（w2 = #1）
    [label setMinimumScaleFactor:0.65];                            // 0x96d0: 0x3FE4CCCCCCCCCCCD = 0.65
    [label setAllowsDefaultTighteningForTruncation:YES];            // 0x96e0（w2 = #1）
    [label setLineBreakMode:NSLineBreakByClipping];                 // 0x96ec（w2 = #2）
    [label setClipsToBounds:NO];                                   // 0x96f8（w2 = #0）
    [[label superview] setClipsToBounds:NO];                        // 0x9704..0x9718
    // 0x9720..0x9734: max(bounds.height, 1.0)
    CGFloat height = MAX(CGRectGetHeight(label.bounds), 1.0);
    // 0x9738..0x9748: sizeThatFits:(DBL_MAX, height) → frintp（向上取整）
    CGFloat width = ceil([label sizeThatFits:CGSizeMake(CGFLOAT_MAX, height)].width) + 6.0;  // 0x974c +6.0
    CGRect frame = [label frame];                                   // 0x9758
    if (width > CGRectGetWidth(frame)) {                            // 0x976c fcmp/b.le
        // 0x9788..0x97a0: 右边界固定，向左扩宽；y/height 不变
        [label setFrame:CGRectMake(CGRectGetMaxX(frame) - width,
                                   frame.origin.y,
                                   width,
                                   frame.size.height)];
    }
}

// imp 0x0097c4  types v16@0:8
- (void)pd_promptForSliderValue {
    // 0x97ec 取一次 [self control] 判类，0x9818 再取一次（源码两次消息）
    if (![[self control] isKindOfClass:[UISlider class]]) {
        return;
    }
    UISlider *slider = (UISlider *)[self control];
    if (!slider) {                                    // 0x982c
        return;
    }
    // 0x9830..0x98cc: isSegmented(@0x4df78) || pdIntegerValue(@0x4df38)，短路求值
    BOOL isInteger = [[[self specifier] propertyForKey:@"isSegmented"] boolValue] ||
                     [[[self specifier] propertyForKey:@"pdIntegerValue"] boolValue];
    NSString *format = isInteger ? @"%.0f" : @"%g";   // 0x98d0 / 0x98e4（@0x4df58 / @0x4df98）
    // 0x98ec..0x9914: [NSString stringWithFormat:format, (double)slider.value]
    NSString *valueText = [NSString stringWithFormat:format, (double)slider.value];
    // 0x9918..0x9948: alertControllerWithTitle: message:nil preferredStyle:1(UIAlertControllerStyleAlert)
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:PDLocalizedString(@"输入数值")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    // 0x9954..0x9994: 文本框配置 block（descriptor @0x4c5c0，invoke 0x9bc4），捕获 valueText
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        [textField setKeyboardType:UIKeyboardTypeDecimalPad];                 // 0x9be0（w2 = #8）
        [textField setText:valueText];                                       // 0x9be8
        [textField setClearButtonMode:UITextFieldViewModeWhileEditing];       // 0x9bf8（w2 = #1）
        [textField selectAll:nil];                                           // 0x9c08（x2 = 0）
    }];
    __weak PDLabeledSliderCell *weakSelf = self;      // 0x9998 objc_initWeak sp+0x58
    __weak UIAlertController *weakAlert = alert;      // 0x99a4 objc_initWeak sp+0x50
    // 0x99b0..0x99f0: 取消（@0x4d898 = 取消）style:1 = UIAlertActionStyleCancel，handler:nil
    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    // 0x9a00..0x9a88: 设置（@0x4dfd8 = 设置）style:0 = UIAlertActionStyleDefault + handler block（descriptor @0x4c5f0，invoke 0x9c20）
    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"设置")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        PDLabeledSliderCell *cell = weakSelf;                 // 0x9c44 loadWeakRetained(block+0x28)
        if (!cell) {
            return;
        }
        UIAlertController *alertRef = weakAlert;              // 0x9c54 loadWeakRetained(block+0x30)
        NSString *text = [[[alertRef textFields] firstObject] text];   // 0x9c60..0x9c80
        NSString *normalized = [text stringByReplacingOccurrencesOfString:@"," withString:@"."];  // 0x9c84
        NSScanner *scanner = [NSScanner scannerWithString:normalized]; // 0x9cb0
        double value = 0;
        if (![scanner scanDouble:&value]) {                   // 0x9cd0
            return;
        }
        if (![scanner isAtEnd]) {                             // 0x9cdc
            return;
        }
        if (fabs(value) == INFINITY) {                        // 0x9ce8..0x9cfc
            return;
        }
        value = MAX(value, (double)slider.minimumValue);       // 0x9d00..0x9d10（block+0x20 捕获的 slider）
        value = MIN(value, (double)slider.maximumValue);       // 0x9d14..0x9d24
        if (isInteger) {                                       // 0x9d28 ldrb block+0x38
            value = round(value);                              // 0x9d2c frinta
        }
        // 0x9d38..0x9d68: [[self specifier] performSetterWithValue:[NSNumber numberWithDouble:value]]
        [[cell specifier] performSetterWithValue:[NSNumber numberWithDouble:value]];
        [slider setValue:(float)value animated:YES];           // 0x9d74..0x9d80（w2 = #1）
        // 0x9d84..0x9d9c: [self refreshCellContentsWithSpecifier:[self specifier]]
        [cell refreshCellContentsWithSpecifier:[cell specifier]];
    }]];
    // 0x9a94..0x9b2c: 优先私有 _viewControllerForAncestor（sel @0x56fc8），否则 window.rootViewController，
    // 然后沿 presentedViewController 下钻到最上层，animated:YES completion:nil
    UIViewController *presenter = nil;
    if ([self respondsToSelector:@selector(_viewControllerForAncestor)]) {
        presenter = [self _viewControllerForAncestor];        // 0x9aa8..0x9ab4
    }
    if (!presenter) {                                         // 0x9ab8 cbnz
        presenter = [[self window] rootViewController];       // 0x9abc..0x9ad4
    }
    while (presenter.presentedViewController) {               // 0x9af0..0x9b18
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:alert animated:YES completion:nil];   // 0x9b2c
}

@end