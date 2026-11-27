# PetDFYPrefs · 独立审计轮（第 1 轮）

> 目的：按鸭主要求，在“符号覆盖 100%”之外验证**语义正确性**。三个审计代理只读，
> 不改源码，独立从二进制取证据（不采信作者自述）。报告：
> `out/notes/audit-prefs-{service,ai,support}.md`。

## 0 结论

| 审计域 | 报告 | 差异 | 高/致命 | 中 | 低/非行为 |
|---|---|---:|---:|---:|---:|
| `PDChatService`（87 实例 + 7 类方法） | `audit-prefs-service.md` 30.6 KB | 7 | 2 | 2 | 3 |
| 30 个 `PDAI*` C 函数 | `audit-prefs-ai.md` 23.1 KB | 6 | 3（含 1 致命） | 3 | 0 |
| 18 个存储/路径/设备工具 | `audit-prefs-support.md` 26.8 KB | 3 | 1（链接期阻断） | 0 | 2 |
| **合计** | 80.5 KB | **16** | **6** | 5 | 5 |

结构层面全部对齐（被审计员逐条复核）：87 实例方法 + 7 类方法 + 32 `@property` + 31 ivar
（0x08–0xe8，instanceSize 0xf0）、状态机时序、token 预算链
（128000 / 64000×0.85 / 2048 / 0x400 / 0x201 / 3.0 / 0x14 / 0x28）、
JSON 字段、错误码 0x15–0x1a、绝大多数 block 捕获偏移。

**问题集中在“回调契约”与“容器层级”两类**——这两种错误都能编译、看起来也合理，
但会让整条链路静默失效，正是单次读码最容易漏的地方。

## 1 高危/致命（已定位，修法中）

| 编号 | 位置 | 二进制 | 原实现 | 后果 |
|---|---|---|---|---|
| D1 | `runNextTool` 文件工具派发 `0x10f20/0x11e6c/0x11f9c` | `[[self memory] executeTool:name arguments:args]`，`read_file` 另有 `@"mem:"+path` → `imageForHandle:` → `saveImage:` → 回执 `[blob mem:%@ %@ image]` | 遍历不存在的 `args[@"images"]` 后调 `toolHandler` | 10 个文件工具不执行；`read_file` 图片永不落盘 |
| D2 | `deviceToolHandler` 块 `0x11370` | 单实参字典，读 `receipt`/`failed`/`images`，含截图落盘（`0x11508`→`0x11768`，失败文案 `\n截图附件保存失败。`） | `^(id receipt, BOOL failed)` | 字典被当回执文本写历史、`failed` 读垃圾、截图全丢 |
| F | `PDAIToolDeclarations` `0x13580` | `root[@"tools"]`（**顶层**，20 条） | `root[@"manifest"][@"tools"]` | 取 nil → 函数返回 nil → 20 条内置工具声明全丢 |
| A | `PDAIRequestBody` `0x1869c–0x188b0` | 图片补条分支 | 走向相反、区间错 | 请求体多/少一条 user 消息 |
| B | `PDAIRequestBody` `0x180c8–0x18134` | synthetic reasoning 闸门 | 变量用错 | reasoning 段错误注入/漏注入 |
| （support） | `PDPreferencesDomain` `0x4cc00` | 已定义的数据符号 | 全树只有 `extern` | **链接期 undefined symbol** |

## 2 中危

| 编号 | 位置 | 差异 |
|---|---|---|
| D3 | `initWithDataDirectory:…` `0xce48` | 孤儿 `tool_call` 占位文案应为 `[interrupted] 上次进程已结束，结果未知，不自动重放。`，源码写成 `@"["` 且会随即落盘 |
| D4 | `+normalizedPromptTemplate:` | 判等对象应是 1254 字符的旧默认模板（`0x4e078`），不是 `@"#"` |
| C | `PDAIRequestBody` `0x17a48–0x17a6c` | reasoning 重放条件多一档 |
| D | `PDAIRequestBody` `0x17940–0x183b8` | responses 分支凭空多出图片补条块 |
| E | `PDAIVocabulary` `0x13630` | `play_ball.seconds` = `6.6`（`0x401a666666666666`），源码 `@0` |

## 3 低危 / 非行为

- D5 `pet_say` 空 `images` 守卫；D6 文件工具主块的 `busy` 校验；D7 头注释 ivar 计数 30→31。
- support #2：`0x236e8–0x23ca8` 368 条属其他 TU 的方法，本文件不覆盖是对的，但注释未交代。
- support #3：注释写 `0x02314c 16 insn`，实际 31。

## 4 审计员确认成立的原 `Assumed`

| 原 Assumed | 审计结论 |
|---|---|
| `0x23d84` 的 `bundleForClass:` 实参 | 正确：`[PDLocalizationBundle class]`（0x58328 → fixup 0x58a80） |
| `0x24bf4` 用 `numberWithInt:` | 正确（末尾 failed 才走 `numberWithBool:`） |
| `0x534a0` 字典布局 count@+0x10 | 正确，5 条中文与源码逐字相同 |
| 中文字面量 | **0 条不一致**：源码 220 条去重中文全部命中二进制（含 `__TEXT,__ustring` 的 UTF-16 长文本），内嵌 JSON 11,876 字符逐字节相同 |

## 5 方法学修正（本轮新增）

1. **字符串池要合并三处**：`__cfstring` + `__cstring` + `__ustring`。只看 `__cfstring` 会把
   `__ustring` 里的长文本误判成“源码臆造”（我第一次就误报了 15 条）。
2. **`__cfstring` 必须按 `flags & 0x10` 解 UTF-16**，否则中文全成乱码（本 bundle 231 条中文串）。
3. **符号区间过滤不能写死 `>= 0x100004000`**：base 0 的 dylib 会被整体过滤掉（曾导致“资产 0/7 同源”的假结论）。
4. **“能编译 + 看起来合理”不是正确性证据**：本轮 6 条高危里，D1/D2/F 的写法全部可编译。

## 6 第 2 轮：定向复核（只核被修的 16 条）

修复由原作者完成（`PDChatService.m` + `PDAIHelpers.m`），复核由原审计员做（仍然只读）。

| 域 | 条目 | 第 2 轮结论 |
|---|---|---|
| Service | D1 | **已修**：`0x11e6c` 块 `mem:`(0x11ee4)→`imageForHandle:`→`saveImage:`(0x11f2c)→`[blob mem:%@ %@ image]`(0x11f7c)；`executeTool:`(0x11f9c)；`_attachments:@[saved]`(0x120e0)；`done(receipt,NO)`(0x12158)；旧 `images` 循环与 `"\n"` 无残留 |
| | D2 | **已修**：单字典实参(0x11370)、三键(0x4f0f8/0x4f118/0x4f138)、空图(0x114d0)、落盘(0x11508)、失败文案(0x4f158)、`_attachments`(0x11768) |
| | D3 | **已修**：789 行与 `0x4e8d8` 逐字一致 |
| | D4 | **已修**：`0x4e078` 1254 字符 vs 源码字面量 1254 字符，逐字相等 |
| | D5/D6 | **已修**：`parts.count` 守卫删除；只留 generation 守卫，未误删 device/pet_say 的 busy |
| | D7 | **已修（注释残留已由我补）**：19 行改 31；1923 行 `.cxx_destruct` 注释写 30、实为 24 条 storeStrong → 已改 |
| AI | F/A/B/C/D | **已修且复核通过**：F 走顶层 `tools`（20 条）；A 极性/段末/回退段首/区间 `[start,i]` 四点齐；B 用 `reasoningPresent`（含跳过分支）；C 逐位对应；D 块已删 |
| | E | **值对但引入编译错误**：`@"seconds": @6.6}   // …];` —— `];` 被写进注释，`PDAIVocabulary` 无法编译。**已由我补回 `];`**，该文件现括号平衡 |
| Support | 阻断项 | **已修**：`PDPreferencesDomain` 在 `PDSupport.m` 定义（`@"com.susudear.petdfyprefs"`，对应 `0x4cc00`），`PDSupport.h` 提供 `PDPreferencesDomainRef()`，其余 5 个 `.m` 的 `extern`/`static` 副本与 ARC 非法转换统一清理 |

### 6.1 复核发现的“修复引入的新问题”

只有 1 条：E 的 `];` 吞进注释（作者笔误）。已修。Service 侧 7 条无新问题；
`done` 三重守卫、`saved/receipt` 定型时机、`_imageCount` 写入点均未受影响。
`deviceToolHandler` 新增的 `isKindOfClass:NSDictionary` 守卫属可接受偏差（合法回调无差异）。

### 6.2 结构复检（忽略字符串/注释的括号走查）

`PDAIHelpers.m` / `PDChatService.m` / `PDSupport.m` / `PDProviderController.m` 全部 OK（`tools/brace2.py`）。

## 7 最终状态

| 项 | 值 |
|---|---|
| ObjC 方法 | 264/264（`prefs_audit`：缺 0、TODO 0、属性不符 0） |
| C 函数 | 55/55（48 在 `PetDFYPrefs`，7 个资产复用 voice） |
| 审计差异 | 16 条 → **全部已修并复核** |
| 残留 `Assumed` | 10 条（见 `docs/05 §5.2`）；AI 侧原 3 条中 2 条被审计判定成立、1 条被证伪并修正 |
| 编译 / 真机 | **NOT RUN** |
