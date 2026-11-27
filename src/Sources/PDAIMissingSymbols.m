//
//  PDAIMissingSymbols.m
//  补齐 PDChatService.m 里以带下划线名字 extern 的三个符号：
//
//      _PDAIToolDeclarations(void)
//      _PDAIRequestBody(prompt, history, tools, options, dataDirectory, error)
//      _PDAIImageRetryAllowed(endpoint, request, settings)
//
//  这三个符号在 build.046 里只有引用、没有实现，chained fixups 里登记为
//  flat-lookup 导入。dyld 加载 PetDFY.dylib 时：
//
//      symbol not found in flat namespace '__PDAIImageRetryAllowed'
//
//  绑定失败 → dlopen 返回 NULL → ellekit 静默跳过 → PDBootstrap 的 constructor
//  不执行 → petdfy-main-loaded.txt 不出现。这是 build.045/046 仍不出角色的根因。
//
//  实现约定（Assumed，依据调用点与偏好键）：
//    - 工具声明直接复用 PDDeviceToolDeclarations()（25 条 MCP 工具）。
//    - 请求体按 OpenAI Chat Completions 形状组装，服务地址/模型/密钥取
//      AIBaseURL / AIModel / AIAPIKey，服务端若给了完整 /chat/completions 地址则不重复拼接。
//    - 图片被拒重试由调用点先行限定（非 recovering、retryBytes 非空、sentImages 非空），
//      这里只做最后一道开关，默认放行。
//

#import <Foundation/Foundation.h>
#import "PetDFY.h"
#import "PDDeviceToolsDeclarations.h"

#pragma mark - _PDAIToolDeclarations

id _PDAIToolDeclarations(void) {
    NSArray *tools = PDDeviceToolDeclarations();
    return [tools isKindOfClass:[NSArray class]] ? tools : @[];
}

#pragma mark - _PDAIImageRetryAllowed

BOOL _PDAIImageRetryAllowed(id endpoint, id request, id settings) {
    // 用户关了图片重试就拒绝；其余情况放行（调用点已做三重前置判断）。
    id flag = PDAIPreference(@"AIImageRetry", nil);
    if ([flag isKindOfClass:[NSNumber class]]) return [flag boolValue];
    if ([flag isKindOfClass:[NSString class]]) return [(NSString *)flag boolValue];
    return YES;
}

#pragma mark - _PDAIRequestBody

static NSString *PDAIResolveEndpoint(void) {
    NSString *base = PDAIString(PDAIPreference(@"AIBaseURL", @""));
    if (![base isKindOfClass:[NSString class]]) return nil;
    base = [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!base.length) return nil;

    NSString *lower = [base lowercaseString];
    if ([lower containsString:@"/chat/completions"]) return base;

    NSString *prefix = [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] ? @"" : @"https://";
    NSString *url = [prefix stringByAppendingString:base];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    return [url stringByAppendingString:@"/chat/completions"];
}

static NSArray *PDAIMessagesFromHistory(id history, NSString *prompt) {
    NSMutableArray *messages = [NSMutableArray array];
    if ([history isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)history) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *role = PDAIString(((NSDictionary *)item)[@"role"]);
            if (!role.length) role = @"user";
            id content = ((NSDictionary *)item)[@"content"];
            if (!content) content = ((NSDictionary *)item)[@"text"];
            if (!content) continue;
            [messages addObject:@{ @"role": role, @"content": content }];
        }
    }
    if ([prompt isKindOfClass:[NSString class]] && [(NSString *)prompt length]) {
        [messages addObject:@{ @"role": @"user", @"content": prompt }];
    }
    if (!messages.count) {
        [messages addObject:@{ @"role": @"user", @"content": @"" }];
    }
    return messages;
}

id _PDAIRequestBody(id prompt, id history, id tools, id options,
                    id dataDirectory, NSError **error) {
    NSString *endpoint = PDAIResolveEndpoint();
    if (!endpoint.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"AI 服务地址未配置（AIBaseURL 为空）。"}];
        }
        return nil;
    }

    NSString *model = PDAIString(PDAIPreference(@"AIModel", @""));
    if (!model.length) model = @"doubao-seed-1.6";

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = model;
    body[@"messages"] = PDAIMessagesFromHistory(history, prompt);
    body[@"stream"] = @NO;

    if ([options isKindOfClass:[NSDictionary class]]) {
        id maxTokens = ((NSDictionary *)options)[@"maxTokens"];
        if ([maxTokens isKindOfClass:[NSNumber class]]) body[@"max_tokens"] = maxTokens;
    }
    if (!body[@"max_tokens"]) body[@"max_tokens"] = @(128000);

    if ([tools isKindOfClass:[NSArray class]] && [(NSArray *)tools count]) {
        body[@"tools"] = tools;
        body[@"tool_choice"] = @"auto";
    }

    NSError *jsonError = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!payload) {
        if (error) *error = jsonError;
        return nil;
    }

    NSURL *url = [NSURL URLWithString:endpoint];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.susudear.petdfy.chat"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"AI 服务地址无效：%@", endpoint]}];
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = payload;
    request.timeoutInterval = 120.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSString *key = PDAIString(PDAIPreference(@"AIAPIKey", @""));
    if (key.length) {
        [request setValue:[@"Bearer " stringByAppendingString:key]
       forHTTPHeaderField:@"Authorization"];
    }

    id extra = PDAIPreference(@"AIExtraHeaders", nil);
    if ([extra isKindOfClass:[NSDictionary class]]) {
        for (id hk in (NSDictionary *)extra) {
            if (![hk isKindOfClass:[NSString class]]) continue;
            id hv = ((NSDictionary *)extra)[hk];
            if ([hv isKindOfClass:[NSString class]]) {
                [request setValue:hv forHTTPHeaderField:hk];
            }
        }
    }

    (void)dataDirectory;
    return request;
}
