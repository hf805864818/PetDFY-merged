//
//  PDChatMemoryController.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDChatMemoryController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (void)viewDidLoad;
- (void) viewWillAppear:(BOOL)a1;
- (void)reloadFiles;
- (NSInteger) numberOfSectionsInTableView:(id)a1;
- (NSInteger) tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2;
- (id) tableView:(id)a1 titleForHeaderInSection:(NSInteger)a2;
- (id) tableView:(id)a1 titleForFooterInSection:(NSInteger)a2;
- (id) fileAtIndexPath:(id)a1;
- (BOOL) canEditFile:(id)a1;
- (id) tableView:(id)a1 cellForRowAtIndexPath:(id)a2;
- (void) tableView:(id)a1 didSelectRowAtIndexPath:(id)a2;
- (BOOL) tableView:(id)a1 canEditRowAtIndexPath:(id)a2;
- (void) tableView:(id)a1 commitEditingStyle:(NSInteger)a2 forRowAtIndexPath:(id)a3;
- (void)confirmCleanup;
- (void) maintain:(id)a1 path:(id)a2;
- (id)memory;
- (void) setMemory:(id)a1;
- (id)table;
- (void) setTable:(id)a1;
- (id)files;
- (void) setFiles:(id)a1;
- (id)protectedFiles;
- (void) setProtectedFiles:(id)a1;
- (BOOL)cleaning;
- (void) setCleaning:(BOOL)a1;

@property (nonatomic, strong) PDAIMemory *memory;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) NSArray *protectedFiles;
@property (nonatomic, assign) BOOL cleaning;

@end
