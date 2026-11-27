//
//  PDFramePlayer — 1.2 源码的逐帧动作播放器
//  读取 frames 素材包的 clips.plist + frames/，在桌宠上方播放 WebP 序列。
//

#import <UIKit/UIKit.h>

@interface PDFramePlayer : UIView

/// 当前播放结束/被点击停止时回调；播放器会自动隐藏。
@property (nonatomic, copy) void (^completion)(void);

- (instancetype)init;
- (BOOL)hasClips;
- (NSString *)nextClipID;
- (void)playClip:(NSString *)clipID;
- (void)stop;

@end
