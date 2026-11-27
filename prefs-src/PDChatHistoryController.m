//
//  PDChatHistoryController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  逐方法来源：out/prefs_asm/000*_PDChatHistoryController_*.asm（image base = 0）
//  所有 CF 字符串、选择器、常量均由二进制解析得到；未还原处标 // Assumed: ...
//
#import "PDChatHistoryController.h"

#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>

#import "PDChatService.h"

// 同 dylib 内 C 函数（out/prefs_objc.txt / __text 符号）
extern NSString *PDAIString(id value);          // 0x1329c：是 NSString 就返回，否则返回 @""
extern id PDAIParseScript(id script);           // 0x13cac：返回含 beats 的字典
extern NSString *PDLocalizedString(NSString *key); // 0x23cac
extern NSString *PDDataPath(void);              // 0x236dc：返回静态 "/var/mobile/Library/Application Support/PetDFY"

// 二进制里是 PDChatService 的类方法（0x229fc 处 x0 = OBJC_CLASS_$_PDChatService）

@interface PDChatHistoryController () {
    NSArray *_rows;
    NSUInteger _loadGeneration;
    BOOL _cleaning;
}
@end

// 0x22558：text 非空且不以 [failed] / [skipped] / [interrupted] 开头
// Assumed: 函数名（二进制内无符号）；数组字面量地址 0x53238 的三个元素来自 __objc_arraydata 0x52da0/0x52da8/0x52db0
static BOOL PDHistoryHasVisibleText(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    for (NSString *prefix in @[@"[failed]", @"[skipped]", @"[interrupted]"]) {
        if ([text hasPrefix:prefix]) {
            return NO;
        }
    }
    return YES;
}

@implementation PDChatHistoryController

// imp 0x021534  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = PDLocalizedString(@"对话记录");

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;

    UIBarButtonItem *clearItem =
        [[UIBarButtonItem alloc] initWithTitle:PDLocalizedString(@"清空")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(confirmClearHistory)];
    self.navigationItem.rightBarButtonItem = clearItem;
}

// imp 0x021658  types v20@0:8B16
- (void) viewWillAppear:(BOOL)a1 {
    [super viewWillAppear:a1];
    [self reloadHistory];
}

// imp 0x0216a0  types v16@0:8
- (void)reloadHistory {
    if (self.cleaning) {
        return;
    }

    NSUInteger generation = self.loadGeneration + 1;
    self.loadGeneration = generation;

    __weak PDChatHistoryController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY /* 0x11 */, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:
            [PDDataPath() stringByAppendingPathComponent:@"conversation.json"]];

        id root = nil;
        if (data) {
            root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        }

        NSMutableArray *rows = [NSMutableArray new];
        NSMutableDictionary *toolResults = [NSMutableDictionary new];

        // ---- 第一遍：收集 tool 结果（tool_call_id -> content）
        if ([root isKindOfClass:[NSArray class]]) {
            for (NSDictionary *entry in (NSArray *)root) {
                if (![entry isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                if ([[entry objectForKeyedSubscript:@"role"] isEqual:@"tool"]) {
                    NSString *callID = PDAIString([entry objectForKeyedSubscript:@"tool_call_id"]);
                    if (callID.length != 0) {
                        toolResults[[entry objectForKeyedSubscript:@"tool_call_id"]] =
                            PDAIString([entry objectForKeyedSubscript:@"content"]);
                    }
                }
            }
        }

        // ---- 第二遍：组装展示行
        if ([root isKindOfClass:[NSArray class]]) {
            for (NSDictionary *entry in (NSArray *)root) {
                if (![entry isKindOfClass:[NSDictionary class]]) {
                    continue;
                }

                if ([[entry objectForKeyedSubscript:@"role"] isEqual:@"user"]) {
                    NSString *content = PDAIString([entry objectForKeyedSubscript:@"content"]);
                    content = [content stringByReplacingOccurrencesOfString:@"<external_event_frame>\n"
                                                                withString:@""];
                    content = [content stringByReplacingOccurrencesOfString:@"\n</external_event_frame>"
                                                                withString:@""];
                    [rows addObject:@{@"title": PDLocalizedString(@"消息与互动"),
                                      @"text": content}];
                }

                id toolCalls = [entry objectForKeyedSubscript:@"tool_calls"];
                if ([toolCalls isKindOfClass:[NSArray class]]) {
                    for (NSDictionary *call in (NSArray *)toolCalls) {
                        if (![call isKindOfClass:[NSDictionary class]]) {
                            continue;
                        }
                        id function = [call objectForKeyedSubscript:@"function"];
                        if (![function isKindOfClass:[NSDictionary class]]) {
                            continue;
                        }

                        NSString *callID = PDAIString([call objectForKeyedSubscript:@"id"]);
                        if (!PDHistoryHasVisibleText(toolResults[callID])) {
                            continue;
                        }

                        NSString *name = [call objectForKeyedSubscript:@"function"][@"name"];
                        NSString *arguments =
                            PDAIString([call objectForKeyedSubscript:@"function"][@"arguments"]);
                        id parsed = [NSJSONSerialization JSONObjectWithData:[arguments dataUsingEncoding:NSUTF8StringEncoding]
                                                                   options:0
                                                                     error:NULL];
                        if (![parsed isKindOfClass:[NSDictionary class]]) {
                            continue;
                        }

                        if ([name isEqual:@"pet_say"]) {
                            id beats = [PDAIParseScript(PDAIString([parsed objectForKeyedSubscript:@"script"]))
                                           objectForKeyedSubscript:@"beats"];
                            for (id beat in (NSArray *)beats) {
                                NSString *text = PDAIString([beat objectForKeyedSubscript:@"text"]);
                                if (text.length != 0) {
                                    [rows addObject:@{@"title": PDLocalizedString(@"大肥鱼"),
                                                      @"text": text}];
                                }
                            }
                        } else if ([name isEqual:@"pet_ask"]) {
                            [rows addObject:@{@"title": PDLocalizedString(@"大肥鱼 · 提问"),
                                              @"text": PDAIString([parsed objectForKeyedSubscript:@"question"])}];
                        }
                    }
                }

                // ---- 附件图片：_attachments（用户上传）与 _shownImages（宠物发出的图片）
                for (NSString *key in @[@"_attachments", @"_shownImages"]) {
                    id items = [entry objectForKeyedSubscript:key];
                    if (![items isKindOfClass:[NSArray class]]) {
                        continue;
                    }
                    for (id item in (NSArray *)items) {
                        if ([key isEqual:@"_shownImages"] &&
                            !PDHistoryHasVisibleText(PDAIString([entry objectForKeyedSubscript:@"content"]))) {
                            continue;
                        }

                        NSString *ident = PDAIString([item objectForKeyedSubscript:@"id"]);
                        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:ident];
                        if (uuid == nil) {
                            continue;
                        }

                        NSData *payload = [NSData dataWithContentsOfFile:
                            [[PDDataPath() stringByAppendingPathComponent:@"attachments"]
                                stringByAppendingPathComponent:ident]];
                        if (!payload) {
                            continue;
                        }

                        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)payload, NULL);
                        if (!source) {
                            continue;
                        }

                        NSDictionary *options = @{
                            (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                            (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @640,
                            (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                        };
                        CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(
                            source, 0, (__bridge CFDictionaryRef)options);
                        if (!thumbnail) {
                            CFRelease(source);
                            continue;
                        }

                        UIImage *image = [UIImage imageWithCGImage:thumbnail];
                        CGImageRelease(thumbnail);
                        CFRelease(source);
                        if (!image) {
                            continue;
                        }

                        NSString *title = [key isEqual:@"_shownImages"]
                            ? PDLocalizedString(@"大肥鱼 · 图片")
                            : PDLocalizedString(@"图片");
                        [rows addObject:@{@"title": title, @"image": image}];
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            PDChatHistoryController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            if (strongSelf.loadGeneration != generation) {
                return;
            }
            if (strongSelf.cleaning) {
                return;
            }

            strongSelf.rows = rows;
            [strongSelf.tableView reloadData];

            if (rows.count != 0) {
                [strongSelf.tableView scrollToRowAtIndexPath:
                        [NSIndexPath indexPathForRow:(NSInteger)(rows.count - 1) inSection:0]
                                             atScrollPosition:UITableViewScrollPositionBottom
                                                     animated:NO];
            }
        });
    });
}

// imp 0x0227c0  types v16@0:8
- (void)confirmClearHistory {
    if (self.cleaning) {
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:PDLocalizedString(@"清空对话记录？")
                         message:PDLocalizedString(@"将停止当前回复，删除消息、互动记录、对话附件和上下文交接笔记。常驻记忆及其他工作区文件会保留。")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:PDLocalizedString(@"清空")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        self.cleaning = YES;
        self.loadGeneration = self.loadGeneration + 1;
        self.navigationItem.rightBarButtonItem.enabled = NO;

        __weak PDChatHistoryController *weakSelf = self;
        [PDChatService requestDataMaintenance:@"clear_history"
                                         path:nil
                                   completion:^(NSError *error) {
            PDChatHistoryController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.cleaning = NO;
            strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
            [strongSelf reloadHistory];

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
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

// imp 0x022bac  types q32@0:8@16q24
- (NSInteger) tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2 {
    return (NSInteger)self.rows.count;
}

// imp 0x022be0  types @32@0:8@16q24
- (id) tableView:(id)a1 titleForFooterInSection:(NSInteger)a2 {
    return self.rows.count != 0
        ? PDLocalizedString(@"查看消息、互动记录和图片。")
        : PDLocalizedString(@"暂无对话记录。");
}

// imp 0x022c34  types @32@0:8@16@24
- (id) tableView:(id)a1 cellForRowAtIndexPath:(id)a2 {
    NSIndexPath *indexPath = a2;
    NSDictionary *row = self.rows[indexPath.row];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:12.0];
    cell.textLabel.textColor = [UIColor secondaryLabelColor];

    cell.detailTextLabel.text = row[@"text"];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:15.0];
    cell.detailTextLabel.numberOfLines = 0;

    if (row[@"image"]) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:row[@"image"]];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        [cell.contentView addSubview:imageView];

        [NSLayoutConstraint activateConstraints:@[
            [imageView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:30.0],
            [imageView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12.0],
            [imageView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
            [imageView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
            [imageView.heightAnchor constraintEqualToConstant:200.0],
        ]];
    }

    return cell;
}

// imp 0x0230d4  types @16@0:8
- (id)rows {
    return _rows;
}

// imp 0x0230e4  types v24@0:8@16
- (void) setRows:(id)a1 {
    _rows = a1;
}

// imp 0x0230f8  types Q16@0:8
- (NSUInteger)loadGeneration {
    return _loadGeneration;
}

// imp 0x023108  types v24@0:8Q16
- (void) setLoadGeneration:(NSUInteger)a1 {
    _loadGeneration = a1;
}

// imp 0x023118  types B16@0:8
- (BOOL)cleaning {
    return _cleaning;
}

// imp 0x023128  types v20@0:8B16
- (void) setCleaning:(BOOL)a1 {
    _cleaning = a1;
}

@end