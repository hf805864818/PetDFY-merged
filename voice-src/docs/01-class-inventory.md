# petdfy-voice · 类 / 方法清单（build.080 arm64）

> 来源：`petdfy-voice`（fat Mach-O，arm64 + arm64e，SHA-256 `b11cb703…75c83`）。
> 下面的结构体偏移、方法 imp、C 函数地址全部从切片 arm64 的 `__objc_classlist` /
> relative method list（`__TEXT,__objc_methlist`）/ `__symtab` 直接解出，未做推测。
> 两个切片（arm64 / arm64e）的类、方法、字符串一致，只是地址不同；本表按 arm64。

## 0 概览

| 项 | 值 |
|---|---|
| 文件类型 | MH_EXECUTE（CLI helper），arm64 + arm64e，`minos 16.0`，`sdk 16.4`，未签名 |
| 明文段 | `__TEXT` 0x100004000–0x10018f1ac（0x18c1ac 字节代码） |
| 动态库 | libobjc / Foundation / CoreFoundation / Security / libz / libiconv / libSystem |
| 静态链入 | opus 1.6.1（`vendor/asr/sources/opus-1.6.1`）、OpenSSL 3（`ossl_*`）、miniz（`mz_*`）、zlib 1.2.11 |
| 入口 | `_main` @ `0x1001855b4` |
| ObjC 类 | 4 个，实例大小 72 / 128 / 128 / 16 字节 |
| ObjC 协议 | 4 个（NSObject、NSURLSessionDelegate、NSURLSessionTaskDelegate、NSURLSessionDownloadDelegate） |
| Category | 0 |
| 应用层函数 | 104 个（4 类方法 + 100 个 C 函数），合计 10,062 条指令 |

## 1 类关系

```
NSObject
├── PDVoiceWorker            ivar 0x08..0x78，instsize 128   ← opus 编码 + 请求泵
├── PDWeTypeClient           ivar 0x08..0x78，instsize 128   ← wss/HTTPS 协议客户端
├── PDWeTypeKeyAgreement     ivar 0x08，      instsize 16    ← ECDH（OpenSSL EC_KEY）
└── PDAssetDownloader        ivar 0x08..0x40，instsize 72   ← NSURLSessionDownloadDelegate
```

`PDVoiceWorker` 持有 `PDWeTypeClient`；`PDWeTypeClient` 持有 `PDWeTypeKeyAgreement`。
`PDAssetDownloader` 只被资产子系统（IPC 命令 4）使用，与语音链路无耦合。

## 2 PDVoiceWorker

`@interface PDVoiceWorker : NSObject`  instsize 128，`class_ro` @ `0x100268a88`

### 实例变量（偏移由 `__objc_ivar` 与 getter 交叉确认）

| 偏移 | 编码 | 名称 | 用途 |
|---|---|---|---|
| 0x08 | `@"NSObject<OS_dispatch_queue>"` | `_queue` | 主队列（由 main 注入） |
| 0x10 | `@"NSObject<OS_dispatch_source>"` | `_timer` | 100 ms 泵定时器 |
| 0x18 | `@"NSObject<OS_dispatch_source>"` | `_watchdog` | 165 s 启动看门狗（`exit(1)`） |
| 0x20 | `@"PDWeTypeClient"` | `_client` | 协议客户端 |
| 0x28 | `^{OpusEncoder=}` | `_encoder` | opus 编码器 |
| 0x30 | `@"NSMutableData"` | `_pcm` | 待编码 PCM16 缓冲 |
| 0x38 | `@"NSMutableArray"` | `_packets` | 待发送的 opus 包队列 |
| 0x40 | `@"NSString"` | `_voiceID` | 本次会话 UUID（发给服务端做回显校验） |
| 0x48 | `@"NSString"` | `_text` | 上一次 partial 文本（去重） |
| 0x50–0x55 | `B` ×6 | `_started _ready _stopping _inFlight _headerSent _endSent` | 状态位 |
| 0x56 | `B` | `_traditional` | 繁体开关 |
| 0x58 | `Q` | `_queuedBytes` | 已入队未发送字节（≥80001 → fail 109） |
| 0x60 | `Q` | `_pollCount` | 空轮询计数（≥31 → fail 104） |
| 0x68 | `I` | `_sequence` | 音频序号（每发一次非空包 +1） |
| 0x70 | `d` | `_nextRequestAt` | 下一次允许发送的 uptime |
| 0x78 | `d` | `_stoppingAt` | 进入 stopping 的 uptime（>8 s → fail 104） |

### 方法（8 个，全部相对方法列表条目已解析）

| imp | 选择器 | 类型 | 作用 |
|---|---|---|---|
| `0x10018440c` | `initWithQueue:` | `@24@0:8@16` | 建 pcm/packets 容器、随机 voiceID、165 s 看门狗 |
| `0x10018457c` | `fail:` | `v24@0:8q16` | 取消 client，emit `{type:error,code:N}`，`exit(1)` |
| `0x100184764` | `failWithError:` | `v24@0:8@16` | 同上，另带 `domain` / `code` / `message` |
| `0x10018491c` | `command:data:` | `v28@0:8C16@20` | IPC 命令分发（1 启动 / 2 PCM / 3 结束 / 4 资产） |
| `0x100184ef0` | `encodeAvailable` | `v16@0:8` | PCM→opus，16 字节流头 + `[u16le len][frame]`，3000 字节封包 |
| `0x1001850a0` | `addPacket:` | `v24@0:8@16` | 入队 + 累计 `_queuedBytes` |
| `0x100185114` | `pump` | `v16@0:8` | 组包（≤3000 B）→ `sendAudio:`，按 interval 节流 |
| `0x10018553c` | `.cxx_destruct` | `v16@0:8` | ARC 释放 |

## 3 PDWeTypeClient

`@interface PDWeTypeClient : NSObject`  instsize 128，`class_ro` @ `0x100268e28`

### 实例变量

| 偏移 | 编码 | 名称 |
|---|---|---|
| 0x08 | `B` | `_ready` |
| 0x0c | `I` | `_task`（初值 1000） |
| 0x10 | `@"NSObject<OS_dispatch_queue>"` | `_queue` |
| 0x18 | `@"NSURLSession"` | `_session` |
| 0x20 | `@"NSURLSessionWebSocketTask"` | `_socket` |
| 0x28 | `@"NSURL"` | `_identityURL` |
| 0x30 | `@"NSString"` | `_model` |
| 0x38 | `@"NSString"` | `_deviceCode` |
| 0x40 | `@"NSString"` | `_serverPublic` |
| 0x48 | `@"PDWeTypeKeyAgreement"` | `_agreement` |
| 0x50 | `@"NSData"` | `_sessionKey`（ASCII hex，32 B） |
| 0x58 | `Q` | `_uin` |
| 0x60 | `Q` | `_timestamp`（毫秒） |
| 0x68 | `Q` | `_generation`（cancel 时 +1，回调作废） |
| 0x70 | `Q` | `_handshakeRequest`（每次 exchange +1） |
| 0x78 | `@?` | `_pendingHandshake` |

### 方法（13 个）

| imp | 选择器 | 类型 |
|---|---|---|
| `0x1001858f4` | `initWithQueue:identityURL:model:` | `@40@0:8@16@24@32` |
| `0x100185a24` | `headersForBody:task:kind:token:` | `@44@0:8@16I24q28@36` |
| `0x100185fec` | `exchangePath:task:body:headers:completion:` | `v52@0:8@16I24@28@36@?44` |
| `0x100186b4c` | `finishHandshake:error:` | `v32@0:8@16@24` |
| `0x100186bcc` | `prepare:` | `v24@0:8@?16` |
| `0x100187010` | `timestampThen:failure:` | `v32@0:8@?16@?24` |
| `0x100187230` | `publicKeyForNewIdentity:completion:` | `v28@0:8B16@?20` |
| `0x100187820` | `saveIdentityWithError:` | `B24@0:8^@16` |
| `0x100187c78` | `generateUIN:completion:` | `v32@0:8@16@?24` |
| `0x1001880e0` | `sendAudio:voiceID:sequence:end:traditional:completion:` | `v52@0:8@16@24I32B36B40@?44` |
| `0x100188fac` | `cancel` | `v16@0:8` |
| `0x100189054` | `dealloc` | `v16@0:8` |
| `0x1001890c8`+ | 14 组属性 getter/setter + `.cxx_destruct` | — |

### 属性（`__objc_property_list`，attribute 串原样）

```
queue            T@"NSObject<OS_dispatch_queue>",&,N,V_queue
session          T@"NSURLSession",&,N,V_session
socket           T@"NSURLSessionWebSocketTask",&,N,V_socket
identityURL      T@"NSURL",&,N,V_identityURL
model            T@"NSString",C,N,V_model
deviceCode       T@"NSString",C,N,V_deviceCode
serverPublic     T@"NSString",C,N,V_serverPublic
agreement        T@"PDWeTypeKeyAgreement",&,N,V_agreement
sessionKey       T@"NSData",&,N,V_sessionKey
uin              TQ,N,V_uin          timestamp  TQ,N,V_timestamp
task             TI,N,V_task        generation TQ,N,V_generation
handshakeRequest TQ,N,V_handshakeRequest       ready TB,N,V_ready
pendingHandshake T@?,C,N,V_pendingHandshake
```

## 4 PDWeTypeKeyAgreement

`@interface PDWeTypeKeyAgreement : NSObject`  instsize 16

| 项 | 内容 |
|---|---|
| ivar 0x08 | `^{ec_key_st=}` `_key` |
| property | `publicKey` — `T@"NSString",R,C,N` |
| `-init` @ `0x10018a284` | `EC_KEY_new_by_curve_name(0x2c2)` + `EC_KEY_generate_key()`，失败返回 nil |
| `-publicKey` @ `0x10018a2fc` | `EC_POINT_point2oct(group, pub, 4 /*uncompressed*/, buf, 0x21)` → `PDWTHex` |
| `-deriveKey:` @ `0x10018a3c4` | unhex → 33 B / 首字节 0x04 → `EC_POINT_oct2point` → `is_on_curve` → `EC_KEY_set_public_key` → `ECDH_compute_key(secret, 16)` → 16 B 共享密钥的**大写 hex ASCII**（32 B） |
| `-dealloc` @ `0x10018a578` | `EC_KEY_free` |

曲线 NID `0x2c2 = 706`。按 OpenSSL NID 表（704 secp112r1、705 secp112r2、**706 secp128r1**、707 secp128r2…）为 secp128r1；
33 字节 0x04 前缀公钥与 128 bit 素域自洽（1 + 2×16）。`Inferred:` 具体曲线名来自 NID 表映射，公钥长度与格式为 `Observed`。

## 5 PDAssetDownloader

`@interface PDAssetDownloader : NSObject <NSURLSessionDownloadDelegate>`  instsize 72

| 偏移 | 类型 | 名称 |
|---|---|---|
| 0x08 | `B` | `_downloaded` |
| 0x10 | `@"NSString"` | `_root`（= `<bundle>/.asset-state`） |
| 0x18 | `@"NSString"` | `_failure` |
| 0x20 | `@"NSURLSession"` | `_session` |
| 0x28 | `@"NSURLSessionDownloadTask"` | `_task` |
| 0x30 | `@"NSObject<OS_dispatch_semaphore>"` | `_finished` |
| 0x38 | `@?` | `_progress` |
| 0x40 | `q` | `_lastProgress` |

方法：`-URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:`、
`-URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:`、
`-URLSession:downloadTask:didFinishDownloadingToURL:`、`-URLSession:task:didCompleteWithError:`
+ 8 组 accessor。协议列表顺序：NSObject、NSURLSessionDelegate、NSURLSessionTaskDelegate、NSURLSessionDownloadDelegate。

## 6 应用层 C 函数（`__symtab`，全部 section 1 = `__text`）

### 6.1 协议辅助 PDWT\*（`0x100189270`–`0x10018a280`）

| 地址 | 符号 | 重建签名 |
|---|---|---|
| `0x100189270` | `PDWTBlob` | `NSMutableData *(uint32_t tag, NSData *data)` |
| `0x100189374` | `PDWTString` | `NSMutableData *(uint32_t tag, NSString *s)` |
| `0x1001893c0` | `PDWTInteger` | `NSMutableData *(uint32_t tag, uint64_t v)` |
| `0x10018949c` | `PDWTFields` | `NSDictionary *(NSData *protobuf)` |
| `0x1001897f8` | `PDWTData` | `NSData *(NSDictionary *fields, uint32_t tag)` |
| `0x1001898a0` | `PDWTNumber` | `uint64_t (NSDictionary *fields, uint32_t tag)` |
| `0x100189954` | `PDWTHex` | `NSString *(NSData *)`（大写） |
| `0x100189a54` | `PDWTUnhex` | `NSData *(NSString *)`（偶数长、≤0x800、0-9A-Fa-f） |
| `0x100189b98` | `PDWTMD5` | `NSString *(NSData *)`（`CC_MD5` → 大写 hex） |
| `0x100189c54` | `PDWTSHA256` | `NSString *(NSString *)`（UTF-8 → `CC_SHA256` → 大写 hex） |
| `0x100189d10` | `PDWTCrypt` | `NSData *(NSData *in, NSData *key32, CCOperation)`（AES-256-ECB-PKCS7） |
| `0x100189e74` | `PDWTSnappyDecode` | `NSData *(NSData *block)`（raw snappy block，≤1 MiB） |
| `0x10018a0f8` | `PDWTNewDeviceCode` | `NSString *(NSString *seed)` |

### 6.2 资产子系统（`0x1001810b0`–`0x10018440c`）

| 地址 | 符号 |
|---|---|
| `0x1001810b0` | `PDDownloadAssetArchive(NSString *stateDir, NSURL *url, void (^progress)(NSInteger))` |
| `0x1001812e8` | `PDRunAssetRequestWithProgress(NSDictionary *request, void (^report)(NSDictionary *))` |
| `0x100183cfc` | `PDAssetSpecification(NSString *bundleRoot)` |
| `0x100183e4c` | `PDAssetStatePath(NSString *bundleRoot)` |
| `0x100183e58` | `PDAssetImportDirectory(void)` |
| `0x100183e64` | `PDAssetImportPath(NSString *token)` |
| `0x100183f0c` | `PDAssetSafeRelativePath(NSString *rel)` |
| `0x100184120` | `PDAssetRegularPath(NSString *root, NSString *rel, BOOL wantDir)` |
| `0x10018426c` | `PDAssetDownloadURL(NSString *s)` |

逐函数伪代码、阶段机与磁盘布局见 `out/notes/asset.md`（835 行，子代理产出，含 7 条 `Assumed`）。

## 7 匿名函数（块 invoke，不在符号表内）

| 地址 | 归属 | 作用 |
|---|---|---|
| `0x10018456c` | `initWithQueue:` | 看门狗 handler：`exit(1)` |
| `0x100184618` | 全局 | `PDVoiceEmit`：JSON → `[u32be len][0x00][json]` 写 fd 1 |
| `0x100184cb0` | `command:data:` cmd 1 | `prepare:` 完成回调：建 opus 编码器、起 100 ms 定时器、emit ready |
| `0x100184e8c` | 同上 | 100 ms 定时器 handler：stopping 超 8 s → fail 104，否则 `pump` |
| `0x1001852f4` | `pump` | `sendAudio:` 完成回调：final/partial 事件、interval 节流、递归 pump |
| `0x10018575c` | `main` | stdin 帧解析 handler |
| `0x100186610` / `0x1001867b0` / `0x10018688c` / `0x100186a80` | `exchangePath:` | ws 发送回调 / 收包派发 / 收包解析 / 10 s 超时 |
| `0x100186fd8` | `prepare:` | `timestampThen` 成功后 → `publicKeyForNewIdentity:(uin==0)` |
| `0x1001870e4` | `timestampThen:` | 解析 `/timestamp` 响应 |
| `0x100187540` | `publicKeyForNewIdentity:` | 解析 `/oauth_pubkey_v2` 响应 |
| `0x100187f00` | `generateUIN:` | 解析 `/gen_uin_v2` 响应 |
| `0x100188760` / `0x100188880` | `sendAudio:` | HTTP 响应处理（MD5 校验、解密、snappy、文本抽取） |
| `0x100263650` / `0x100263740` / `0x100263780` / `0x1002637a0` | `__const` 全局块 | 看门狗 / 父进程退出 / dispatch_io 清理 / dispatch_io 描述符 |

## 8 协议（4 个）

| 协议 | 委托方法 |
|---|---|
| `NSObject` | 19 条（继承用） |
| `NSURLSessionDelegate` | 无（空协议列表） |
| `NSURLSessionTaskDelegate` | 无 |
| `NSURLSessionDownloadDelegate` | `-URLSession:downloadTask:didFinishDownloadingToURL:` |

## 9 与源码包的关系（README 提示的 PDVoiceServiceConnection.m）

helper 侧只负责「stdin 帧 → opus/wss → stdout JSON 事件」。宿主侧 IPC 客户端的唯一协议就是
`[u32be totalLength][u8 command][payload]`（见 `docs/02-wire-protocol.md` §1），因此
`PDVoiceServiceConnection.m` 可以用这个帧格式对上，不需要其它头文件。
