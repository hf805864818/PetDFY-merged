//
//  PDPreferences.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDPreferences : NSObject

- (id)init;
- (void)reload;
- (BOOL)enabled;
- (BOOL)interactive;
- (BOOL)responsive;
- (BOOL)soundEnabled;
- (BOOL)stroking;
- (double)size;
- (double)bottomInset;
- (BOOL)keyboardAvoidanceEnabled;
- (double)keyboardAvoidanceExtra;
- (NSInteger)framesPerSecond;
- (id)scheme;
- (id)outfit;
- (id)roam;
- (id)doubleTapAction;
- (id)longPressAction;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL interactive;
@property (nonatomic, readonly) BOOL responsive;
@property (nonatomic, readonly) BOOL soundEnabled;
@property (nonatomic, readonly) BOOL stroking;
@property (nonatomic, readonly) double size;
@property (nonatomic, readonly) double bottomInset;
@property (nonatomic, readonly) BOOL keyboardAvoidanceEnabled;
@property (nonatomic, readonly) double keyboardAvoidanceExtra;
@property (nonatomic, readonly) NSInteger framesPerSecond;
@property (nonatomic, readonly) NSString *scheme;
@property (nonatomic, readonly) NSString *outfit;
@property (nonatomic, readonly) NSString *roam;
@property (nonatomic, readonly) NSString *doubleTapAction;
@property (nonatomic, readonly) NSString *longPressAction;

@end
