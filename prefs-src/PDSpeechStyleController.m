//
//  PDSpeechStyleController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/000075d4_..、00007c60_..、00007e44_..、00007e54_..、00007e68_..
//
#import "PDSpeechStyleController.h"

extern NSString *PDLocalizedString(NSString *key);
extern id PDAIPreference(id key, id fallback);            // imp 0x133d8
extern NSString *PDAIString(id value);                    // imp 0x1329c
extern void PDAIWritePreferences(NSDictionary *values);   // imp 0x1343c

@interface PDSpeechStyleController () {
    // 二进制中 -editor / -setEditor: 是直接读写 ivar（_OBJC_IVAR_$_PDSpeechStyleController._editor），
    // 两个存取器都手写，故 ivar 显式声明。
    UITextView *_editor;
}
@end

@implementation PDSpeechStyleController

// imp 0x0075d4  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"说话风格")];
    [[self view] setBackgroundColor:[UIColor systemBackgroundColor]];

    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc] initWithTitle:PDLocalizedString(@"保存")
                                                                 style:UIBarButtonItemStyleDone   // 2
                                                                target:self
                                                                action:@selector(save)];
    [[self navigationItem] setRightBarButtonItem:saveItem];

    UILabel *label = [UILabel new];
    [label setTranslatesAutoresizingMaskIntoConstraints:NO];
    [label setNumberOfLines:0];
    [label setFont:[UIFont systemFontOfSize:13.0]];
    [label setTextColor:[UIColor secondaryLabelColor]];
    [label setText:PDLocalizedString(@"描述语气、情绪和语速，例如“像朋友聊天一样，语气亲切、稍微开心一点，语速正常”。留空使用音色的默认风格。")];
    [[self view] addSubview:label];

    [self setEditor:[UITextView new]];
    [[self editor] setTranslatesAutoresizingMaskIntoConstraints:NO];
    [[self editor] setFont:[UIFont systemFontOfSize:16.0]];
    [[self editor] setBackgroundColor:[UIColor secondarySystemBackgroundColor]];
    [[[self editor] layer] setCornerRadius:10.0];
    [[self editor] setTextContainerInset:UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0)];
    [[self editor] setText:PDAIString(PDAIPreference(@"AIDoubaoInstruction", @""))];
    [[self view] addSubview:[self editor]];

    UILayoutGuide *safeArea = [[self view] safeAreaLayoutGuide];
    UILayoutGuide *keyboardGuide = [[self view] keyboardLayoutGuide];

    [NSLayoutConstraint activateConstraints:@[
        // 说明文字
        [[label topAnchor] constraintEqualToAnchor:[safeArea topAnchor] constant:16.0],
        [[label leadingAnchor] constraintEqualToAnchor:[safeArea leadingAnchor] constant:16.0],
        [[label trailingAnchor] constraintEqualToAnchor:[safeArea trailingAnchor] constant:-16.0],
        // 编辑框
        [[[self editor] topAnchor] constraintEqualToAnchor:[label bottomAnchor] constant:12.0],
        [[[self editor] leadingAnchor] constraintEqualToAnchor:[safeArea leadingAnchor] constant:16.0],
        [[[self editor] trailingAnchor] constraintEqualToAnchor:[safeArea trailingAnchor] constant:-16.0],
        [[[self editor] bottomAnchor] constraintEqualToAnchor:[keyboardGuide topAnchor] constant:-12.0],
    ]];
}

// imp 0x007c60  types v16@0:8
- (void)save {
    NSString *text = [[[self editor] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([text length] >= 1001) {   // cmp #0x3e9
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:PDLocalizedString(@"描述过长")
                                                 message:PDLocalizedString(@"说话风格最多 1000 个字符。")
                                          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    PDAIWritePreferences(@{ @"AIDoubaoInstruction": text ?: @"" });
    [[self navigationController] popViewControllerAnimated:YES];
}

// imp 0x007e44  types @16@0:8
- (id)editor {
    return _editor;
}

// imp 0x007e54  types v24@0:8@16
- (void)setEditor:(id)a1 {
    _editor = a1;
}

// imp 0x007e68  types v16@0:8  →  - .cxx_destruct
// 原二进制只做 objc_storeStrong(&_editor, nil)，属编译器生成物；ARC 下自动合成，不再手写。

@end