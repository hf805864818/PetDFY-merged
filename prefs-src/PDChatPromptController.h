//
//  PDChatPromptController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDChatPromptController : UIViewController <UITextViewDelegate>

- (void)viewDidLoad;
- (id)savedTemplate;
- (void) insertVariable:(id)a1;
- (void)resetTemplate;
- (void)save;
- (void) textViewDidChange:(id)a1;
- (id)editor;
- (void) setEditor:(id)a1;

@property (nonatomic, strong) UITextView *editor;

@end
