//
//  PDSwitchWithInfoCell.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <Preferences/Preferences.h>

@interface PDSwitchWithInfoCell : PSSwitchTableCell

- (id) initWithStyle:(NSInteger)a1 reuseIdentifier:(id)a2 specifier:(id)a3;
- (void)pd_infoButtonTapped;
- (void)tintColorDidChange;
- (void) refreshCellContentsWithSpecifier:(id)a1;
- (id)infoButton;
- (void) setInfoButton:(id)a1;

@property (nonatomic, strong) UIButton *infoButton;

@end
