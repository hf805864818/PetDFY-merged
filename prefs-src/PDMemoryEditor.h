//
//  PDMemoryEditor.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDMemoryEditor : UIViewController

- (void)viewDidLoad;
- (void)pd_positionInitialText;
- (void)viewDidLayoutSubviews;
- (void) viewDidAppear:(BOOL)a1;
- (void)save;
- (id)path;
- (void) setPath:(id)a1;
- (id)original;
- (void) setOriginal:(id)a1;
- (id)editor;
- (void) setEditor:(id)a1;
- (BOOL)initialViewportPending;
- (void) setInitialViewportPending:(BOOL)a1;

@property (nonatomic, strong) PDAIMemory *memory;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *original;
@property (nonatomic, strong) UITextView *editor;
@property (nonatomic, assign) BOOL initialViewportPending;

@end
