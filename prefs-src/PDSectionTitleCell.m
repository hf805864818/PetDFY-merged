//
//  PDSectionTitleCell.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  参照：out/prefs_asm/0000{9e40,a18c,a22c,a2e8,a35c,a36c,a380}_PDSectionTitleCell_*.asm
//  父类 PSTableCell；自有 ivar 仅 sectionTitleLabel（ivar offset 0x8，@0x583c8）。
//
#import "PDSectionTitleCell.h"

// _PDLocalizedString @0x23cac：dylib 内部全局函数，签名 (NSString *key) -> NSString *
// NOT-DEFINED-IN-THIS-TU：重建工程需在别处提供实现，详见 out/notes/prefs-cells.md。
extern NSString *PDLocalizedString(NSString *key);

// 头文件里 sectionTitleLabel 是 @property；但二进制同时有手写 getter/setter（0xa35c / 0xa36c），
// clang 因此不会自动合成 ivar —— 存储放这里（对应二进制 ivar offset 0x8）。
@interface PDSectionTitleCell () {
    UILabel *_sectionTitleLabel;
}
@end

@implementation PDSectionTitleCell

// imp 0x009e40  types @40@0:8q16@24@32
- (id) initWithStyle:(NSInteger)a1 reuseIdentifier:(id)a2 specifier:(id)a3 {
    // 0x9e98 mov x2, #0：style 被硬编码为 0（UITableViewCellStyleDefault），a1 未使用
    self = [super initWithStyle:0 reuseIdentifier:a2 specifier:a3];
    if (self) {                                                          // 0x9eac cbz
        // 0x9eb0..0x9ec4: [specifier setProperty:@(32.0) forKey:@"height"]
        //   @0x53610 = NSConstantDoubleNumber 实例，值 32.0 在其 +8；key @0x4e018 "height"
        [(PSSpecifier *)a3 setProperty:@(32.0) forKey:@"height"];
        [self setSelectionStyle:0];                                      // 0x9ec8（UITableViewCellSelectionStyleNone）
        [self setUserInteractionEnabled:NO];                             // 0x9ed4（w2 = #0）
        [[self textLabel] setHidden:YES];                                // 0x9ee0（w2 = #1）
        [[self detailTextLabel] setHidden:YES];                          // 0x9efc（w2 = #1）
        // 0x9f18..0x9f34: [[UILabel alloc] initWithFrame:CGRectZero]（@0x581b8；CGRectZero @0x4c080）
        _sectionTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        // 0x9f50..0x9f7c: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]（@0x581c0 / d1 @0x4c108）
        [_sectionTitleLabel setFont:[UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]];
        // 0x9f84..0x9fa0: [UIColor secondaryLabelColor]（@0x58190）
        [_sectionTitleLabel setTextColor:[UIColor secondaryLabelColor]];
        [_sectionTitleLabel setNumberOfLines:1];                         // 0x9fa8（w2 = #1）
        [_sectionTitleLabel setTranslatesAutoresizingMaskIntoConstraints:NO];  // 0x9fb4（w2 = #0）
        [[self contentView] addSubview:_sectionTitleLabel];               // 0x9fc0..0x9fd4
        [NSLayoutConstraint activateConstraints:@[                          // @0x58240，count = 3
            // 0x9fe8..0xa024: leading == contentView.leading + 20.0
            [_sectionTitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                             constant:20.0],
            // 0xa034..0xa06c: trailing <= contentView.trailing - 20.0（lessThanOrEqualTo，非 equal）
            [_sectionTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor
                                                                       constant:-20.0],
            // 0xa07c..0xa0b4: centerY == contentView.centerY + 2.0
            [_sectionTitleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor
                                                            constant:2.0],
        ]];
        [self pd_refreshTitleWithSpecifier:a3];                           // 0xa134
    }
    return self;
}

// imp 0x00a18c  types v24@0:8@16
- (void) refreshCellContentsWithSpecifier:(id)a1 {
    [super refreshCellContentsWithSpecifier:a1];                          // 0xa19c..0xa1cc（sel @0x57788）
    [[self textLabel] setHidden:YES];                                     // 0xa1d0..0xa1e4（w2 = #1）
    [[self detailTextLabel] setHidden:YES];                               // 0xa1ec..0xa200（w2 = #1）
    [self pd_refreshTitleWithSpecifier:a1];                               // 0xa208
}

// imp 0x00a22c  types v24@0:8@16
- (void) pd_refreshTitleWithSpecifier:(id)a1 {
    // 0xa248..0xa258: [specifier propertyForKey:@"label"]（@0x4cff8）
    NSString *title = [a1 propertyForKey:@"label"];
    // 0xa260: PDLocalizedString(title) → 0xa280: [[self sectionTitleLabel] setText:...]
    [[self sectionTitleLabel] setText:PDLocalizedString(title)];
    // 0xa28c..0xa2b0: [self setAccessibilityLabel:[[self sectionTitleLabel] text]]
    [self setAccessibilityLabel:[[self sectionTitleLabel] text]];
    // 0xa2bc..0xa2cc: [self setAccessibilityTraits:UIAccessibilityTraitHeader]（GOT @0x4c0f0）
    [self setAccessibilityTraits:UIAccessibilityTraitHeader];
}

// imp 0x00a2e8  types v16@0:8
- (void)tintColorDidChange {
    [super tintColorDidChange];                                           // 0xa2fc..0xa314（sel @0x58100）
    // 0xa318..0xa340: [[self sectionTitleLabel] setTextColor:[UIColor secondaryLabelColor]]
    [[self sectionTitleLabel] setTextColor:[UIColor secondaryLabelColor]];
}

// imp 0x00a35c  types @16@0:8
- (id)sectionTitleLabel {
    return _sectionTitleLabel;                                            // 0xa35c: ivar offset 0x8（@0x583c8）
}

// imp 0x00a36c  types v24@0:8@16
- (void) setSectionTitleLabel:(id)a1 {
    _sectionTitleLabel = a1;                                              // 0xa36c: objc_storeStrong
}

// imp 0x00a380  types v16@0:8
- (void)dealloc {
    // 0xa380..0xa390: objc_storeStrong(&sectionTitleLabel, nil)
    _sectionTitleLabel = nil;
}

@end