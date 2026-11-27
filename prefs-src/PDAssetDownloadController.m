//
//  PDAssetDownloadController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import "PDAssetDownloadController.h"

extern NSString *PDLocalizedString(NSString *key);

@implementation PDAssetDownloadController

// imp 0x007e7c  types @16@0:8
- (id)specifiers {
    // 0x7e8c: _OBJC_IVAR_$_PSListController._specifiers（ldrsw 取偏移）
    if (_specifiers == nil) {
        _specifiers = [self localizedSpecifiers:@"Assets"];   // 0x7ea4 CF "Assets"
    }
    return _specifiers;
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
