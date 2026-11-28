//
//  PDDoubaoTTS.m
//  PetDFY
//
//  豆包（火山引擎）语音合成客户端：请求构造 + SSE 流式下载。
//
//  二进制证据
//    image base          : 0（arm64 切片 extract/bin/PetDFY.arm64.dylib,
//                          sha256 E4DE3DA94AA849AA6E68690510CE3FD642BDD8C23F69A999104187511109B6EF）
//    方法表              : out/method-table-all.md → 20 条（全 `-`）
//    方法体区间          : 0x14e00 .. 0x15584（末尾 .cxx_destruct 止于 0x15584）
//    实例布局            : instanceSize 56；ivar 见 §ivar（__objc_ivar 实读）
//                          _cancelled +0x08(B)  _configuration +0x10  _session +0x18
//                          _decoder   +0x20     _completion    +0x28  _failure +0x30
//    静态 C 函数          : _PDDoubaoRequest     0x13b9c..0x141e0（401 insns，symtab 有符号）
//                          _PDDoubaoSpeechSegments 0x142a8（本文件不涉及，被 SSE decoder 使用）
//                          PDDoubaoTrim        0x14180..0x141e0（无符号，由 -synthesizeText 调用）
//                          PDDoubaoError       0x141e0..0x142a8（无符号，4 处校验 + 2 处回调共用）
//
//  纠错（对照旧快照 src-orig/Sources/PDDoubaoTTS.m.orig）
//    旧快照把 _PDDoubaoRequest 的地址标成 0x14b10。实测 0x14b10 落在
//    -[PDDoubaoSSEDecoder appendData:] 体内（方法表：0x14a40..0x14e00），
//    与请求构造无关。真地址由 symtab 直接读出：_PDDoubaoRequest = 0x13b9c，
//    并且 -synthesizeText: 在 0x14ed0 处 `bl 0x13b9c` 调用它 —— 双向印证。
//
//  记号
//    [0xADDR]     该行对应指令地址
//    <CALL 0xADDR>  未解析的 bl 目标（本文件 0 处）
//  已定案 2026-11-28（复核）：实测成立，不是图例空话——
//    方法表 20 条 → 类体区间 0x14e00..0x15584（末方法 .cxx_destruct 0x15530..0x15584）；
//    静态函数 _PDDoubaoRequest 0x13b9c..0x14180、PDDoubaoTrim 0x14180..0x141e0、
//    PDDoubaoError 0x141e0..0x142a8。两个区间内 bl/b 共 261 条，逐条解目标：
//      · 运行时桩（_objc_retain_x*/_objc_release_x*/_objc_msgSendSuper2/_objc_opt_new/
//        _dispatch_async/___stack_chk_fail 等）与 objc_msgSend 型选择器（sel:xxx）
//      · 文件内静态：0x14180(PDDoubaoTrim) / 0x141e0(PDDoubaoError) / 0x13b9c(_PDDoubaoRequest)
//    没有任何一条落到“既非桩、又非文件内静态”的外部地址 → 0 处未解析。
//    Assumed      语义推断（结构判定仍是 Observed），逐处标注地址
//
//  编译状态：NOT RUN（Windows 主机，无 iOS SDK / 无 PDDoubaoTTS.h 全量声明；
//  括号走查见文末 §SELFCHECK）
//

#import "PDDoubaoTTS.h"
#import "PDDoubaoSSEDecoder.h"

// ---------------------------------------------------------------------------
// 语音参数结构
//
// 观测：-synthesizeText: 第 5 个形参在 arm64 上按“大于 16 字节的复合类型”间接传入
// （x6 = 指针，方法体内 ldr q0,[x20] 取 16 字节 + ldr x8,[x20,#0x10] 取第 3 个 8 字节），
// 且 _PDDoubaoRequest 会把换算后的整数写回该结构（0x13dd0 str q0,[x25] / 0x13dd4 str x8,[x25,#0x10]）。
// type encoding 为 {?=qqq}（method-table 第 2 列），即 3 个 8 字节字段。
// 字段名已定案：+0x00 → audio_params/post_process 的 "pitch"（0x13f40/0x13f4c、0x13f30）；
//   +0x08 → "speech_rate"（0x13e38/0x13e4c v0.d[1]）；+0x10 → "loudness_rate"（0x13e64/0x13e70）。
// 类型已定案为 int64：0x13d88/0x13dac scvtf 读入，0x13dd0/0x13dd4 以整数回写，故用 int64_t。
// ---------------------------------------------------------------------------
typedef struct PDDoubaoVoiceParams {
    int64_t pitch;         // +0x00  夹到 [-12, 12]   （0x13db4/0x13dc0 向量常量 0xbfef0/0xbff00）
    int64_t speechRate;    // +0x08  夹到 [-50, 100]  （同左向量）
    int64_t loudnessRate;  // +0x10  夹到 [-50, 100]  （标量版 0x13d8c/0x13d98，fcvtas 0x13da4）
} PDDoubaoVoiceParams;

// 错误域：0x1424c `CF "com.susudear.petdfy.doubao"`
static NSString *const PDDoubaoTSErrorDomain = @"com.susudear.petdfy.doubao";

// 端点与固定头：0x14080 / 0x14114
static NSString *const PDDoubaoEndpoint =
    @"https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse";
static NSString *const PDDoubaoResourceId = @"seed-tts-2.0";

// 默认音色：0x13d80 `CF "zh_female_xiaohe_uranus_bigtts"`
static NSString *const PDDoubaoDefaultSpeaker = @"zh_female_xiaohe_uranus_bigtts";

static NSString *PDDoubaoTrim(NSString *s);
static NSError *PDDoubaoError(NSInteger code, NSString *message);
static NSURLRequest *PDDoubaoRequest(NSString *text, NSString *apiKey, NSString *speaker,
                                     NSString *instruction, PDDoubaoVoiceParams *params,
                                     NSError **outError);

#pragma mark - 静态辅助

// PDDoubaoTrim —— 无符号静态函数，0x14180..0x141e0，38 insns。
// 调用点：0x13bf8 / 0x13c0c / 0x13c20 / 0x13c34（_PDDoubaoRequest 开头四次）。
// 语义：whitespaceAndNewlineCharacterSet 两端裁剪。
static NSString *PDDoubaoTrim(NSString *s) {
    // [0x14190] NSCharacterSet 类引用（0x119000+0xd00）
    NSCharacterSet *set = [NSCharacterSet whitespaceAndNewlineCharacterSet];   // [0x141a4]
    return [s stringByTrimmingCharactersInSet:set];                            // [0x141b8]
}

// PDDoubaoError —— 无符号静态函数，0x141e0..0x142a8，43 insns。
// userInfo 只有一个键：0x141f8 取 GOT 槽（NSLocalizedDescriptionKey），
// 0x14240 dictionaryWithObjects:forKeys:count: count=1。
static NSError *PDDoubaoError(NSInteger code, NSString *message) {
    // 0x1421c stp x8,x1,[sp,#8]：keys[0] = GOT 槽里的 NSLocalizedDescriptionKey，
    // objects[0] = 消息本身；0x14234/0x14238 把两段栈地址分别给 x3/x2，w4 = 1（0x1423c）。
    NSString *key = NSLocalizedDescriptionKey;
    NSDictionary *info = [NSDictionary dictionaryWithObjects:&message
                                                     forKeys:&key
                                                       count:1];           // [0x14240]
    return [NSError errorWithDomain:PDDoubaoTSErrorDomain code:code userInfo:info]; // [0x14260]
}

#pragma mark -

@implementation PDDoubaoTTS

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS initWithConfiguration:]  imp=0x14e00 insns=27
//   x2 = configuration；super 是 NSObject（objc_msgSendSuper2 @0x14e34）
// ---------------------------------------------------------------------------
- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration {
    // [0x14e14] 形参 retain
    if ((self = [super init])) {                                   // [0x14e34]
        // [0x14e40] [configuration copy] → +0x10 就地 storeStrong
        _configuration = [configuration copy];                     // self+0x10
    }
    return self;                                                   // [0x14e58]
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS synthesizeText:key:speaker:instruction:options:completion:]
//   imp=0x14e6c insns=141
//
//   arm64 形参落位（由 0x14e88..0x14ea4 的搬运反推）：
//     x0 self / x1 _cmd / x2 text / x3 key / x4 speaker / x5 instruction
//     x6 = &options（24 字节结构体，间接传） / x7 completion
//   栈帧 0xa0：sp+0x30..0x47 options 本地副本，sp+0x48 错误输出槽
// ---------------------------------------------------------------------------
- (void)synthesizeText:(NSString *)text
                   key:(NSString *)key
               speaker:(NSString *)speaker
           instruction:(NSString *)instruction
               options:(PDDoubaoVoiceParams)options
            completion:(void (^)(NSData *audio, NSError *error))completion {
    // [0x14e88] x20 = &options；[0x14ea4] x19 = retain(completion)
    PDDoubaoVoiceParams local = options;                           // [0x14ea8] ldr q0,[x20]
                                                                   // [0x14eb0] ldr x8,[x20,#0x10]
    NSError *error = nil;
    // [0x14ed0] bl _PDDoubaoRequest(text, key, speaker, instruction, &local, &error)
    NSURLRequest *request = PDDoubaoRequest(text, key, speaker, instruction, &local, &error);
    // [0x14ed4] claimAutoreleasedReturnValue；[0x14ee0] 错误槽 retain
    if (request) {                                                 // [0x14ee8] cbz x20
        self.completion = completion;                              // [0x14ef4] setCompletion:
        self.decoder = [PDDoubaoSSEDecoder new];                   // [0x14f00] _objc_opt_new
        // [0x14f1c] configuration / [0x14f28] copy
        NSURLSessionConfiguration *cfg = [self.configuration copy];
        cfg.timeoutIntervalForRequest = 25.0;                      // [0x14f34] fmov d0,#25.0
        cfg.timeoutIntervalForResource = 45.0;                     // [0x14f44] ldr d0,[0xbf000+0xf10]=45.0
        cfg.HTTPMaximumConnectionsPerHost = 1;                     // [0x14f58]
        cfg.HTTPShouldSetCookies = NO;                             // [0x14f64] w2=0
        cfg.HTTPCookieStorage = nil;                               // [0x14f70]
        cfg.URLCache = nil;                                        // [0x14f7c]
        NSOperationQueue *queue = [NSOperationQueue new];           // [0x14f88] _objc_opt_new
        queue.maxConcurrentOperationCount = 1;                     // [0x14f94]
        queue.qualityOfService = NSQualityOfServiceUtility;         // [0x14fa0] w2=0x11
        // [0x14fb8] sessionWithConfiguration:delegate:delegateQueue:
        self.session = [NSURLSession sessionWithConfiguration:cfg
                                                     delegate:self
                                                delegateQueue:queue];
        // [0x14fe8] dataTaskWithRequest: / [0x14ff4] resume
        [[self.session dataTaskWithRequest:request] resume];
    } else {
        // [0x15008] 失败路径：主队列异步回调 completion(nil, error)
        //   块字面量：0x1500c __NSConcreteStackBlock / 0x15024 invoke=0x1508c
        //   捕获顺序（0x15038 sp+0x28 = completion，0x15040 sp+0x20 = error）
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(nil, error);
            }
        });
    }
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:]
//   imp=0x150a0 insns=26
//   拒绝跟随重定向：任何 3xx 都当作“语音服务地址异常”。
// ---------------------------------------------------------------------------
- (void)URLSession:(NSURLSession *)session
                task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // [0x150c4] w0=6 → 错误码 6
    self.failure = PDDoubaoError(6, @"语音服务地址异常。");          // [0x150c8]/[0x150dc]
    completionHandler(nil);                                        // [0x150f0] blr x8, x1=#0
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS URLSession:dataTask:didReceiveResponse:completionHandler:]
//   imp=0x15108 insns=57
// ---------------------------------------------------------------------------
- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    // [0x15138] NSHTTPURLResponse 类引用 0x119000+0xea0；[0x15148] isKindOfClass:
    NSInteger status = 0;                                          // [0x15174] mov x21,#0
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        status = ((NSHTTPURLResponse *)response).statusCode;        // [0x15154]
    }
    if (status != 200) {                                           // [0x1515c] cmp x0,#0xc8
        // [0x15188] @"语音服务连接失败（HTTP %ld）。"
        self.failure = PDDoubaoError(status,
            [NSString stringWithFormat:@"语音服务连接失败（HTTP %ld）。", (long)status]);
        completionHandler(NSURLSessionResponseCancel);              // [0x151c0] x1=#0
    } else {
        // [0x15168] cancelled → eor w1,w0,#1：未取消才允许继续收数据
        completionHandler(!self.cancelled);                         // [0x15170]
    }
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS URLSession:dataTask:didReceiveData:]  imp=0x151ec insns=52
// ---------------------------------------------------------------------------
- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (self.cancelled) {                                          // [0x15220] tbnz w0,#0
        return;
    }
    [self.decoder appendData:data];                                // [0x15238]
    // 0x15244..0x15260 取两次 decoder.error（一次判空、一次取出赋值），源码为：
    if (self.decoder.error) {                                       // [0x15264] cbz x22
        self.failure = self.decoder.error;                          // [0x1528c] setFailure:
        [self cancel];                                             // [0x1529c]
    }
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS URLSession:task:didCompleteWithError:]  imp=0x152bc insns=111
// ---------------------------------------------------------------------------
- (void)URLSession:(NSURLSession *)session
                task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    // [0x152f0] failure；[0x15300] csel：failure ?: error
    NSError *failure = self.failure ?: error;
    if (self.cancelled) {                                          // [0x15318] cbz w0
        // [0x15320] NSError 类 + 0x4f8 处 NSURLErrorDomain，x3 = -0x3e7 = -999
        failure = [NSError errorWithDomain:NSURLErrorDomain
                                      code:NSURLErrorCancelled
                                  userInfo:nil];
    }
    NSData *audio = nil;                                           // [0x15350] mov x22,#0
    if (!failure) {                                                // [0x1534c] cbz x20
        audio = [self.decoder finish];                              // [0x15368]
        failure = self.decoder.error;                               // [0x15388]
    }
    void (^completion)(NSData *, NSError *) = self.completion;      // [0x153a0]
    self.completion = nil;                                         // [0x153b0]
    [self.session finishTasksAndInvalidate];                        // [0x153b8]
    self.session = nil;                                            // [0x153c8]
    if (completion) {                                               // [0x153cc] cbz x24
        // [0x153ec] 块 invoke=0x15464，捕获 (audio, failure, completion)
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(audio, failure);
        });
    }
}

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS cancel]  imp=0x15478 insns=17
// ---------------------------------------------------------------------------
- (void)cancel {
    self.cancelled = YES;                                          // [0x15490] w2=1
    [self.session invalidateAndCancel];                            // [0x154a4]
}

#pragma mark - 属性访问器

// -[PDDoubaoTTS configuration]   imp=0x154bc insns=2
- (NSURLSessionConfiguration *)configuration { return _configuration; }   // [0x154bc]
// -[PDDoubaoTTS setConfiguration:]  imp=0x154c4 insns=3
- (void)setConfiguration:(NSURLSessionConfiguration *)configuration {
    _configuration = configuration;                                 // [0x154c8] storeStrong
}
// -[PDDoubaoTTS session]  imp=0x154d0 insns=2
- (NSURLSession *)session { return _session; }                       // [0x154d0]
// -[PDDoubaoTTS setSession:]  imp=0x154d8 insns=3
- (void)setSession:(NSURLSession *)session { _session = session; }   // [0x154dc]
// -[PDDoubaoTTS decoder]  imp=0x154e4 insns=2
- (PDDoubaoSSEDecoder *)decoder { return _decoder; }                 // [0x154e4]
// -[PDDoubaoTTS setDecoder:]  imp=0x154ec insns=3
- (void)setDecoder:(PDDoubaoSSEDecoder *)decoder { _decoder = decoder; }
// -[PDDoubaoTTS completion]  imp=0x154f8 insns=2
- (void (^)(NSData *, NSError *))completion { return _completion; }   // [0x154f8]
// -[PDDoubaoTTS setCompletion:]  imp=0x15500 insns=2
- (void)setCompletion:(void (^)(NSData *, NSError *))completion {
    // [0x15504] objc_setProperty_nonatomic_copy，偏移 0x28
    _completion = [completion copy];
}
// -[PDDoubaoTTS failure]  imp=0x15508 insns=2
- (NSError *)failure { return _failure; }                             // [0x15508]
// -[PDDoubaoTTS setFailure:]  imp=0x15510 insns=3
- (void)setFailure:(NSError *)failure { _failure = failure; }        // [0x15514]
// -[PDDoubaoTTS cancelled]  imp=0x1551c insns=3
- (BOOL)cancelled { return _cancelled & 1; }                         // [0x1551c] ldrb +0x08
// -[PDDoubaoTTS setCancelled:]  imp=0x15528 insns=2
- (void)setCancelled:(BOOL)cancelled { _cancelled = cancelled; }     // [0x15528] strb +0x08

// ---------------------------------------------------------------------------
// -[PDDoubaoTTS .cxx_destruct]  imp=0x15530 insns=21
//   释放顺序 = ivar 声明逆序：+0x30 failure / +0x28 completion / +0x20 decoder
//                            / +0x18 session / +0x10 configuration
// ---------------------------------------------------------------------------
- (void).cxx_destruct {
    // [0x15540] +0x30；[0x1554c] +0x28；[0x15558] +0x20；[0x15564] +0x18；[0x15570] +0x10
    _failure = nil;
    _completion = nil;
    _decoder = nil;
    _session = nil;
    _configuration = nil;
}

@end

#pragma mark - _PDDoubaoRequest（C 静态函数，0x13b9c..0x141e0，401 insns）

// 请求构造与参数校验。返回值即 -synthesizeText: 里的 request（NSURLRequest*），
// 失败时返回 nil 并写 *outError。
//
// 形参落位（由 0x13b9c 序言与 0x14eb8..0x14ed0 调用点双方读出）：
//   w0/x0 text  x1 apiKey  x2 speaker  x3 instruction
//   x4 &params（24B 结构，会被就地改写）  x5 NSError** 
//
// 校验串（Observed，逐条对应 CFString）：
//   0x13cbc "没有可朗读的文字。"          text 去空白后为空
//   0x13ccc "尚未配置豆包语音 API Key。"   apiKey 为空
//   0x13cdc "API Key 不能包含换行。"       apiKey 命中 newlineCharacterSet
//   0x13cac "单段语音文字过长。"           UTF-8 字节数 > 12000（0x13c9c mov w8,#0x2ee0）
//   0x13d14 "语气描述最多 1000 个字符。"   instruction.length >= 1001（0x13d08 cmp #0x3e9）
//   四处的错误码都是 1（0x13ce4 mov w0,#1）。
static NSURLRequest *PDDoubaoRequest(NSString *text, NSString *apiKey, NSString *speaker,
                                     NSString *instruction, PDDoubaoVoiceParams *params,
                                     NSError **outError) {
    // [0x13bd8] 栈保护槽
    NSString *trimText        = PDDoubaoTrim(text);                 // [0x13bf8]
    NSString *trimInstruction = PDDoubaoTrim(instruction);          // [0x13c0c]
    NSString *trimKey         = PDDoubaoTrim(apiKey);               // [0x13c20]
    NSString *trimSpeaker     = PDDoubaoTrim(speaker);              // [0x13c34]

    // [0x13c4c] 文字为空
    if (trimText.length == 0) {                                     // [0x13c40] length
        if (outError) { *outError = PDDoubaoError(1, @"没有可朗读的文字。"); }  // [0x13cb8]
        return nil;
    }
    // [0x13c58] key 为空
    if (trimKey.length == 0) {
        if (outError) { *outError = PDDoubaoError(1, @"尚未配置豆包语音 API Key。"); } // [0x13cc8]
        return nil;
    }
    // [0x13c64] newlineCharacterSet / [0x13c78] rangeOfCharacterFromSet:
    NSRange nl = [trimKey rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    if (nl.location != NSNotFound) {                                // [0x13c84] cmp #0x7fff…
        if (outError) { *outError = PDDoubaoError(1, @"API Key 不能包含换行。"); } // [0x13cd8]
        return nil;
    }
    // [0x13c90] lengthOfBytesUsingEncoding:NSUTF8StringEncoding（w2=4）
    if ([trimText lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 12000) { // [0x13c9c]
        if (outError) { *outError = PDDoubaoError(1, @"单段语音文字过长。"); }  // [0x13cac]
        return nil;
    }
    // [0x13d00] 语气描述长度
    if (trimInstruction.length > 1000) {                            // [0x13d08] cmp #0x3e9
        if (outError) { *outError = PDDoubaoError(1, @"语气描述最多 1000 个字符。"); } // [0x13d14]
        return nil;
    }
    // [0x13d6c] 音色缺省
    if (trimSpeaker.length == 0) {                                  // [0x13d74] cbnz x0
        trimSpeaker = PDDoubaoDefaultSpeaker;
    }

    // ---- 参数夹紧并就地写回（0x13d84..0x13dd4） ----
    // loudnessRate(+0x10)：0x13d84 ldr d0 / 0x13d88 scvtf 走标量，夹 [-50,100]（0x13d8c/0x13d98），
    //   0x13da4 fcvtas 取整，0x13dd4 以整数回写。
    // pitch/speechRate(+0x00/+0x08)：0x13da8 ldr q0 / 0x13dac scvtf 走两路向量，夹 [-12,12] 与
    //   [-50,100]（0x13db4/0x13dc0 向量常量），0x13dc8 frinta + 0x13dcc fcvtzs，0x13dd0 以整数回写。
    // 已定案：两路取整均为 round-half-away；字段类型是 int64（scvtf 读入 / str 整数回写），不是 double。
    params->loudnessRate = (int64_t)llround(MIN(MAX((double)params->loudnessRate, -50.0), 100.0)); // [0x13d84..0x13da4]
    double pitchD  = MIN(MAX((double)params->pitch, -12.0), 12.0);        // [0x13db8]/[0x13dc4]
    double speechD = MIN(MAX((double)params->speechRate, -50.0), 100.0);
    params->pitch      = (int64_t)llround(pitchD);                        // [0x13dc8]/[0x13dd0]
    params->speechRate = (int64_t)llround(speechD);

    // ---- audio_params（5 键，0x13e98 dictionaryWithObjects:forKeys:count: w4=5） ----
    // 键序（0x13e14/0x13e40/0x13e60）：format, sample_rate, bit_rate, speech_rate, loudness_rate
    // 值：@"mp3"（0x13e08）、0x108790 与 0x1087a8 两个常量整数对象。
    //   常量对象已按 __objc_intobj（0x108778 起，每项 24 字节）解出：
    //   0x108790 → 0x5dc0 = 24000，0x1087a8 → 0xfa00 = 64000。
    NSDictionary *audioParams = @{
        @"format":        @"mp3",
        @"sample_rate":   @24000,      // 0x108790（__objc_intobj，值 24000）
        @"bit_rate":      @64000,      // 0x1087a8（__objc_intobj，值 64000）
        @"speech_rate":   @((NSInteger)params->speechRate),
        @"loudness_rate": @((NSInteger)params->loudnessRate),
    };                                                              // [0x13e98]

    // ---- 顶层对象（3 键，0x13eb8 w4=3）：text / speaker / audio_params ----
    NSMutableDictionary *body = [@{ @"text": trimText,
                                    @"speaker": trimSpeaker,
                                    @"audio_params": audioParams } mutableCopy];  // [0x13ec4]

    // [0x13ee4] NSMutableDictionary 新建（0x119000+0xe68）
    NSMutableDictionary *additions = [NSMutableDictionary new];
    if (trimInstruction.length) {                                   // [0x13ef4] cbz x0
        // [0x13f0c] arrayWithObjects:count: → @[instruction]
        additions[@"context_texts"] = @[trimInstruction];           // [0x13f28] key 0x2c8
    }
    // ---- post_process（单键 "pitch"；0x13f6c w4=1，二进制里没有 vibRate 键） ----
    // 已定案 0x13f30: ldr x2,[x25] 即 params->pitch；0x13f34 cbz 是门——pitch==0 时整块跳过（→0x13f98）。
    // 0x13f4c numberWithInteger: 复用同一个 x2；0x13f84 接收者是 x26 = additions，不是 body。
    // （原文写的 0x13f68 "vibRate" 实为 add x3,sp,#0x28 的栈地址，非 CF 串。）
    if (params->pitch != 0) {
        additions[@"post_process"] = @{ @"pitch": @(params->pitch) };    // [0x13f8c] key 0x308
    }

    // 已定案 0x13f98..0x13ff8: 仅在 additions 非空时写入 body["additions"]（0x13f98 count / 0x13fa8 cbz），
    // 且写入的是 0x13fbc dataWithJSONObject: → 0x13fe0 initWithData:encoding:4 得到的 JSON 字符串，
    // 不是 additions 字典本身。
    if (additions.count != 0) {
        NSData *additionsData = [NSJSONSerialization dataWithJSONObject:additions
                                                               options:0
                                                                 error:outError];  // [0x13fbc] x4=x23=outError（0x13bbc）
        if (additionsData != nil) {                                  // [0x13fc8] cbz → 0x14170
            NSString *additionsText =
                [[NSString alloc] initWithData:additionsData
                                      encoding:NSUTF8StringEncoding];  // [0x13fe0] w3=4
            body[@"additions"] = additionsText;                      // [0x13ff8] key 0x328
        }
    }

    // ---- 顶层 user / req_params（0x14004/0x14018/0x14038, w4=2） ----
    // 已定案 0x140010: add x9,x9,#0x250 直接取 0x108250 这个地址（无 ldr），其 isa 为
    // NSConstantDictionary，载荷槽 0x108268→CF "uid"、0x108270→CF "petdfy"——即 @{@"uid": @"petdfy"}，
    // 不是空字典。0x140024 stp x9,x28,[sp,#0x18]: objects=[0x108250, body]，req_params 承载 body。
    NSDictionary *envelope = @{ @"user": @{ @"uid": @"petdfy" },
                                @"req_params": body };               // [0x1403c]

    // [0x14048] dataWithJSONObject:options:0 error:；失败跳 0x14168（返回 nil 并写 *outError）
    NSError *jsonError = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:&jsonError];
    if (!json) {                                                    // [0x14068] cbz x23
        if (outError) { *outError = jsonError; }
        return nil;
    }

    // ---- 组装请求（0x14080..0x14158） ----
    NSURL *url = [NSURL URLWithString:PDDoubaoEndpoint];            // [0x14084]
    NSMutableURLRequest *req =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestUseProtocolCachePolicy
                            timeoutInterval:45.0];              // [0x140a0]（x2=x27=0 缓存策略；
                                                                //   x3 = 0xbf000+0xf10 = 45.0）
    req.HTTPMethod = @"POST";                                        // [0x140bc] CF 0x3c8
    req.HTTPBody = json;                                             // [0x140c8]
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];   // [0x140e0]
    [req setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];        // [0x140f8]
    [req setValue:trimKey forHTTPHeaderField:@"X-Api-Key"];                  // [0x1410c]
    [req setValue:PDDoubaoResourceId forHTTPHeaderField:@"X-Api-Resource-Id"];// [0x14124]
    [req setValue:[NSUUID UUID].UUIDString forHTTPHeaderField:@"X-Api-Request-Id"]; // [0x14158]
    return req;                                                      // [0x13d48]
}

#pragma mark - §SELFCHECK

// 括号走查（人工）：本文件 @implementation 内 20 个方法，全部成对闭合；
//   PDDoubaoRequest 内 6 个顶层 if 各自 return，末尾统一 return req；
//   3 处块字面量（0x1500c / 0x153ec / 0x140a0 无关）均在 dispatch_async 括号内闭合。
// 方法计数核对：method-table 20 条 → 本文件显式实现 20 条（getter/setter 12 条亦逐条给出）。
// NOT RUN：未编译、未链接、未运行；无 iOS SDK，无法产出 dSYM 级比对。
