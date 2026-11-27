//
//  PDAIMemory.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  权威来源：out/prefs_asm/0001a688_PDAIMemory_initWithRoot_.asm … 0001e900_PDAIMemory__cxx_destruct.asm
//  image base = 0，所有 imp 地址均为 slice 内 VA。
//
//  实例变量：+0x08 NSString *_root（instsize=16，仅 1 个 ivar，见 __objc_ivar_list）
//
//  ---------------------------------------------------------------
//  方法分组（22 个实例方法 + 1 个类方法）
//    读写：   initWithRoot: / read:error: / write:path:operation:error: / save 路径
//    裁剪：   removeGeneratedFiles: / removeConversationHandoffs: / removeFilesForConversationOnly:error:
//    序列化： snapshot:operation: / imageForHandle: / systemContext
//    查询：   files / path: / writablePath:error: / prepareWrite:error: / isProtectedFile: /
//             protected: / lines: / lineRange:args: / glob:
//    工具：   executeTool:arguments: / run:arguments: / root / +protectedFileNames
//  ---------------------------------------------------------------
//
#import "PDAIMemory.h"

#import <sys/stat.h>
#import <stdlib.h>
#import <errno.h>

#pragma mark - 同 dylib 内的 C 辅助函数（__TEXT 段，符号已导出）

// imp 0x1329c  NSString *PDAIString(id value)
//   返回 value 本身（当它是 NSString 时），否则返回 @""
extern NSString *PDAIString(id value);

// imp 0x133d8  id PDAIPreference(NSString *key, id fallback)
extern id PDAIPreference(NSString *key, id fallback);

// imp 0x132f8  double PDAINumber(id value, double fallback)
extern double PDAINumber(id value, double fallback);

// imp 0x13718  NSString *PDAIDefaultPersona(void)   —— 返回内建人设常量
extern NSString *PDAIDefaultPersona(void);

// imp 0x13724  NSString *PDAIOrientation(void)      —— 返回 "You are …" 之类的方向说明
extern NSString *PDAIOrientation(void);

#pragma mark - 错误构造（imp 0x1b324）

// imp 0x1b324  id PDMemoryFail(NSString *message, NSError **error)
//   域 "com.susudear.petdfy.memory"，code 1，userInfo = @{ NSLocalizedDescriptionKey: message }
//   始终返回 nil（调用方写成 `return PDMemoryFail(...)`）。
static id PDMemoryFail(NSString *message, void *errorPtr) {
    NSError *__autoreleasing *error = (NSError *__autoreleasing *)errorPtr;
    if (error) {
        *error = [NSError errorWithDomain:kPDMemoryErrorDomain
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: (message ?: @"")}];
    }
    return nil;
}

#pragma mark - 常量（__cfstring / __const）

static NSString *const kPDMemoryErrorDomain;   // 前向声明（定义在下方）
static NSString *const kPDMemoryErrorDomain = @"com.susudear.petdfy.memory"; // 0x514b8

// NSDataWritingAtomic == 1（imp 0x1c8a4 / 0x1dddc 里的 w3 = 1）
static const NSDataWritingOptions kPDMemoryWriteAtomic = NSDataWritingAtomic;

static id PDMemoryFail(NSString *message, void *errorPtr);

#pragma mark -

@interface PDAIMemory () {
    NSString *_root;   // +0x08，strong
}

// 类方法：imp 0x1a67c —— 直接返回 @[@"CONSTITUTION.md", @"PARTNER.md", @"KEY_MEMORY.md"]（__objc_arrayobj 0x531d8）
+ (id)protectedFileNames;

@end

@implementation PDAIMemory

#pragma mark - 生命周期

// imp 0x01a688  types @24@0:8@16
- (id)initWithRoot:(id)a1 {
    self = [super init];
    if (self) {
        // 0x1a6fc: [[a1 stringByStandardizingPath] copy]
        _root = [[PDAIString(a1) stringByStandardizingPath] copy];

        // 0x1a710: 确保目录存在（withIntermediateDirectories:YES, attributes:NULL, error:NULL）
        [[NSFileManager defaultManager] createDirectoryAtPath:_root
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];

        // 0x1a73c: 解析真实路径（去掉符号链接与 ".."）
        char *real = realpath([_root fileSystemRepresentation], NULL);
        if (real) {
            _root = [[NSString stringWithUTF8String:real] copy];
            free(real);
        }

        // 0x1a788: 为三个常驻文件建立初始内容
        for (NSString *name in [[self class] protectedFileNames]) {
            NSString *file = [_root stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] fileExistsAtPath:file]) {
                continue;
            }
            NSString *content;
            if ([name isEqualToString:@"CONSTITUTION.md"]) {
                content = PDAIDefaultPersona();                        // 0x1a838
            } else if ([name isEqualToString:@"PARTNER.md"]) {
                content = PDAIString(PDAIPreference(@"AIMemory", @"")); // 0x1a864
            } else {
                content = @"# Key memory\n\n";                          // 0x1a85c
            }
            [content writeToFile:file
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:NULL];                            // 0x1a8a4
        }
    }
    return self;
}

// imp 0x01e8f8  types @16@0:8
- (id)root {
    return _root;
}

// imp 0x01e900  types v16@0:8
- (void)dealloc {
    // _cxx_destruct：objc_storeStrong(&_root, nil)；ARC 下由编译器生成
}

// imp 0x1b520  types @16@0:8
//   枚举 self.root 下的条目：只要「普通文件且不是符号链接」，realpath 后必须落在 root 内，
//   取相对路径收集，最后按 compare: 排序。
- (id)files {
    NSMutableArray *relativePaths = [NSMutableArray array];                     // 0x580180 objc_opt_new
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *rootURL = [NSURL fileURLWithPath:self.root];
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey];           // 0x4c0d0 / 0x4c0d8
    NSDirectoryEnumerator<NSURL *> *enumerator =
        [manager enumeratorAtURL:rootURL
      includingPropertiesForKeys:keys
                         options:NSDirectoryEnumerationSkipsHiddenFiles       // 0x4
                      errorHandler:NULL];
    for (NSURL *url in enumerator) {
        NSNumber *isRegular = nil;
        NSNumber *isLink = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:NULL];
        [url getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:NULL];
        if (!isRegular.boolValue || isLink.boolValue) {
            continue;
        }
        char *resolved = realpath(url.fileSystemRepresentation, NULL);
        if (resolved == NULL) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String:resolved];
        free(resolved);
        NSString *prefix = [self.root stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            [relativePaths addObject:[path substringFromIndex:self.root.length + 1]];
        }
    }
    return [relativePaths sortedArrayUsingSelector:@selector(compare:)];
}

// imp 0x1a67c  types @16@0:8（metaclass 上唯一的方法）
+ (id)protectedFileNames {
    return @[@"CONSTITUTION.md", @"PARTNER.md", @"KEY_MEMORY.md"];
}

#pragma mark - 路径解析

// imp 0x01a924  types @24@0:8@16
//   mem: 前缀剥离 → 拒绝绝对路径 / ".." / ".git" / ".versions" / 含 NUL 的路径
//   → 逐段拼接并 lstat，遇到符号链接即失败
//   → 结果必须以 root 开头（或恰好等于 root）
- (id)path:(id)a1 {
    NSString *p = PDAIString(a1);

    if ([p hasPrefix:@"mem:"]) {                       // 0x1a974
        p = [p substringFromIndex:4];
    }
    if ([p isAbsolutePath]) {                          // 0x1a99c
        return nil;
    }
    if ([[p pathComponents] containsObject:@".."]) {   // 0x1a9bc
        return nil;
    }
    if ([[p pathComponents] containsObject:@".git"]) { // 0x1a9dc
        return nil;
    }
    if ([[p pathComponents] containsObject:@".versions"]) { // 0x1a9fc
        return nil;
    }
    if ([p containsString:@"\0"]) {                    // 0x1aa60（CF 长度 1 的 NUL 字符串）
        return nil;
    }

    NSString *root = [self root];
    NSString *res = root;
    for (NSString *comp in [p pathComponents]) {       // 0x1aaa0
        if ([comp isEqualToString:@"."]) {             // 0x1ab08
            continue;
        }
        res = [res stringByAppendingPathComponent:comp];
        struct stat st;
        if (lstat([res fileSystemRepresentation], &st) != 0) {   // 0x1ab40
            continue;
        }
        if ((st.st_mode & S_IFMT) == S_IFLNK) {                  // 0x1ab4c
            return nil;
        }
    }

    if ([res isEqualToString:root]) {                  // 0x1ab88
        return res;
    }
    NSString *rootSlash = [root stringByAppendingString:@"/"];
    if ([res hasPrefix:rootSlash]) {                   // 0x1abbc
        return res;
    }
    return nil;
}

// imp 0x01abf8  types @32@0:8@16^@24
//   把任意用户输入规范化为工作区内的绝对路径；任何越界/异常都通过 error 返回中文原因。
- (id)writablePath:(id)a1 error:(void *)a2 {
    NSString *p = PDAIString(a1);
    p = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; // 0x1ac5c
    if ([p hasPrefix:@"mem:"]) {                                         // 0x1ac7c
        p = [p substringFromIndex:4];
    }
    NSString *path = [p stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]; // 0x1acb4

    if ([path isAbsolutePath] || [path containsString:@"\0"]) {          // 0x1acc8
        return PDMemoryFail(@"请使用记忆工作区内的相对路径。", a2);
    }

    NSMutableArray *parts = [NSMutableArray array];                      // 0x1ad00
    for (NSString *comp in [path componentsSeparatedByString:@"/"]) {    // 0x1ad2c
        if (comp.length == 0) {                                          // 0x1ad9c
            continue;
        }
        if ([comp isEqualToString:@"."]) {                               // 0x1ada8
            continue;
        }
        if ([comp isEqualToString:@".."]) {                              // 0x1adb8
            return PDMemoryFail(@"路径不能包含上级目录。", a2);
        }
        if ([comp hasPrefix:@"."]) {                                     // 0x1adc8
            return PDMemoryFail(@"点开头的路径由系统管理，不能写入、移动或删除。", a2);
        }
        [parts addObject:comp];
    }
    if (parts.count == 0) {                                             // 0x1ae10
        return PDMemoryFail(@"请指定记忆工作区内的文件。", a2);
    }

    NSString *joined = [parts componentsJoinedByString:@"/"];           // 0x1ae20
    NSString *cur = [[self root] stringByAppendingPathComponent:joined]; // 0x1ae48

    // 0x1ae6c: 自下而上找到第一个存在的祖先，记录缺失的路径段
    NSMutableArray *missing = [NSMutableArray array];
    struct stat st;
    while (lstat([cur fileSystemRepresentation], &st) != 0) {           // 0x1ae84
        if (errno != ENOENT && errno != ENOTDIR) {                      // 0x1ae9c
            return PDMemoryFail(@"路径无法解析。", a2);
        }
        NSString *parent = [cur stringByDeletingLastPathComponent];     // 0x1aeb8
        if ([parent isEqualToString:cur]) {                            // 0x1aec8
            return PDMemoryFail(@"路径无法解析。", a2);
        }
        [missing insertObject:[cur lastPathComponent] atIndex:0];       // 0x1aeec
        cur = parent;
    }

    // 0x1af14: 取 root 与祖先的真实路径，确认结果没有越出工作区
    char *rootReal = realpath([[self root] fileSystemRepresentation], NULL);
    char *curReal  = realpath([cur fileSystemRepresentation], NULL);
    NSString *rootRealPath = rootReal ? [NSString stringWithUTF8String:rootReal] : nil;
    NSString *curRealPath  = curReal  ? [NSString stringWithUTF8String:curReal]  : nil;
    free(rootReal);
    free(curReal);
    if (!rootRealPath || !curRealPath) {                               // 0x1b010
        return PDMemoryFail(@"路径无法解析。", a2);
    }

    NSString *candidate = curRealPath;
    for (NSString *comp in missing) {                                  // 0x1b02c
        candidate = [candidate stringByAppendingPathComponent:comp];
    }
    if (![candidate hasPrefix:[rootRealPath stringByAppendingString:@"/"]]) { // 0x1b0e0
        return PDMemoryFail(@"路径解析后越出了记忆工作区。", a2);
    }

    NSString *rel = [candidate substringFromIndex:[rootRealPath length] + 1]; // 0x1b100
    for (NSString *comp in [rel pathComponents]) {                      // 0x1b11c
        if ([comp hasPrefix:@"."]) {                                    // 0x1b174
            return PDMemoryFail(@"实际路径位于系统管理的隐藏目录中。", a2);
        }
    }
    if (![rel isEqualToString:joined]) {                                // 0x1b1b4
        return PDMemoryFail([NSString stringWithFormat:@"路径与盘上的真实名字不一致，请改用：%@", rel], a2);
    }

    id result = [self path:joined];                                     // 0x1b1c4
    if (!result) {                                                      // 0x1b1d4
        return PDMemoryFail(@"路径包含符号链接或不在记忆工作区内。", a2);
    }
    return result;
}

// imp 0x01b3fc  types B32@0:8@16^@24
- (BOOL)prepareWrite:(id)a1 error:(void *)a2 {
    NSString *p = PDAIString(a1);
    NSString *rootSlash = [[self root] stringByAppendingString:@"/"];   // 0x1b438
    if (![p hasPrefix:rootSlash]) {                                     // 0x1b450
        PDMemoryFail(@"请使用记忆工作区内的文件路径。", a2);
        return NO;
    }
    NSString *rel = [p substringFromIndex:[rootSlash length]];          // 0x1b468
    if (![self writablePath:rel error:a2]) {                            // 0x1b480
        return NO;
    }
    return [[NSFileManager defaultManager]
                createDirectoryAtPath:[p stringByDeletingLastPathComponent]  // 0x1b4d0
          withIntermediateDirectories:YES
                           attributes:nil
                                error:(NSError *__autoreleasing *)a2];
}

#pragma mark - 读取

// imp 0x01b824  types @32@0:8@16^@24
- (id)read:(id)a1 error:(void *)a2 {
    return [NSString stringWithContentsOfFile:PDAIString(a1)
                                     encoding:NSUTF8StringEncoding   // 0x1b830: w3 = 4
                                       error:(NSError *__autoreleasing *)a2];
}

// imp 0x01b838  types @24@0:8@16
//   mem:<path> → 走 path:；log:<uuid> → 走 <root>/../attachments/<uuid>
//   两者都要能读出 4 字节以上、6MB 以内的图片，并嗅探 mime。
- (id)imageForHandle:(id)a1 {
    NSString *filePath = nil;

    if ([a1 hasPrefix:@"mem:"]) {                                       // 0x1b874
        filePath = [self path:[a1 substringFromIndex:4]];
    } else if ([a1 hasPrefix:@"log:"]) {                                // 0x1b8b4
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:[a1 substringFromIndex:4]]; // 0x1b8e8
        if (!uuid) {
            return nil;
        }
        NSString *dir = [[[self root] stringByDeletingLastPathComponent]
                            stringByAppendingPathComponent:@"attachments"];      // 0x1b924
        filePath = [dir stringByAppendingPathComponent:[a1 substringFromIndex:4]]; // 0x1b948
    }

    if (!filePath) {                                                    // 0x1b964
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:filePath];            // 0x1b974
    if (data.length < 4) {                                              // 0x1b984
        return nil;
    }
    if (data.length > 0x600000) {                                       // 0x1b994: 6 MiB
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSString *mime = nil;
    if (data.length >= 8 && *(const uint64_t *)bytes == 0x0A1A0A0D474E5089ULL) {   // \x89PNG\r\n\x1a\n
        mime = @"image/png";                                            // 0x1bab0
    } else if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        mime = @"image/jpeg";                                           // 0x1babc
    } else if (*(const uint32_t *)bytes == 0x38464947) {                // "GIF8"
        mime = @"image/gif";                                            // 0x1baa4
    } else if (data.length >= 12 &&
               *(const uint32_t *)bytes == 0x46464952 &&                // "RIFF"
               *(const uint32_t *)(bytes + 8) == 0x50424557) {          // "WEBP"
        mime = @"image/webp";                                           // 0x1ba98
    }
    if (!mime) {
        return nil;
    }
    return @{@"data": data, @"mime": mime};                             // 0x1baf0
}

// imp 0x01bb04  types @16@0:8
- (id)systemContext {
    NSString *constitution = [self read:[[self root] stringByAppendingPathComponent:@"CONSTITUTION.md"]
                                   error:NULL];                                  // 0x1bb50
    if (!constitution) {
        constitution = PDAIDefaultPersona();                                     // 0x1bb68
    }
    NSString *partner = [self read:[[self root] stringByAppendingPathComponent:@"PARTNER.md"]
                              error:NULL];                                       // 0x1bbb0
    partner = partner ?: @"";                                                    // 0x1bbc8
    NSString *keyMemory = [self read:[[self root] stringByAppendingPathComponent:@"KEY_MEMORY.md"]
                                 error:NULL];                                    // 0x1bc10
    keyMemory = keyMemory ?: @"";                                                // 0x1bc20
    NSString *orientation = PDAIOrientation();                                   // 0x1bc40
    NSString *listing = [[self files] componentsJoinedByString:@"\n"];           // 0x1bc64

    return [NSString stringWithFormat:
            @"%@\n\n%@\n\nPARTNER.md is read in full on every request. Keep it a short, distilled portrait; longer notes go under partner/.\n%@\n\nKEY_MEMORY.md — important lasting memories (read in full on every request):\n%@\n\nHow you keep your workspace:\n- CONSTITUTION.md, PARTNER.md and KEY_MEMORY.md survive workspace cleanup and conversation-history clearing. Other files are disposable notes.\n- Save genuinely important, confirmed long-term user preferences, boundaries, and habits for interacting with the pet in KEY_MEMORY.md using edit_file or append_file during the same turn, before end_turn. Do not merely claim you remembered something.\n- Keep KEY_MEMORY.md concise, deduplicate existing facts, and correct or remove outdated facts when the user changes or rejects them. Do not infer preferences from a one-off request or store ordinary chat, transient device state, tool logs, credentials, or speculative facts there. Respect user edits and requests not to remember.\n- PARTNER.md remains the user portrait; do not erase or automatically copy its existing contents into KEY_MEMORY.md.\n- One subject per other file; name it for what it holds.\n- Before creating a file, find existing notes with glob_files or grep_files. Update stale facts in place.\n- Date time-bound notes. Move old sections or completed files to archive/.\n\nWorkspace files (read with read_file when needed):\n%@",
            orientation, constitution, partner, keyMemory, listing];             // 0x1bc88
}

#pragma mark - 保护判定

// imp 0x01bccc  types B24@0:8@16
- (BOOL)isProtectedFile:(id)a1 {
    NSString *p = [self path:a1];                                       // 0x1bcfc
    if (!p) {                                                           // 0x1bd08
        return YES;
    }
    if ([p isEqualToString:[self root]]) {                              // 0x1bd24
        return YES;
    }
    NSString *rel = [p substringFromIndex:[[self root] length] + 1];    // 0x1bd58
    for (NSString *name in [[self class] protectedFileNames]) {         // 0x1bd7c
        if ([rel caseInsensitiveCompare:name] == NSOrderedSame) {       // 0x1bdd0
            return YES;
        }
    }
    return NO;
}

// imp 0x01be50  types B24@0:8@16
- (BOOL)protected:(id)a1 {
    // 0x1be88: [a1 substringFromIndex:[[self root] length] + 1]
    return [self isProtectedFile:[PDAIString(a1) substringFromIndex:[[self root] length] + 1]];
}

#pragma mark - 删除 / 裁剪

// imp 0x01bec4  types B24@0:8^@16
- (BOOL)removeGeneratedFiles:(void *)a1 {
    return [self removeFilesForConversationOnly:NO error:a1];
}

// imp 0x01bed0  types B24@0:8^@16
- (BOOL)removeConversationHandoffs:(void *)a1 {
    return [self removeFilesForConversationOnly:YES error:a1];
}

// imp 0x01bedc  types B28@0:8B16^@20
//   conversationOnly == NO  → 删除除常驻文件外的全部普通文件
//   conversationOnly == YES → 只删 handoffs/ 下的文件
//   删除前先 snapshot:operation:，删除后清理空目录（深度优先）。
- (BOOL)removeFilesForConversationOnly:(BOOL)a1 error:(void *)a2 {
    __block NSError *blockError = nil;                                  // 0x1bf2c byref

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *rootURL = [NSURL fileURLWithPath:[self root]];               // 0x1bf78
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLIsDirectoryKey]; // 0x1bfc8

    NSDirectoryEnumerator *enumerator =
        [fm enumeratorAtURL:rootURL
 includingPropertiesForKeys:keys
                    options:0                                              // 0x1c018: w4 = 0
               errorHandler:^BOOL(NSURL *url, NSError *error) {             // 0x1c630
                   if (!blockError) {
                       blockError = error;
                   }
                   return YES;
               }];

    NSMutableArray *directories = [NSMutableArray array];               // 0x1c040
    NSMutableArray *files = [NSMutableArray array];                     // 0x1c04c
    BOOL deleteAll = !a1;                                              // 0x1c084: eor w9,w9,#1

    for (NSURL *url in enumerator) {
        NSString *rel = [[url path] substringFromIndex:[[self root] length] + 1]; // 0x1c0e8

        NSNumber *isRegular = nil;                                      // 0x1c108
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:NULL];
        NSNumber *isSymlink = nil;                                      // 0x1c12c
        [url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:NULL];
        NSNumber *isDirectory = nil;                                    // 0x1c150
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];

        if ([isSymlink boolValue]) {                                    // 0x1c16c
            continue;
        }
        if ([[rel pathComponents] containsObject:@".git"]) {            // 0x1c1ac
            if ([isDirectory boolValue]) {
                [enumerator skipDescendants];                           // 0x1c1cc
            }
            continue;
        }
        if ([isDirectory boolValue]) {                                  // 0x1c1d8
            [directories addObject:url];
            continue;
        }
        if (![isRegular boolValue]) {                                   // 0x1c1f4
            continue;
        }

        if ([rel hasPrefix:@".versions/"]) {                            // 0x1c208
            NSData *data = [NSData dataWithContentsOfURL:url];          // 0x1c21c
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil; // 0x1c240
            NSString *target = @"";
            if ([json isKindOfClass:[NSDictionary class]]) {            // 0x1c298
                target = PDAIString([json objectForKeyedSubscript:@"path"]);
            }
            if (target.length == 0) {                                   // 0x1c2d8
                continue;
            }
            BOOL prot = [self isProtectedFile:target];                  // 0x1c2e4
            BOOL remove;
            if (prot || deleteAll) {
                remove = !prot;                                         // 0x1c2f4
            } else {
                remove = [target hasPrefix:@"handoffs/"];               // 0x1c320
            }
            if (remove) {
                [files addObject:url];                                  // 0x1c348
            }
            continue;
        }

        if ([self isProtectedFile:rel]) {                               // 0x1c258
            continue;
        }
        if (deleteAll || [rel hasPrefix:@"handoffs/"]) {                // 0x1c264 / 0x1c274
            [files addObject:url];
        }
    }

    // 0x1c36c: 逐个删除，记录第一个错误
    for (NSURL *url in files) {
        NSError *err = nil;
        BOOL removed = [fm removeItemAtURL:url error:&err];             // 0x1c3dc
        if (!removed && !blockError) {
            blockError = err;                                          // 0x1c404
        }
    }

    // 0x1c434: 深度优先清理空目录
    for (NSURL *url in [directories reverseObjectEnumerator]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:[url path] error:NULL]; // 0x1c4b4
        if (contents && contents.count == 0) {                          // 0x1c4cc
            [fm removeItemAtURL:url error:NULL];                        // 0x1c4e0
        }
    }

    if (a2) {                                                           // 0x1c514
        *(NSError *__autoreleasing *)a2 = blockError;
    }
    return blockError == nil;                                           // 0x1c53c
}

#pragma mark - 快照

// imp 0x01c69c  types v32@0:8@16@24
//   把 path 的当前内容以 base64 存进 <root>/.versions/<uuid>.json
- (void)snapshot:(id)a1 operation:(id)a2 {
    NSString *path = PDAIString(a1);
    NSData *data = [NSData dataWithContentsOfFile:path];                // 0x1c6f0
    if (!data) {
        return;                                                         // 0x1c6fc
    }
    NSString *versionsDir = [[self root] stringByAppendingPathComponent:@".versions"]; // 0x1c718
    [[NSFileManager defaultManager] createDirectoryAtPath:versionsDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];        // 0x1c74c

    NSString *rel = [path substringFromIndex:[[self root] length] + 1]; // 0x1c77c
    NSNumber *stamp = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]; // 0x1c7c4
    NSDictionary *entry = @{@"path": rel,                               // 0x1c80c
                            @"operation": (a2 ?: @""),
                            @"at": stamp,
                            @"data": [data base64EncodedStringWithOptions:0]};

    NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:NULL]; // 0x1c840
    NSString *name = [[[NSUUID UUID] UUIDString] stringByAppendingString:@".json"];    // 0x1c878
    [json writeToFile:[versionsDir stringByAppendingPathComponent:name]
              options:kPDMemoryWriteAtomic
                error:NULL];                                           // 0x1c8a4
}

// imp 0x01c90c  types B48@0:8@16@24@32^@40
- (BOOL)write:(id)a1 path:(id)a2 operation:(id)a3 error:(void *)a4 {
    if (![self prepareWrite:a2 error:a4]) {                             // 0x1c954
        return NO;
    }
    [self snapshot:a2 operation:a3];                                    // 0x1c968
    return [PDAIString(a1) writeToFile:a2
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:(NSError *__autoreleasing *)a4]; // 0x1c980
}

#pragma mark - 行处理

// imp 0x01c9b4  types {_NSRange=QQ}32@0:8@16@24
//   offset 默认 1（负值从末尾算），limit 默认剩余全部；结果夹在 [0, count] 内。
- (NSRange)lineRange:(id)a1 args:(id)a2 {
    NSArray *lines = (NSArray *)a1;
    NSDictionary *args = (NSDictionary *)a2;

    NSInteger count = [lines count];                                    // 0x1c9d8
    NSInteger offset;
    if ([[args objectForKeyedSubscript:@"offset"] respondsToSelector:@selector(integerValue)]) {
        offset = [[args objectForKeyedSubscript:@"offset"] integerValue]; // 0x1ca20
    } else {
        offset = 1;                                                    // 0x1ca30
    }

    NSInteger limit;
    if ([args objectForKeyedSubscript:@"limit"]) {                      // 0x1ca50
        NSInteger l = [[args objectForKeyedSubscript:@"limit"] integerValue]; // 0x1ca6c
        limit = (l > 1) ? l : 1;                                       // 0x1ca7c
    } else {
        limit = count;                                                 // 0x1ca84
    }

    // 0x1ca88: loc = offset < 0 ? count + offset : (offset > 1 ? offset - 1 : 0)
    NSInteger loc = (offset < 0) ? (count + offset)
                                 : ((offset > 1) ? (offset - 1) : 0);
    if (loc < 0) {                                                     // 0x1caa0 bic … asr #63
        loc = 0;
    }
    if (count < loc) {                                                 // 0x1caa8
        loc = count;
    }
    NSInteger remaining = count - loc;
    NSInteger len = (remaining < limit) ? remaining : limit;           // 0x1cab8
    return NSMakeRange((NSUInteger)loc, (NSUInteger)len);
}

// imp 0x01cadc  types @24@0:8@16
- (id)lines:(id)a1 {
    NSString *text = PDAIString(a1);
    NSMutableArray *result = [[text componentsSeparatedByString:@"\n"] mutableCopy]; // 0x1cafc
    if (text.length == 0 || [text hasSuffix:@"\n"]) {                   // 0x1cb1c / 0x1cb2c
        [result removeLastObject];
    }
    return result;
}

// imp 0x01cb54  types @24@0:8@16
//   glob → NSRegularExpression："^(?:.*/)?" + 逐字符翻译 + "$"
//     '?'  → "[^/]"
//     "**" → "(?:.*/)?" （后面跟 '/' 时）否则 ".*"
//     '*'  → "[^/]*"
//     其他 → escapedPatternForString:
- (id)glob:(id)a1 {
    NSString *pattern = PDAIString(a1);
    NSMutableString *regex = [NSMutableString stringWithString:@"^(?:.*/)?"]; // 0x1cb88

    for (NSUInteger i = 0; i < pattern.length; i++) {                   // 0x1cbcc
        unichar c = [pattern characterAtIndex:i];
        if (c == '?') {                                                // 0x1cbd4
            [regex appendString:@"[^/]"];
        } else if (c == '*') {                                         // 0x1cbdc
            NSUInteger next = i + 1;
            if (next < pattern.length && [pattern characterAtIndex:next] == '*') {
                i += 2;
                if (i < pattern.length && [pattern characterAtIndex:i] == '/') {
                    [regex appendString:@"(?:.*/)?"];                  // 0x1cc38
                } else {
                    [regex appendString:@".*"];                        // 0x1ccc0
                }
            } else {
                [regex appendString:@"[^/]*"];                         // 0x1cc98
            }
        } else {
            NSString *ch = [pattern substringWithRange:NSMakeRange(i, 1)];
            [regex appendString:[NSRegularExpression escapedPatternForString:ch]]; // 0x1cc70
        }
    }
    [regex appendString:@"$"];                                         // 0x1ccd8
    return [NSRegularExpression regularExpressionWithPattern:regex options:0 error:NULL]; // 0x1cec
}

#pragma mark - 工具入口

// imp 0x01cd20  types @32@0:8@16@24
- (id)executeTool:(id)a1 arguments:(id)a2 {
    @try {
        return [self run:a1 arguments:a2];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"[failed] %@",
                [e reason] ?: @"参数无效"];                            // 0x1cde0
    }
}

// imp 0x01ce0c  types @32@0:8@16@24
//   全部记忆工具的分发器。每个分支的字符串常量与原实现逐字一致。
- (id)run:(id)a1 arguments:(id)a2 {
    NSString *tool = a1;
    NSDictionary *args = a2;

#pragma mark list_files / glob_files / grep_files
    if ([@[@"list_files", @"glob_files", @"grep_files"] containsObject:tool]) {   // 0x1ce60
        NSString *key = [tool isEqualToString:@"list_files"] ? @"dir"
                       : ([tool isEqualToString:@"glob_files"] ? @"target_directory" : @"path");
        NSString *rel = PDAIString([args objectForKeyedSubscript:key]);            // 0x1cf20
        NSString *absPath = [self path:rel];                                        // 0x1cf44
        if (!absPath) {                                                             // 0x1cf50
            return @"[failed] 路径不在记忆工作区内。";
        }
        NSString *relPath = [absPath isEqualToString:[self root]]
                          ? @""
                          : [absPath substringFromIndex:[[self root] length] + 1];  // 0x1cf9c

        NSString *pattern = PDAIString([args objectForKeyedSubscript:
                                   [tool isEqualToString:@"glob_files"] ? @"glob_pattern" : @"glob"]); // 0x1cfdc
        NSRegularExpression *regex = pattern.length ? [self glob:pattern] : nil;    // 0x1d010

        if ([tool isEqualToString:@"grep_files"]) {                                 // 0x1d150
            NSString *rePattern = PDAIString([args objectForKeyedSubscript:@"pattern"]); // 0x1d180
            BOOL ignoreCase = [[args objectForKeyedSubscript:@"ignore_case"] boolValue]; // 0x1d1a4
            NSError *reError = nil;
            regex = [NSRegularExpression regularExpressionWithPattern:rePattern
                                                              options:(ignoreCase ? NSRegularExpressionCaseInsensitive : 0)
                                                                error:&reError];  // 0x1d1bc
            if (reError) {                                                          // 0x1d1e0
                return [@"[failed] " stringByAppendingString:[reError localizedDescription]];
            }
        }

        NSMutableArray *results = [NSMutableArray array];                            // 0x1d224
        NSInteger headLimit;
        if ([tool isEqualToString:@"glob_files"]) {
            headLimit = 100;                                                        // 0x1d240
        } else {
            double raw = PDAINumber([args objectForKeyedSubscript:@"head_limit"], 50.0); // 0x1d268
            NSInteger v = (NSInteger)raw;
            if (v > 1000) v = 1000;                                                 // 0x1d274
            if (v < 1) v = 1;                                                       // 0x1d284
            headLimit = v;
        }

        NSArray *allFiles = [self files];                                            // 0x1d290
        if ([tool isEqualToString:@"glob_files"]) {
            // 0x1d2e8: 按修改时间倒序
            allFiles = [allFiles sortedArrayUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
                NSDictionary *ax = [[NSFileManager defaultManager]
                                       attributesOfItemAtPath:[[self root] stringByAppendingPathComponent:x]
                                                        error:NULL];
                NSDictionary *ay = [[NSFileManager defaultManager]
                                       attributesOfItemAtPath:[[self root] stringByAppendingPathComponent:y]
                                                        error:NULL];
                return [[ay objectForKeyedSubscript:NSFileModificationDate]
                            compare:[ax objectForKeyedSubscript:NSFileModificationDate]];
            }];
        }

        for (NSString *item in allFiles) {                                            // 0x1d368
            if (relPath.length != 0 &&
                ![item isEqualToString:relPath] &&
                ![item hasPrefix:[relPath stringByAppendingString:@"/"]]) {            // 0x1d3d0
                continue;
            }
            if (regex && [regex numberOfMatchesInString:item
                                                options:0
                                                  range:NSMakeRange(0, item.length)] == 0) { // 0x1d408
                continue;
            }
            NSString *itemAbs = [self path:item];                                     // 0x1d418
            if (!itemAbs) {
                continue;
            }

            if ([tool isEqualToString:@"grep_files"]) {                               // 0x1d434
                NSString *content = [self read:itemAbs error:NULL];                   // 0x1d44c
                NSArray *fileLines = [self lines:(content ?: @"")];                   // 0x1d46c
                NSMutableIndexSet *emitted = [NSMutableIndexSet indexSet];            // 0x1d484
                NSUInteger matchCount = 0;

                for (NSUInteger i = 0; i < fileLines.count; i++) {                    // 0x1d4ac
                    NSString *line = fileLines[i];
                    if ([regex numberOfMatchesInString:line
                                               options:0
                                                 range:NSMakeRange(0, line.length)] == 0) { // 0x1d4d0
                        continue;
                    }
                    matchCount++;                                                     // 0x1d4dc
                    NSString *mode = PDAIString([args objectForKeyedSubscript:@"output_mode"]); // 0x1d4fc
                    if ([mode isEqualToString:@"files_with_matches"]) {                // 0x1d518
                        [results addObject:item];                                      // 0x1d7f4
                        continue;
                    }
                    if ([mode isEqualToString:@"count"]) {                             // 0x1d52c
                        continue;
                    }

                    // 0x1d534: context 默认 0，范围 [0, 20]
                    double rawCtx = PDAINumber([args objectForKeyedSubscript:@"context"], 0.0);
                    NSInteger ctx = (NSInteger)rawCtx;
                    if (ctx > 20) ctx = 20;
                    if (ctx < 0) ctx = 0;

                    NSInteger start = (NSInteger)i - ctx;
                    if (start < 0) start = 0;
                    NSInteger end = (NSInteger)i + ctx + 1;
                    if ((NSInteger)fileLines.count < end) end = (NSInteger)fileLines.count;

                    for (NSInteger j = start; j < end; ) {
                        if ([emitted containsIndex:(NSUInteger)j]) {                   // 0x1d594
                            j++;
                            continue;
                        }
                        [emitted addIndex:(NSUInteger)j];                              // 0x1d5b4
                        NSString *text = fileLines[(NSUInteger)j];                     // 0x1d5c0
                        if (text.length >= 0xc9) {                                     // 0x1d5d0: > 200
                            text = [[text substringToIndex:200] stringByAppendingString:@"&"]; // 0x1d5f8
                        }
                        [results addObject:[NSString stringWithFormat:@"%@:%ld: %@",
                                                                     item, (long)(j + 1), text]]; // 0x1d62c
                        if (results.count >= (NSUInteger)headLimit) {                  // 0x1d65c
                            break;
                        }
                        j++;                                                           // 0x1d618
                    }
                    if (results.count >= (NSUInteger)headLimit) {                      // 0x1d688
                        break;
                    }
                }

                if (matchCount != 0) {                                                 // 0x1d6bc
                    NSString *mode = PDAIString([args objectForKeyedSubscript:@"output_mode"]);
                    if ([mode isEqualToString:@"count"]) {                             // 0x1d6e0
                        [results addObject:[NSString stringWithFormat:@"%@:%lu",
                                                                     item, (unsigned long)matchCount]]; // 0x1d708
                    }
                }
            } else {
                // 0x1d730: list_files / glob_files 的条目描述
                NSDictionary *attrs = [[NSFileManager defaultManager]
                                          attributesOfItemAtPath:itemAbs error:NULL];
                id size = [attrs objectForKeyedSubscript:NSFileSize] ?: @"~";       // 0x1d788
                id date = [attrs objectForKeyedSubscript:NSFileModificationDate] ?: @""; // 0x1d7ac
                [results addObject:[NSString stringWithFormat:@"%@  %@ bytes  %@",
                                                             item, size, date]];    // 0x1d7c4
            }

            if (![tool isEqualToString:@"list_files"] &&                                   // 0x1d834
                results.count >= (NSUInteger)headLimit) {
                break;
            }
        }

        if (results.count != 0) {                                                       // 0x1d898
            return [results componentsJoinedByString:@"\n"];
        }
        return @"没有匹配的文件或内容。";                                                 // 0x1d8c0
    }

#pragma mark read_file / write_file / edit_file / append_file / move_file
    NSString *argPath = PDAIString([args objectForKeyedSubscript:
                                 [tool isEqualToString:@"move_file"] ? @"from" : @"path"]); // 0x1ceb8
    NSString *absPath;
    NSError *pathError = nil;
    if ([tool isEqualToString:@"read_file"]) {                                          // 0x1ced0
        absPath = [self path:argPath];                                                  // 0x1cee0
    } else {
        absPath = [self writablePath:argPath error:&pathError];                          // 0x1d030
    }
    if (!absPath || [absPath isEqualToString:[self root]]) {                             // 0x1d04c
        return [@"[failed] " stringByAppendingString:([pathError localizedDescription]
                                                        ?: @"请使用记忆工作区内的相对路径。")]; // 0x1d0a0
    }

#pragma mark read_file
    if ([tool isEqualToString:@"read_file"]) {                                          // 0x1d0d4
        NSError *readError = nil;
        NSString *content = [self read:absPath error:&readError];                        // 0x1d0ec
        if (!content) {                                                                  // 0x1d108
            return [@"[read failed] " stringByAppendingString:([readError localizedDescription]
                                                                   ?: @"文件不存在或不是文本")]; // 0x1d9d8
        }
        NSMutableArray *fileLines = [self lines:content];                                // 0x1d114
        if ([args objectForKeyedSubscript:@"offset"] || [args objectForKeyedSubscript:@"limit"]) { // 0x1d134 / 0x1dba0
            NSRange range = [self lineRange:fileLines args:args];                         // 0x1dc4
            return [[fileLines subarrayWithRange:range] componentsJoinedByString:@"\n"];  // 0x1dbec
        }
        if (content.length < 0x5dc1) {                                                    // 0x1de58: 24001
            return content;
        }
        return [NSString stringWithFormat:
                @"[共 %lu 行，以下为前 24000 字符；用 offset/limit 继续读取]\n%@",
                (unsigned long)fileLines.count, [content substringToIndex:0x5dc0]];       // 0x1dea4
    }

#pragma mark save_blob
    if ([tool isEqualToString:@"save_blob"]) {                                            // 0x1d908
        NSString *handle = PDAIString([args objectForKeyedSubscript:@"handle"]);          // 0x1d92c
        NSString *dest = nil;
        if ([handle hasPrefix:@"mem:"]) {                                                 // 0x1d944
            dest = [self path:[handle substringFromIndex:4]];                             // 0x1d96c
        } else if ([handle hasPrefix:@"log:"]) {                                          // 0x1d9f4
            NSString *uuidPart = [handle substringFromIndex:4];                           // 0x1da04
            if (uuidPart.length >= 8) {                                                   // 0x1da14
                NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"];
                NSRange bad = [uuidPart rangeOfCharacterFromSet:[allowed invertedSet]];   // 0x1da4c
                if (bad.location == NSNotFound) {                                         // 0x1da60
                    dest = [[[[self root] stringByDeletingLastPathComponent]
                                 stringByAppendingPathComponent:@"attachments"]
                                    stringByAppendingPathComponent:uuidPart];              // 0x1da9c
                }
            }
        }
        if (!dest) {                                                                      // 0x1dd60
            return @"[save failed] 没有这份附件；请使用上下文中出现的 log: 或 mem: 句柄。";
        }
        NSData *data = [NSData dataWithContentsOfFile:dest];                               // 0x1dd70
        if (!data) {
            return @"[save failed] 没有这份附件；请使用上下文中出现的 log: 或 mem: 句柄。";
        }
        NSError *prepError = nil;
        if (![self prepareWrite:dest error:&prepError]) {                                  // 0x1dd98
            return [@"[save failed] " stringByAppendingString:[prepError localizedDescription]]; // 0x1e01c
        }
        [self snapshot:dest operation:tool];                                               // 0x1ddc0
        NSError *writeError = nil;
        if (![data writeToFile:dest options:kPDMemoryWriteAtomic error:&writeError]) {     // 0x1ddd8
            return [@"[save failed] " stringByAppendingString:[writeError localizedDescription]];
        }
        return [@"[saved] mem:" stringByAppendingString:
                    [dest substringFromIndex:[[self root] length] + 1]];                   // 0x1de2c
    }

#pragma mark delete_file
    if ([tool isEqualToString:@"delete_file"]) {                                           // 0x1d988
        if ([self protected:absPath]) {                                                    // 0x1d99c
            return @"[delete failed] CONSTITUTION.md、PARTNER.md 和 KEY_MEMORY.md 是常驻文件，不能删除；可以编辑内容。";
        }
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:absPath isDirectory:&isDirectory]; // 0x1dc2c
        if (isDirectory) {                                                                  // 0x1dc38
            return @"[delete failed] 只能删除文件。";
        }
        [self snapshot:absPath operation:tool];                                              // 0x1df80
        NSError *removeError = nil;
        if ([[NSFileManager defaultManager] removeItemAtPath:absPath error:&removeError]) {  // 0x1dfa0
            return [@"[deleted] " stringByAppendingString:
                        PDAIString([args objectForKeyedSubscript:@"path"])];                 // 0x1dfe8
        }
        return [@"[delete failed] " stringByAppendingString:([removeError localizedDescription]
                                                                 ?: @"写入失败")];        // 0x1e178
    }

#pragma mark move_file
    if ([tool isEqualToString:@"move_file"]) {                                             // 0x1dac4
        NSError *destError = nil;
        NSString *to = [args objectForKeyedSubscript:@"to"];                                // 0x1dad8
        NSString *dest = [self writablePath:to error:&destError];                           // 0x1daf4
        if (!dest || [dest isEqualToString:absPath] ||
            ![dest hasPrefix:[absPath stringByAppendingString:@"/"]]) {                     // 0x1db48
            return [@"[move failed] " stringByAppendingString:([destError localizedDescription]
                                                                   ?: @"目标路径无效。")];   // 0x1db80
        }

        BOOL hasOffset = [args objectForKeyedSubscript:@"offset"] != nil;                    // 0x1e198
        BOOL hasLimit  = [args objectForKeyedSubscript:@"limit"] != nil;                    // 0x1e2c4

        if (!hasOffset && !hasLimit) {
            // 0x1e5d8: 整文件移动
            if ([self protected:absPath]) {
                return @"[move failed] 常驻记忆文件不能移走，可使用 offset/limit 移动其中的行。";
            }
            BOOL destIsDirectory = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:dest isDirectory:&destIsDirectory]; // 0x1e614
            if (!destIsDirectory) {
                if ([[args objectForKeyedSubscript:@"to"] hasSuffix:@"/"]) {                // 0x1e654
                    dest = [dest stringByAppendingPathComponent:[absPath lastPathComponent]]; // 0x1e680
                } else if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {      // 0x1e6ac
                    return @"[move failed] 目标已存在，不覆盖。";
                }
            } else {
                dest = [dest stringByAppendingPathComponent:[absPath lastPathComponent]]; // 0x1e680
                if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {             // 0x1e6ac
                    return @"[move failed] 目标已存在，不覆盖。";
                }
            }
            NSError *prepError = nil;
            if (![self prepareWrite:dest error:&prepError]) {                            // 0x1e6d8
                return [@"[move failed] " stringByAppendingString:[prepError localizedDescription]];
            }
            [self snapshot:absPath operation:tool];                                      // 0x1e700
            NSError *moveError = nil;
            if ([[NSFileManager defaultManager] moveItemAtPath:absPath
                                                        toPath:dest
                                                         error:&moveError]) {           // 0x1e724
                return [NSString stringWithFormat:@"[moved] %@ → %@",
                                                  [args objectForKeyedSubscript:@"from"],
                                                  [args objectForKeyedSubscript:@"to"]]; // 0x1e56c
            }
            return [@"[move failed] " stringByAppendingString:[moveError localizedDescription]]; // 0x1e780
        }

        // 0x1e2dc: 按行移动
        NSError *srcError = nil;
        NSString *source = [self read:absPath error:&srcError];                            // 0x1e2e8
        if (!source) {
            return @"[move failed] 源文件不存在或不是文本。";                                 // 0x1e4ac
        }
        NSMutableArray *sourceLines = [[self lines:source] mutableCopy];                    // 0x1e320
        NSRange range = [self lineRange:sourceLines args:args];                             // 0x1e338
        NSString *moved = [[sourceLines subarrayWithRange:range] componentsJoinedByString:@"\n"]; // 0x1e368
        [sourceLines removeObjectsInRange:range];                                           // 0x1e380

        NSString *destContent = [self read:dest error:NULL] ?: @"";                         // 0x1e390
        if (destContent.length != 0 && ![destContent hasSuffix:@"\n"]) {
            destContent = [destContent stringByAppendingString:@"\n"];                      // 0x1e3e8
        }
        destContent = [destContent stringByAppendingString:moved];                          // 0x1e408
        NSError *appendError = nil;
        if (![self write:destContent path:dest operation:tool error:&appendError]) {        // 0x1e430
            return [@"[move failed] " stringByAppendingString:([appendError localizedDescription]
                                                                   ?: @"写入失败")];       // 0x1e4e8
        }
        NSString *remaining = [sourceLines componentsJoinedByString:@"\n"];                 // 0x1e460
        NSError *trimError = nil;
        if (![self write:remaining path:absPath operation:tool error:&trimError]) {        // 0x1e484
            return @"[move failed] 目标已追加，但源文件未能删除原行，请检查。";               // 0x1e4ec
        }
        return [NSString stringWithFormat:@"[moved] %@ → %@",
                                          [args objectForKeyedSubscript:@"from"],
                                          [args objectForKeyedSubscript:@"to"]];        // 0x1e56c
    }

#pragma mark write_file / edit_file / append_file
    // 0x1e0cc: 类型检查作用在原始字典值上（不是 PDAIString 之后的结果）
    id rawContent = [args objectForKeyedSubscript:
                     [tool isEqualToString:@"edit_file"] ? @"new_string" : @"content"]; // 0x1dcd0
    NSString *content = PDAIString(rawContent);
    if ([tool isEqualToString:@"edit_file"]) {                                             // 0x1dc8c
        NSString *oldString = PDAIString([args objectForKeyedSubscript:@"old_string"]);     // 0x1dcb0
        NSString *newString = PDAIString([args objectForKeyedSubscript:@"new_string"]);     // 0x1dcd8
        NSString *original = [self read:absPath error:NULL];                                // 0x1dcf4
        if (!original || oldString.length == 0 || [oldString isEqualToString:newString]) {  // 0x1dd2c
            return @"[edit failed] 文件、old_string 或 new_string 无效。";                    // 0x1dd30
        }
        NSArray *pieces = [original componentsSeparatedByString:oldString];                  // 0x1e200
        if (pieces.count < 2) {                                                             // 0x1e214
            return @"[edit failed] old_string 必须精确且唯一匹配，或设置 replace_all。";
        }
        BOOL replaceAll = [[args objectForKeyedSubscript:@"replace_all"] boolValue];        // 0x1e230
        if (!replaceAll && pieces.count != 2) {                                             // 0x1e59c
            return @"[edit failed] old_string 必须精确且唯一匹配，或设置 replace_all。";
        }
        content = [pieces componentsJoinedByString:newString];                              // 0x1e5a8
    } else if ([tool isEqualToString:@"append_file"]) {                                     // 0x1ded4
        NSString *existing = [self read:absPath error:NULL] ?: @"";                        // 0x1dee8
        if (existing.length != 0 && ![existing hasSuffix:@"\n"]) {
            existing = [existing stringByAppendingString:@"\n"];                            // 0x1df3c
        }
        content = [existing stringByAppendingString:content];                               // 0x1df58
    } else if (![tool isEqualToString:@"write_file"]) {                                     // 0x1e0a4
        return @"[failed] 未知记忆工具。";                                                    // 0x1e1e8
    }

    if (![rawContent isKindOfClass:[NSString class]]) {                                     // 0x1e0f0
        return @"[failed] content 必须是文本。";                                             // 0x1e154
    }
    NSError *writeError = nil;
    if (![self write:content path:absPath operation:tool error:&writeError]) {              // 0x1e118
        return [@"[write failed] " stringByAppendingString:([writeError localizedDescription]
                                                                 ?: @"写入失败")];        // 0x1e1d8
    }
    NSString *verb = [tool isEqualToString:@"edit_file"]   ? @"edited"
                   : [tool isEqualToString:@"append_file"] ? @"appended"
                                                           : @"written";                     // 0x1e264
    return [NSString stringWithFormat:@"[%@] %@", verb,
                                       [args objectForKeyedSubscript:@"path"]];             // 0x1e29c
}

@end
