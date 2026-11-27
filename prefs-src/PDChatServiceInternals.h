//
//  PDChatServiceInternals.h
//  PetDFYPrefs — 同 dylib 内的 C 辅助函数声明（PDChatService.m 专用）
//
//  这些实现都在 PetDFYPrefs 这个二进制里，但不在 PDChatService 的 87/97 个方法内，
//  原始工程中应是独立的 .m/.h。地址为 arm64 切片内的 VA（image base = 0）。
//
#import <Foundation/Foundation.h>

extern NSString *PDDataPath(void);                          // _PDDataPath                 0x236dc
extern id PDAIPreference(NSString *key, id fallback);       // _PDAIPreference             0x133d8
extern NSString *PDAIString(id value);                      // _PDAIString                 0x1329c
extern double PDAINumber(id value, double fallback);        // _PDAINumber                 0x132f8
extern NSDictionary *PDAIPromptValues(void);                // _PDAIPromptValues           0x14af0
extern NSString *PDPreferencesDomain;                       // _PDPreferencesDomain        0x51b38
extern NSDictionary *PDAIProviderSettings(void);             // _PDAIProviderSettings       0x15774
extern id PDAIEndpoint(NSDictionary *settings);             // _PDAIEndpoint               0x158dc
extern NSString *PDLoadAIAPIKey(void);                      // _PDLoadAIAPIKey             0x2314c
extern NSString *PDAIImageEndpointKey(NSDictionary *settings); // _PDAIImageEndpointKey    0x15f10
extern NSUInteger PDAIEstimatedTokens(id text);             // _PDAIEstimatedTokens        0x15c28
extern NSArray *PDAIToolDeclarations(void);                 // _PDAIToolDeclarations       0x13580
extern NSArray *PDAIContextSinceLastDelivery(NSArray *messages); // _PDAIContextSinceLastDelivery 0x16c14
extern NSArray *PDAIHistoryWithoutImages(NSArray *messages, NSSet *skip); // _PDAIHistoryWithoutImages 0x160c0
extern NSInteger PDAIImageSafeHandoffBoundary(NSArray *messages); // _PDAIImageSafeHandoffBoundary 0x171b4
extern NSString *PDAIHandoffNote(NSArray *head, NSUInteger index, NSUInteger count); // _PDAIHandoffNote 0x19c00
extern NSString *PDAIHandoffNotice(NSString *file);         // _PDAIHandoffNotice          0x1a648
extern NSDictionary *PDAIRequestBody(NSString *prompt, NSArray *messages, NSArray *tools,
                                     NSDictionary *settings, NSString *dataDirectory,
                                     NSError **error);       // _PDAIRequestBody            0x17460
extern BOOL PDAIRequestHasImages(NSDictionary *body);        // _PDAIRequestHasImages       0x16554
extern NSSet *PDAISentImageIDs(NSDictionary *body, NSArray *messages, NSString *dataDirectory); // _PDAISentImageIDs 0x16888
extern id PDAINormalizeResponse(id json, NSDictionary *settings, NSError **error); // _PDAINormalizeResponse 0x192a8
extern BOOL PDAIImageRetryAllowed(NSInteger status, NSData *body, NSError *error); // _PDAIImageRetryAllowed 0x16f44
extern BOOL PDIsDeviceTool(NSString *name);                  // _PDIsDeviceTool             0x241c4
extern NSString *PDDeviceToolPermissionError(NSString *name, NSDictionary *args); // _PDDeviceToolPermissionError 0x24564
extern NSString *PDCommandNotification;                     // _PDCommandNotification      0x4cc10
extern NSString *PDAIDefaultEnvironment(void);               // _PDAIDefaultEnvironment     0x1370c
