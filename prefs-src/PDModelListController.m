//
//  PDModelListController.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  反汇编来源：out/prefs_asm/00004710_..、00004774_..、000047a8_..、00004ad4_..、00004ca0_..
//
#import "PDModelListController.h"

extern NSString *PDLocalizedString(NSString *key);
extern void PDAIWritePreferences(NSDictionary *values);   // imp 0x1343c

@interface PDModelListController () {
    // 二进制中 -models / -setModels: 是直接读写 ivar（_OBJC_IVAR_$_PDModelListController._models），
    // 两个存取器都手写，故 ivar 显式声明。
    NSArray *_models;
}
@end

@implementation PDModelListController

// imp 0x004710  types v16@0:8
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setTitle:PDLocalizedString(@"模型列表")];
}

// imp 0x004774  types q24@0:8@16q24
- (NSInteger)tableView:(id)a1 numberOfRowsInSection:(NSInteger)a2 {
    return [[self models] count];
}

// imp 0x0047a8  types @32@0:8@16@24
- (id)tableView:(id)a1 cellForRowAtIndexPath:(id)a2 {
    UITableViewCell *cell = [a1 dequeueReusableCellWithIdentifier:@"model"];
    if (!cell) {
        // UITableViewCellStyleSubtitle = 3
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"model"];
    }

    NSDictionary *model = [[self models] objectAtIndexedSubscript:[a2 row]];

    [[cell textLabel] setText:model[@"name"]];
    [[cell textLabel] setNumberOfLines:2];

    NSMutableArray *parts = [NSMutableArray arrayWithObject:model[@"id"]];

    if (model[@"contextWindow"]) {
        [parts addObject:[NSString stringWithFormat:PDLocalizedString(@"上下文 %@"), model[@"contextWindow"]]];
    }
    if (model[@"inputImages"]) {
        [parts addObject:PDLocalizedString([model[@"inputImages"] boolValue] ? @"接受图片" : @"仅文字")];
    }
    if (model[@"maxOutputTokens"]) {
        [parts addObject:[NSString stringWithFormat:PDLocalizedString(@"最大输出 %@"), model[@"maxOutputTokens"]]];
    }

    [[cell detailTextLabel] setText:[parts componentsJoinedByString:@" · "]];
    [[cell detailTextLabel] setNumberOfLines:0];

    return cell;
}

// imp 0x004ad4  types v32@0:8@16@24
- (void)tableView:(id)a1 didSelectRowAtIndexPath:(id)a2 {
    NSDictionary *model = [[self models] objectAtIndexedSubscript:[a2 row]];

    NSMutableDictionary *values = [@{ @"AIModel": model[@"id"] } mutableCopy];
    if (model[@"contextWindow"]) {
        [values setObject:model[@"contextWindow"] forKeyedSubscript:@"AIContextTokens"];
    }
    if (model[@"inputImages"]) {
        [values setObject:model[@"inputImages"] forKeyedSubscript:@"AIAcceptImages"];
    }
    PDAIWritePreferences(values);

    [[self navigationController] popViewControllerAnimated:YES];
}

// imp 0x004ca0  types @16@0:8
- (id)models {
    return _models;
}

// imp 0x004cb0  types v24@0:8@16
- (void)setModels:(id)a1 {
    _models = a1;
}

// imp 0x004cc4  types v16@0:8  →  - .cxx_destruct
// 原二进制的 .cxx_destruct 只做 objc_storeStrong(&_models, nil)，属于编译器生成物；
// ARC 下由编译器自动合成，源码不重复实现（手写会与合成版本冲突）。

@end