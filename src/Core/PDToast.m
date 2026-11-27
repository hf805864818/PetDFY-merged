//
//  PDToast.m — 浮层提示实现
//

#import "PDToast.h"
#import <UIKit/UIKit.h>

static UIWindow *gToastWindow = nil;

@interface PDToastViewController : UIViewController
- (void)dismissSelf;
@end

@implementation PDToastViewController
- (void)dismissSelf { PDHideToast(); }
@end

void PDHideToast(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gToastWindow) return;
        gToastWindow.hidden = YES;
        gToastWindow.rootViewController = nil;
        gToastWindow = nil;
    });
}

void PDShowToast(NSString *text, NSTimeInterval sec) {
    if (!text.length) return;
    NSString *body = [text copy];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gToastWindow) {
            gToastWindow.hidden = YES;
            gToastWindow.rootViewController = nil;
            gToastWindow = nil;
        }

        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
        UIWindow *w = scene
            ? [[UIWindow alloc] initWithWindowScene:scene]
            : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        w.windowLevel = UIWindowLevelAlert + 2;
        w.backgroundColor = [UIColor clearColor];

        PDToastViewController *vc = [PDToastViewController new];
        vc.view.backgroundColor = [UIColor clearColor];

        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectInset(vc.view.bounds, 12, 70)];
        tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tv.editable = NO;
        tv.selectable = YES;
        tv.alwaysBounceVertical = YES;
        tv.text = body;
        tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        tv.textColor = [UIColor labelColor];
        tv.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.97];
        tv.layer.cornerRadius = 14;
        tv.layer.masksToBounds = YES;
        tv.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
        [vc.view addSubview:tv];

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:vc action:@selector(dismissSelf)];
        [vc.view addGestureRecognizer:tap];

        w.rootViewController = vc;
        w.hidden = NO;
        gToastWindow = w;

        NSLog(@"[PetDFY.Toast] %@", [body stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);

        if (sec > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PDHideToast();
            });
        }
    });
}
