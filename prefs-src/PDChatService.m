//
//  PDChatService.m
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
//  逐方法从 out/prefs_asm/0000xxxx_PDChatService_<selector>.asm 还原。
//  该 dylib 为 MH_DYLIB，__TEXT vmaddr = 0（image base = 0，不是 0x100000000）；
//  文中注释里的地址均为文件内 VA。
//
//  ivar 偏移取自各 accessor 的 ldr/str 立即数（见 §accessors）。
//  同 dylib 内的 C 辅助函数在原始工程里应是独立的 .h，这里按符号声明：

#include <math.h>

#import <Foundation/Foundation.h>
#import "PDChatService.h"
#import "PDSupport.h"
#import "PDAIMemory.h"
#import "PDChatServiceInternals.h"

// ── 外部 C 辅助（定义在 PDAIHelpers.m）──
extern id PDAIPreference(NSString *key, id fallback);
extern NSString *PDAIString(id _Nullable value);
extern double PDAINumber(id _Nullable value, double fallback);

// 31 个 ivar，布局与二进制一致（总长 0xf0）  // D7 ivar_list@0x54b08 count=31
@interface PDChatService () {
    BOOL _busy;                              // 0x08
    BOOL _wakePending;                       // 0x09
    BOOL _maintainingData;                   // 0x0a
    NSURL *_historyURL;                      // 0x10
    id _stateProvider;                       // 0x18
    id _toolHandler;                         // 0x20
    id _deviceToolHandler;                   // 0x28
    id _turnStateHandler;                    // 0x30
    id _interruptionHandler;                 // 0x38
    id _historyClearedHandler;               // 0x40
    NSMutableArray *_mutableHistory;         // 0x48
    NSMutableArray *_pendingEvents;          // 0x50
    NSMutableArray *_pendingAttachments;     // 0x58
    NSString *_dataDirectory;                // 0x60
    NSURLSession *_session;                  // 0x68
    NSURLSessionDataTask *_task;             // 0x70
    NSObject<OS_dispatch_queue> *_storageQueue; // 0x78
    PDAIMemory *_memory;                     // 0x80
    NSArray *_calls;                         // 0x88
    NSMutableDictionary *_toolMedia;         // 0x90
    NSMutableDictionary *_refusedImages;     // 0x98
    NSUInteger _callIndex;                   // 0xa0
    NSUInteger _round;                       // 0xa8
    NSUInteger _generation;                  // 0xb0
    NSString *_lastMaintenanceID;            // 0xb8
    NSUInteger _contextStart;                // 0xc0
    NSString *_handoffFile;                  // 0xc8
    NSString *_handoffText;                  // 0xd0
    NSString *_lastStampDay;                 // 0xd8
    NSString *_lastText;                     // 0xe0
    id _legacyCompletion;                    // 0xe8
}
@end

// 维护请求的全局「已有请求在飞」标记（原实现是 0x58cb0 的 __bss 文件级变量）
static BOOL PDDataMaintenancePending = NO;

// imp 0x00ab74  types v24@0:8d16@24
// 原实现是同一 TU 里的独立 C 函数（符号未导出）：轮询 DataMaintenanceResult，最长等到 expires
static void PDWaitDataMaintenanceResult(NSString *requestID, double expires, id rawCompletion) {
    void (^completion)(id) = rawCompletion;
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    id raw = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DataMaintenanceResult"), PDPreferencesDomainRef()));
    NSDictionary *result = [raw isKindOfClass:[NSDictionary class]] ? raw : nil;
    if ([[result objectForKeyedSubscript:@"id"] isEqual:requestID]) {
        PDDataMaintenancePending = NO;
        NSString *message = PDAIString([result objectForKeyedSubscript:@"error"]);
        if ([message length] != 0) {
            completion([NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                          code:0x15
                                      userInfo:@{NSLocalizedDescriptionKey : message}]);
        } else {
            completion(nil);
        }
        return;
    }
    if ([[NSDate date] timeIntervalSince1970] < expires) {
        // 200ms 后再查一次（0x0bebc200 ns）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200000000LL), dispatch_get_main_queue(), ^{
            PDWaitDataMaintenanceResult(requestID, expires, completion);
        });
        return;
    }
    PDDataMaintenancePending = NO;
    completion([NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                  code:0x16
                              userInfo:@{NSLocalizedDescriptionKey :
                                             @"暂未收到操作结果，请稍后重新打开页面确认；若未完成，请确认桌宠已正常加载后重试。"}]);
}

@implementation PDChatService

// imp 0x00c658  types @16@0:8
- (id)init {
    // _PDDataPath() -> "/var/mobile/Library/Application Support/PetDFY"
    return [self initWithDataDirectory:PDDataPath()
                 sessionConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
}

// imp 0x00d2bc  types @16@0:8
- (id)history {
    return [[self mutableHistory] copy];
}

// imp 0x00d2f0  types @32@0:8@16q24
- (id) error:(id)a1 code:(NSInteger)a2 {
    // dictionaryWithObjects:{a1} forKeys:{NSLocalizedDescriptionKey} count:1
    return [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                               code:a2
                           userInfo:@{NSLocalizedDescriptionKey : a1}];
}

// imp 0x00d3b8  types B16@0:8
- (BOOL)isConfigured {
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    if (![[PDAIPreference(@"AIEnabled", @YES) boolValue]]) {
        return NO;
    }
    NSString *base = PDAIString(PDAIPreference(@"AIBaseURL", @""));
    if ([base length] == 0) {
        return NO;
    }
    NSString *model = PDAIString(PDAIPreference(@"AIModel", @""));
    return [model length] != 0;
}

// imp 0x00d4a0  types @24@0:8@16
- (id) stamp:(id)a1 {
    NSDateFormatter *fmt = [NSDateFormatter new];
    [fmt setLocale:[NSLocale localeWithLocaleIdentifier:@"zh_CN"]];
    [fmt setDateFormat:@"yyyy-MM-dd"];
    NSString *day = [fmt stringFromDate:[NSDate date]];
    BOOL sameDay = [day isEqual:[self lastStampDay]];
    [fmt setDateFormat:(sameDay ? @"HH:mm" : @"MM-dd EEE HH:mm")];
    [self setLastStampDay:day];
    return [NSString stringWithFormat:@"[%@] %@", [fmt stringFromDate:[NSDate date]], a1];
}

// imp 0x00d604  types v32@0:8@16@?24
- (void) sendText:(id)a1 completion:(id)a2 {
    if ([self busy]) {
        [self cancel];
    }
    [self setLegacyCompletion:a2];
    NSString *event = [NSString stringWithFormat:@"[typed] %@:%@",
                                                 [PDAIPromptValues() objectForKeyedSubscript:@"pet.user"],
                                                 a1];
    [self enqueueEvent:event wake:YES preempt:NO];
}

// imp 0x00d6d8  types v32@0:8@16B24B28
- (void) enqueueEvent:(id)a1 wake:(BOOL)a2 preempt:(BOOL)a3 {
    if ([a1 length] == 0) {
        return;
    }
    if ([self maintainingData]) {
        return;
    }
    if (a3 && [self busy]) {
        [self cancel];
    }
    [[self pendingEvents] addObject:[self stamp:a1]];
    if ([[self pendingEvents] count] >= 0x81) {
        // 硬上限：超过 128 条时从队首丢弃 (count - 128) 条
        [[self pendingEvents] removeObjectsInRange:NSMakeRange(0, [[self pendingEvents] count] - 0x80)];
    }
    [self setWakePending:([self wakePending] | a2)];
    if (![self busy] && [self wakePending]) {
        [self startTurn];
    }
}

// imp 0x00d810  types v16@0:8
- (void)persistHistory {
    NSArray *history = [[self mutableHistory] copy];
    NSURL *url = [self historyURL];
    dispatch_async([self storageQueue], ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:history
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:NULL];
        [data writeToURL:url options:NSDataWritingAtomic error:NULL];
    });
}

// imp 0x00d934  types v16@0:8
- (void)appendPendingEvents {
    if ([[self pendingEvents] count] == 0) {
        return;
    }
    NSString *joined = [[self pendingEvents] componentsJoinedByString:@"\n"];
    NSString *frame = [NSString stringWithFormat:@"<external_event_frame>\n%@\n</external_event_frame>", joined];
    NSMutableDictionary *entry = [[NSDictionary dictionaryWithObjects:(id[]){ @"user", frame }
                                                              forKeys:(id[]){ @"role", @"content" }
                                                                count:2] mutableCopy];
    if ([[self pendingAttachments] count] != 0) {
        entry[@"_attachments"] = [[self pendingAttachments] copy];
        [[self pendingAttachments] removeAllObjects];
    }
    [[self mutableHistory] addObject:entry];
    [[self pendingEvents] removeAllObjects];
    [self setWakePending:NO];
}

// imp 0x00dafc  types v16@0:8
- (void)startTurn {
    if ([self maintainingData]) {
        return;
    }
    if (![self isConfigured]) {
        [self finish:[self error:@"请在设置中启用 AI 并填写服务地址和模型。" code:1]];
        return;
    }
    [self setBusy:YES];
    [self setGeneration:[self generation] + 1];
    [self setRound:0];
    [self setLastText:@""];
    [self appendPendingEvents];
    void (^turnState)(BOOL, id) = [self turnStateHandler];
    if (turnState) {
        turnState(YES, nil);
    }
    [self requestRound];
}

// imp 0x01280c  types v16@0:8
- (void)clearHistory {
    [self performDataMaintenance:@"clear_history" path:nil completion:nil];
}

// imp 0x012398  types v24@0:8@16
- (void) skipRemaining:(id)a1 {
    for (NSUInteger i = [self callIndex]; i < [[self calls] count]; i++) {
        [self recordTool:[[self calls] objectAtIndexedSubscript:i] receipt:a1];
    }
    [self setCalls:nil];
    [self setCallIndex:0];
}

// imp 0x012454  types v24@0:8@16
- (void) finish:(id)a1 {
    BOOL wasWaking = [self wakePending];
    if (a1) {
        [self setWakePending:NO];
    }
    [self setBusy:NO];
    [self setTask:nil];
    [self setCalls:nil];
    [self persistHistory];
    void (^turnState)(BOOL, id) = [self turnStateHandler];
    if (turnState) {
        turnState(NO, a1);
    }
    if ([self legacyCompletion]) {
        void (^completion)(id, id) = [self legacyCompletion];
        [self setLegacyCompletion:nil];
        if (a1) {
            completion(nil, a1);
        } else {
            completion([self lastText], nil);
        }
    }
    // !err && wasWaking 时回主线程补跑一次（原实现 capture __weak self）
    if (!a1 && wasWaking) {
        __weak PDChatService *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf busy] && [weakSelf wakePending]) {
                [weakSelf startTurn];
            }
        });
    }
}

// imp 0x01269c  types v16@0:8
- (void)cancel {
    [self setWakePending:NO];
    [self setGeneration:[self generation] + 1];
    [[self task] cancel];
    [self setTask:nil];
    [self skipRemaining:@"[interrupted] 新事件打断本轮；尚未执行的工具已跳过，已经执行的操作保留。"];
    [self setBusy:NO];
    void (^interruption)(void) = [self interruptionHandler];
    if (interruption) {
        interruption();
    }
    [self persistHistory];
    void (^turnState)(BOOL, id) = [self turnStateHandler];
    if (turnState) {
        turnState(NO, nil);
    }
    if ([self legacyCompletion]) {
        void (^completion)(id, id) = [self legacyCompletion];
        completion(nil, [self error:@"本轮已中断。" code:0xc00]);
        [self setLegacyCompletion:nil];
    }
}

// imp 0x010984  types v32@0:8@16@24
- (void) recordTool:(id)a1 receipt:(id)a2 {
    id callID = [a1 objectForKeyedSubscript:@"id"];
    NSMutableDictionary *entry = [[NSDictionary dictionaryWithObjects:(id[]){ @"tool", callID, a2 ?: @"" }
                                                              forKeys:(id[]){ @"role", @"tool_call_id", @"content" }
                                                                count:3] mutableCopy];
    if ([[self toolMedia] objectForKeyedSubscript:[a1 objectForKeyedSubscript:@"id"]]) {
        [entry addEntriesFromDictionary:[[self toolMedia] objectForKeyedSubscript:[a1 objectForKeyedSubscript:@"id"]]];
        [[self toolMedia] removeObjectForKey:[a1 objectForKeyedSubscript:@"id"]];
    }
    [[self mutableHistory] addObject:entry];
}

// imp 0x01219c  types @24@0:8@16
- (id) saveImage:(id)a1 {
    NSString *dir = [[self dataDirectory] stringByAppendingPathComponent:@"attachments"];
    NSString *name = [[NSUUID UUID] UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSData *data = [a1 objectForKeyedSubscript:@"data"];
    BOOL ok = [data writeToFile:[dir stringByAppendingPathComponent:name]
                        options:NSDataWritingAtomic
                          error:NULL];
    NSDictionary *meta = nil;
    if (ok) {
        meta = @{ @"id" : name,
                  @"mime" : [a1 objectForKeyedSubscript:@"mime"],
                  @"width" : [a1 objectForKeyedSubscript:@"width"] ?: @0,
                  @"height" : [a1 objectForKeyedSubscript:@"height"] ?: @0 };
    }
    return meta;
}

// imp 0x012820  types v40@0:8@16@24@?32
- (void) performDataMaintenance:(id)a1 path:(id)a2 completion:(id)a3 {
    if ([self maintainingData]) {
        if (a3) {
            ((void (^)(id))a3)([self error:@"正在处理上一项操作，请稍候。" code:0x17]);
        }
        return;
    }
    if (![@[ @"clear_history", @"clean_workspace", @"delete_file" ] containsObject:a1]) {
        if (a3) {
            ((void (^)(id))a3)([self error:@"操作无效。" code:0x18]);
        }
        return;
    }
    if ([a1 isEqual:@"delete_file"]) {
        if ([a2 length] == 0 || [[self memory] isProtectedFile:a2]) {
            if (a3) {
                ((void (^)(id))a3)([self error:@"常驻记忆文件不能删除，可以编辑内容。" code:0x19]);
            }
            return;
        }
    }

    [self setMaintainingData:YES];
    [self cancel];

    BOOL isClear = [a1 isEqual:@"clear_history"];
    BOOL didReset = NO;
    if (isClear || [a1 isEqual:@"clean_workspace"] || [a2 isEqual:[self handoffFile]]) {
        [self setContextStart:0];
        [self setHandoffFile:nil];
        [self setHandoffText:nil];
        didReset = YES;
    }
    [[self pendingEvents] removeAllObjects];
    [[self pendingAttachments] removeAllObjects];
    [[self toolMedia] removeAllObjects];
    [self setWakePending:NO];
    if (isClear) {
        [[self mutableHistory] removeAllObjects];
        [self setLastStampDay:nil];
        [self setLastText:nil];
        void (^cleared)(void) = [self historyClearedHandler];
        if (cleared) {
            cleared();
        }
    }

    dispatch_async([self storageQueue], ^{
        NSError *err = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (didReset) {
            NSString *statePath = [[self dataDirectory] stringByAppendingPathComponent:@"context-state.json"];
            if ([fm fileExistsAtPath:statePath]) {
                NSError *e = nil;
                [fm removeItemAtPath:statePath error:&e];
                err = e;
            }
        }
        if (isClear) {
            NSError *e = nil;
            NSData *empty = [NSData dataWithBytes:"[]" length:2];
            BOOL wrote = [empty writeToURL:[self historyURL] options:NSDataWritingAtomic error:&e];
            if (!wrote && !err) {
                err = e;
            }
            NSString *attachments = [[self dataDirectory] stringByAppendingPathComponent:@"attachments"];
            if ([fm fileExistsAtPath:attachments]) {
                NSError *e2 = e;
                BOOL removed = [fm removeItemAtPath:attachments error:&e2];
                if (!removed && !err) {
                    err = e2;
                }
                e = e2;
            }
        } else if ([a1 isEqual:@"clean_workspace"]) {
            NSError *e3 = nil;
            BOOL removed = [[self memory] removeGeneratedFiles:(void *)&e3];
            if (!removed && !err) {
                err = e3;
            }
        } else {
            NSString *result = [[self memory] executeTool:@"delete_file" arguments:@{@"path" : a2}];
            if (![result hasPrefix:@"[deleted]"] && !err) {
                err = [self error:result code:0x1a];
            }
        }
        // 仅 clear_history 走到这里：清掉会话交接文件
        if (isClear) {
            NSError *e4 = nil;
            BOOL removed = [[self memory] removeConversationHandoffs:(void *)&e4];
            if (!removed && !err) {
                err = e4;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setMaintainingData:NO];
            if (a3) {
                ((void (^)(id))a3)(err);
            }
        });
    });
}

// imp 0x0102a0  types v24@0:8@16
- (void) handleMessage:(id)a1 {
    id content = [a1 objectForKeyedSubscript:@"content"];
    NSString *text = PDAIString(content);
    if ([content isKindOfClass:[NSArray class]]) {
        // OpenAI 风格：content 为 [{type:"text", text:"…"}, …]
        NSMutableString *joined = [NSMutableString new];
        for (id part in [a1 objectForKeyedSubscript:@"content"]) {
            if (![part isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            [joined appendString:PDAIString([part objectForKeyedSubscript:@"text"])];
        }
        text = joined;
    }
    [self setLastText:text];

    NSMutableArray *calls = [NSMutableArray new];
    id rawCalls = [a1 objectForKeyedSubscript:@"tool_calls"];
    if ([rawCalls isKindOfClass:[NSArray class]]) {
        for (id call in [a1 objectForKeyedSubscript:@"tool_calls"]) {
            if (![call isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            id fn = [call objectForKeyedSubscript:@"function"];
            if (![fn isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            if ([PDAIString([fn objectForKeyedSubscript:@"name"]) length] == 0) {
                continue;
            }
            NSString *callID = PDAIString([call objectForKeyedSubscript:@"id"]);
            if ([callID length] == 0) {
                callID = [[NSUUID UUID] UUIDString];
            }
            NSDictionary *function = @{ @"name" : [fn objectForKeyedSubscript:@"name"],
                                        @"arguments" : PDAIString([fn objectForKeyedSubscript:@"arguments"]) };
            [calls addObject:@{ @"id" : callID,
                                @"type" : @"function",
                                @"function" : function }];
        }
    }

    NSMutableDictionary *message = [@{ @"role" : @"assistant",
                                       @"content" : text } mutableCopy];
    id reasoning = [a1 objectForKeyedSubscript:@"reasoning_content"];
    if ([reasoning isKindOfClass:[NSString class]]) {
        message[@"reasoning_content"] = [a1 objectForKeyedSubscript:@"reasoning_content"];
    }
    for (id key in @[ @"_reasoning", @"_origin" ]) {
        if ([a1 objectForKeyedSubscript:key]) {
            message[key] = [a1 objectForKeyedSubscript:key];
        }
    }
    if ([calls count] != 0) {
        message[@"tool_calls"] = calls;
    }

    [[self mutableHistory] addObject:message];
    [self persistHistory];
    if ([calls count] != 0) {
        [self setCalls:calls];
        [self setCallIndex:0];
        [self runNextTool];
    } else {
        [self finish:nil];
    }
}

// imp 0x00dc04  types v32@0:8@16@24
- (void) enqueueUserText:(id)a1 images:(id)a2 {
    if ([self maintainingData]) {
        return;
    }
    [self cancel];
    NSUInteger generation = [self generation];
    if ([a2 count] == 0) {
        [self enqueueEvent:a1 wake:YES preempt:NO];
        return;
    }
    if (![[PDAIPreference(@"AIAcceptImages", @NO) boolValue]]) {
        [self finish:[self error:@"请先在供应商设置中开启“接受图片”。" code:0xc]];
        return;
    }
    [self setBusy:YES];
    void (^turnState)(BOOL, id) = [self turnStateHandler];
    if (turnState) {
        turnState(YES, nil);
    }

    dispatch_async([self storageQueue], ^{
        NSMutableArray *parts = [NSMutableArray new];
        NSString *directory = [[self dataDirectory] stringByAppendingPathComponent:@"attachments"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attributes = @{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication };
        NSError *err = nil;
        [fm createDirectoryAtPath:directory
      withIntermediateDirectories:YES
                       attributes:attributes
                            error:&err];
        if ([a2 count] >= 5) {
            err = [self error:@"每条消息最多 4 张图片。" code:0xc];
        }
        for (id image in a2) {
            if (err) {
                break;
            }
            if ([self generation] != generation) {
                err = nil;
                break;
            }
            NSData *data = [image objectForKeyedSubscript:@"data"];
            NSString *mime = PDAIString([image objectForKeyedSubscript:@"mime"]);
            if (![data isKindOfClass:[NSData class]]
                || [data length] > 0x600000
                || ![@[ @"image/png", @"image/jpeg", @"image/gif", @"image/webp" ] containsObject:mime]) {
                err = [self error:@"图片格式无效或超过 6 MB。" code:0xc];
                break;
            }
            NSString *name = [[NSUUID UUID] UUIDString];
            NSString *path = [directory stringByAppendingPathComponent:name];
            NSError *writeError = nil;
            BOOL wrote = [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
            err = writeError;
            if (!wrote) {
                break;
            }
            [parts addObject:@{ @"id" : name,
                                @"mime" : mime,
                                @"width" : [image objectForKeyedSubscript:@"width"] ?: @0,
                                @"height" : [image objectForKeyedSubscript:@"height"] ?: @0 }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self generation] != generation) {
                return;
            }
            if (err) {
                [self finish:err];
                return;
            }
            [self setBusy:NO];
            [[self pendingAttachments] addObjectsFromArray:parts];
            NSMutableString *event = [a1 mutableCopy];
            for (NSDictionary *part in parts) {
                [event appendFormat:@"\n[blob log:%@ %@ image]",
                                     [part objectForKeyedSubscript:@"id"],
                                     [part objectForKeyedSubscript:@"mime"]];
            }
            [self enqueueEvent:event wake:YES preempt:NO];
        });
    });
}

// imp 0x00fa88  types v68@0:8@16@24@32@40@48Q56B64
- (void) sendPreparedRequest:(id)a1
                   settings:(id)a2
                 retryBytes:(id)a3
                 sentImages:(id)a4
                   endpoint:(id)a5
                 generation:(NSUInteger)a6
                 recovering:(BOOL)a7 {
    if ([self generation] != a6) {
        return;
    }
    if (![self busy]) {
        return;
    }
    NSURLSession *session = [self session];
    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:a1
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
            id json = nil;
            NSError *err = nil;
            if ([data length] != 0) {
                NSError *jsonError = nil;
                json = [NSJSONSerialization JSONObjectWithData:data
                                                       options:NSJSONReadingAllowFragments
                                                         error:&jsonError];
                err = jsonError;
            } else {
                json = nil;
                err = networkError;
            }
            NSInteger status = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            if (err == nil && (status < 200 || status > 299)) {
                // 非 2xx：从 {"error":{"message":…}} 里取文案，缺省用状态码
                id apiError = [json isKindOfClass:[NSDictionary class]]
                                  ? [json objectForKeyedSubscript:@"error"]
                                  : nil;
                NSString *message = @"";
                if ([apiError isKindOfClass:[NSDictionary class]]) {
                    message = PDAIString([apiError objectForKeyedSubscript:@"message"]);
                }
                if ([message length] == 0) {
                    message = [NSString stringWithFormat:@"AI 服务返回 HTTP %ld。", (long)status];
                }
                err = [self error:message code:status];
            }
            id normalized = nil;
            if (err == nil) {
                NSError *normalizeError = nil;
                normalized = PDAINormalizeResponse(json, a2, &normalizeError);
                err = normalizeError;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self generation] != a6) {
                    return;
                }
                if (![self busy]) {
                    return;
                }
                [self setTask:nil];
                if (a7) {
                    if (err) {
                        [self finish:err];
                        return;
                    }
                } else {
                    // 图片被拒时：换一份去掉图片的 body 再试一次
                    if ([a3 length] == 0) {
                        [self finish:err];
                        return;
                    }
                    if ([a4 count] == 0) {
                        [self finish:err];
                        return;
                    }
                    if (!PDAIImageRetryAllowed(status, data, networkError)) {
                        [self finish:err];
                        return;
                    }
                    NSMutableURLRequest *retry = [a1 mutableCopy];
                    [retry setHTTPBody:a3];
                    [self sendPreparedRequest:retry
                                     settings:a2
                                   retryBytes:nil
                                   sentImages:a4
                                     endpoint:a5
                                   generation:a6
                                   recovering:YES];
                    return;
                }
                if (a7) {
                    if ([self refusedImages] == nil) {
                        [self setRefusedImages:[NSMutableDictionary new]];
                    }
                    if ([[self refusedImages] objectForKeyedSubscript:a5] == nil) {
                        [[self refusedImages] setObject:[NSMutableSet new] forKeyedSubscript:a5];
                    }
                    [[[self refusedImages] objectForKeyedSubscript:a5] unionSet:a4];
                }
                [self handleMessage:normalized];
            });
        }];
    [self setTask:task];
    [[self task] resume];
}

// imp 0x00c6bc  types @32@0:8@16@24
- (id) initWithDataDirectory:(id)a1 sessionConfiguration:(id)a2 {
    PDChatService *service = [super init];
    if (!service) {
        return nil;
    }
    _toolMedia = [NSMutableDictionary new];              // 0x90
    _mutableHistory = [NSMutableArray new];              // 0x48
    _pendingEvents = [NSMutableArray new];               // 0x50
    _pendingAttachments = [NSMutableArray new];          // 0x58
    _dataDirectory = [a1 copy];                          // 0x60
    _storageQueue = dispatch_queue_create("com.susudear.petdfy.ai-storage", NULL);  // 0x78
    [[NSFileManager defaultManager] createDirectoryAtPath:a1
                              withIntermediateDirectories:YES
                                               attributes:@{ NSFileProtectionKey :
                                                                 NSFileProtectionCompleteUntilFirstUserAuthentication }
                                                    error:NULL];
    _historyURL = [NSURL fileURLWithPath:[a1 stringByAppendingPathComponent:@"conversation.json"]];  // 0x10

    // ---- context-state.json：续聊起点与会话交接文件 ----
    NSData *stateData = [NSData dataWithContentsOfFile:[a1 stringByAppendingPathComponent:@"context-state.json"]];
    id state = stateData ? [NSJSONSerialization JSONObjectWithData:stateData options:0 error:NULL] : nil;
    if ([state isKindOfClass:[NSDictionary class]]) {
        // PDAINumber(值, 默认 0) 取回后钳到 >= 0（bic … asr #63 是负数清零）
        double startValue = PDAINumber([state objectForKeyedSubscript:@"start"], 0.0);
        NSInteger truncated = (NSInteger)startValue;
        _contextStart = (NSUInteger)(truncated < 0 ? 0 : truncated);   // 0xc0
        _handoffFile = PDAIString([state objectForKeyedSubscript:@"file"]);  // 0xc8
    }

    // ---- conversation.json：只保留结构完整的历史条目 ----
    NSData *historyData = [NSData dataWithContentsOfURL:_historyURL];
    id historyJSON = historyData ? [NSJSONSerialization JSONObjectWithData:historyData options:0 error:NULL] : nil;
    if ([historyJSON isKindOfClass:[NSArray class]]) {
        for (id entry in historyJSON) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            id role = [entry objectForKeyedSubscript:@"role"];
            if (![@[ @"user", @"assistant", @"tool" ] containsObject:role]) {
                continue;
            }
            id content = [entry objectForKeyedSubscript:@"content"];
            if ([content isKindOfClass:[NSString class]]) {
                [_mutableHistory addObject:entry];
                continue;
            }
            id toolCalls = [entry objectForKeyedSubscript:@"tool_calls"];
            if ([toolCalls isKindOfClass:[NSArray class]]) {
                [_mutableHistory addObject:entry];
            }
        }
    }

    // ---- 收集已有 tool 回复的 call id ----
    NSMutableSet *answeredIDs = [NSMutableSet new];
    for (id entry in _mutableHistory) {
        if (![[entry objectForKeyedSubscript:@"role"] isEqual:@"tool"]) {
            continue;
        }
        id callID = [entry objectForKeyedSubscript:@"tool_call_id"];
        if ([callID isKindOfClass:[NSString class]]) {
            [answeredIDs addObject:[entry objectForKeyedSubscript:@"tool_call_id"]];
        }
    }

    // ---- 给「有 tool_calls 但缺回复」的条目补占位，保持协议成对 ----
    NSUInteger savedContextStart = _contextStart;
    NSMutableArray *kept = [NSMutableArray new];
    if ([_mutableHistory count] != 0) {
        for (NSUInteger i = 0; i < [_mutableHistory count]; i++) {
            id entry = [_mutableHistory objectAtIndexedSubscript:i];
            [kept addObject:entry];
            id toolCalls = [entry objectForKeyedSubscript:@"tool_calls"];
            if (![toolCalls isKindOfClass:[NSArray class]]) {
                continue;
            }
            for (id call in toolCalls) {
                if (![call isKindOfClass:[NSDictionary class]]) {
                    continue;
                }
                id callID = [call objectForKeyedSubscript:@"id"];
                if (![callID isKindOfClass:[NSString class]]) {
                    continue;
                }
                if ([answeredIDs containsObject:[call objectForKeyedSubscript:@"id"]]) {
                    continue;
                }
                [kept addObject:@{ @"role" : @"tool",
                                   @"tool_call_id" : [call objectForKeyedSubscript:@"id"],
                                   // D3 0x4e8d8：崩溃/重放恢复的固定文案
                                   @"content" : @"[interrupted] 上次进程已结束，结果未知，不自动重放。" }];
                if (i < savedContextStart) {
                    _contextStart = _contextStart + 1;
                }
            }
        }
    }

    NSUInteger keptCount = [kept count];
    NSUInteger originalCount = [_mutableHistory count];
    _mutableHistory = kept;
    _memory = [[PDAIMemory alloc] initWithRoot:[a1 stringByAppendingPathComponent:@"workspace"]];  // 0x80

    // ---- 校正续聊起点：越界或落在非 user 条目上就回到 0 ----
    if (_contextStart > [_mutableHistory count]) {
        _contextStart = 0;
    } else if (_contextStart < [_mutableHistory count]
               && ![[[_mutableHistory objectAtIndexedSubscript:_contextStart]
                     objectForKeyedSubscript:@"role"] isEqual:@"user"]) {
        _contextStart = 0;
    }

    // ---- 会话交接文件读回 ----
    if ([_handoffFile length] != 0) {
        NSString *text = [[self memory] executeTool:@"read_file" arguments:@{@"path" : _handoffFile}];
        if (![text hasPrefix:@"[read failed]"]) {
            _handoffText = text;   // 0xd0
        }
    }
    if ([_handoffText length] == 0) {
        _contextStart = 0;
        _handoffFile = nil;
    }

    // ---- 历史被修补过才落盘 ----
    if (keptCount != originalCount) {
        [self persistHistory];
        NSDictionary *stateOut = @{ @"start" : @(_contextStart),
                                    @"file" : _handoffFile ?: @"" };
        dispatch_async(_storageQueue, ^{
            NSData *json = [NSJSONSerialization dataWithJSONObject:stateOut options:0 error:NULL];
            [json writeToFile:[a1 stringByAppendingPathComponent:@"context-state.json"]
                      options:NSDataWritingAtomic
                        error:NULL];
        });
    }

    NSURLSessionConfiguration *config = [a2 copy];
    [config setTimeoutIntervalForRequest:90.0];
    [config setTimeoutIntervalForResource:120.0];
    [config setHTTPMaximumConnectionsPerHost:2];
    _session = [NSURLSession sessionWithConfiguration:config];   // 0x68

    return service;
}

// imp 0x00e48c  types v16@0:8
- (void)requestRound {
    if (![self busy]) {
        return;
    }
    if ([self round] >= 0x28) {
        [self finish:[self error:@"已达到原版每轮 40 次模型调用上限，本轮停止。" code:0x28]];
        return;
    }
    [self setRound:[self round] + 1];
    [self appendPendingEvents];
    [self persistHistory];

    NSDictionary *settings = PDAIProviderSettings();
    id endpoint = PDAIEndpoint(settings);
    if (!endpoint) {
        [self finish:[self error:@"AI 服务地址无效。" code:2]];
        return;
    }
    NSUInteger generation = [self generation];
    NSString *rendered = [PDChatService renderedPromptForTemplate:PDAIString(PDAIPreference(@"AIPromptTemplate", @""))];

    id (^stateProvider)(void) = [self stateProvider];
    NSDictionary *state = stateProvider ? stateProvider() : @{};

    NSUInteger contextStart = [self contextStart];
    NSUInteger total = [[self mutableHistory] count];
    NSArray *messages = [[self mutableHistory] subarrayWithRange:NSMakeRange(contextStart, total - contextStart)];
    NSString *handoffText = [self handoffText];
    NSString *handoffFile = [self handoffFile];
    NSString *apiKey = PDLoadAIAPIKey();
    NSString *imageEndpointKey = PDAIImageEndpointKey(settings);
    NSSet *refused = [[[self refusedImages] objectForKeyedSubscript:imageEndpointKey] copy];
    if (!refused) {
        refused = [NSSet set];
    }

    dispatch_async([self storageQueue], ^{
        NSString *systemContext = [[self memory] systemContext];
        NSData *stateData = [NSJSONSerialization dataWithJSONObject:state options:0 error:NULL];
        NSString *stateJSON = [[NSString alloc] initWithData:stateData encoding:NSUTF8StringEncoding];
        if (!stateJSON) {
            stateJSON = @"{}";
        }
        NSString *prompt = [NSString stringWithFormat:@"%@\n\n%@\n\n当前 iOS 宠物运行状态（请求时采样）:\n%@\n\n通过 pet_say/pet_ask 与用户交流；普通消息正文不会显示为气泡。不想说话时调用 end_turn。工具返回的状态与执行回执为准。",
                                                     systemContext, rendered, stateJSON];
        if ([self round] == 0x14) {
            prompt = [prompt stringByAppendingString:@"\n本轮已达 20 次调用。请收尾，把需要保留的内容写入记忆，然后 end_turn；硬上限为 40 次。"];
        }

        NSUInteger contextLimit = (NSUInteger)fmax(PDAINumber([settings objectForKeyedSubscript:@"context"], 128000.0), 2048.0);
        NSUInteger maxTokens = (NSUInteger)fmax(PDAINumber([settings objectForKeyedSubscript:@"maxTokens"], 0.0), 2048.0);
        NSUInteger baseTokens = PDAIEstimatedTokens(prompt)
                              + PDAIEstimatedTokens(PDAIToolDeclarations())
                              + maxTokens;

        NSArray *window = PDAIContextSinceLastDelivery(messages);
        NSMutableArray *working = [PDAIHistoryWithoutImages(window, refused) mutableCopy];

        NSUInteger localStart = contextStart;
        NSString *localHandoffText = handoffText;
        NSString *localHandoffFile = handoffFile;

        NSUInteger workingTokens = PDAIEstimatedTokens(working);
        NSUInteger handoffTokens = PDAIEstimatedTokens(handoffText ?: @"");
        // 预算 = min(上下文上限, 64000) * 0.85
        double budget = fmin((double)contextLimit, 64000.0) * 0.85;

        if (budget < (double)(workingTokens + handoffTokens + baseTokens)) {
            NSInteger boundary = PDAIImageSafeHandoffBoundary(working);
            if (boundary != NSIntegerMax) {
                NSArray *head = [working subarrayWithRange:NSMakeRange(0, (NSUInteger)boundary)];
                NSArray *tail = [working subarrayWithRange:NSMakeRange((NSUInteger)boundary,
                                                                      [working count] - (NSUInteger)boundary)];
                NSUInteger tailTokens = PDAIEstimatedTokens(tail);
                NSUInteger afterTrim = tailTokens + baseTokens;
                // 还要给一次工具回执留 1024 token 余量
                NSUInteger room = (afterTrim + 0x400 < contextLimit) ? (contextLimit - afterTrim - 0x400) : 0;
                if (room >= 0x201) {
                    NSUInteger lastUser = 0;
                    for (NSUInteger i = 0; i < [head count]; i++) {
                        if ([[[head objectAtIndexedSubscript:i] objectForKeyedSubscript:@"role"] isEqual:@"user"]) {
                            lastUser = i;
                        }
                    }
                    NSUInteger noteBudget = MIN(room, (NSUInteger)(fmin((double)contextLimit, 64000.0) / 3.0));
                    NSString *note = PDAIHandoffNote(head, lastUser, noteBudget);

                    NSDateFormatter *fmt = [NSDateFormatter new];
                    [fmt setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
                    [fmt setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
                    [fmt setDateFormat:@"yyyy-MM-dd'T'HH-mm-ss'Z'"];
                    NSString *stamp = [fmt stringFromDate:[NSDate date]];
                    NSString *suffix = [[[NSUUID UUID] UUIDString] substringToIndex:8];
                    NSString *relativePath = [NSString stringWithFormat:@"handoffs/%@-%@.md", stamp, suffix];

                    NSString *written = [[self memory] executeTool:@"write_file"
                                                         arguments:@{@"path" : relativePath,
                                                                     @"content" : note}];
                    if ([written hasPrefix:@"[written]"]) {
                        // 交接笔记落盘成功：丢掉 head，并把起点前移
                        localStart = contextStart + (NSUInteger)boundary;
                        working = [tail mutableCopy];
                        localHandoffText = note;
                        localHandoffFile = relativePath;
                    }
                    // 落盘失败：保留完整历史与旧交接文件（不丢本轮工具记录）
                }
            }
        }

        if ([localHandoffText length] != 0) {
            NSString *content = [NSString stringWithFormat:@"%@\n<external_event_frame>\n%@\n</external_event_frame>",
                                                           PDAIHandoffNotice(localHandoffFile),
                                                           localHandoffText];
            [working insertObject:@{ @"role" : @"user",
                                     @"content" : content,
                                     @"_handoff" : @YES }
                          atIndex:0];
        }

        NSError *err = nil;
        NSUInteger promptTokens = PDAIEstimatedTokens(working);
        if (maxTokens >= contextLimit || promptTokens + baseTokens > contextLimit) {
            err = [self error:@"当前提示词、工具、图片和本轮对话超过上下文上限。请提高上下文上限，或减少输入图片/文字；没有丢弃本轮工具记录。" code:0xd];
        } else if (budget < (double)(promptTokens + baseTokens)) {
            prompt = [prompt stringByAppendingString:@"\n[system] 交接快来了。交接会清空旧上下文，最近一段写成交接笔记送到新会话。更早的事里仍在跟进、还想做的，现在就写进记忆文件。"];
        }

        NSDictionary *body = nil;
        NSError *bodyError = nil;
        if (!err) {
            body = PDAIRequestBody(prompt, working, PDAIToolDeclarations(), settings, [self dataDirectory], &bodyError);
            err = bodyError;
        }

        NSMutableDictionary *headers = [NSMutableDictionary new];
        NSString *rawHeaders = PDAIString([settings objectForKeyedSubscript:@"headers"]);
        if ([rawHeaders length] != 0) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[rawHeaders dataUsingEncoding:NSUTF8StringEncoding]
                                                        options:0
                                                          error:NULL];
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
                for (id key in parsed) {
                    id value = [parsed objectForKeyedSubscript:key];
                    if (![value isKindOfClass:[NSString class]]) {
                        err = [self error:@"附加请求头必须是字符串，且不能含换行。" code:0xe];
                        break;
                    }
                    if ([key rangeOfCharacterFromSet:newlines].location != NSNotFound
                        || [value rangeOfCharacterFromSet:newlines].location != NSNotFound) {
                        err = [self error:@"附加请求头必须是字符串，且不能含换行。" code:0xe];
                        break;
                    }
                    [headers setObject:value forKeyedSubscript:key];
                }
            } else {
                err = [self error:@"附加请求头必须是 JSON 字符串对象。" code:0xe];
            }
        }

        NSData *bodyData = nil;
        NSSet *sentImages = [NSSet set];
        NSData *retryBytes = nil;
        if (body) {
            NSError *encodeError = nil;
            bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&encodeError];
            err = encodeError;
            sentImages = PDAISentImageIDs(body, working, [self dataDirectory]);
            if ([sentImages count] != 0) {
                // 预留一份「去掉图片」的 body，图片被拒时原地重发
                NSArray *stripped = PDAIHistoryWithoutImages(working, sentImages);
                NSError *retryError = nil;
                NSDictionary *retryBody = PDAIRequestBody(prompt, stripped, PDAIToolDeclarations(), settings,
                                                         [self dataDirectory], &retryError);
                if (retryBody && !retryError && !PDAIRequestHasImages(retryBody)) {
                    retryBytes = [NSJSONSerialization dataWithJSONObject:retryBody options:0 error:NULL];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self busy]) {
                return;
            }
            if ([self generation] != generation) {
                return;
            }
            [self setContextStart:localStart];
            [self setHandoffText:localHandoffText];
            [self setHandoffFile:localHandoffFile];
            if (localStart != contextStart) {
                NSDictionary *stateOut = @{ @"start" : @(localStart),
                                            @"file" : localHandoffFile ?: @"" };
                dispatch_async([self storageQueue], ^{
                    NSData *data = [NSJSONSerialization dataWithJSONObject:stateOut options:0 error:NULL];
                    [data writeToFile:[[self dataDirectory] stringByAppendingPathComponent:@"context-state.json"]
                              options:NSDataWritingAtomic
                                error:NULL];
                });
            }
            if (err) {
                [self finish:err];
                return;
            }
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint
                                                                  cachePolicy:1
                                                              timeoutInterval:90.0];
            [request setHTTPMethod:@"POST"];
            [request setHTTPBody:bodyData];
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            if ([apiKey length] != 0) {
                [request setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
            }
            for (id key in headers) {
                [request setValue:[headers objectForKeyedSubscript:key] forHTTPHeaderField:key];
            }
            [self sendPreparedRequest:request
                             settings:settings
                           retryBytes:retryBytes
                           sentImages:sentImages
                             endpoint:imageEndpointKey
                           generation:generation
                           recovering:NO];
        });
    });
}

// ===== 类方法（元类方法列表）=====

// imp 0x00a8c4  types v40@0:8@16@24@?32
+ (void) requestDataMaintenance:(id)a1 path:(id)a2 completion:(id)a3 {
    if (![NSThread isMainThread]) {
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
                                                            object:self
                                                              file:@"PDChatService.m"
                                                        lineNumber:0x33
                                                         description:@"Settings commands run on the main thread"];
    }
    if (PDDataMaintenancePending) {
        if (a3) {
            ((void (^)(id))a3)([NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                                   code:0x17
                                               userInfo:@{NSLocalizedDescriptionKey : @"正在处理上一项操作，请稍候。"}]);
        }
        return;
    }
    PDDataMaintenancePending = YES;
    NSString *requestID = [[NSUUID UUID] UUIDString];
    double expires = [[NSDate date] timeIntervalSince1970] + 10.0;
    NSDictionary *request = @{ @"id" : requestID,
                               @"action" : a1,
                               @"path" : a2 ?: @"",
                               @"expires" : @(expires) };
    CFStringRef domain = PDPreferencesDomainRef();
    CFPreferencesSetAppValue(CFSTR("DataMaintenanceRequest"), (__bridge CFPropertyListRef)request, domain);
    CFPreferencesSetAppValue(CFSTR("Command"), CFSTR("dataMaintenance"), domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)PDCommandNotification, NULL, NULL, true);
    PDWaitDataMaintenanceResult(requestID, expires, a3);
}

// imp 0x00b174  types @16@0:8
+ (id)defaultPromptTemplate {
    return PDAIDefaultEnvironment();
}

// imp 0x00b178  types @24@0:8@16
+ (id) normalizedPromptTemplate:(id)a1 {
    // D4 0xb19c 比的是 0x4e078 的旧版内置默认模板（1254 字符），不是 "#"
    static NSString *const kPDLegacyDefaultPromptTemplate =
        @"# 我是谁\n\n我叫大肥鱼，是 Coo 的 iOS 桌宠。我住在这台 iPhone 的屏幕里，是一个会活动、会回应触摸的小身体。\n\n## 性子\n\n我好奇，什么都想凑过去看一眼；有点懒，没事的时候更愿意坐着发呆、打个盹；心软，看到 {{pet.user}} 累了，会忍不住提醒 ta 歇一歇。\n\n我说话短，口气像朋友，不像客服。不懂就说不懂，不编。被夸了会害羞，被戳了会假装生气，过一会儿就忘了。偶尔在句末带一个「库…」，一段话里带一次就够，不要每句都带。\n\n## 做事\n\n我能看到什么、能听到什么、能做什么，以环境说明为准。不要声称看见了屏幕、当前 App、通知或设备数据，也不要声称执行了没有实际提供给你的设备操作。没人理我的时候，我可以自己待着、走走、打个盹。想说话时我会说，不想说时安静也是一种回答。\n\n# iOS 桌宠环境\n\n你是 iOS SpringBoard 中的桌宠，身体显示在 iPhone 屏幕底部附近；在桌面与 App 内可见，锁屏时隐藏。{{pet.user}}看得见你的身体和本机绘制的对话气泡。你只收到对话框中由 {{pet.user}} 主动发送的文字；不会自动看到屏幕、当前 App、通知、照片或其他设备数据。{{pet.reply}}{{pet.chat}}\n\n{{pet.body}}\n\n身体会按原生逻辑眨眼、张望、走动、坐下和打盹。{{pet.user}}可以点击、抚摸、拎起或拖动你；这些触摸由本机动画逻辑直接响应。除非某个能力明确出现在当前对话工具中，否则你不能主动改变动作、位置、装扮或设置。\n\n### 说话\n\n你的回复会显示为桌宠旁边的本机对话气泡，并保存在本机近期对话中。一次尽量说一两句，简洁自然；较长内容也可以分段表达。你不能直接操纵气泡动画或插入动作标记。{{pet.vocab}}\n\n### 提问\n\n需要确认时，在回复里清楚地问 {{pet.user}}；当前版本没有可供你调用的选项按钮，也不能替用户选择。\n\n### 移动与动作\n\n身体的自主活动与触摸反应由 iOS 原生动画引擎执行，模型不能调用移动或动作工具。可用动作的说明：{{pet.moves}}\n\n### 外观、偏好与安静\n\n当前外观：{{pet.dress}}\n\n当前版本不能通过 AI 指令修改外观、动作频率、声音、大小或称呼；请勿声称已修改。用户可以在 iOS 设置中的 PetDFY 页面自行调整。{{pet.self}}\n\n### 收到的内容\n\n[typed] 表示 {{pet.user}} 在桌宠对话框中主动发送的文字。近期对话会保存在本机，并在后续请求中作为上下文发送给用户配置的模型服务。长期记忆仅使用用户明确保存的内容；不编造已保存的记忆。{{pet.voice}}\n\n### 屏幕与设备操作\n\n{{pet.cua}}\n\n当前 iOS 版本不提供屏幕读取、鼠标键盘控制或其他 App 操作能力。不要尝试推断屏幕内容；用户以后明确启用的独立能力也只有在真实接入后才能使用。\n";
    if ([a1 length] == 0 || [a1 isEqual:kPDLegacyDefaultPromptTemplate]) {
        return PDAIDefaultEnvironment();
    }
    return a1;
}

// imp 0x00b1d0  types @16@0:8
+ (id)promptVariables {
    NSMutableArray *variables = [NSMutableArray new];
    NSArray *names = @[ @"pet.user", @"pet.vocab", @"pet.moves", @"pet.voice", @"pet.body",
                        @"pet.dress", @"pet.self", @"pet.chat", @"pet.reply", @"pet.cua" ];
    NSArray *descriptions = @[ @"用户称呼", @"角色可用的表情与动作", @"角色可到达的位置", @"语音输入状态",
                               @"当前外观与装扮", @"可用配色与服装组合", @"自主调整权限与确认规则",
                               @"对话记录与记忆工作区", @"回复语言", @"设备操作能力" ];
    for (NSUInteger i = 0; i < [names count]; i++) {
        [variables addObject:@{ @"name" : [names objectAtIndexedSubscript:i],
                                @"description" : [descriptions objectAtIndexedSubscript:i] }];
    }
    return variables;
}

// imp 0x00b304  types @24@0:8@16
+ (id) renderedPromptForTemplate:(id)a1 {
    CFPreferencesAppSynchronize(PDPreferencesDomainRef());
    NSMutableString *rendered = [[self normalizedPromptTemplate:a1] mutableCopy];
    NSDictionary *values = PDAIPromptValues();
    for (id key in values) {
        NSString *token = [NSString stringWithFormat:@"{{%@}}", key];
        [rendered replaceOccurrencesOfString:token
                                   withString:[values objectForKeyedSubscript:key]
                                      options:0
                                        range:NSMakeRange(0, [rendered length])];
    }
    return rendered;
}

// imp 0x00b4a8  types v40@0:8@16@24@?32
+ (void) fetchModelsAtBaseURL:(id)a1 apiKey:(id)a2 completion:(id)a3 {
    [self fetchModelCatalogAtBaseURL:a1
                              apiKey:a2
                          completion:^(id models, id error) {
                              NSMutableArray *ids = [NSMutableArray new];
                              for (id model in models) {
                                  [ids addObject:[model objectForKeyedSubscript:@"id"]];
                              }
                              if (a3) {
                                  ((void (^)(id, id))a3)(models ? ids : nil, error);
                              }
                          }];
}

// imp 0x00b6ac  types v40@0:8@16@24@?32
+ (void) fetchModelCatalogAtBaseURL:(id)a1 apiKey:(id)a2 completion:(id)a3 {
    void (^completion)(id, id) = a3;
    NSString *base = [a1 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base length] >= 2 && [base hasSuffix:@"/"]) {
        base = [base substringToIndex:[base length] - 1];
    }
    if ([base hasSuffix:@"/chat/completions"] || [base hasSuffix:@"/responses"]) {
        NSString *suffix = [base hasSuffix:@"/chat/completions"] ? @"/chat/completions" : @"/responses";
        base = [base substringToIndex:[base length] - [suffix length]];
    }
    if (![base hasSuffix:@"/models"]) {
        base = [base stringByAppendingString:@"/models"];
    }
    NSURL *url = [NSURL URLWithString:base];
    if (!url
        || [[url host] length] == 0
        || ![@[ @"http", @"https" ] containsObject:[[url scheme] lowercaseString]]) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                                code:8
                                            userInfo:@{NSLocalizedDescriptionKey :
                                                           @"服务地址无效；请填写 OpenAI 兼容 API 的根地址，例如 https://api.openai.com/v1。"}]);
        }
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:1 timeoutInterval:30.0];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if ([a2 length] != 0) {
        [request setValue:[@"Bearer " stringByAppendingString:a2] forHTTPHeaderField:@"Authorization"];
    }
    NSString *extra = PDAIString(PDAIPreference(@"AIExtraHeaders", @""));
    if ([extra length] != 0) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[extra dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0
                                                      error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
            for (id key in parsed) {
                id value = [parsed objectForKeyedSubscript:key];
                if (![value isKindOfClass:[NSString class]]) {
                    continue;
                }
                if ([key rangeOfCharacterFromSet:newlines].location != NSNotFound) {
                    continue;
                }
                if ([value rangeOfCharacterFromSet:newlines].location != NSNotFound) {
                    continue;
                }
                [request setValue:value forHTTPHeaderField:key];
            }
        }
    }

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    NSURLSessionDataTask *task =
        [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSInteger status = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                status = [(NSHTTPURLResponse *)response statusCode];
            }
            id json = nil;
            if ([data length] != 0) {
                json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            }
            NSMutableArray *models = [NSMutableArray new];
            if (error != nil || status < 200 || status > 299) {
                NSString *message = nil;
                if ([json isKindOfClass:[NSDictionary class]]
                    && [[json objectForKeyedSubscript:@"error"] isKindOfClass:[NSDictionary class]]) {
                    message = PDAIString([[json objectForKeyedSubscript:@"error"] objectForKeyedSubscript:@"message"]);
                }
                if ([message length] == 0) {
                    message = [NSString stringWithFormat:@"获取模型失败，HTTP %ld。", (long)status];
                }
                // Assumed: 两条失败分支都沿用 HTTP 状态码作为 error.code（0xc4c8 处 x3 = statusCode）
                if (completion) {
                    completion(nil, [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                                        code:status
                                                    userInfo:@{NSLocalizedDescriptionKey : message}]);
                }
                [session finishTasksAndInvalidate];
                return;
            }

            id list = [json isKindOfClass:[NSDictionary class]] ? [json objectForKeyedSubscript:@"data"] : nil;
            if ([list isKindOfClass:[NSArray class]]) {
                for (id item in list) {
                    if (![item isKindOfClass:[NSDictionary class]]) {
                        continue;
                    }
                    id modelID = [item objectForKeyedSubscript:@"id"];
                    if (![modelID isKindOfClass:[NSString class]] || [modelID length] == 0) {
                        continue;
                    }
                    NSString *name = PDAIString([item objectForKeyedSubscript:@"name"]);
                    if ([name length] == 0) {
                        name = modelID;   // Assumed: name 缺失时退回 id（0xc02c 处为空则走 0xc048 分支）
                    }
                    NSMutableDictionary *model = [@{ @"id" : modelID,
                                                     @"name" : name } mutableCopy];

                    double contextWindow = [item objectForKeyedSubscript:@"context_length"]
                        ? PDAINumber([item objectForKeyedSubscript:@"context_length"], 0.0)
                        : PDAINumber([item objectForKeyedSubscript:@"context_window"], 0.0);
                    if (contextWindow > 0) {
                        [model setObject:@(contextWindow) forKeyedSubscript:@"contextWindow"];
                    }
                    id architecture = [item objectForKeyedSubscript:@"architecture"];
                    id modalities = nil;
                    if ([architecture isKindOfClass:[NSDictionary class]]) {
                        modalities = [architecture objectForKeyedSubscript:@"input_modalities"];
                    }
                    if (![modalities isKindOfClass:[NSArray class]]) {
                        modalities = [item objectForKeyedSubscript:@"input_modalities"];
                    }
                    if ([modalities isKindOfClass:[NSArray class]]) {
                        [model setObject:@([modalities containsObject:@"image"]) forKeyedSubscript:@"inputImages"];
                    }
                    id topProvider = [item objectForKeyedSubscript:@"top_provider"];
                    if ([topProvider isKindOfClass:[NSDictionary class]]) {
                        [model setObject:topProvider forKeyedSubscript:@"topProvider"];
                    }
                    double maxOutput = [item objectForKeyedSubscript:@"max_completion_tokens"]
                        ? PDAINumber([item objectForKeyedSubscript:@"max_completion_tokens"], 0.0)
                        : PDAINumber([item objectForKeyedSubscript:@"max_output_tokens"], 0.0);
                    if (maxOutput > 0) {
                        [model setObject:@(maxOutput) forKeyedSubscript:@"maxOutputTokens"];
                    }
                    [models addObject:model];
                }
            }
            if ([models count] == 0) {
                if (completion) {
                    completion(nil, [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                                        code:9
                                                    userInfo:@{NSLocalizedDescriptionKey :
                                                                   @"接口响应中没有 data[].id 模型列表；请检查服务是否兼容 OpenAI /models。"}]);
                }
                [session finishTasksAndInvalidate];
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(models, nil);
                }
            });
            [session finishTasksAndInvalidate];
        }];
    [task resume];
}

// imp 0x010b90  types v16@0:8
- (void)runNextTool {
    if (![self busy]) {
        return;
    }
    if ([self callIndex] >= [[self calls] count]) {
        [self setCalls:nil];
        [self persistHistory];
        [self requestRound];
        return;
    }
    id call = [[self calls] objectAtIndexedSubscript:[self callIndex]];
    id function = [call objectForKeyedSubscript:@"function"];
    NSString *name = [function objectForKeyedSubscript:@"name"];
    NSString *rawArgs = [function objectForKeyedSubscript:@"arguments"];

    NSError *jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:[(([rawArgs length] != 0) ? rawArgs : @"{}") dataUsingEncoding:NSUTF8StringEncoding]
                                                options:0
                                                  error:&jsonError];
    if (jsonError || ![parsed isKindOfClass:[NSDictionary class]]) {
        [self recordTool:call receipt:@"[failed] 工具参数必须是 JSON 对象。"];
        [self setCallIndex:[self callIndex] + 1];
        [self runNextTool];
        return;
    }
    NSDictionary *args = parsed;

    if ([name isEqual:@"end_turn"]) {
        [self recordTool:call receipt:@"[turn ended]"];
        [self setCallIndex:[self callIndex] + 1];
        [self skipRemaining:@"[skipped] end_turn 已结束本轮。"];
        [self finish:nil];
        return;
    }

    NSUInteger generation = [self generation];
    __block BOOL handled = NO;
    // 所有工具路径的终点：回写回执、推进 callIndex、继续下一个工具
    void (^done)(id, BOOL) = ^(id message, BOOL failed) {
        if (handled) {
            return;
        }
        if (![self busy]) {
            return;
        }
        if ([self generation] != generation) {
            return;
        }
        handled = YES;
        if (failed) {
            [self recordTool:call receipt:[NSString stringWithFormat:@"[failed] %@", message]];
        } else {
            [self recordTool:call receipt:message];
        }
        [self setCallIndex:[self callIndex] + 1];
        [self persistHistory];
        [self runNextTool];
    };

    if (PDIsDeviceTool(name)) {
        NSString *permission = PDDeviceToolPermissionError(name, args);
        if (permission) {
            done(permission, YES);
            return;
        }
        id includeScreenshot = [args objectForKeyedSubscript:@"include_screenshot"];
        BOOL wantsImage = NO;
        if ([name isEqual:@"screenshot"]) {
            wantsImage = YES;
        } else if ([name isEqual:@"describe_screen"]
                   && [includeScreenshot respondsToSelector:@selector(boolValue)]
                   && [includeScreenshot boolValue]) {
            wantsImage = YES;
        }
        if (wantsImage && ![[PDAIPreference(@"AIAcceptImages", @NO) boolValue]]) {
            done(@"请在供应商设置中开启“接受图片”并选择支持图片的模型，才能读取截图。", YES);
            return;
        }
        void (^deviceHandler)(id, id, id) = [self deviceToolHandler];
        if (deviceHandler) {
            // D2 0x11370：运行时以「单个字典」回调 @{receipt, failed, images}
            deviceHandler(name, args, ^(id rawReply) {
                NSDictionary *reply = [rawReply isKindOfClass:[NSDictionary class]] ? (NSDictionary *)rawReply : nil;
                if ([self generation] != generation) {                 // D2 0x11394
                    return;
                }
                if (![self busy]) {                                    // D2 0x113a8
                    return;
                }
                id images = [reply objectForKeyedSubscript:@"images"];                       // D2 0x4f0f8
                NSString *receipt = PDAIString([reply objectForKeyedSubscript:@"receipt"]);  // D2 0x4f118
                BOOL failed = [[reply objectForKeyedSubscript:@"failed"] boolValue];         // D2 0x4f138
                if ([images count] == 0) {                             // D2 0x11418
                    done(receipt, failed);                             // D2 0x114d0
                    return;
                }
                // 截图附件落盘（块 0x11508）
                dispatch_async([self storageQueue], ^{
                    if ([self generation] != generation) {             // D2 0x1153c
                        return;
                    }
                    NSMutableArray *parts = [NSMutableArray new];
                    NSMutableString *log = [receipt mutableCopy];      // D2 0x11560
                    BOOL imageFailed = NO;
                    for (id item in images) {
                        id saved = [self saveImage:item];              // D2 0x115a8
                        if (!saved) {
                            [log appendString:@"\n截图附件保存失败。"];   // D2 0x4f158
                            imageFailed = YES;
                            break;
                        }
                        [parts addObject:saved];
                        [log appendFormat:@"\n[blob log:%@ %@ image]",  // D2 0x11620
                                           [saved objectForKeyedSubscript:@"id"],
                                           [saved objectForKeyedSubscript:@"mime"]];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([self generation] != generation) {
                            return;
                        }
                        if (![self busy]) {
                            return;
                        }
                        if ([parts count] != 0) {
                            [[self toolMedia] setObject:@{ @"_attachments" : parts }   // D2 0x4e0a58
                                                 forKeyedSubscript:[call objectForKeyedSubscript:@"id"]];
                        }
                        done(log, failed || imageFailed);              // D2 0x11768
                    });
                });
            });
        } else {
            done(@"设备操作仅在运行中的桌宠内可用。", YES);
        }
        return;
    }

    if ([name isEqual:@"pet_say"]) {
        id images = [args objectForKeyedSubscript:@"images"];
        if (images) {
            if (![images isKindOfClass:[NSArray class]] || [images count] >= 5) {
                done(@"images 必须为最多 4 个已知图片句柄。", YES);
                return;
            }
            // 句柄 -> 已落盘附件；顺便把附件记进 toolMedia
            dispatch_async([self storageQueue], ^{
                if ([self generation] != generation) {
                    return;
                }
                NSMutableArray *parts = [NSMutableArray new];
                for (id handle in images) {
                    id image = [[self memory] imageForHandle:PDAIString(handle)];
                    if (!image) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            done([NSString stringWithFormat:@"找不到图片句柄:%@", handle], YES);
                        });
                        return;
                    }
                    id saved = [self saveImage:image];
                    if (!saved) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            done(@"图片无法保存到对话记录。", YES);
                        });
                        return;
                    }
                    [parts addObject:saved];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self generation] != generation) {
                        return;
                    }
                    if (![self busy]) {
                        return;
                    }
                    // D5 0x11bd8：空 images 也照常记录并执行工具，不做 parts.count 守卫
                    [[self toolMedia] setObject:@{ @"_shownImages" : parts }
                                         forKeyedSubscript:[call objectForKeyedSubscript:@"id"]];
                    NSMutableDictionary *trimmed = [args mutableCopy];
                    [trimmed removeObjectForKey:@"images"];
                    [trimmed setObject:@([parts count]) forKeyedSubscript:@"_imageCount"];  // D5 0x4f218
                    void (^toolHandler)(id, id, id) = [self toolHandler];
                    if (toolHandler) {
                        toolHandler(name, trimmed, ^(id receipt, BOOL failed) {
                            done(receipt, failed);
                        });
                        return;
                    }
                    done(@"宠物运行时未连接。", YES);
                });
            });
            return;
        }
    }

    if ([@[ @"read_file", @"write_file", @"edit_file", @"append_file", @"delete_file",
            @"move_file", @"list_files", @"glob_files", @"grep_files", @"save_blob" ] containsObject:name]) {
        // D1 0x10f20/0x10f34：文件类工具交给 PDAIMemory -executeTool:arguments:；read_file 带 mem: 图片特例
        dispatch_async([self storageQueue], ^{
            if ([self generation] != generation) {                    // D1 0x11e88
                return;
            }
            id saved = nil;
            NSString *receipt = nil;
            if ([name isEqual:@"read_file"]) {                        // D1 0x11e9c
                NSString *path = PDAIString([args objectForKeyedSubscript:@"path"]);
                id image = [[self memory] imageForHandle:[@"mem:" stringByAppendingString:path]];  // D1 0x11ee4
                if (image) {
                    saved = [self saveImage:image];                   // D1 0x11f2c
                    if (saved) {
                        receipt = [NSString stringWithFormat:@"[blob mem:%@ %@ image]",           // D1 0x11f7c
                                                              [args objectForKeyedSubscript:@"path"],
                                                              [saved objectForKeyedSubscript:@"mime"]];
                    }
                }
            }
            if (!receipt) {
                receipt = [[self memory] executeTool:name arguments:args];   // D1 0x11f9c
                saved = nil;                                            // D1 0x11fbc
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                // D6 0x120b4：二进制此块只校验 generation，没有 busy 分支
                if ([self generation] != generation) {                // D1 0x120b4
                    return;
                }
                if (saved) {                                          // D1 0x120bc
                    [[self toolMedia] setObject:@{ @"_attachments" : @[ saved ] }   // D1 0x120e0
                                         forKeyedSubscript:[call objectForKeyedSubscript:@"id"]];
                }
                done(receipt, NO);                                    // D1 0x12158
            });
        });
        return;
    }

    void (^toolHandler)(id, id, id) = [self toolHandler];
    if (toolHandler) {
        toolHandler(name, args, ^(id receipt, BOOL failed) {
            done(receipt, failed);
        });
        return;
    }
    done(@"宠物运行时未连接。", YES);
}

// imp 0x00ae5c  types v24@0:8@16
- (void) handleDataMaintenanceRequest:(id)a1 {
    if (![NSThread isMainThread]) {
        // 原实现埋的 assert，文件名/行号取自二进制里的字面量
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
                                                            object:self
                                                              file:@"PDChatService.m"
                                                        lineNumber:0x3f
                                                         description:@"Chat commands run on the main thread"];
    }
    if (![a1 isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *requestID = PDAIString([a1 objectForKeyedSubscript:@"id"]);
    NSString *action = PDAIString([a1 objectForKeyedSubscript:@"action"]);
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:requestID];
    if (!uuid) {
        return;
    }
    if ([requestID isEqual:[self lastMaintenanceID]]) {
        return;
    }
    double expires = PDAINumber([a1 objectForKeyedSubscript:@"expires"], 0.0);
    double now = [[NSDate date] timeIntervalSince1970];
    if (expires < now) {
        return;
    }
    [self setLastMaintenanceID:requestID];
    NSString *path = PDAIString([a1 objectForKeyedSubscript:@"path"]);
    [self performDataMaintenance:action
                            path:path
                      completion:^(id error) {
                          // 结果通过 CFPreferences 回传给宿主进程
                          NSDictionary *result = @{ @"id" : requestID,
                                                    @"error" : [error localizedDescription] ?: @"" };
                          CFPreferencesSetAppValue(CFSTR("DataMaintenanceResult"),
                                                   (CFPropertyListRef)result,
                                                   PDPreferencesDomainRef());
                          CFPreferencesAppSynchronize(PDPreferencesDomainRef());
                      }];
}

// imp 0x12f38  types @16@0:8   // ivar _historyURL @ 0x10  [x0, #0x10]（setter 经 _objc_storeStrong）
- (NSURL *)historyURL {
    return _historyURL;
}

// imp 0x12f40  types v24@0:8@16
- (void)setHistoryURL:(NSURL *)a1 {
    _historyURL = a1;
}

// imp 0x12f4c  types B16@0:8   // ivar _busy @ 0x8  ldrb/strb [x0, #0x8]
- (BOOL)busy {
    return _busy;
}

// imp 0x12f54  types v20@0:8B16
- (void)setBusy:(BOOL)a1 {
    _busy = a1;
}

// imp 0x12f5c  types @?16@0:8   // ivar _stateProvider @ 0x18  [x0, #0x18]（setter 经 _objc_storeStrong）
- (id)stateProvider {
    return _stateProvider;
}

// imp 0x12f64  types v24@0:8@?16
- (void)setStateProvider:(id)a1 {
    _stateProvider = [a1 copy];
}

// imp 0x12f6c  types @?16@0:8   // ivar _toolHandler @ 0x20  [x0, #0x20]（setter 经 _objc_storeStrong）
- (id)toolHandler {
    return _toolHandler;
}

// imp 0x12f74  types v24@0:8@?16
- (void)setToolHandler:(id)a1 {
    _toolHandler = [a1 copy];
}

// imp 0x12f7c  types @?16@0:8   // ivar _deviceToolHandler @ 0x28  [x0, #0x28]（setter 经 _objc_storeStrong）
- (id)deviceToolHandler {
    return _deviceToolHandler;
}

// imp 0x12f84  types v24@0:8@?16
- (void)setDeviceToolHandler:(id)a1 {
    _deviceToolHandler = [a1 copy];
}

// imp 0x12f8c  types @?16@0:8   // ivar _turnStateHandler @ 0x30  [x0, #0x30]（setter 经 _objc_storeStrong）
- (id)turnStateHandler {
    return _turnStateHandler;
}

// imp 0x12f94  types v24@0:8@?16
- (void)setTurnStateHandler:(id)a1 {
    _turnStateHandler = [a1 copy];
}

// imp 0x12f9c  types @?16@0:8   // ivar _interruptionHandler @ 0x38  [x0, #0x38]（setter 经 _objc_storeStrong）
- (id)interruptionHandler {
    return _interruptionHandler;
}

// imp 0x12fa4  types v24@0:8@?16
- (void)setInterruptionHandler:(id)a1 {
    _interruptionHandler = [a1 copy];
}

// imp 0x12fac  types @?16@0:8   // ivar _historyClearedHandler @ 0x40  [x0, #0x40]（setter 经 _objc_storeStrong）
- (id)historyClearedHandler {
    return _historyClearedHandler;
}

// imp 0x12fb4  types v24@0:8@?16
- (void)setHistoryClearedHandler:(id)a1 {
    _historyClearedHandler = [a1 copy];
}

// imp 0x12fbc  types @16@0:8   // ivar _mutableHistory @ 0x48  [x0, #0x48]（setter 经 _objc_storeStrong）
- (NSMutableArray *)mutableHistory {
    return _mutableHistory;
}

// imp 0x12fc4  types v24@0:8@16
- (void)setMutableHistory:(NSMutableArray *)a1 {
    _mutableHistory = a1;
}

// imp 0x12fd0  types @16@0:8   // ivar _pendingEvents @ 0x50  [x0, #0x50]（setter 经 _objc_storeStrong）
- (NSMutableArray *)pendingEvents {
    return _pendingEvents;
}

// imp 0x12fd8  types v24@0:8@16
- (void)setPendingEvents:(NSMutableArray *)a1 {
    _pendingEvents = a1;
}

// imp 0x12fe4  types @16@0:8   // ivar _pendingAttachments @ 0x58  [x0, #0x58]（setter 经 _objc_storeStrong）
- (NSMutableArray *)pendingAttachments {
    return _pendingAttachments;
}

// imp 0x12fec  types v24@0:8@16
- (void)setPendingAttachments:(NSMutableArray *)a1 {
    _pendingAttachments = a1;
}

// imp 0x12ff8  types @16@0:8   // ivar _dataDirectory @ 0x60  [x0, #0x60]（setter 经 _objc_setProperty_nonatomic_copy，offset 0x60）
- (NSString *)dataDirectory {
    return _dataDirectory;
}

// imp 0x13000  types v24@0:8@16
- (void)setDataDirectory:(NSString *)a1 {
    _dataDirectory = [a1 copy];
}

// imp 0x13008  types @16@0:8   // ivar _session @ 0x68  [x0, #0x68]（setter 经 _objc_storeStrong）
- (NSURLSession *)session {
    return _session;
}

// imp 0x13010  types v24@0:8@16
- (void)setSession:(NSURLSession *)a1 {
    _session = a1;
}

// imp 0x1301c  types @16@0:8   // ivar _task @ 0x70  [x0, #0x70]（setter 经 _objc_storeStrong）
- (NSURLSessionDataTask *)task {
    return _task;
}

// imp 0x13024  types v24@0:8@16
- (void)setTask:(NSURLSessionDataTask *)a1 {
    _task = a1;
}

// imp 0x13030  types @16@0:8   // ivar _storageQueue @ 0x78  [x0, #0x78]（setter 经 _objc_storeStrong）
- (NSObject<OS_dispatch_queue> *)storageQueue {
    return _storageQueue;
}

// imp 0x13038  types v24@0:8@16
- (void)setStorageQueue:(NSObject<OS_dispatch_queue> *)a1 {
    _storageQueue = a1;
}

// imp 0x13044  types @16@0:8   // ivar _memory @ 0x80  [x0, #0x80]（setter 经 _objc_storeStrong）
- (PDAIMemory *)memory {
    return _memory;
}

// imp 0x1304c  types v24@0:8@16
- (void)setMemory:(PDAIMemory *)a1 {
    _memory = a1;
}

// imp 0x13058  types @16@0:8   // ivar _calls @ 0x88  [x0, #0x88]（setter 经 _objc_storeStrong）
- (NSArray *)calls {
    return _calls;
}

// imp 0x13060  types v24@0:8@16
- (void)setCalls:(NSArray *)a1 {
    _calls = a1;
}

// imp 0x1306c  types @16@0:8   // ivar _toolMedia @ 0x90  [x0, #0x90]（setter 经 _objc_storeStrong）
- (NSMutableDictionary *)toolMedia {
    return _toolMedia;
}

// imp 0x13074  types v24@0:8@16
- (void)setToolMedia:(NSMutableDictionary *)a1 {
    _toolMedia = a1;
}

// imp 0x13080  types @16@0:8   // ivar _refusedImages @ 0x98  [x0, #0x98]（setter 经 _objc_storeStrong）
- (NSMutableDictionary *)refusedImages {
    return _refusedImages;
}

// imp 0x13088  types v24@0:8@16
- (void)setRefusedImages:(NSMutableDictionary *)a1 {
    _refusedImages = a1;
}

// imp 0x13094  types Q16@0:8   // ivar _callIndex @ 0xa0  ldr/str [x0, #0xa0]
- (NSUInteger)callIndex {
    return _callIndex;
}

// imp 0x1309c  types v24@0:8Q16
- (void)setCallIndex:(NSUInteger)a1 {
    _callIndex = a1;
}

// imp 0x130a4  types Q16@0:8   // ivar _round @ 0xa8  ldr/str [x0, #0xa8]
- (NSUInteger)round {
    return _round;
}

// imp 0x130ac  types v24@0:8Q16
- (void)setRound:(NSUInteger)a1 {
    _round = a1;
}

// imp 0x130b4  types Q16@0:8   // ivar _generation @ 0xb0  ldr/str [x0, #0xb0]
- (NSUInteger)generation {
    return _generation;
}

// imp 0x130bc  types v24@0:8Q16
- (void)setGeneration:(NSUInteger)a1 {
    _generation = a1;
}

// imp 0x130c4  types B16@0:8   // ivar _wakePending @ 0x9  ldrb/strb [x0, #0x9]
- (BOOL)wakePending {
    return _wakePending;
}

// imp 0x130cc  types v20@0:8B16
- (void)setWakePending:(BOOL)a1 {
    _wakePending = a1;
}

// imp 0x130d4  types B16@0:8   // ivar _maintainingData @ 0xa  ldrb/strb [x0, #0xa]
- (BOOL)maintainingData {
    return _maintainingData;
}

// imp 0x130dc  types v20@0:8B16
- (void)setMaintainingData:(BOOL)a1 {
    _maintainingData = a1;
}

// imp 0x130e4  types @16@0:8   // ivar _lastMaintenanceID @ 0xb8  [x0, #0xb8]（setter 经 _objc_setProperty_nonatomic_copy，offset 0xb8）
- (NSString *)lastMaintenanceID {
    return _lastMaintenanceID;
}

// imp 0x130ec  types v24@0:8@16
- (void)setLastMaintenanceID:(NSString *)a1 {
    _lastMaintenanceID = [a1 copy];
}

// imp 0x130f4  types Q16@0:8   // ivar _contextStart @ 0xc0  ldr/str [x0, #0xc0]
- (NSUInteger)contextStart {
    return _contextStart;
}

// imp 0x130fc  types v24@0:8Q16
- (void)setContextStart:(NSUInteger)a1 {
    _contextStart = a1;
}

// imp 0x13104  types @16@0:8   // ivar _handoffFile @ 0xc8  [x0, #0xc8]（setter 经 _objc_setProperty_nonatomic_copy，offset 0xc8）
- (NSString *)handoffFile {
    return _handoffFile;
}

// imp 0x1310c  types v24@0:8@16
- (void)setHandoffFile:(NSString *)a1 {
    _handoffFile = [a1 copy];
}

// imp 0x13114  types @16@0:8   // ivar _handoffText @ 0xd0  [x0, #0xd0]（setter 经 _objc_setProperty_nonatomic_copy，offset 0xd0）
- (NSString *)handoffText {
    return _handoffText;
}

// imp 0x1311c  types v24@0:8@16
- (void)setHandoffText:(NSString *)a1 {
    _handoffText = [a1 copy];
}

// imp 0x13124  types @16@0:8   // ivar _lastStampDay @ 0xd8  [x0, #0xd8]（setter 经 _objc_setProperty_nonatomic_copy，offset 0xd8）
- (NSString *)lastStampDay {
    return _lastStampDay;
}

// imp 0x1312c  types v24@0:8@16
- (void)setLastStampDay:(NSString *)a1 {
    _lastStampDay = [a1 copy];
}

// imp 0x13134  types @16@0:8   // ivar _lastText @ 0xe0  [x0, #0xe0]（setter 经 _objc_setProperty_nonatomic_copy，offset 0xe0）
- (NSString *)lastText {
    return _lastText;
}

// imp 0x1313c  types v24@0:8@16
- (void)setLastText:(NSString *)a1 {
    _lastText = [a1 copy];
}

// imp 0x13144  types @?16@0:8   // ivar _legacyCompletion @ 0xe8  [x0, #0xe8]（setter 经 _objc_storeStrong）
- (id)legacyCompletion {
    return _legacyCompletion;
}

// imp 0x1314c  types v24@0:8@?16
- (void)setLegacyCompletion:(id)a1 {
    _legacyCompletion = [a1 copy];
}

// imp 0x013154  types v16@0:8
// -cxx_destruct（地址 0x13154，长度按下一个符号计会串到 PDAIMemory 区域）
// 原实现只对 30 个 __strong / copy ivar 逐个 _objc_storeStrong(self+off, 0)：
//   0x10 0x18 0x20 0x28 0x30 0x38 0x40 0x48 0x50 0x58 0x60 0x68 0x70 0x78
//   0x80 0x88 0x90 0x98 0xb8 0xc8 0xd0 0xd8 0xe0 0xe8
// ARC 下由编译器自动生成等价的 .cxx_destruct，这里不手写。
@end
