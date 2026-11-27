//
//  PDChatHistoryController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDChatHistoryController : UITableViewController

- (void)viewDidLoad;
- (void) viewWillAppear:(BOOL)a1;
- (void)reloadHistory;
- (void)confirmClearHistory;
- (NSInteger) tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2;
- (id) tableView:(id)a1 titleForFooterInSection:(NSInteger)a2;
- (id) tableView:(id)a1 cellForRowAtIndexPath:(id)a2;
- (id)rows;
- (void) setRows:(id)a1;
- (NSUInteger)loadGeneration;
- (void) setLoadGeneration:(NSUInteger)a1;
- (BOOL)cleaning;
- (void) setCleaning:(BOOL)a1;

@property (nonatomic, strong) NSArray *rows;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) BOOL cleaning;

@end
