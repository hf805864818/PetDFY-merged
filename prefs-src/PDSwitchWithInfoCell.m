//
//  PDSwitchWithInfoCell.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  参照：out/prefs_asm/0000{a394,a57c,a7ac,a81c,a88c,a89c,a8b0}_PDSwitchWithInfoCell_*.asm
//  父类 PSSwitchTableCell；自有 ivar 仅 infoButton（ivar offset 0x10，@0x583cc）。
//
#import "PDSwitchWithInfoCell.h"

// _PDLocalizedString @0x23cac：dylib 内部全局函数，签名 (NSString *key) -> NSString *
// NOT-DEFINED-IN-THIS-TU：重建工程需在别处提供实现，详见 out/notes/prefs-cells.md。
extern NSString *PDLocalizedString(NSString *key);

// UIView 私有方法（二进制 0x25700 处调用）
@interface UIView (PDViewControllerLookup)
- (UIViewController *)_viewControllerForAncestor;
@end

// 头文件里 infoButton 是 @property；但二进制同时有手写 getter/setter（0xa88c / 0xa89c），
// clang 因此不会自动合成 ivar —— 存储放这里（对应二进制 ivar offset 0x10）。
@interface PDSwitchWithInfoCell () {
    UIButton *_infoButton;
}
@end

@implementation PDSwitchWithInfoCell

// imp 0x00a394  types @40@0:8q16@24@32
- (id) initWithStyle:(NSInteger)a1 reuseIdentifier:(id)a2 specifier:(id)a3 {
    // 0xa3d0..0xa3dc: style 原样透传（x2 未被改写），sel @0x580f8
    self = [super initWithStyle:a1 reuseIdentifier:a2 specifier:a3];
    if (self) {                                                       // 0xa3e4 cbz
        // 0xa3e8..0xa3f4: [UIButton buttonWithType:4]（@0x58278；4 = UIButtonTypeInfoDark）
        _infoButton = [UIButton buttonWithType:UIButtonTypeInfoDark];
        [_infoButton setTranslatesAutoresizingMaskIntoConstraints:NO];  // 0xa410（w2 = #0）
        // 0xa41c..0xa430: action sel @0x58108 = pd_infoButtonTapped，controlEvents 0x40 = UIControlEventTouchUpInside
        [_infoButton addTarget:self
                        action:@selector(pd_infoButtonTapped)
              forControlEvents:UIControlEventTouchUpInside];
        [[self contentView] addSubview:_infoButton];                   // 0xa434..0xa448
        [NSLayoutConstraint activateConstraints:@[                      // @0x58240，count = 2
            // 0xa45c..0xa490: centerY == contentView.centerY（无 constant）
            [_infoButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            // 0xa4a0..0xa4d8: trailing == contentView.trailing - 4.0
            [_infoButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                       constant:-4.0],
        ]];
    }
    return self;
}

// imp 0x00a57c  types v16@0:8
- (void)pd_infoButtonTapped {
    // 0xa59c..0xa5b8: title = [[self specifier] propertyForKey:@"infoTitle"]（@0x4d058）
    NSString *title = [[self specifier] propertyForKey:@"infoTitle"];
    if ([title length] == 0) {                                        // 0xa5c0 cbnz
        // 0xa5cc..0xa5f0: 回退到 specifier 的 "label"（@0x4cff8）
        title = [[self specifier] propertyForKey:@"label"];
    }
    // 0xa600..0xa620: message = [[self specifier] propertyForKey:@"infoMessage"]（@0x4d078）
    NSString *message = [[self specifier] propertyForKey:@"infoMessage"];
    if ([message length] == 0) {                                      // 0xa628 cbnz
        message = @"";                                                // 0xa638（@0x4d158）
    }
    NSString *localizedTitle = PDLocalizedString(title);              // 0xa640
    // 0xa650..0xa670: 把字面 "\\n" 两字符序列还原成真实换行（@0x4e038 = "\\n"，@0x4e058 = "\n"）
    NSString *localizedMessage = [PDLocalizedString(message) stringByReplacingOccurrencesOfString:@"\\n"
                                                                                       withString:@"\n"];
    // 0xa680..0xa694: alertControllerWithTitle:message:preferredStyle:1（UIAlertControllerStyleAlert，@0x581f8）
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localizedTitle
                                                                   message:localizedMessage
                                                            preferredStyle:UIAlertControllerStyleAlert];
    // 0xa6a0..0xa6e0: 只用一条 action：@"好"（@0x4d7f8）style:1 = UIAlertActionStyleCancel，handler:nil（@0x58200）
    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    // 0xa6ec..0xa774: 与 PDLabeledSliderCell 完全相同的顶层 VC 定位 + present
    UIViewController *presenter = nil;
    if ([self respondsToSelector:@selector(_viewControllerForAncestor)]) {
        presenter = [self _viewControllerForAncestor];
    }
    if (!presenter) {                                                 // 0xa710 cbnz
        presenter = [[self window] rootViewController];               // 0xa714..0xa72c
    }
    while (presenter.presentedViewController) {                       // 0xa734..0xa760
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:alert animated:YES completion:nil];   // 0xa774
}

// imp 0x00a7ac  types v16@0:8
- (void)tintColorDidChange {
    [super tintColorDidChange];                                       // 0xa7c0..0xa7d8（sel @0x58100）
    // 0xa7dc..0xa800: [infoButton setTintColor:[self tintColor]]
    [[self infoButton] setTintColor:[self tintColor]];
}

// imp 0x00a81c  types v24@0:8@16
- (void) refreshCellContentsWithSpecifier:(id)a1 {
    [super refreshCellContentsWithSpecifier:a1];                      // 0xa83c..0xa848（sel @0x57788）
    // 0xa84c..0xa870: [infoButton setTintColor:[self tintColor]]
    [[self infoButton] setTintColor:[self tintColor]];
}

// imp 0x00a88c  types @16@0:8
- (id)infoButton {
    return _infoButton;                                               // 0xa88c: ivar offset 0x10（@0x583cc）
}

// imp 0x00a89c  types v24@0:8@16
- (void) setInfoButton:(id)a1 {
    _infoButton = a1;                                                 // 0xa89c: objc_storeStrong
}

// imp 0x00a8b0  types v16@0:8
- (void)dealloc {
    // 0xa8b0..0xa8c0: objc_storeStrong(&infoButton, nil)
    _infoButton = nil;
}

@end