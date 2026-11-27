//
//  PDSectionTitleCell.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <Preferences/Preferences.h>

@interface PDSectionTitleCell : PSTableCell

- (id) initWithStyle:(NSInteger)a1 reuseIdentifier:(id)a2 specifier:(id)a3;
- (void) refreshCellContentsWithSpecifier:(id)a1;
- (void) pd_refreshTitleWithSpecifier:(id)a1;
- (void)tintColorDidChange;
- (id)sectionTitleLabel;
- (void) setSectionTitleLabel:(id)a1;

@property (nonatomic, strong) UILabel *sectionTitleLabel;

@end
