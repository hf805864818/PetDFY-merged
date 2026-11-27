//
//  PDProviderController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/000088b8_..、0000890c_..、00008970_..、00008974_..、000089bc_..
//
#import "PDProviderController.h"

extern NSString *PDLocalizedString(NSString *key);
extern id PDAIPreference(id key, id fallback);                     // imp 0x133d8
extern double PDAINumber(id value, double fallback);               // imp 0x132f8

// 头文件把本类写成 NSObject 子类（二进制里是 PSListController，super 派发走
// _OBJC_CLASS_$_PDProviderController；0x58358）。补齐声明以便编译与 super 派发。

@implementation PDProviderController

// imp 0x0088b8  types @16@0:8
- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self localizedSpecifiers:@"Provider"];
    }
    return _specifiers;
}

// imp 0x00890c  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"供应商设置")];
}

// imp 0x008970  types v16@0:8
- (void)installHeader {
    // 二进制为单条 ret，空实现。
}

// imp 0x008974  types v20@0:8B16
- (void)viewWillAppear:(BOOL)a1 {
    [super viewWillAppear:a1];
    [self reloadSpecifiers];
}

// imp 0x0089bc  types v32@0:8@16@24
- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *errorMessage = nil;

    // ── Token 数值区间校验：常量数组 0x52f68 = @[@"AIContextTokens", @"AIMaxTokens"]
    if ([@[ @"AIContextTokens", @"AIMaxTokens" ] containsObject:key]) {
        double current = PDAINumber(value, -1.0);
        BOOL isEmpty = ([value isKindOfClass:[NSString class]] && [value length] == 0);

        double contextTokens;
        if ([key isEqual:@"AIContextTokens"]) {
            contextTokens = isEmpty ? 128000.0 : current;                    // 0x2b728 = 128000.0
        } else {
            contextTokens = PDAINumber(PDAIPreference(@"AIContextTokens", @128000), 128000.0);
        }

        double maxTokens;
        if ([key isEqual:@"AIMaxTokens"]) {
            maxTokens = isEmpty ? 0.0 : current;
        } else {
            maxTokens = PDAINumber(PDAIPreference(@"AIMaxTokens", @0), 0.0);
        }

        BOOL valid = YES;
        if (!isEmpty) {
            // 必须是 >= 1 的整数（fcmp 1.0 / frintm 取整回比）
            if (current < 1.0 || trunc(current) != current) {
                valid = NO;
            }
        }
        if (!(contextTokens > maxTokens)) {
            valid = NO;
        }
        if (!valid) {
            errorMessage = PDLocalizedString(@"请输入正整数；上下文上限必须大于最大输出 Token。");
        }
    }

    // ── JSON 校验：常量数组 0x52f80 = @[@"AIExtraHeaders", @"AIExtraBody"]
    if ([@[ @"AIExtraHeaders", @"AIExtraBody" ] containsObject:key] && [value length] != 0) {
        id json = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] // 4
                                                  options:0
                                                    error:NULL];
        if (![json isKindOfClass:[NSDictionary class]]) {
            errorMessage = PDLocalizedString(@"请输入有效的 JSON 对象。");
        } else if ([key isEqual:@"AIExtraHeaders"]) {
            for (id headerKey in json) {
                if (![[json objectForKeyedSubscript:headerKey] isKindOfClass:[NSString class]]) {
                    errorMessage = PDLocalizedString(@"请求头的值必须是字符串。");
                }
            }
        }
    }

    // ── 端点路径校验
    if ([key isEqual:@"AIEndpointPath"] && [value length] != 0) {
        BOOL ok = ([value hasPrefix:@"/"] && ![value hasPrefix:@"//"]);
        if (!ok) {
            errorMessage = PDLocalizedString(@"端点路径必须是以 / 开头的相对路径。");
        }
    }

    if (errorMessage) {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:PDLocalizedString(@"设置未保存")
                                                 message:errorMessage
                                          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
        return;
    }

    [super setPreferenceValue:value specifier:specifier];
}
@end
