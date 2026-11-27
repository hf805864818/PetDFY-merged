# 证据台账（Observed / Inferred / Assumed / NOT RUN）

## 输入与身份

| 项 | 值 | 状态 |
|---|---|---|
| 附件 SHA-256 | `BC44BC53E0BFECCCB694BBFD564CC264198042FFD57018BD95A51BBCF4A9BE51` | Observed |
| `petdfy-voice` SHA-256 | `B11CB7038A9353033CCB969D640026B4C4632B0DF1D010ED18E795CB30375C83` | Observed |
| `PetDFYPrefs` SHA-256 | `2D6E25F08DEE51844F5A3562042CEEDB6EEBAEB320AF64C9666DAF15B094763B` | Observed |
| fat 切片 | arm64 `bddc4c20…af9fde`、arm64e `f082ee4e…d1e2cf`，均 `minos 16.0 / sdk 16.4` | Observed |
| 未签名 | 无 LC_CODE_SIGNATURE；README 要求 `ldid -S` | Observed（README + 段表） |

## 静态分析手段（可复现）

| 手段 | 位置 | 说明 |
|---|---|---|
| Mach-O 解析 | `tools/macho.py` | fat/薄片、load command、段表、`va2off` |
| chained fixups 指针解码 | `tools/an.py` `Bin.slot()` | `DYLD_CHAINED_PTR_64_OFFSET`(fmt 6, arm64) / ARM64E(fmt 12)；bind 走 imports 表 |
| stub / selref 解析 | `tools/an.py` `parse_stubs()` | `__stubs`、`__objc_stubs` → GOT → 符号名（`_CCCrypt`、`sel:xxx`） |
| ObjC 元数据 | `tools/objc.py` | classlist → class_ro（+0x18 name / +0x20 methods / +0x30 ivars / +0x40 props）、relative method list（entsize 0x8000000c，name 经 selref 再解引用） |
| CFString / NSArray / NSNumber 常量 | `tools/cfs_all.py`、`arr.py`、`intobj.py` | `__cfstring`、`__objc_arrayobj`、`__objc_intobj` |
| 反汇编 | `tools/dump_app.py`（capstone 5.0） | 104 个函数 / 10,062 条，`adrp+add/ldr` 自动注字符串、`bl` 自动注符号 |
| 线路格式镜像 | `tools/proto_ref.py` | 9 组自检全绿 |

## 关键结论的等级

| 结论 | 等级 | 依据 |
|---|---|---|
| 4 个类、8/13/4/4 个方法、ivar 偏移 | Observed | class_ro + relative method list + `__objc_ivar` + getter 汇编 |
| IPC 帧 `[u32be len][u8 cmd][payload]`，len 必为 0x10000 | Observed | `main` 0x100185804–0x1001858bc |
| 输出帧 `[u32be len][0x00][JSON]`，写入循环处理 EINTR | Observed | `0x100184618`–0x10018475c |
| opus 参数（16k/单声道/AUDIO/64000/5/VOICE/320 采样/1500 上限） | Observed | 0x100184ce0–0x100184d6c、0x100184f6c–0x100184f88 |
| 16 B 流头 `#!OPUS_RAW_V1\x02\x01\x00` | Observed | `0x1001c9d08` 原始字节 |
| 包格式 `[u16le len][frame]`，3000 B 封包，80001 上限 | Observed | `0x100184fa0`、`0x100185038` |
| Kb-\* 头 12 条 + kind 追加 + 签名顺序 + 盐 | Observed | `0x100185a24`–`0x100185f30`，4 个常量数组 + CFString |
| `/timestamp`、`/oauth_pubkey_v2`、`/gen_uin_v2` 字段表 | Observed | 三处构造点 + 三处解析点 |
| AES-256-ECB-PKCS7，key = appId / sessionKey | Observed | `PDWTCrypt` + 调用点 `w2=3` 选项位 |
| sessionKey = 16 B ECDH 共享密钥的大写 hex（32 B） | Observed | `0x10018a530`–`0x10018a56c` |
| ECDH 曲线 = secp128r1 | Inferred | `EC_KEY_new_by_curve_name(706)` + 33 B/0x04 公钥；NID 表映射 |
| deviceCode 结构（IOS + 't' 补齐 + 12 随机 + MD5 尾） | Observed | `0x10018a0f8` 全函数 |
| 错误码 10–26 / 100–110 的归属 | Observed | 每个 `errorWithDomain:code:` 与 `fail:` 立即数 |
| `emit({type:"ready"})` 的 key | Assumed | 全局常量字典 `0x100264dd8` 只解出值 `ready`，键被链式修复指针的 bind 掩盖 |
| 结束命令把残余 PCM 截断到 640 B | Observed | `0x100184c8c`（`setLength:0x280`），语义上是截断，原样保留 |
| 资产子系统阶段机 / 状态文件 / 路径闸门 | Observed | 见 `out/notes/asset.md`（含逐函数地址） |
| 资产 manifest 逐项登记细节 | Assumed | 归纳段，子代理在 asset.md §7 列了 7 条 |

## 未做 / 无法做

| 项 | 原因 |
|---|---|
| `make` 编译 | 本机 Windows 无 clang / iPhoneOS SDK → **NOT RUN** |
| 真机联调（wss 握手、语音识别回包） | 需真实 deviceCode 与服务端；静态分析不产生运行观测 → **NOT RUN** |
| opus / OpenSSL / miniz 源码级重建 | 第三方库，原二进制静态链入；本工程改为链接同版本 |
| `PetDFYPrefs`（14 个 PD UI 类）重建 | 另一个 dylib（`MH_DYLIB`，image base 0），本任务范围外 → 未做 |
| arm64e 切片逐方法对拍 | 结构与字符串一致，未逐指令对拍 → 未做 |

## 复核命令

```powershell
# 结构
python tools\macho.py extract\petdfy-voice
# 类/方法清单
python tools\objc.py extract\slices\petdfy-voice_arm64 arm64
# 任意函数反汇编（带字符串/符号注释）
python tools\disas.py extract\slices\petdfy-voice_arm64 arm64 name _PDWeTypeClient_sendAudio_...
# 线路格式自检
python tools\proto_ref.py
# 源码静态自检（括号平衡、占位符、声明/定义）
python tools\src_check.py
```

## 第二轮审计（同一目标的复检）

方法：修好反汇编器的 `adrp` 注解（原先 `int('#0x…')` 抛错导致 CF 串全部没标注），
再加一个**逐操作数 xref 扫描器**（`tools/xref.py`，寄存器被写即失效 page 表），
用「字符串 × 引用函数」矩阵反查有没有漏读的代码路径。

### 本轮新发现 / 已修

| # | 发现 | 等级 | 处理 |
|---|---|---|---|
| 1 | `saveIdentityWithError:` 的错误域是 **`PetDFY.VoiceStorage`**（code 18），`stage` = `identity-directory` / `identity-write`，带 `NSUnderlyingErrorKey` | Observed | 源码新增 `PDVoiceStorageError()`，错误码表补 18 |
| 2 | 写完 plist 还 `setAttributes:{NSFileProtectionKey: …CompleteUntilFirstUserAuthentication}` | Observed | 源码补齐 |
| 3 | `encodeAvailable` 封包阈值是 **2999**（0xbb7），不是 3000；`pump` 才是 3000 含等号 | Observed | 常量与注释修正 |
| 4 | 命令 4 会先 `emit(result)` 再 `exit(![result[@"type"] isEqual:@"asset-result"])`；而 `"asset-result"` 全二进制无构造点 → 恒 exit 1 | Observed | 源码照抄并注释（疑似 build 遗留缺陷） |
| 5 | 资产下载用 `downloadTaskWithRequest:` + `Accept-Encoding: identity`，`NSOperationQueue(maxConcurrent=1)`、`requestCachePolicy=1`、45/600 s、`HTTPShouldSetCookies=NO`；重定向要重过 URL 校验并禁 `https→http`；进度按 10% 台阶节流、成功回调 100 | Observed | 下载器整段重写 |
| 6 | 加锁重试只对 `{prepare,import,remove}` 生效（40 次 × 50 ms），`check/install` 0 次等待 | Observed | 锁逻辑修正 |
| 7 | `"__cdcd__"`、`"r+b"`、`".z%02d"`、`"1.2.11"`、`"%x_%llx"` 在应用代码中零引用 | Observed | 记录为死串/三方库残留 |
| 8 | 11 条常量数组全部解出（新增 `@[prepare,import,remove]` 与 `@[originals,live]`） | Observed | 写入协议文档 §12.5 |

### 本轮确认没漏

| 检查 | 结论 |
|---|---|
| selref（208 条）− 方法表/属性名（167） = 136 条遗留 | 全是 Foundation 选择器（`dataUsingEncoding:` 等），**没有**未登记的本类方法 |
| `__objc_catlist` | 空（0 个 category），方法表即全集 |
| 5 条无直接 xref 的 CFString | `prepare`/`originals`/`live`/`http` 是数组常量元素，`wxws_pb` 由 `@[@"wxws_pb"]` 引用 → 均已解释 |
| 127 条 CFString + 11 条数组 + 5 条 NSNumber 常量 | 全部有归属 |

### 仍然开着的（未逐条落地）

| 项 | 现状 |
|---|---|
| `PDRunAssetRequestWithProgress` 的 3 个分支族：`@[originals,live]` 舞台化安装、`@[ready.json,…]` 清理名单、manifest 逐项登记 | 行为级等价，未逐条对拍（2693 条指令） |
| `emit({type:"ready"})` 的 key | 全局字典 `0x100264dd8` 只解出值 `ready` → `Assumed` |
| 编译 / 真机 | NOT RUN（无 clang；需真实 deviceCode） |
| arm64e 切片 | 未逐条对拍 |

## 第三轮审计（方法论修正 + 2 处真实遗漏）

上一轮的字符串 xref 只扫**代码操作数**（`adrp+add/ldr`），这漏掉一整类引用：**常量容器**
（`__objc_arraydata` / `__objc_dictobj` 只被数据段指到，代码里看不到）。
这轮补了三条扫描：类引用（classref → 函数）、常量容器解码、数据段里的函数指针表。

### 修正的错误结论

| # | 上轮结论 | 实际 | 证据 |
|---|---|---|---|
| 1 | 命令 4 恒 `exit 1`（`asset-result` 无构造点） | 错。`asset-result` 来自常量字典 `0x100264d10/d38/d60/d88`；成功/未就绪都 `exit 0`，只有 `type == "error"` 才 `exit 1` | `__objc_arraydata` `0x100264b38`–`b50`；`__kCFBooleanTrue` = import 19、`__kCFBooleanFalse` = import 221 |
| 2 | `"__cdcd__"` / `"r+b"` / `"wb"` 等「应用代码零引用」 | 应用层零引用成立，但 `'wb'`/`'r+b'` 被 **0x10018be60**（应用区间之外的三方/工具函数）引用 | gap 扫描 `0x10018a700`–`0x10018c1ac` 命中 2 处 |
| 3 | `emit({type:"ready"})` 的 key 只能 `Assumed` | 解除：常量字典 `0x100264dd8` = `{ "type": "ready" }`（keys `0x100264ba8`, values `0x100264bb0`） | `__objc_arraydata` 解码 |

### 新增遗漏（已修）

| # | 发现 | 证据 | 处理 |
|---|---|---|---|
| 4 | `PDAssetImportPath(token)` 会先 `[[NSUUID alloc] initWithUUIDString:token]` 校验，非法 token 返回 **nil**；然后用 `stringByAppendingPathExtension:@"zip"` 拼 `AssetImports/<uuid>.zip` | `0x100183e64`–`0x100183ef0` | 源码补 UUID 校验 + nil 分支 |
| 5 | 资产结果字典统一为 `{ ready: <bool>, type: "asset-result" }`（不是只有 `ready`） | 常量字典 ×4 | 新增 `PDAssetResult()`，4 处返回点改用它 |

### 本轮的反向确认

| 检查 | 结论 |
|---|---|
| 应用区间之前的代码（`0x10017a000`–`0x1001809c8`）引用应用字符串 | 0 条 → 边界正确，没有漏掉的“第 105 个函数” |
| 数据段里指向应用代码的指针（`__DATA_CONST,__const`） | 21 个去重目标，全是 block 的 copy/dispose/weak 辅助与已知 handler（`0x10018456c` exit(1)、`0x100184ca8` emit 跳板、`0x100185748` exit(0)…），没有未知函数 |
| 类引用逐函数归属 | 27 个 Foundation 类的使用点全部落到已分析函数；`NSMutableSet`/`NSArray` 的额外使用点都在资产的 2693 条主干里 |
| 11 条常量数组 + 常量字典 + 5 个 NSNumber | 全部解码并有归属 |

### 仍然开着的

| 项 | 现状 |
|---|---|
| 资产主干 3 个分支族（舞台化安装 / 清理名单 / manifest 逐项登记） | 行为级等价，未逐条对拍 |
| 编译 / 真机 | NOT RUN |
| arm64e 切片 | 未逐条对拍 |

## 第四轮审计（立即数对拍 → 又抓到 4 处）

这轮换了手段：把每个应用函数的**语义立即数**（`mov/movz/movk/cmp` 里的常量）抽出来，
逐个到重建源码里找；找不到的就是「我漏掉的常量」。工具 `tools/immaudit.py`。

### 新发现（已修）

| # | 发现 | 地址 | 处理 |
|---|---|---|---|
| 1 | 命令 2 的上界是 `length >= 0x1901` 才报错（即最大 **6400** 字节）；我写成 `>= 0x1900`，等于把 6400 也拒了 | `0x100184a58` `mov w8,#0x1901` | 常量改 `0x1901` |
| 2 | 锁文件用 `open(lock, 0x302, 0600)`：`0x302 = O_RDWR\|O_CREAT\|O_NOFOLLOW`，我漏了 `O_NOFOLLOW` | `0x1001816d4` | 加 `O_NOFOLLOW` |
| 3 | 解包是**逐条目**处理的：`mz_zip_attrib_is_symlink()` 命中即失败；`external_attr & 0xF000` 必须是 `S_IFDIR(0x4000)` 或 `S_IFREG(0x8000)`；目录 `mkdir(path,0755)` 且 `EEXIST` 容错后用 `PDAssetRegularPath(...,YES)` 复核；文件 `open(path, 0xb01=O_WRONLY\|O_CREAT\|O_EXCL\|O_NOFOLLOW, 0600)` + `mz_zip_reader_entry_read()` 每次 `0x10000` 字节 | `0x100182fb4`–`0x100183138`、`0x100183754` | `PDUnpackArchive` 整段重写（原来是 `extract_to_file`，没有类型/链接闸门） |
| 4 | `PDAssetDownloader.root` / `.failure` 的属性是 `C`（copy），我写成 `strong` | 属性表 `T@"NSString",C,N,V_root/V_failure` | 改 `copy` |

### 常数含义表（本轮解出的“神秘常量”）

| 常量 | 含义 |
|---|---|
| `0x302` | `O_RDWR\|O_CREAT\|O_NOFOLLOW`（锁文件） |
| `0xb01` | `O_WRONLY\|O_CREAT\|O_EXCL\|O_NOFOLLOW`（解包写文件） |
| `0x1ed` | `0755`（`mkdir` 的 mode） |
| `0x8000` / `0x4000` | `S_IFREG` / `S_IFDIR`（zip external_attr 类型闸门） |
| `0x10000` | `entry_read` 单次读块 |
| `0xc350` | `usleep(50000)`（锁重试 50 ms） |
| `0x27f` | 编码循环 `remaining > 639` |
| `0x13881` | 待发包上限 80001 |
| `0x4059000000000000` / `0x6666…` | `100.0` / 0.1 的 double 常量 |

### 仍未落地

| 项 | 现状 |
|---|---|
| 资产主干“舞台化安装/清理名单/manifest 逐项登记”三族 | 行为级等价 |
| 状态目录自身按 `mkdir 0755` 还是 `0700` 创建 | 二进制里两处并存，未确认哪个对应 `.asset-state` |
| 编译 / 真机 / arm64e 对拍 | NOT RUN |

## 第五轮：四路子代理并行审查

分工：`audit-worker`（main/worker/PDWT，2335 条）、`audit-client`（3679 条）、`audit-asset`（3729 条）、
`review-compile`（纯代码/API 评审，无汇编）。报告：`out/notes/audit-{worker,client,asset,compile}.md`。

### 已修（15 处，按严重度）

| # | 差异 | 地址 | 影响 |
|---|---|---|---|
| 1 | IPC 帧长闸门语义反了：真机接受 **1..0x10000**，只在 `0` 或 `>0x10000` 时 exit(2) | `0x10018580c` | 重建版原来只认恰好 65536 → 任何变长帧直接 exit(2)，IPC 主干走不通 |
| 2 | `/oauth_pubkey_v2` 响应体用 **appKey** 解密（块捕获 `0x20`），不是 sessionKey | `0x10018758c` | 首轮 sessionKey 为 nil → 恒 error 16，握手起不来 |
| 3 | `/oauth_pubkey_v2` 的 `kind` 传 **0**（头里没有 CmdId/SubCmdId） | `0x100187450` | 头集合与签名序列全错 |
| 4 | `Kb-TraceId` 取去横线小写 UUID 的**前 16 字符**再入字典与签名 | `0x100185c68` | 32 字符版 → Kb-Sign 全错 |
| 5 | `kind != 2` 的请求追加 `Kb-DeviceCodeRestrictionV2 = "1"`（不进签名串） | `0x100185e1c` | 缺头 |
| 6 | 100 ms handler：`stopping` 且 `elapsed <= 8 s` 时**仍要 pump**，只有 `>8 s` 才 104 | `0x100184ec0` | 重建版停流后彻底停泵，尾部包与 final 收敛不到 |
| 7 | 两处 `failWithError:` 的接收者是 **worker 自己**，不是 client（client 无此 selector，必崩） | `0x100184cc8`、`0x100185348` | 崩溃 + 不发 error 事件 |
| 8 | `failWithError:` 事件键是 `stage`，另补 `underlyingDomain` / `underlyingCode` | `0x100184860`、`0x1001848b4` | 我写成 `message` 且丢了 underlying 信息 |
| 9 | 非 1/4 命令分派前先判 `_ready`，未就绪一律 105 | `0x100184a24` | 错误码级联判断错（我报 107） |
| 10 | `traditional` 必须是 `NSNumber`，否则 101 | `0x100184b18` | 我默认 NO 继续起流，行为分叉 |
| 11 | 命令 2 末尾补 `pump`（真机每块 PCM 立刻尝试发包） | `0x100184a70` | 上行延迟多 100 ms |
| 12 | 命令 3 只在残留 PCM 非空时才 `encodeAvailable` | `0x100184c7c` | 纯 end 会多发一个只含流头的包 |
| 13 | `PDWTFields`：wire 1/5 只跳过不记录；`key<8` 或 `>0xFFFFFFFF` 整包 nil；字段上限 8192 | `0x1001895dc`、`0x1001895a8`、`0x1001895b4` | 解析结果与拒绝条件不一致 |
| 14 | varint 10 字节硬上限（第 10 字节只允许 1 bit 且不许带续位） | `0x100189558` | 畸形包真机 nil、我这边可能返回伪造值 |
| 15 | deviceCode 填充字节是 **`'0'`(0x30)**，不是 `'t'` | `0x1001cb0b5` | 设备码前缀/被签名内容全错 |

附带：`ppid < 2` 时 main 直接返回 0（`0x1001855e0`）；资产进度事件补 `type:asset-progress`（`0x100182c28`）；
`remove` 失败不再写 `removed`；`.asset-state` 只校验不创建（缺失 → `permissions`）。

### 编译面（review-compile 报告）

| 项 | 处理 |
|---|---|
| `[PDWeTypeClient failWithError:]` 不存在 | 已改为 `[self failWithError:]` |
| `mz_zip_attr_is_symlink` / `mz_zip_reader_entry_*` 版本依赖 | 改为 `mz_zip_reader_extract_to_callback` + 内联 `S_IFLNK` 判定（`m_external_attr >> 16 & 0xF000 == 0xA000`） |
| 缺 `<stdlib.h>/<string.h>/<openssl/crypto.h>` | 已补 |
| Makefile 缺 miniz 静默跳过 | 改为 `$(error …)`；`check` 路径修正 |

### 第六轮：资产 4 项已补全（`PDAssetImporter.m` 重写 flows 层）

| 项 | 落地内容 | 证据地址 |
|---|---|---|
| 1a 安装 | `PDInstallFiles`：逐段 `mkdir 0755` + `EEXIST` 容错 + `PDAssetRegularPath` 复核 → 目标存在时 `lstat` 必须 `S_IFREG` → `chmod(staging/rel, 0644)` → `rename(2)` 原子落位；随后条数校验、`PDVerifyInstalled`、`PDWriteReadyJSON` | `0x100183754`、`0x1001837e4`、`0x100183818`、`0x100183870`、`0x100183298`、`0x10018394c`、`0x100183adc` |
| 1b remove | 新增 `PDCleanupStale`：`importTokens` 校验（数组、≤1000、每个 token 必须是合法 UUID）→ 写 `removing` → 清 `originals/`、`live/` **子项** → 清四个状态名 → 清每个 token 的 `<uuid>.zip` 与 `.partial` → 返回 `{ready:NO}`；`licenses/` 有意留下 | `0x100181d50`–`0x1001822f8` |
| 1c manifest | `files` 必须字典、1..2000 条、`asset_version` 等于 spec；每项值必须 `NSDictionary`；`licenses/*` **不登记**（因此也不安装、不校验）；`store` 为空 → `manifest` | `0x1001817d4`–`0x100181854`、`0x1001815e4`、`0x100181604` |
| 4 importTokens | `remove` 的两名单；`import` 的 `imported.json` 幂等续跑（同 token → 合成 `check` 请求）；容器 `<uuid>.zip` 必须是常规文件；`copy → download.zip + chmod 0600 → 解包安装 → 写 imported.json → 删源` | `0x100181df8`、`0x1001821f4`、`0x1001824e0`、`0x100182564`、`0x10018261c`、`0x1001826f0` |

顺带修正的流程级差异：`install` **不下载**（要求 `download.zip` 已存在，`0x1001828b4`）；`check` 只做
`PDVerifyInstalled`（`0x10018295c`）；`ready.json` **只写不读**（我原来的“版本短路”是凭空新增语义）；
锁重试改回非阻塞 `LOCK_NB`（`0x100181774`），`install.lock` 不再 unlink（`0x100181af4`）；
收尾对**所有** operation 删 `unpacking`（`0x100181a7c`）；结果分派顺序 error → ready → remove（`0x1001819c4`）；
解包失败区分 `archive`（打不开包）/`unpack`（条目级）。

自检：`tools/assetverify.py` 27 项断言全绿；`tools/src_check.py` 括号/声明定义全绿（仅 `miniz.h` 为 vendor 依赖）。

### 仍然开着

| 项 | 现状 |
|---|---|
| `NSMutableSet`（`0x100182e6c`）的「未登记名重复检测」 | 只有归纳描述，未落地（`store` 已是字典，语义上等价，但真机是 set 判重） |
| `PDWriteStatus` 的进度数值范围、`imported.json`/`status.json` 的原子写细节 | 行为等价 |
| 编译 / 真机 / arm64e 逐条对拍 | NOT RUN |

## 第七轮：清掉“等价实现”（按鸭主要求，不再留降级）

| # | 原降级项 | 现在 | 证据 |
|---|---|---|---|
| 1 | `NSMutableSet` 重复检测只做语义替代 | **照抄实现**：解包循环前建空集；`containsObject:` 命中 → `unpack` 失败；「不在 manifest 且不是探针」的条目 `addObject:` 后跳过（因此同名未登记条目第二次出现必失败；保留名守卫对首次出现恒假——原 build 的死代码，一并照抄） | `0x100182e6c`、`0x100182f88`、`0x100183218` |
| 2 | `status.json` 多打了 `chmod` | 删除：只 `dataWithJSONObject` + `writeToFile:atomically:YES` | `0x100182be0` |
| 3 | 下载进度回调我加了去重 | 删除：无条件 `PDWriteStatus(downloading, pct)`（去重在 downloader 的 10% 台阶） | `0x100183c88` |
| 4 | `ready.json` 多打了 `chmod` | 删除，只原子写 | `0x100183adc` |
| 5 | 解包只做 symlink/类型两道闸 | 补齐全部闸：`bit_flag & 1` 加密条目、`m_comment[0]` 非空、`m_uncomp_size < 1`、managed 目录条目、非清单条目跳过、重复名失败 | `0x100182f98`–`0x100183024` |
| 6 | 探针资源未实现 | 新增 `PDIsManagedTexture` + **两遍安装**：第一次装清单 → `enumeratorAtPath:` 扫 staging 把探针资源收成第二个 store → 再装一遍 | `0x100183bf0`、`0x1001832e4`–`0x1001833e4` |
| 7 | accessor / `dealloc` / `.cxx_destruct` 属“按模式重建” | **证明等价**：把二进制 4 个类的 `__objc_property_list` 与源码 `@property` 全量对拍，29 条属性名与 attribute 串逐条一致（仅 NSObject 自带的 `hash`/`superclass`/`description`/`debugDescription` 未重复声明，属继承）；同一 `@property` 列表 ⇒ clang 合成出同样的 accessor 与 `.cxx_destruct` | `tools/propdiff.py` |

自检：`tools/assetverify.py` **38/38** 断言通过；`tools/propdiff.py` 属性对拍无差异。

### 仍然标注 Assumed 的两处（不是降级，是二进制未定位到）

| 项 | 说明 |
|---|---|
| 解包写暂存文件时父目录的创建方式 | 用 `createDirectoryAtPath:0700`；最终权限由 `chmod 0644`+`rename` 决定，不影响结果 |
| arm64e 切片 | 只做元数据级对拍（方法名/类型串逐字节相同、127 CFString 集合相同、7651 字符串仅差 2 条 OpenSSL 构建路径）；两切片是同一源码两次编译，未逐函数对指令 |
