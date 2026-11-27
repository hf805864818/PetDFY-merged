//
//  PDRootListController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/000xxxxx_PDRootListController_*.asm
//  image base = 0（MH_DYLIB），所有 imp 地址即文件 VA。
//
#import "PDRootListController.h"
#import "PDSupport.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "PDAIMemory.h"      // PDChatService.h 用到 PDAIMemory *，需先给出完整声明
#import "PDChatService.h"
#import "PDChatPromptController.h"
#import "PDChatHistoryController.h"
#import "PDChatMemoryController.h"
#import "PDModelListController.h"

// ── 外部 C 符号（定义在 PetDFYPrefs 其它编译单元，本文件只声明）──────────────
extern NSString *PDLocalizedString(NSString *key);

extern NSString *PDPreferencesDomain;              // CF "com.susudear.petdfyprefs"
extern CFStringRef const PDPreferencesChangedNotification;
extern CFStringRef const PDCommandNotification;
extern CFStringRef const PDAssetStatusNotification;        // CF "com.susudear.petdfy/assets-status"
extern CFStringRef const PDAssetStatusPreferenceKey;       // CF "AssetDownloadStatus"

extern NSString *PDAssetImportDirectory(void);             // imp 0x415c
extern NSString *PDAssetImportPath(NSString *name);        // imp 0x4168
extern NSString *PDAssetDownloadURL(NSString *urlString);  // imp 0x4570，校验失败返回 nil
extern void PDAIWritePreferences(NSDictionary *values);    // imp 0x1343c
extern NSString *PDLoadAIAPIKey(void);                     // imp 0x2314c
extern BOOL PDHasAIAPIKey(void);                           // imp 0x232fc
extern BOOL PDStoreAIAPIKey(NSString *apiKey, NSError **error); // imp 0x23334

// PDChatService 的类方法：头文件只导出了实例方法，此处按二进制补声明（不改 .h）。

// 两个属性都由手写存取器实现，故 ivar 显式声明在 class extension 内。
@interface PDRootListController () {
    UIView *_pdHeader;      // ivar offset 见 _OBJC_IVAR_$_PDRootListController._pdHeader
    BOOL _assetCopying;     // ivar offset 见 _OBJC_IVAR_$_PDRootListController._assetCopying
}
@end

// 0x541c：Darwin 通知回调，仅把工作甩回主线程。
static void PDPreferencesChangedCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFNotificationName name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    id target = (__bridge id)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [(PDRootListController *)target updateAssetStatus];   // block invoke 0x8f4c
    });
}

// 0x69e8：在视图树里递归找第一个 UITableView（无捕获，二进制中直接调用）。
static UITableView *PDFirstTableView(UIView *view) {
    if ([view isKindOfClass:[UITableView class]]) {
        return (UITableView *)view;
    }
    for (UIView *subview in [view subviews]) {
        UITableView *found = PDFirstTableView(subview);
        if (found) {
            return found;
        }
    }
    return nil;
}

@implementation PDRootListController

// imp 0x004cd8  types @24@0:8@16
- (id)localizedSpecifiers:(id)a1 {
    NSArray *specs = [self loadSpecifiersFromPlistName:a1 target:self];
    // 常量数组 0x52f38 = @[@"label", @"footerText", @"placeholder", @"infoTitle", @"infoMessage"]
    for (PSSpecifier *spec in specs) {
        [spec setName:PDLocalizedString([spec name])];
        for (NSString *key in @[@"label", @"footerText", @"placeholder", @"infoTitle", @"infoMessage"]) {
            id value = [spec propertyForKey:key];
            if ([value isKindOfClass:[NSString class]]) {
                [spec setProperty:PDLocalizedString(value) forKey:key];
            }
        }
        NSMutableDictionary *titles = [NSMutableDictionary new];
        for (id key in [spec titleDictionary]) {
            [titles setObject:PDLocalizedString([[spec titleDictionary] objectForKeyedSubscript:key])
                       forKeyedSubscript:key];
        }
        if ([titles count]) {
            [spec setTitleDictionary:titles];
        }
        NSMutableDictionary *shortTitles = [NSMutableDictionary new];
        for (id key in [spec shortTitleDictionary]) {
            [shortTitles setObject:PDLocalizedString([[spec shortTitleDictionary] objectForKeyedSubscript:key])
                            forKeyedSubscript:key];
        }
        if ([shortTitles count]) {
            [spec setShortTitleDictionary:shortTitles];
        }
    }
    return specs;
}

// imp 0x005104  types @16@0:8
- (id)specifiers {
    // _specifiers 是 PSListController 的 ivar（_OBJC_IVAR_$_PSListController._specifiers）
    if (!_specifiers) {
        _specifiers = [self localizedSpecifiers:@"Root"];
    }
    return _specifiers;
}

// imp 0x005158  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"大肥鱼")];

    // colorWithRed:0.3 green:0.42 blue:1.0 alpha:1.0
    [[self view] setTintColor:[UIColor colorWithRed:0.3 green:0.42 blue:1.0 alpha:1.0]];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [[self view] bounds].size.width, 210.0)];

    UIImageView *iconView =
        [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PetDFYHeaderIcon.png"
                                                      inBundle:[NSBundle bundleForClass:[self class]]
                                 compatibleWithTraitCollection:nil]];
    [iconView setContentMode:UIViewContentModeScaleAspectFit]; // 1
    [iconView setFrame:CGRectMake(([header bounds].size.width - 140.0) * 0.5, 10.0, 140.0, 140.0)];
    [iconView setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin]; // 5
    [header addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 156.0, [header bounds].size.width, 29.0)];
    [titleLabel setText:PDLocalizedString(@"大肥鱼 PetDFY")];
    [titleLabel setFont:[UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold]];
    [titleLabel setTextAlignment:NSTextAlignmentCenter]; // 1
    [titleLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth]; // 2
    [header addSubview:titleLabel];

    [self setPdHeader:header];
    [self installHeader];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                   (__bridge const void *)self,
                                   PDPreferencesChangedCallback,
                                   PDAssetStatusNotification,
                                   NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately); // 4
    [self updateAssetStatus];
}

// imp 0x005494  types v16@0:8
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self installHeader];
}

// imp 0x0054dc  types v20@0:8B16
- (void)viewWillAppear:(BOOL)a1 {
    [super viewWillAppear:a1];
    [self updateAssetStatus];
}

// imp 0x005524  types v16@0:8
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       PDAssetStatusNotification,
                                       NULL);
    // ARC：二进制在 0x556c 的 [super dealloc] 由编译器插入，源码不再书写。
}

// imp 0x005580  types v16@0:8
- (void)updateAssetStatus {
    PSSpecifier *spec = [self specifierForID:@"PDAssetStatus"];
    if (!spec) {
        return;
    }

    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    id prefs = (__bridge_transfer id)CFPreferencesCopyAppValue(PDAssetStatusPreferenceKey, PDPreferencesDomainRef());
    if (![prefs isKindOfClass:[NSDictionary class]]) {
        prefs = @{};
    }

    id rawStatus = [prefs objectForKeyedSubscript:@"status"];
    NSString *status = nil;
    if ([rawStatus isKindOfClass:[NSString class]]) {
        status = [prefs objectForKeyedSubscript:@"status"];
    } else {
        status = @"";
    }

    // 常量字典 0x53310 = @{@"archive": @"素材包为空或无法读取，请检查地址后重试。"}
    NSString *footer = @{@"archive": @"素材包为空或无法读取，请检查地址后重试。"}[status];
    if (!footer) {
        footer = PDLocalizedString([status length] == 0
                                   ? @"填写素材 ZIP 下载地址，启用后自动下载并解压。"
                                   : @"素材处理失败，请重试或重新安装插件。");
    }

    // 常量字典 0x53338：import / importing / remove / removed / removing
    NSString *mapped = @{
        @"import":     @"无法读取导入的 ZIP，请重新选择文件。",
        @"importing":  @"正在读取素材 ZIP…",
        @"remove":     @"素材移除失败，请重试。",
        @"removed":    @"素材已移除，可重新下载或从文件导入。",
        @"removing":   @"正在移除素材…"
    }[status];
    if (mapped) {
        footer = PDLocalizedString(mapped);
    }

    if ([status isEqual:@"downloading"]) {
        id progress = [prefs objectForKeyedSubscript:@"progress"];
        footer = [NSString stringWithFormat:PDLocalizedString(@"正在下载素材：%@%%"), progress ?: @0];
    }

    if ([self assetCopying]) {
        footer = PDLocalizedString(@"正在读取素材 ZIP…");
    }

    [spec setProperty:footer forKey:@"footerText"];
    [self reloadSpecifier:spec animated:NO];
}

// imp 0x0057f8  types v16@0:8
- (void)retryAssets {
    if ([self assetCopying]) {
        return;
    }
    [[self view] endEditing:YES];
    PDAIWritePreferences(@{ @"AssetRequest": @{},
                            @"AssetRetryToken": [[NSUUID UUID] UUIDString] });
}

// imp 0x0058e8  types v16@0:8
- (void)importAssets {
    if ([self assetCopying]) {
        return;
    }
    [[self view] endEditing:YES];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeZIP ] asCopy:YES];
    [picker setDelegate:self];
    [picker setAllowsMultipleSelection:NO];
    [self presentViewController:picker animated:YES completion:nil];
}

// imp 0x0059e8  types v32@0:8@16@24
- (void)documentPicker:(id)picker didPickDocumentsAtURLs:(NSArray *)urls {
    NSURL *url = [urls firstObject];
    if (!url) {
        return;
    }
    if ([self assetCopying]) {
        return;
    }
    [self setAssetCopying:YES];
    [[self view] setUserInteractionEnabled:NO];
    [self updateAssetStatus];

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSString *token = [[NSUUID UUID] UUIDString];

    __block NSError *error = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{   // 0x11 = QOS_CLASS_DEFAULT
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *targetPath = PDAssetImportPath(token);
        NSString *partialPath = [targetPath stringByAppendingString:@".partial"];
        NSString *directory = PDAssetImportDirectory();

        BOOL created = [fileManager createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @(0700)}
                                                    error:&error];
        if (created) {
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            // Assumed: @try 边界取 coordinateReadingItemAtURL 调用本身（0x5c98–0x5eac 的异常表范围）
            @try {
                [coordinator coordinateReadingItemAtURL:url
                                                options:0
                                                  error:&error
                                             byAccessor:^(NSURL *newURL) {
                    NSDictionary *attributes = [fileManager attributesOfItemAtPath:[newURL path] error:&error];
                    if ([[attributes objectForKey:NSFileType] isEqual:NSFileTypeRegular]
                        && [[attributes objectForKey:NSFileSize] longLongValue] > 0) {
                        if (![fileManager copyItemAtURL:newURL
                                                  toURL:[NSURL fileURLWithPath:partialPath]
                                                  error:&error]) {
                            return;
                        }
                        if (![fileManager setAttributes:@{NSFilePosixPermissions: @(0600)}
                                          ofItemAtPath:partialPath
                                                 error:&error]) {
                            return;
                        }
                        [fileManager moveItemAtPath:partialPath toPath:targetPath error:&error];
                        return;
                    }
                    if (!error) {
                        error = [NSError errorWithDomain:@"PetDFY.Assets" code:1 userInfo:nil];
                    }
                }];
            } @catch (NSException *exception) {
                error = [NSError errorWithDomain:@"PetDFY.Assets" code:1 userInfo:nil];
            }
        }

        if (accessed) {
            [url stopAccessingSecurityScopedResource];
        }
        [fileManager removeItemAtPath:partialPath error:NULL];
        if (error) {
            [fileManager removeItemAtPath:targetPath error:NULL];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setAssetCopying:NO];
            [[self view] setUserInteractionEnabled:YES];

            if (error) {
                UIAlertController *alert =
                    [UIAlertController alertControllerWithTitle:PDLocalizedString(@"导入失败")
                                                         message:PDLocalizedString(@"无法读取导入的 ZIP，请重新选择文件。")
                                                  preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                NSDictionary *request = @{ @"operation": @"import",
                                           @"token": token };
                PDAIWritePreferences(@{ @"AssetRequest": request,
                                        @"AssetRetryToken": token });
            }
            [self updateAssetStatus];
        });
    });
}

// imp 0x00648c  types v16@0:8
- (void)removeAssets {
    if ([self assetCopying]) {
        return;
    }
    [[self view] endEditing:YES];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:PDLocalizedString(@"移除素材？")
                         message:PDLocalizedString(@"移除已安装素材并暂停桌宠。可重新下载或导入 ZIP 恢复，聊天记录和设置会保留。")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"移除素材")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        // 全局 block（__NSConcreteGlobalBlock @0x4c490，invoke 0x65f4）
        NSString *token = [[NSUUID UUID] UUIDString];
        NSMutableArray *names = [NSMutableArray new];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *directory = PDAssetImportDirectory();

        for (NSString *name in [fileManager contentsOfDirectoryAtPath:directory error:NULL]) {
            NSString *base = [[name pathExtension] isEqual:@"partial"] ? [name stringByDeletingPathExtension] : name;
            NSString *stem = [base stringByDeletingPathExtension];
            NSString *extension = [base pathExtension];
            if (![extension isEqual:@"zip"]) {
                continue;
            }
            if (!PDAssetImportPath(stem)) {
                continue;
            }
            if ([names containsObject:stem]) {
                continue;
            }
            if ([names count] > 999) {
                continue;
            }
            [names addObject:stem];
        }

        NSDictionary *request = @{ @"operation": @"remove",
                                   @"token": token,
                                   @"importTokens": names };
        PDAIWritePreferences(@{ @"AssetRetryToken": request });
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x0068e4  types v16@0:8
- (void)installHeader {
    UITableView *table = PDFirstTableView([self view]);
    if (!table) {
        return;
    }
    UIView *header = [self pdHeader];
    if (!header) {
        return;
    }
    // 高度常量 0x2b6f8 = 210.0
    [header setFrame:CGRectMake(0, 0, [table bounds].size.width, 210.0)];
    if ([table tableHeaderView] != header) {
        [table setTableHeaderView:header];
    }
}

// imp 0x006b2c  types v32@0:8@16@24
- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    if ([[specifier propertyForKey:@"key"] isEqual:@"AssetDownloadURL"]) {
        NSString *trimmed = nil;
        if ([value isKindOfClass:[NSString class]]) {
            trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            trimmed = @"";
        }
        // 0x6bf4：非空时用 PDAssetDownloadURL 做一次合法性校验，结果仅用于判空
        if ([trimmed length] != 0 && !PDAssetDownloadURL(trimmed)) {
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:PDLocalizedString(@"下载地址无效")
                                                     message:PDLocalizedString(@"请输入有效的 HTTP 或 HTTPS 地址。")
                                              preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        value = trimmed;
    }

    [super setPreferenceValue:value specifier:specifier];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         PDPreferencesChangedNotification,
                                         NULL,
                                         NULL,
                                         true); // 1
}

// imp 0x006d30  types v24@0:8@16
- (void)sendCommand:(id)a1 {
    CFPreferencesSetAppValue(CFSTR("Command"), (__bridge CFPropertyListRef)a1, PDPreferencesDomainRef());
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         PDCommandNotification,
                                         NULL,
                                         NULL,
                                         true);
}

// imp 0x006d8c  types v16@0:8
- (void)openAIChat {
    [self sendCommand:@"chat"];
}

// imp 0x006d98  types v16@0:8
- (void)editAIPrompt {
    PDChatPromptController *controller = [PDChatPromptController new];
    [[self navigationController] pushViewController:controller animated:YES];
}

// imp 0x006df0  types v16@0:8
- (void)openAIHistory {
    UINavigationController *navigation = [self navigationController];
    PDChatHistoryController *controller = [[PDChatHistoryController alloc] initWithStyle:UITableViewStyleInsetGrouped]; // 2
    [navigation pushViewController:controller animated:YES];
}

// imp 0x006e4c  types v16@0:8
- (void)editAIMemory {
    PDChatMemoryController *controller = [PDChatMemoryController new];
    [[self navigationController] pushViewController:controller animated:YES];
}

// imp 0x006ea4  types v16@0:8
- (void)fetchAIModels {
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    id configured = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("AIBaseURL"), PDPreferencesDomainRef());
    NSString *baseURL = [configured isKindOfClass:[NSString class]] ? configured : @"";

    __weak PDRootListController *weakSelf = self;
    NSString *apiKey = PDLoadAIAPIKey();

    [PDChatService fetchModelCatalogAtBaseURL:baseURL apiKey:apiKey completion:^(NSArray *models, NSError *error) {
        PDRootListController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:PDLocalizedString(@"获取模型失败")
                                                     message:[error localizedDescription]
                                              preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        } else {
            PDModelListController *controller = [[PDModelListController alloc] initWithStyle:UITableViewStyleInsetGrouped]; // 2
            [controller setModels:models];
            [[strongSelf navigationController] pushViewController:controller animated:YES];
        }
    }];
}

// imp 0x007158  types v16:4@0:8
- (void)configureAIKey {
    BOOL hasKey = PDHasAIAPIKey();
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:PDLocalizedString(@"AI 服务密钥")
                         message:PDLocalizedString(hasKey
                                                   ? @"密钥仅保存在本机。填写新密钥可替换，留空保存可删除。"
                                                   : @"用于验证模型服务的访问权限，密钥仅保存在本机。")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        // 全局 block（invoke 0x7344）
        [textField setPlaceholder:PDLocalizedString(PDHasAIAPIKey() ? @"已配置，填写新密钥可替换"
                                                                   : @"API Key（无需验证时可留空）")];
        [textField setSecureTextEntry:YES];
        [textField setAutocorrectionType:UITextAutocorrectionTypeNo];              // 1
        [textField setAutocapitalizationType:UITextAutocapitalizationTypeNone];    // 0
    }];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"保存")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        // stack block（invoke 0x73cc），捕获 alert 与 self
        NSString *text = [[[alert textFields] firstObject] text] ?: @"";
        NSError *error = nil;
        BOOL stored = PDStoreAIAPIKey(text, &error);
        if (!stored) {
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

    if (PDHasAIAPIKey()) {
        [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"删除密钥")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *action) {
            // 全局 block（__NSConcreteGlobalBlock @0x4c550，invoke 0x756c）
            PDStoreAIAPIKey(@"", NULL);
        }]];
    }

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x00757c  types @16@0:8
- (id)pdHeader {
    return _pdHeader;
}

// imp 0x00758c  types v24@0:8@16
- (void)setPdHeader:(id)a1 {
    _pdHeader = a1;
}

// imp 0x0075a0  types B16@0:8
- (BOOL)assetCopying {
    return _assetCopying;
}

// imp 0x0075b0  types v20@0:8B16
- (void)setAssetCopying:(BOOL)a1 {
    _assetCopying = a1;
}

@end