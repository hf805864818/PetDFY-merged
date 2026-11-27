//
//  PDProviderController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PDRootListController.h"

@interface PDProviderController : PDRootListController

- (id)specifiers;
- (void)viewDidLoad;
- (void)installHeader;
- (void) viewWillAppear:(BOOL)a1;
- (void) setPreferenceValue:(id)a1 specifier:(id)a2;

@end
