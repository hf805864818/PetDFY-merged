//
//  PDRootListController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <Preferences/Preferences.h>

@interface PDRootListController : PSListController <UIDocumentPickerDelegate>

- (id) localizedSpecifiers:(id)a1;
- (id)specifiers;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
- (void) viewWillAppear:(BOOL)a1;
- (void)dealloc;
- (void)updateAssetStatus;
- (void)retryAssets;
- (void)importAssets;
- (void) documentPicker:(id)a1 didPickDocumentsAtURLs:(id)a2;
- (void)removeAssets;
- (void)installHeader;
- (void) setPreferenceValue:(id)a1 specifier:(id)a2;
- (void) sendCommand:(id)a1;
- (void)openAIChat;
- (void)editAIPrompt;
- (void)openAIHistory;
- (void)editAIMemory;
- (void)fetchAIModels;
- (void)configureAIKey;
- (id)pdHeader;
- (void) setPdHeader:(id)a1;
- (BOOL)assetCopying;
- (void) setAssetCopying:(BOOL)a1;

@property (nonatomic, strong) UIView *pdHeader;
@property (nonatomic, assign) BOOL assetCopying;

@end
