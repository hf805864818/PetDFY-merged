//
//  PDChatMemoryController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  逐方法来源：out/prefs_asm/000*_PDChatMemoryController_*.asm（image base = 0）
//
#import "PDChatMemoryController.h"

#import "PDAIMemory.h"
#import "PDChatService.h"
#import "PDMemoryEditor.h"

extern NSString *PDDataPath(void);                 // 0x236dc
extern NSString *PDLocalizedString(NSString *key); // 0x23cac

// 二进制 0x2129c / 0x229fc 处接收者都是 OBJC_CLASS_$_PDChatService，即类方法

@interface PDChatMemoryController () {
    PDAIMemory *_memory;
    UITableView *_table;
    NSArray *_files;
    NSArray *_protectedFiles;
    BOOL _cleaning;
}
@end

@implementation PDChatMemoryController

// imp 0x0204e4  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = PDLocalizedString(@"记忆工作区");

    self.memory = [[PDAIMemory alloc] initWithRoot:
        [PDDataPath() stringByAppendingPathComponent:@"workspace"]];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.table setDelegate:self];
    [self.table setDataSource:self];
    [self.view addSubview:self.table];
}

// imp 0x020678  types v20@0:8B16
- (void) viewWillAppear:(BOOL)a1 {
    [super viewWillAppear:a1];
    [self reloadFiles];
}

// imp 0x0206c0  types v16@0:8
- (void)reloadFiles {
    NSMutableArray *protectedFiles = [NSMutableArray new];
    NSMutableArray *files = [NSMutableArray new];

    for (NSString *file in self.memory.files) {
        [([self.memory isProtectedFile:file] ? protectedFiles : files) addObject:file];
    }

    self.protectedFiles = protectedFiles;
    self.files = files;
    [self.table reloadData];
}

// imp 0x020850  types q24@0:8@16
- (NSInteger) numberOfSectionsInTableView:(id)a1 {
    return 3;
}

// imp 0x020858  types q32@0:8@16q24
- (NSInteger) tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2 {
    if (a2 == 0) {
        return (NSInteger)self.protectedFiles.count;
    }
    if (a2 == 1) {
        return (NSInteger)self.files.count;
    }
    return 1;
}

// imp 0x0208d0  types @32@0:8@16q24
- (id) tableView:(id)a1 titleForHeaderInSection:(NSInteger)a2 {
    if (a2 == 0) {
        return PDLocalizedString(@"常驻记忆");
    }
    if (a2 == 1) {
        return PDLocalizedString(@"普通文件");
    }
    return nil;
}

// imp 0x020930  types @32@0:8@16q24
- (id) tableView:(id)a1 titleForFooterInSection:(NSInteger)a2 {
    if (a2 == 0) {
        return PDLocalizedString(@"常驻文件可手动编辑，不会被清理或随对话记录删除。KEY_MEMORY.md 专门保存重要的用户偏好与互动习惯。");
    }
    if (a2 == 1) {
        return self.files.count != 0
            ? PDLocalizedString(@"文本文件可点开编辑；左滑可删除普通文件。")
            : PDLocalizedString(@"暂无普通文件。");
    }
    return PDLocalizedString(@"清理对话生成的普通文件及其旧版本，保留常驻文件和对话记录。");
}

// imp 0x0209d4  types @24@0:8@16
- (id) fileAtIndexPath:(id)a1 {
    NSIndexPath *indexPath = a1;
    NSArray *array = indexPath.section == 0 ? self.protectedFiles : self.files;
    return array[indexPath.row];
}

// imp 0x020a54  types B24@0:8@16
- (BOOL) canEditFile:(id)a1 {
    return [@[@"md", @"txt", @"json"] containsObject:[a1 pathExtension].lowercaseString];
}

// imp 0x020ab0  types @32@0:8@16@24
- (id) tableView:(id)a1 cellForRowAtIndexPath:(id)a2 {
    UITableView *tableView = a1;
    NSIndexPath *indexPath = a2;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"file"];
    }

    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.userInteractionEnabled = !self.cleaning;

    if (indexPath.section == 2) {
        cell.textLabel.text = self.cleaning
            ? PDLocalizedString(@"正在清理…")
            : PDLocalizedString(@"清理普通文件…");
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else {
        NSString *file = [self fileAtIndexPath:indexPath];
        cell.textLabel.text = file;

        if ([self canEditFile:file]) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }

        if ([file isEqual:@"CONSTITUTION.md"]) {
            cell.detailTextLabel.text = PDLocalizedString(@"角色性格与习惯");
        } else if ([file isEqual:@"PARTNER.md"]) {
            cell.detailTextLabel.text = PDLocalizedString(@"用户资料与长期印象");
        } else if ([file isEqual:@"KEY_MEMORY.md"]) {
            cell.detailTextLabel.text = PDLocalizedString(@"关键记忆：重要偏好与互动习惯");
        }
    }

    return cell;
}

// imp 0x020d24  types v32@0:8@16@24
- (void) tableView:(id)a1 didSelectRowAtIndexPath:(id)a2 {
    UITableView *tableView = a1;
    NSIndexPath *indexPath = a2;

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.cleaning) {
        return;
    }

    if (indexPath.section == 2) {
        [self confirmCleanup];
        return;
    }

    NSString *file = [self fileAtIndexPath:indexPath];
    if ([self canEditFile:file]) {
        PDMemoryEditor *editor = [PDMemoryEditor new];
        editor.memory = self.memory;
        editor.path = file;
        [self.navigationController pushViewController:editor animated:YES];
    }
}

// imp 0x020e24  types B32@0:8@16@24
- (BOOL) tableView:(id)a1 canEditRowAtIndexPath:(id)a2 {
    NSIndexPath *indexPath = a2;

    if (self.cleaning) {
        return NO;
    }
    if (indexPath.section != 1) {
        return NO;
    }
    return ![self.memory isProtectedFile:[self fileAtIndexPath:indexPath]];
}

// imp 0x020eb8  types v40@0:8@16q24@32
- (void) tableView:(id)a1 commitEditingStyle:(NSInteger)a2 forRowAtIndexPath:(id)a3 {
    NSIndexPath *indexPath = a3;

    if (a2 != UITableViewCellEditingStyleDelete) {
        return;
    }
    if (indexPath.section != 1) {
        return;
    }

    NSString *file = [self fileAtIndexPath:indexPath];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:PDLocalizedString(@"删除文件？")
                         message:file
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"删除")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [self maintain:@"delete_file" path:file];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x021070  types v16@0:8
- (void)confirmCleanup {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:PDLocalizedString(@"清理普通文件？")
                         message:PDLocalizedString(@"将停止当前回复并删除普通工作区文件及其旧版本。CONSTITUTION.md、PARTNER.md、KEY_MEMORY.md 和对话记录会保留。")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"清理")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [self maintain:@"clean_workspace" path:nil];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x0211e8  types v32@0:8@16@24
- (void) maintain:(id)a1 path:(id)a2 {
    NSString *operation = a1;
    NSString *path = a2;

    self.cleaning = YES;
    [self.table reloadData];

    __weak PDChatMemoryController *weakSelf = self;
    [PDChatService requestDataMaintenance:operation
                                     path:path
                               completion:^(NSError *error) {
        PDChatMemoryController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.cleaning = NO;
        [strongSelf reloadFiles];

        if (error) {
            UIAlertController *failure = [UIAlertController
                alertControllerWithTitle:PDLocalizedString(@"操作未完成")
                                 message:PDLocalizedString([error localizedDescription])
                          preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                        style:UIAlertActionStyleDefault
                                                      handler:nil]];
            [strongSelf presentViewController:failure animated:YES completion:nil];
        }
    }];
}

// imp 0x02141c  types @16@0:8
- (id)memory {
    return _memory;
}

// imp 0x02142c  types v24@0:8@16
- (void) setMemory:(id)a1 {
    _memory = a1;
}

// imp 0x021440  types @16@0:8
- (id)table {
    return _table;
}

// imp 0x021450  types v24@0:8@16
- (void) setTable:(id)a1 {
    _table = a1;
}

// imp 0x021464  types @16@0:8
- (id)files {
    return _files;
}

// imp 0x021474  types v24@0:8@16
- (void) setFiles:(id)a1 {
    _files = a1;
}

// imp 0x021488  types @16@0:8
- (id)protectedFiles {
    return _protectedFiles;
}

// imp 0x021498  types v24@0:8@16
- (void) setProtectedFiles:(id)a1 {
    _protectedFiles = a1;
}

// imp 0x0214ac  types B16@0:8
- (BOOL)cleaning {
    return _cleaning;
}

// imp 0x0214bc  types v20@0:8B16
- (void) setCleaning:(BOOL)a1 {
    _cleaning = a1;
}

@end