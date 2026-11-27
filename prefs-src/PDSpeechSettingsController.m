//
//  PDSpeechSettingsController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/00007f38_..、000080e0_..、00008144_..、
//              00008148_..、00008190_..、000081e4_..、000085f8_..
//
#import "PDSpeechSettingsController.h"

#import "PDSpeechStyleController.h"

extern NSString *PDLocalizedString(NSString *key);
extern NSString *PDDoubaoSpeechStatus(void);                       // imp 0x2355c
extern void PDStoreDoubaoSpeechStatus(NSString *status);           // imp 0x235d8
extern BOOL PDHasDoubaoAPIKey(void);                               // imp 0x23514
extern BOOL PDStoreDoubaoAPIKey(NSString *apiKey, NSError **error); // imp 0x2354c
extern double PDAINumber(id value, double fallback);               // imp 0x132f8
extern NSString *PDAIString(id value);                             // imp 0x1329c
extern void PDAIWritePreferences(NSDictionary *values);            // imp 0x1343c

// 头文件把本类写成 NSObject 子类（二进制里其实是 PSListController，super 派发
// 走 _OBJC_CLASS_$_PDSpeechSettingsController；0x58350）。为可编译+可 super 派发，
// 在此补齐父类与框架方法声明，不实现。

@implementation PDSpeechSettingsController

// imp 0x007f38  types @16@0:8
- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self localizedSpecifiers:@"Speech"];
        for (PSSpecifier *spec in _specifiers) {
            if ([[spec propertyForKey:@"id"] isEqual:@"SpeechStatus"]) {
                [spec setProperty:PDLocalizedString(PDDoubaoSpeechStatus()) forKey:@"footerText"];
            }
        }
    }
    return _specifiers;
}

// imp 0x0080e0  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"对话声音")];
}

// imp 0x008144  types v16@0:8
- (void)installHeader {
    // 二进制为单条 ret，空实现。
}

// imp 0x008148  types v20@0:8B16
- (void)viewWillAppear:(BOOL)a1 {
    [super viewWillAppear:a1];
    [self reloadSpecifiers];
}

// imp 0x008190  types v16@0:8
- (void)editDoubaoStyle {
    UINavigationController *navigation = [self navigationController];
    PDSpeechStyleController *controller = [PDSpeechStyleController new];
    [navigation pushViewController:controller animated:YES];
}

// imp 0x0081e4  types v16:4@0:8
- (void)configureDoubaoKey {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:PDLocalizedString(@"豆包语音 API Key")
                                             message:PDLocalizedString(@"用于语音合成，保存在本机。填写新密钥可替换，留空保存可删除。")
                                      preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        // 全局 block（__NSConcreteGlobalBlock @0x4c570，invoke 0x8368）
        [textField setPlaceholder:PDLocalizedString(PDHasDoubaoAPIKey() ? @"已配置，填写新密钥可替换"
                                                                       : @"豆包语音 API Key")];
        [textField setSecureTextEntry:YES];
        [textField setAutocorrectionType:UITextAutocorrectionTypeNo];           // 1
        [textField setAutocapitalizationType:UITextAutocapitalizationTypeNone]; // 0
    }];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"保存")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        // stack block（invoke 0x83f0），捕获 alert 与 self
        NSString *text = [[[alert textFields] firstObject] text] ?: @"";
        NSError *error = nil;
        BOOL stored = PDStoreDoubaoAPIKey(text, &error);
        if (stored) {
            PDStoreDoubaoSpeechStatus(PDLocalizedString(@"配置已更新"));
            PDAIWritePreferences(@{ @"AIDoubaoKeyRevision": [[NSUUID UUID] UUIDString] });
            [self reloadSpecifiers];
        } else {
            UIAlertController *failure =
                [UIAlertController alertControllerWithTitle:PDLocalizedString(@"保存失败")
                                                     message:[error localizedDescription]
                                              preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
            [self presentViewController:failure animated:YES completion:nil];
        }
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x0085f8  types v32@0:8@16@24
- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    NSString *key = [specifier propertyForKey:@"key"];

    // 常量数组 0x52f50 = @[@"AIDoubaoPitch", @"AIDoubaoSpeechRate", @"AIDoubaoLoudnessRate"]
    if ([@[ @"AIDoubaoPitch", @"AIDoubaoSpeechRate", @"AIDoubaoLoudnessRate" ] containsObject:key]) {
        BOOL isPitch = [key isEqual:@"AIDoubaoPitch"];
        double limit = isPitch ? 12.0 : 100.0;       // 0x4059 / 0x4028
        double floorValue = isPitch ? -12.0 : -50.0; // -0x4048 / -0x4049
        double number = PDAINumber(value, 0.0);
        // 非有限值一律按 0 处理（fcmp inf / fcsel vs）
        if (isinf(number) || isnan(number)) {
            number = 0.0;
        }
        number = fmax(floorValue, number);
        number = fmin(limit, number);
        value = [NSNumber numberWithInteger:(NSInteger)round(number)]; // fcvtas
    }

    if ([[specifier propertyForKey:@"key"] isEqual:@"AIDoubaoSpeaker"]) {
        NSString *trimmed = [PDAIString(value)
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed length] > 200
            || [trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:PDLocalizedString(@"音色码无效")
                                                     message:PDLocalizedString(@"音色码不能包含空格或换行，最多 200 个字符。")
                                              preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self reloadSpecifiers];
            return;
        }
        value = trimmed;
    }

    [super setPreferenceValue:value specifier:specifier];
}
@end
