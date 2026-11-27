//
//  PDDeviceControlController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/00008e90_..、00008ee4_..、00008f48_..
//
#import "PDDeviceControlController.h"

extern NSString *PDLocalizedString(NSString *key);

// 头文件把本类写成 NSObject 子类（二进制里是 PSListController，super 派发走
// _OBJC_CLASS_$_PDDeviceControlController；0x58360）。补齐声明以便编译与 super 派发。
@end

@implementation PDDeviceControlController

// imp 0x008e90  types @16@0:8
- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self localizedSpecifiers:@"DeviceControl"];
    }
    return _specifiers;
}

// imp 0x008ee4  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"设备操控")];
}

// imp 0x008f48  types v16@0:8
- (void)installHeader {
    // 二进制为单条 ret，空实现。
}

@end