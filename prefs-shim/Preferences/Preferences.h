//
//  Preferences/Preferences.h — 编译期 shim
//
//  iOS SDK 不带 Preferences 私有框架头。prefs-src/ 里 18 个类需要编译，
//  但运行时由越狱环境的 Preferences 框架提供真实实现（这里是声明，不是实现）。
//
//  只放 prefs-src 实际用到的 API，够编译即可；不要在这里写实现。
//

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class PSSpecifier;

#pragma mark - PSSpecifier

@interface PSSpecifier : NSObject

@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) id target;
@property (nonatomic, assign) SEL setter;
@property (nonatomic, assign) SEL getter;
@property (nonatomic, assign) SEL detail;
@property (nonatomic, retain) Class detailControllerClass;
@property (nonatomic, retain) Class cellType;
@property (nonatomic, retain) id userInfo;
@property (nonatomic, retain) NSDictionary *properties;

+ (id)preferenceSpecifierNamed:(NSString *)name
                        target:(id)target
                           set:(SEL)setter
                           get:(SEL)getter
                        detail:(Class)detail
                          cell:(NSInteger)cell
                          edit:(Class)edit;
+ (id)emptyGroupSpecifier;
+ (id)groupSpecifierWithName:(NSString *)name;
+ (id)switchSpecifierWithTitle:(NSString *)title
                        target:(id)target
                           set:(SEL)setter
                           get:(SEL)getter;

- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)removePropertyForKey:(NSString *)key;

@end

#pragma mark - 控制器

@interface PSViewController : UIViewController

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;

@end

@interface PSListController : PSViewController {
    NSMutableArray *_specifiers;
}

@property (nonatomic, retain) NSArray *specifiers;

- (id)specifierForID:(NSString *)identifier;
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;

- (void)reload;
- (void)reloadSpecifiers;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (void)reloadSpecifierID:(NSString *)identifier;

- (void)beginUpdates;
- (void)endUpdates;

- (NSArray *)localizedSpecifiers:(NSArray *)specifiers;

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;

@end

#pragma mark - Cell

@interface PSTableCell : UITableViewCell

- (id)initWithStyle:(NSInteger)style
    reuseIdentifier:(NSString *)reuseIdentifier
          specifier:(PSSpecifier *)specifier;

- (void)setSpecifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifier;
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;

@end

@interface PSSwitchTableCell : PSTableCell
- (void)controlChanged:(id)sender;
@end

@interface PSSliderTableCell : PSTableCell
- (void)controlChanged:(id)sender;
@end

@interface PSListItemsController : PSListController
@end

@interface PSDetailController : PSViewController
@end
