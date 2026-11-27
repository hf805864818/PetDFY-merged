//
//  PDLabeledSliderCell.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <Preferences/Preferences.h>

@interface PDLabeledSliderCell : PSSliderTableCell

- (void) controlChanged:(id)a1;
- (void)layoutSubviews;
- (void) refreshCellContentsWithSpecifier:(id)a1;
- (void)prepareForReuse;
- (void)pd_enableValueLabelInput;
- (void) pd_preventValueLabelClipping:(id)a1;
- (void)pd_promptForSliderValue;

@end
