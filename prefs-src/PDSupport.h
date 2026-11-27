//
//  PDSupport.h
//  PetDFYPrefs — reconstructed from build.080 (arm64, MH_DYLIB, image base 0)
//
//  本头文件对应 PDSupport.m：密钥/状态文件、路径、本地化、设备工具声明与回执。
//  资产子系统（_PDAssetSpecification 等 7 个）与 petdfy-voice/PDAssetImporter.h 同源，
//  不在此重复声明。
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 路径

// 0x0236d0：jbroot(@"/Library/Application Support/PetDFY.bundle")
NSString *PDResourcePath(void);

// 0x0236dc：@"/var/mobile/Library/Application Support/PetDFY"（不经 jbroot）
NSString *PDDataPath(void);

#pragma mark - 密钥 / 语音状态（文件存储，非钥匙串）

// 文件名 "ai-provider-key"，NSUTF8StringEncoding，缺文件回 @""
NSString *PDLoadAIAPIKey(void);                          // 0x02314c
BOOL PDHasAIAPIKey(void);                                // 0x0232fc
BOOL PDStoreAIAPIKey(NSString *key, NSError **error);     // 0x023334

// 文件名 "doubao-tts-key"
NSString *PDLoadDoubaoAPIKey(void);                      // 0x023498
BOOL PDHasDoubaoAPIKey(void);                            // 0x023514
BOOL PDStoreDoubaoAPIKey(NSString *key, NSError **error); // 0x02354c

// 文件名 "doubao-tts-status"，缺文件回 @"尚未使用"；写走串行队列
// "com.susudear.petdfy.speech-status" 异步落盘
NSString *PDDoubaoSpeechStatus(void);                    // 0x02355c
void PDStoreDoubaoSpeechStatus(NSString *status);         // 0x0235d8

#pragma mark - 本地化

// 0x023cac：从 <lang>.lproj/Localizable.strings 取串，未命中回原 key；
// 空串 / nil 直接原样返回。key 为空时不触碰本地化包。
NSString *PDLocalizedString(NSString *key);

#pragma mark - 设备工具

// 0x023ee4：由内嵌 JSON 常量解析、并把 5 个工具的说明替换为中文提示后的
// {"type":"function","function":{name,description,parameters}} 数组（结果被缓存）。
NSArray *PDDeviceToolDeclarations(void);

// 0x0241c4：name 是否为已声明的设备工具
BOOL PDIsDeviceTool(NSString *name);

// 0x02431c：总开关 DeviceControlEnabled + 单项 DeviceTool_<name>，两者都为真才启用
BOOL PDDeviceToolEnabled(NSString *name);

// 0x0243f4：PDDeviceToolEnabled 过滤后的声明数组
NSArray *PDEnabledDeviceToolDeclarations(void);

// 0x024564：工具被关闭（或 describe_screen 附带截图但截图工具未授权）时返回提示文案，
// 正常返回 nil。options 为工具入参（可为 nil / 非字典）。
NSString *PDDeviceToolPermissionError(NSString *name, id options);

// 0x024654：已启用工具的中文说明；无启用工具时返回 @""
NSString *PDDeviceToolPrompt(void);

// 0x0248e4：把设备工具原始回执改写成
//   @{ @"receipt": NSString, @"failed": NSNumber, @"images": NSArray }
NSDictionary *PDDeviceToolResult(NSDictionary *payload);// 0x004cc00 数据符号：CFString "com.susudear.petdfyprefs"
extern NSString *PDPreferencesDomain;
static inline CFStringRef PDPreferencesDomainRef(void) {
    return (__bridge CFStringRef)PDPreferencesDomain;
}

