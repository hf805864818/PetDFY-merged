//
//  PDMemoryEditor.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  逐方法来源：out/prefs_asm/000*_PDMemoryEditor_*.asm（image base = 0）
//
#import "PDMemoryEditor.h"

#import "PDAIMemory.h"

extern NSString *PDLocalizedString(NSString *key); // 0x23cac

@interface PDMemoryEditor () {
    PDAIMemory *_memory;
    NSString *_path;
    NSString *_original;
    UITextView *_editor;
    BOOL _initialViewportPending;
}
@end

@implementation PDMemoryEditor

// imp 0x01f940  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = [self.path lastPathComponent];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIBarButtonItem *saveItem =
        [[UIBarButtonItem alloc] initWithTitle:PDLocalizedString(@"保存")
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(save)];
    self.navigationItem.rightBarButtonItem = saveItem;

    self.editor = [UITextView textViewUsingTextLayoutManager:NO];
    self.editor.translatesAutoresizingMaskIntoConstraints = NO;
    self.editor.font = [UIFont systemFontOfSize:16.0];
    self.editor.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    self.editor.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    self.original = [self.memory executeTool:@"read_file"
                                   arguments:@{@"path": self.path}];
    self.editor.text = self.original;
    [self.editor setSelectedRange:NSMakeRange(0, 0)];
    self.initialViewportPending = YES;

    [self.view addSubview:self.editor];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.editor.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.editor.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.editor.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.editor.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    ]];
}

// imp 0x01fe70  types v16@0:8
- (void)pd_positionInitialText {
    if (!self.initialViewportPending) {
        return;
    }
    if (self.editor.isFirstResponder) {
        return;
    }
    if (self.editor.isDragging) {
        return;
    }
    if (self.editor.isDecelerating) {
        return;
    }
    if (CGRectIsEmpty(self.editor.bounds)) {
        return;
    }

    [self.editor layoutIfNeeded];
    [self.editor.layoutManager ensureLayoutForTextContainer:self.editor.textContainer];
    [self.editor setContentOffset:CGPointZero animated:NO];
}

// imp 0x01ffe0  types v16@0:8
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pd_positionInitialText];
}

// imp 0x020028  types v20@0:8B16
- (void) viewDidAppear:(BOOL)a1 {
    [super viewDidAppear:a1];
    [self.view layoutIfNeeded];
    [self pd_positionInitialText];
    self.initialViewportPending = NO;
}

// imp 0x020094  types v16@0:8
- (void)save {
    NSString *current = [self.memory executeTool:@"read_file"
                                      arguments:@{@"path": self.path}];

    if ([current isEqual:self.original]) {
        NSString *result = [self.memory executeTool:@"write_file"
                                         arguments:@{
            @"path": self.path,
            @"content": self.editor.text ?: @"",
        }];

        if ([result containsString:@"failed"]) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:PDLocalizedString(@"保存失败")
                                 message:result
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
    } else {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:PDLocalizedString(@"记忆文件已更新")
                             message:PDLocalizedString(@"此文件在编辑期间发生变化，当前修改尚未保存。可先复制修改内容，再重新打开文件进行合并。")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"好")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

// imp 0x0203dc  types @16@0:8
- (id)memory {
    return _memory;
}

// imp 0x0203ec  types v24@0:8@16
- (void) setMemory:(id)a1 {
    _memory = a1;
}

// imp 0x020400  types @16@0:8
- (id)path {
    return _path;
}

// imp 0x020410  types v24@0:8@16
- (void) setPath:(id)a1 {
    _path = a1;
}

// imp 0x02041c  types @16@0:8
- (id)original {
    return _original;
}

// imp 0x02042c  types v24@0:8@16
- (void) setOriginal:(id)a1 {
    _original = a1;
}

// imp 0x020438  types @16@0:8
- (id)editor {
    return _editor;
}

// imp 0x020448  types v24@0:8@16
- (void) setEditor:(id)a1 {
    _editor = a1;
}

// imp 0x02045c  types B16@0:8
- (BOOL)initialViewportPending {
    return _initialViewportPending;
}

// imp 0x02046c  types v20@0:8B16
- (void) setInitialViewportPending:(BOOL)a1 {
    _initialViewportPending = a1;
}

@end