//
//  PDChatPromptController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  逐方法来源：out/prefs_asm/000*_PDChatPromptController_*.asm（image base = 0）
//
#import "PDChatPromptController.h"
#import "PDSupport.h"

#import "PDChatService.h"

extern NSString *PDLocalizedString(NSString *key);   // 0x23cac
extern CFStringRef PDPreferencesDomain;              // 0x4cc00 全局变量（__DATA_CONST __const）
extern CFStringRef PDPreferencesChangedNotification; // 0x4cc08 全局变量

// 0x1f6f8 / 0x1f808 / 0x1f5d8 处接收者都是 OBJC_CLASS_$_PDChatService，即类方法

@interface PDChatPromptController () {
    UITextView *_editor;
}
@end

@implementation PDChatPromptController

// imp 0x01e90c  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = PDLocalizedString(@"系统提示词");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIBarButtonItem *saveItem =
        [[UIBarButtonItem alloc] initWithTitle:PDLocalizedString(@"保存")
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(save)];
    self.navigationItem.rightBarButtonItem = saveItem;

    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stackView = [UIStackView new];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 12.0;
    [scrollView addSubview:stackView];

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = PDLocalizedString(@"提示词模板");
    titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    [stackView addArrangedSubview:titleLabel];

    UILabel *hintLabel = [UILabel new];
    hintLabel.numberOfLines = 0;
    hintLabel.font = [UIFont systemFontOfSize:13.0];
    hintLabel.textColor = [UIColor secondaryLabelColor];
    hintLabel.text = PDLocalizedString(@"模板变量在发送请求前替换为角色状态及相关信息。点击变量可插入光标位置。");
    [stackView addArrangedSubview:hintLabel];

    self.editor = [UITextView new];
    self.editor.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.editor.layer.borderWidth = 1.0;
    self.editor.layer.borderColor = [UIColor separatorColor].CGColor;
    self.editor.layer.cornerRadius = 10.0;
    self.editor.scrollEnabled = YES;
    self.editor.delegate = self;
    self.editor.text = self.savedTemplate;
    [stackView addArrangedSubview:self.editor];

    UILabel *variablesLabel = [UILabel new];
    variablesLabel.text = PDLocalizedString(@"模板变量");
    variablesLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    [stackView addArrangedSubview:variablesLabel];

    UIStackView *variableStack = [UIStackView new];
    variableStack.axis = UILayoutConstraintAxisVertical;
    variableStack.spacing = 6.0;
    [stackView addArrangedSubview:variableStack];

    for (NSDictionary *variable in [PDChatService promptVariables]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.titleLabel.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightMedium];

        NSString *buttonTitle = [NSString stringWithFormat:@"{{%@}}   %@",
                                 variable[@"name"],
                                 PDLocalizedString(variable[@"description"])];
        [button setTitle:buttonTitle forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 0;
        button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.title = [NSString stringWithFormat:@"{{%@}}   %@",
                               variable[@"name"],
                               PDLocalizedString(variable[@"description"])];
        configuration.baseForegroundColor = [UIColor systemIndigoColor];
        configuration.background.backgroundColor =
            [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.9];
        configuration.background.cornerRadius = 7.0;
        configuration.background.strokeWidth = 1.0;
        configuration.background.strokeColor =
            [[UIColor systemIndigoColor] colorWithAlphaComponent:0.45];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 9.0, 8.0, 9.0);
        [button setConfiguration:configuration];

        button.titleLabel.numberOfLines = 0;
        button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

        button.tag = (NSInteger)[[PDChatService promptVariables] indexOfObject:variable];
        [button addTarget:self
                   action:@selector(insertVariable:)
         forControlEvents:UIControlEventTouchUpInside];
        [variableStack addArrangedSubview:button];
    }

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:PDLocalizedString(@"恢复默认提示词") forState:UIControlStateNormal];
    [resetButton addTarget:self
                    action:@selector(resetTemplate)
          forControlEvents:UIControlEventTouchUpInside];
    [variableStack addArrangedSubview:resetButton];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        [stackView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor
                                           constant:16.0],
        [stackView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor
                                              constant:-24.0],
        [stackView.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor
                                                constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor
                                                 constant:-16.0],
        [self.editor.heightAnchor constraintEqualToConstant:460.0],
    ]];
}

// imp 0x01f648  types @16@0:8
- (id)savedTemplate {
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    id stored = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("AIPromptTemplate"), PDPreferencesDomainRef());
    return [PDChatService normalizedPromptTemplate:
        [stored isKindOfClass:[NSString class]] ? stored : @""];
}

// imp 0x01f6d0  types v24@0:8@16
- (void) insertVariable:(id)a1 {
    UIControl *sender = a1;
    NSArray *variables = [PDChatService promptVariables];

    if (sender.tag < 0) {
        return;
    }
    if ((NSUInteger)sender.tag >= variables.count) {
        return;
    }

    NSString *name = [variables objectAtIndexedSubscript:(NSUInteger)sender.tag][@"name"];
    NSString *text = [NSString stringWithFormat:@"{{%@}}", name];

    [self.editor replaceRange:self.editor.selectedTextRange withText:text];
}

// imp 0x01f7f0  types v16@0:8
- (void)resetTemplate {
    NSString *template = [PDChatService defaultPromptTemplate];
    self.editor.text = template;
}

// imp 0x01f848  types v16@0:8
- (void)save {
    NSString *text = self.editor.text;

    CFPreferencesSetAppValue(CFSTR("AIPromptTemplate"), (__bridge CFStringRef)text, PDPreferencesDomainRef());
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         PDPreferencesChangedNotification,
                                         NULL, NULL, 1);

    [self.navigationController popViewControllerAnimated:YES];
}

// imp 0x01f900  types v24@0:8@16
- (void) textViewDidChange:(id)a1 {
    [a1 invalidateIntrinsicContentSize];
}

// imp 0x01f908  types @16@0:8
- (id)editor {
    return _editor;
}

// imp 0x01f918  types v24@0:8@16
- (void) setEditor:(id)a1 {
    _editor = a1;
}

@end