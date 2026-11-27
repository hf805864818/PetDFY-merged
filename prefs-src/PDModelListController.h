//
//  PDModelListController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDModelListController : UITableViewController

- (void)viewDidLoad;
- (NSInteger) tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2;
- (id) tableView:(id)a1 cellForRowAtIndexPath:(id)a2;
- (void) tableView:(id)a1 didSelectRowAtIndexPath:(id)a2;
- (id)models;
- (void) setModels:(id)a1;

@property (nonatomic, strong) NSArray *models;

@end
