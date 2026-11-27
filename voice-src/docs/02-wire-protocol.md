# petdfy-voice · 线路协议（wss / HTTPS / opus / IPC）

> 全部字段号、header 名、常量从 `__cstring` / `__cfstring` / `__const` 与
> `PDWT*` 编码函数的调用点逆向得出；`tools/proto_ref.py` 是同一套逻辑的 Python
> 镜像，跑通 9 组自检（varint 边界、字段树、ws 帧、header 签名顺序、device code、
> snappy literal+copy）。地址均为 arm64 切片。

## 1 宿主 ↔ helper IPC（stdin / stdout）

```
宿主 → helper (stdin) :  [u32 BE totalLength][u8 command][payload]
                         totalLength = 1 + len(payload)
```
payload 长度必须落在 **1..0x10000**：`length == 0` 或 `> 0x10000` 时 helper `exit(2)`
（`0x10018580c`：`add w8,w23,#-0x10001` / `cmp w8,#-0x10001` / `b.ls`，等价于
`(uint32_t)(length-1) > 0xFFFF`）。**不是**固定 64 KiB 帧——`0x10000` 只是上限。

```
helper → 宿主 (stdout):  [u32 BE totalLength][u8 0x00][JSON]
```
缓冲上限 0x20000（128 KiB），超了同样 `exit(2)`。

| command | payload | 行为 |
|---|---|---|
| 0x01 | JSON `{"model": <str ≤64>, "traditional": <bool>}` | `prepare:` → 建 opus → emit `{"type":"ready"}` |
| 0x02 | PCM16 LE，偶数长、`< 6401` 字节 | 追加到 PCM 缓冲并编码 |
| 0x03 | 空 | 结束：截断残余 PCM 到 640 B → 编码 → `pump` |
| 0x04 | 资产请求 JSON | `PDRunAssetRequestWithProgress` → `exit` |

事件（stdout，`PDVoiceEmit` @ `0x100184618`）：

| type | 其它字段 |
|---|---|
| `ready` | — |
| `partial` | `text` |
| `final` | `text` |
| `error` | `code`（`fail:`）/ `domain` `code` `message`（`failWithError:`） |
| `asset-progress` | `status` `progress`（资产阶段回报，原样转发） |

命令 4 的判定：`exit(![result[@"type"] isEqual:@"asset-result"])`（`0x1001849c4`）。

## 2 常量

| 名称 | 值 | 出处 |
|---|---|---|
| host | `wetype.weixin.qq.com` | `0x1002643a0` |
| ws URL | `wss://%@/` | `0x100264820` |
| ws 子协议 | `wxws_pb` | `0x100264cf8` |
| HTTP base | `https://%@/api_v2` | `0x100264940` |
| 路径 | `/timestamp`、`/oauth_pubkey_v2`、`/gen_uin_v2` | `0x100264860`、`0x1002648a0`、`0x100264920` |
| task 号 | `/timestamp` = 0x7FFFFFFF、oauth = 0x7FFFFFFE、gen_uin = 0x7FFFFFFD | 调用点立即数 |
| AES key（oauth 请求体） | `V0J7L5C2C1N7G9B8S4K8W8H5U5H0J5K0`（32 B ASCII） | `0x100264360` |
| 签名盐 | `wC4bY5nV2kE0xK0r` | `0x100264380` |
| 身份文件 | `/var/mobile/Library/Application Support/PetDFY/voice-identity.plist` | `0x1002642c0` |
| 错误域 | `PetDFY.VoiceProtocol` | `0x100264980` |

## 3 Kb-\* 请求头

固定 12 条（`headersForBody:task:kind:token:` @ `0x100185a24`）：

| 头 | 值 |
|---|---|
| `Kb-OsType` | `2` |
| `Kb-Version` | `4.0.0.749` |
| `Kb-SystemVersion` | `16.1.2` |
| `Kb-PackageType` | `3` |
| `Kb-Scene` | `1` |
| `Use_DebugNet` | `0` |
| `Kb-CompressionType` | `1` |
| `Kb-TimeStamp` | `%llu` ← `/timestamp` 返回值 |
| `Kb-BodyMd5` | `MD5(body)` 大写 hex |
| `Kb-TraceId` | UUID 去 `-` 转小写 |
| `Kb-TaskId` | `DEC(task)` |
| `Content-Type` | `application/octet-stream` |

按 `kind` 追加：

| kind | 追加头 | 签名串顺序 |
|---|---|---|
| 0（timestamp） | `Kb-Uin` | OsType, Version, Scene, TimeStamp, BodyMd5, TraceId, TaskId |
| 1（gen_uin） | `Kb-GenUinToken` | OsType, Version, Scene, TimeStamp, BodyMd5, GenUinToken, TraceId, TaskId |
| 2（data） | `Kb-CmdId=4547`、`Kb-SubCmdId=0`、`Kb-Uin`、`Kb-SharedKeySuffix`=sessionKey 末 4 字符 | OsType, Version, Scene, CmdId, SubCmdId, TimeStamp, BodyMd5, Uin, TraceId, TaskId |

```
Kb-Sign = SHA256( concat(上述顺序的 header 值) + "wC4bY5nV2kE0xK0r" )   大写 hex
```
顺序表来自 4 个常量数组：`[OsType,Version,Scene]`、`[CmdId,SubCmdId]`、`[TimeStamp,BodyMd5]`、`[TraceId,TaskId]`
（`0x100264c98/cc8/cb0/ce0`），kind1 另外 insert `Kb-GenUinToken`，kind2 另外 insert `Kb-Uin`。

## 4 WebSocket 交换（`exchangePath:` @ `0x100185fec`）

一条消息 = 两个 protobuf 层：

```
message {                     // → ws binary frame
  1: varint 0
  2: varint 0
  3: varint task
  5: bytes frame {
       1: string "POST"
       3: string path                 // "/timestamp" 等
       4: string ""
       5: bytes headerPair*  { 1: name, 2: value }   // 含 HOST / Content-Type / Content-Length + Kb-*
       6: bytes body                  // 加密后的请求体（/timestamp 为空）
     }
}
```

响应：

```
message {
  2: varint task          // 必须与请求一致，否则 error 11
  4: bytes payload        // 再解一层 protobuf，交给 finishHandshake:
}
```

- 已有 pending 握手时再次 `exchangePath:` → 立即 error 10。
- 发送失败 → error 11（原样把 NSError 传出）；10 s 未回 → error 12（`dispatch_after` 0x2540BE400 ns）。
- 收包与发送回调都在 `_queue` 上串行，且用 `_generation` + `_handshakeRequest` 双重作废检查。
- 握手完成后 `socket cancelWithCloseCode:1000`，`socket = nil`；音频走 HTTPS，不再用 ws。

## 5 /timestamp（task 0x7FFFFFFF）

请求体：空。响应 `payload`：
```
1: bytes ts { 1: varint milliseconds }
2: varint status        // 必须 200
```
`_timestamp = ts`；否则 error 14。

## 6 /oauth_pubkey_v2（task 0x7FFFFFFE，kind 2）

明文请求（AES-256-ECB-PKCS7，key = appId）：

| 字段 | 值 |
|---|---|
| 1 | 本端 ECDH 公钥（大写 hex，33 B） |
| 2 | 已存的 `serverPublic`（首次为空串） |
| 3 | varint `newIdentity`（1 新身份 / 0 复用） |
| 4 | `deviceCode`（64 字符） |
| 5 | varint `uin`（`newIdentity == 0` 时） |
| 6 | 空串（`newIdentity == 1` 时） |
| 7 | 空串 |
| 8 | `model` |
| 9 | `"PetDFY"` |

响应：`payload[5]` → AES 解密（key = `sessionKey`）→

| 字段 | 含义 |
|---|---|
| 1 | varint 结果码，必须存在且 == 0 |
| 2 | 服务端公钥（大写 hex，33 B） |
| 4 | `gen_uin` 用的 token（仅新身份） |

判定顺序：`outer[2] == 200` → `decoded[1]` 存在 → `== 0` → `deriveKey(decoded[2])`；
任何一步失败分别是 error 16 / 17。成功后 `sessionKey`、`serverPublic` 落地。

- 新身份：继续 `generateUIN:`；
- 旧身份：`saveIdentityWithError:` → `ready = YES` → 关 ws → 完成。

## 7 /gen_uin_v2（task 0x7FFFFFFD，kind 1，token = 上一步的字段 4）

明文请求（AES，key = `sessionKey`）：

| 字段 | 值 |
|---|---|
| 1 | `deviceCode` |
| 2 | `serverPublic` |
| 4 | trace = `UUID + "%.0f"%(epoch*1000)` |
| 5 | 空串 |

响应解密后：字段 1 == 0、字段 2 != 0 → `_uin = 字段 2`；然后重跑 `/timestamp` 再跑一次
`/oauth_pubkey_v2`（`newIdentity = 0`）完成落盘。失败 error 19 / 20。

## 8 音频请求（`sendAudio:...` @ `0x1001880e0`，HTTPS POST）

前置：`ready`、`voiceID` 非空、`audio.length < 3501`，否则 error 21。

明文消息：

| 字段 | 值 | 说明 |
|---|---|---|
| 2 | `voiceID` | 服务端原样回显，用于校验 |
| 3 | 0 | |
| 4 | audio bytes | 16 B 流头 + `[u16le len][opus frame]`* |
| 5 | 5 | 编码标识（常量） |
| 6 | varint `end` | 是否末包 |
| 7 | varint `sequence` | 非空包才 +1 |
| 8 | 空 bytes | |
| 9 | varint `traditional` | |
| 11 | varint audio.length | |
| 14 / 15 | 0 / 0 | |
| 16 | 空串 | |
| 17 / 19 | 0 / 0 | |

外层 `PDWTBlob(1, message)` 再用 `sessionKey` AES 加密 → POST `https://wetype.weixin.qq.com/api_v2`，
`_task` 取当前值后 +1，headers = `headersForBody:task:kind:2`。

响应处理（`0x100188880`）：

1. 必须是 `NSHTTPURLResponse`；`statusCode == 200`；`0 < data.length ≤ 1 MiB` → 否则 error 23。
2. 若带 `Kb-BodyMd5`：必须等于 `MD5(data)` 大写 → 否则 error 24。
3. `Kb-CompressionType`：`1` → 原样；`2` → snappy 解压；其它 → nil → error 25。
4. 字段树：`outer = PDWTFields(plain)`；`l2 = PDWTFields(outer[1])`；`st = PDWTFields(l2[1])`。
   `st[1]` 必须存在且 == 0，否则 error 25。
5. `l2[2]`（回显 voiceID）非空且不等于请求 voiceID → error 26。
6. 文本：`l2[15]`（partial）> `l2[13]` > `l2[4]`（取第一个非空）。
7. 结果字典：
   ```
   text          = 上面选出的文本
   final         = (st[5] == 1)
   interval      = st[6]        ← 毫秒，worker 用它算下一次允许发送时间（clamp 0.1–1.0 s）
   maxPacketSize = st[7]
   ```

## 9 opus 编码参数（`0x100184cb0`）

```
opus_encoder_create(16000, 1, OPUS_APPLICATION_AUDIO /*0x801*/, &err)
OPUS_SET_BITRATE(64000)      // 4002, 0xFA00
OPUS_SET_COMPLEXITY(5)       // 4010
OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE)  // 4024, 3001
opus_encode(enc, pcm+off, 320 /*20 ms*/, out, 1500)
```

流头（只发一次，16 B）：`"#!OPUS_RAW_V1" 02 01 00`（`0x1001c9d08`）。
每帧前缀 2 B 小端长度；待发块累计 ≥ 3000 B 就 flush 成一个请求（`pump` 里同样 ≤3000 B 组包）。
`_queuedBytes ≥ 80001` → error 109。

## 10 deviceCode（`0x10018a0f8`）

```
"IOS" + (seed 不足 17 字节时用 't' 补齐到 17) + seed[:17] + 12 个随机小写字母
        ↑ 共 32 字符
+ MD5( 上面 32 字节 + "wC4bY5nV2kE0xK0r" ) 的大写 hex（32 字符）
= 64 字符
```

## 11 错误码

| code | 位置 | 含义 |
|---|---|---|
| 10 | `exchangePath:` | 上一次握手未结束 |
| 11 | `exchangePath:` | 响应无法解析 / task 不匹配 |
| 12 | `exchangePath:` | 10 s 未回包 |
| 13 | `prepare:` | deviceCode / 公钥缺失 |
| 14 | `timestampThen:` | `/timestamp` 状态非 200 或无时间戳 |
| 15 | `publicKeyForNewIdentity:` | oauth 请求体加密失败 |
| 16 | 同上 | oauth 状态/结果码异常 |
| 17 | 同上 | `deriveKey:` 失败 |
| 18 | `saveIdentityWithError:` | **域是 `PetDFY.VoiceStorage`**（不是 VoiceProtocol），`stage` = `identity-directory` / `identity-write`，`NSUnderlyingErrorKey` 带底层错误 |
| 19 | `generateUIN:` | token 为空 |
| 20 | 同上 | gen_uin 状态/uin 异常 |
| 21 | `sendAudio:` | 未 ready / voiceID 空 / audio ≥ 3501 |
| 22 | 同上 | 音频体加密失败 |
| 23 | 同上 | HTTP 状态或长度非法 |
| 24 | 同上 | `Kb-BodyMd5` 不匹配 |
| 25 | 同上 | 解密/解压/状态字段非法 |
| 26 | 同上 | 回显 voiceID 不匹配 |
| 100 | worker | 已启动（重复 start / start 后收到资产命令） |
| 101 | worker | start 的 JSON / model 非法 |
| 103 | worker | opus 编码器创建失败 |
| 104 | worker | 结束超时（8 s）/ 空轮询 31 次 / 看门狗 |
| 105 | worker | 未 ready 就送 PCM/结束 |
| 106 | worker | PCM 非法（奇数长 / ≥6401）或不带空 payload 的结束 |
| 107 | worker | 未知命令 |
| 108 | worker | `opus_encode` 返回负值 |
| 109 | worker | 待发包 ≥ 80001 字节 |
| 110 | worker | 收到 final 但未发送过 end 标记 |


## 12 第二轮审计补充（逐条附地址）

### 12.1 身份文件还设置文件保护类

`saveIdentityWithError:` 在 `chmod 0600` 之后还调用
`-[NSFileManager setAttributes:ofItemAtPath:error:]`：
`@{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication }`
（GOT `0x100200030` / `0x100200028`，`0x100187a50`–`0x100187ad8`）。
目录属性用 `NSFilePosixPermissions = @0700`（`0x100200020` + intobj `@448`）。

### 12.2 两个封包阈值不对称

| 位置 | 判据 | 行为 |
|---|---|---|
| `encodeAvailable` `0x100184fa0` | `out.length + frameLen >= 2999`（0xbb7） | flush |
| `pump` `0x1001851a4` | `body.length + next > 3000`（0xbb8） | 停止组包（即允许正好 3000） |

即单次编码出的块上限 2999，而 HTTP 请求体可以堆到 3000。

### 12.3 IPC 命令 4 的退出码（第三轮修正）

`PDVoiceWorker command:data:` 资产分支：

```
result = PDRunAssetRequestWithProgress(request, ^(NSDictionary *p){ emit(p); });
PDVoiceEmit(result);                                   // 0x1001849c4
exit(![result[@"type"] isEqual:@"asset-result"]);       // 0x1001849dc
```

`"asset-result"` 由 **常量字典** 提供（`__objc_arraydata` 里的
`0x100264b38/b40/b48/b50` 等），不在代码里出现，所以按「代码操作数」扫 xref 会漏掉：

| 常量字典 | 内容 |
|---|---|
| `0x100264d10` / `0x100264d38` / `0x100264d60` / `0x100264d88` | `@{ ready: @YES, type: "asset-result" }`（`__kCFBooleanTrue` = import #19） |
| `0x100264dd8` | `@{ "type": "ready" }`（`__NSConstantDictionary`，emit ready 用） |
| 另一组 ready=@NO 的同形字典 | `@{ ready: @NO, type: "asset-result" }`（`__kCFBooleanFalse` = import #221） |

结论：命令 4 的退出码 = **“没有错误”**（成功与“未就绪”都 exit 0，只有
`type == "error"` 才 exit 1），不是我上一轮写的“恒 exit 1”。

### 12.4 无引用字符串

`"__cdcd__"`（`0x1001f60e0`，`__cstring` 里应用层最后一条）在应用代码中**零引用**，
deviceCode 只用 `"wC4bY5nV2kE0xK0r"` 做盐。`"r+b"` / `".z%02d"` / `"1.2.11"` / `"%x_%llx"`
（`0x1001f60c3`–`0x1001f60d8`）同样零引用，属于静态链入库（zlib 等）的残留常量。

### 12.5 常量数组全表（11 条）

| 地址 | 内容 | 用途 |
|---|---|---|
| `0x100264c08` | check, install, prepare, import, remove | operation 白名单 |
| `0x100264c20` | originals, live, licenses | manifest 顶层目录白名单 |
| `0x100264c38` | prepare, import, remove | **加锁重试子集**（40×50 ms；其余 0 次） |
| `0x100264c50` | originals, live | 可见资产根 |
| `0x100264c68` | ready.json, imported.json, download.zip, unpacking | 保留/清理名单 |
| `0x100264c80` | http, https | URL scheme 白名单 |
| `0x100264c98/cb0/cc8/ce0` | Kb-* 签名顺序 | 见 §3 |
| `0x100264cf8` | wxws_pb | ws 子协议 |

### 12.6 资产下载器的真实配置

`PDDownloadAssetArchive`（`0x1001810b0`）用的是
`downloadTaskWithRequest:` + `@[Accept-Encoding: identity]`，会话配置：
`URLCache=nil`、`requestCachePolicy=1`、`request=45 s`、`resource=600 s`、
`HTTPShouldSetCookies=NO`、cookie/credential storage 置空，delegateQueue 是
`NSOperationQueue`（`maxConcurrentOperationCount=1`）。重定向处理器会重新过
`PDAssetDownloadURL` 并拒绝 `https -> http` 降级；进度回调按 10% 台阶节流、封顶 99，
成功搬到 `<bundle>/.asset-state/download.zip` 并 `setAttributes 0600` 后回调 100。
