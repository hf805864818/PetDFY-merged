//
//  PDAssetDownloadController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import "PDAssetDownloadController.h"

extern NSString *PDLocalizedString(NSString *key);

@implementation PDAssetDownloadController

// imp 0x007e7c  types @16@0:8
//
// 【build.93 改造】在原版 specifiers 基础上做两件事：
//   1) 分组 footer 补「手动放置素材」的完整说明（含 frames/ 可选）
//   2) 插入「打开素材目录」按钮，跳到 /var/mobile/Library/Xfy
- (id)specifiers {
    // 0x7e8c: _OBJC_IVAR_$_PSListController._specifiers（ldrsw 取偏移）
    if (_specifiers == nil) {
        NSMutableArray *list = [[self localizedSpecifiers:@"Assets"] mutableCopy];

        // ---- 1) 分组 footer ----
        for (PSSpecifier *spec in list) {
            NSString *ident = [spec propertyForKey:@"id"];
            if (![ident isEqual:@"PDAssetStatus"]) continue;
            [spec setProperty:
                @"⚠️ 手动放置素材时请注意：\n"
                @"· 必须是「解压后」的文件夹内容，不要直接放 zip 文件\n"
                @"· 如果 ZIP 里有顶层文件夹（如 素材PetDFY-1.2-.../），\n"
                @"  请把「里层内容」拷到素材目录，不要带外壳文件夹\n"
                @"· 正确结构：Xfy/live/model.json、Xfy/originals/tex/\n"
                @"· frames/ 可选：占 80 MB，仅帧动画（116 个动作）使用；\n"
                @"  不放也能显示角色，只是动作播不出来\n"
                @"· 放好后注销一次（或重启 SpringBoard）生效\n\n"
                @"素材目录：/var/mobile/Library/Xfy"
                        forKey:@"footerText"];
            break;
        }

        // ---- 2) 「打开素材目录」按钮，插在「移除素材…」之前 ----
        PSSpecifier *openButton =
            [PSSpecifier preferenceSpecifierNamed:@"打开素材目录"
                                            target:self
                                               set:nil
                                               get:nil
                                            detail:nil
                                              cell:PSButtonCellType
                                              edit:nil];
        [openButton setProperty:@"openAssetDirectory" forKey:@"action"];

        NSUInteger removeIndex = NSNotFound;
        for (NSUInteger i = 0; i < list.count; i++) {
            id action = [list[i] propertyForKey:@"action"];
            if ([action isKindOfClass:[NSString class]] && [action isEqual:@"removeAssets"]) {
                removeIndex = i;
                break;
            }
        }
        if (removeIndex != NSNotFound) {
            [list insertObject:openButton atIndex:removeIndex];
        } else {
            [list addObject:openButton];
        }

        _specifiers = list;
    }
    return _specifiers;
}

#pragma mark - 打开素材目录（build.93 新增）

/// 跳到 /var/mobile/Library/Xfy。
/// ① 优先 shareddocuments:// 让「文件」App 直接定位到该目录；
/// ② 不可用时弹窗显示路径，提供「复制路径」/「取消」。
- (void)openAssetDirectory {
    static NSString *const kAssetRoot = @"/var/mobile/Library/Xfy";

    NSString *encoded =
        [kAssetRoot stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLPathAllowedCharacterSet]];
    NSURL *filesURL =
        [NSURL URLWithString:[@"shareddocuments://" stringByAppendingString:encoded ?: @""]];

    UIApplication *app = [UIApplication sharedApplication];
    if (filesURL && [app canOpenURL:filesURL]) {
        [app openURL:filesURL options:@{} completionHandler:nil];
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"素材目录"
                                            message:kAssetRoot
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制路径"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = kAssetRoot;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x007ed0  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PDLocalizedString(@"下载");                  // 0x7f04 CF(UTF-16) "下载"
}

// imp 0x007f34  types v16@0:8
- (void)installHeader {
    // 0x7f34: 函数体只有 ret —— 本页不装自定义 header
}

@end
