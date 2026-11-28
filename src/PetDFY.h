//
//  PetDFY 1.2.1 — 逆向还原源码（可编译骨架）
//  由 Mach-O 元数据生成：类/父类/ivar/方法签名/属性均为真实结构
//  方法体为空实现，仅供编译与结构验证
//
#ifndef PETDFY_UMBRELLA_H
#define PETDFY_UMBRELLA_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/Security.h>

// 前向声明：系统类
@class AVAudioEngine, AVAudioFormat, AVAudioPlayerNode, AVAudioFile;
@class AVAudioPCMBuffer, AVAudioSession, AVAudioInputNode;
@class MTLDevice, MTLTexture, MTLBuffer, MTLRenderPipelineState;
@class MTLSamplerState, MTLRenderPassDescriptor, MTKTextureLoader;
@class SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest;
@class SFSpeechRecognitionTask, AVSpeechSynthesizer, AVSpeechUtterance;
@class NSURLSession, NSURLSessionDataTask, NSURLSessionConfiguration;
@class UIImage, UIColor, UIFont, UIView, UIWindow, UIViewController;
@class CALayer, CAShapeLayer, CAKeyframeAnimation, CATransaction;
@class UIScrollView, UITextView, UITextField, UICollectionView;
@class UIPanGestureRecognizer, UILongPressGestureRecognizer;
@class MPVolumeView, MPMusicPlayerController;
@class MPSImageGaussianBlur, MPSImage, MPSKernel;
// 前向声明：私有/系统结构体
struct __IOHIDEvent; struct __AXUIElement; struct __CFMessagePort;

// 运动状态结构体（WNMotion.p 的类型，56 字段 / 464 字节）
// 字段名与类型从 ivar 的完整 type encoding 还原
// B 方案：字段名/偏移按 recon 的实测版本（原逆向版从 gap 之后整体错位）
// 偏移锚点：facing +0x38、low +0xc8、feet +0xf8、hasPrev +0x1d0，整体 0x1d0
typedef struct WNMotionState {
    double   x           ;
    double   fy          ;
    double   gy          ;
    double   gvy         ;
    double   vx          ;
    double   vy          ;
    double   facing      ;
    double   faceVis     ;
    double   modeT       ;
    double   dwell       ;
    double   walkToX     ;
    double   walkToY     ;
    double   speed       ;
    double   bob         ;
    double   lift        ;
    double   sway        ;
    double   phase       ;
    double   lean        ;
    double   tilt        ;
    double   tiltV       ;
    double   sq          ;
    double   sqv         ;
    double   sitK        ;
    double   stretch     ;
    double   low         ;
    double   drowse      ;
    double   gapX        ;
    double   gapY        ;
    double   lookX       ;
    double   lookY       ;
    double   feet       [4];   // +0xf8..0x110  feet[0].x,.y,feet[1].x,.y
    double   blinkT      ;
    double   blinkAge    ;
    double   exprUntil   ;
    double   nextAt      ;
    double   fxCool      ;
    double   stallT      ;
    double   dragX       ;
    double   dragY       ;
    double   launchY     ;
    double   launchX     ;
    double   blushK      ;
    double   eyeT        ;
    double   glanceX     ;
    double   glanceY     ;
    double   glanceAt    ;
    double   snoreAt     ;
    double   swing       ;
    double   swingV      ;
    double   prevX       ;
    double   velX        ;
    double   talkK       ;
    double   voiceCool   ;
    double   nextNoteAt  ;
    BOOL     hasPrev     ;
    BOOL     flipOnce    ;
    BOOL     wokeNow     ;
    BOOL     sitSeen     ;
    BOOL     skidded     ;
} WNMotionState;

@class PDAIAlarms, PDAIMemory, PDAIPetRuntime, PDActiveInterfaceOrientationMonitor, PDAssetManager, PDChatController, PDChatPassthroughView, PDChatService, PDCloudVoiceInput, PDComposerTextView, PDDeviceAXScope, PDDeviceNativeExecutor, PDDeviceTools, PDDoubaoSSEDecoder, PDDoubaoTTS, PDHostRootView, PDInteractionView, PDKeyboardMonitor, PDLocalizationBundle, PDNative_AccessibilityManager, PDNative_AppManager, PDNative_ClipboardManager, PDNative_IOSMCPHIDManager, PDNative_MCPAXAttributeBridge, PDNative_MCPAXNodeSource, PDNative_MCPAXQueryContext, PDNative_MCPAXRemoteContextResolver, PDNative_MCPLogger, PDNative_MCPUIElementSerializer, PDNative_MCPUIElementsFacade, PDNative_ScreenManager, PDNative_TextInputManager, PDOverlayController, PDPetView, PDPreferences, PDReplySpeech, PDRootController, PDSoundPlayer, PDSpeechBubbleView, PDVoice, PDVoiceServiceConnection, PDVoiceTextReveal, PDWindow, WNClip, WNGlowSurface, WNHitMask, WNLiveRig, WNMesh, WNMotion, WNPainter, WNPreparedDeformer, WNRenderer, WNSpring, WNUploadSurface;

#import "PDAIAlarms.h"
#import "PDAIMemory.h"
#import "PDAIPetRuntime.h"
#import "PDActiveInterfaceOrientationMonitor.h"
#import "PDAssetManager.h"
#import "PDChatController.h"
#import "PDChatPassthroughView.h"
#import "PDChatService.h"
#import "PDCloudVoiceInput.h"
#import "PDComposerTextView.h"
#import "PDDeviceAXScope.h"
#import "PDDeviceToolsDeclarations.h"
#import "PDDeviceNativeExecutor.h"
#import "PDDeviceTools.h"
#import "PDDoubaoSSEDecoder.h"
#import "PDDoubaoTTS.h"
#import "PDHostRootView.h"
#import "PDInteractionView.h"
#import "PDKeyboardMonitor.h"
#import "PDLocalizationBundle.h"
#import "PDNative_AccessibilityManager.h"
#import "PDNative_AppManager.h"
#import "PDNative_ClipboardManager.h"
#import "PDNative_IOSMCPHIDManager.h"
#import "PDNative_MCPAXAttributeBridge.h"
#import "PDNative_MCPAXNodeSource.h"
#import "PDNative_MCPAXQueryContext.h"
#import "PDNative_MCPAXRemoteContextResolver.h"
#import "PDNative_MCPLogger.h"
#import "PDNative_MCPUIElementSerializer.h"
#import "PDNative_MCPUIElementsFacade.h"
#import "PDNative_ScreenGeometry.h"
#import "PDNative_ScreenManager.h"
#import "PDNative_TextInputManager.h"
#import "PDOverlayController.h"
#import "PDPetView.h"
#import "PDPreferences.h"
#import "PDReplySpeech.h"
#import "PDRootController.h"
#import "PDSoundPlayer.h"
#import "PDSpeechBubbleView.h"
#import "PDVoice.h"
#import "PDVoiceServiceConnection.h"
#import "PDVoiceTextReveal.h"
#import "PDWindow.h"
#import "WNClip.h"
#import "WNGlowSurface.h"
#import "WNHitMask.h"
#import "WNLiveRig.h"
#import "WNMesh.h"
#import "WNMotion.h"
#import "WNPainter.h"
#import "WNPreparedDeformer.h"
#import "WNRenderer.h"
#import "WNSpring.h"
#import "WNUploadSurface.h"

// ── 全局 C 辅助（由 dylib 符号表还原：PDDataPath / PDAIPreference / PDAIString）
NSString *PDDataPath(void);
NSDictionary *PDAIPromptValues(void);
id PDAIPreference(NSString *key, id fallback);
void PDAIWritePreferences(NSDictionary *values);   // 0x9af8 等调用点：写 CFPreferences 并同步
NSString *PDAIString(id value);
NSString *PDLocalizedString(NSString *key);        // 0x432a0：key 为空返回空，否则查语言表回退 key
double PDAINumber(id value, double fallback);
NSString *PDAIDefaultEnvironment(void);
BOOL PDAIImageRetryAllowed(id a, id b, id c);

#endif