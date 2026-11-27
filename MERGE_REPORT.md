# 合并报告 · PetDFY 合并版（build.077 + 第一套导入链路）

> 版本：`0.1.9-merge2`（高于 `0.1.8-e2+build.077`，避免 dpkg 降级）
> 基线：`纯源码PetDFY-src-only-build.077-20261127-r2.zip`（T3 可编辑基线）
> 补入：`hf805864818/Pet` 仓库的 RootHide 素材导入链路
> 静态自检：**PASS**（import 闭环 / 括号配平 / 依赖 / 接入点 / Makefile）
> 编译验证：**NOT RUN**（本机无 clang / theos / iOS SDK，需 CI 或 macOS）

---

## 一、为什么要合并

两套源码同源分叉，各缺一半：

| | build.077（基线） | hf805864818/Pet（第一套） |
|---|---|---|
| 可编辑层（发色/服装/布局/贴图） | ✅ 完整 | ❌ 无 |
| RootHide 素材导入（进程内解压） | ❌ 依赖 `/usr/bin/unzip` | ✅ 完整 |
| 辅助 dylib（PDFYEnhance / PDFYSecurity） | ✅ 完整 | ❌ 无 |
| 能出 deb 的 CI | ❌ 被剔出 src-only 包 | ✅ 22 次绿 |
| 崩溃守卫 / 文件日志 | ✅ 完整 | 部分 |

合并后：**编辑能力 + 可安装性 + RootHide 兼容** 三者齐备。

---

## 二、新增文件（12 个，全部来自第一套）

| 文件 | 作用 | 依赖 |
|---|---|---|
| `src/Core/PDZipExtract.h/.m` | 进程内 ZIP 解压（zlib，stored/deflate/ZIP64/路径穿越防护） | `zlib.h`、`-lz` |
| `src/Core/PDAssetInstaller.h/.m` | 素材安装编排（扫描投递目录→校验→staging→双写→状态回写） | 上两行 + `PDDiag.h` |
| `src/Core/PDJailbreak.h` | 越狱根解析（rootful / `/var/jb` / `.jbroot-*` / `/rootfs`） | 无（inline） |
| `src/Core/PDFramePlayer.h/.m` | 帧动画播放器（补 `M3` 缺口的一部分） | `PDJailbreak.h`、`ImageIO` |
| `src/Core/PDDiagnostics.h/.m` | 素材/渲染诊断报告 | `PDJailbreak.h`、`PDAssetInstaller.h` |
| `src/Core/PDToast.h/.m` | 导入结果浮层提示 | UIKit |
| `src/Core/PDDiag.h` | 落盘日志（`PDDiagLog`） | `PDJailbreak.h` |

> `Entry.m` **没有**合并：build.077 用 `PDBootstrap.m`（带崩溃守卫 + 诊断日志），入口更完整。

---

## 三、改动清单（4 个文件，7 处）

### 1. `src/Core/PDOverlayController.m`

| 位置 | 改动 |
|---|---|
| 头部 import | `+ #import "PDJailbreak.h"`、`+ #import "PDAssetInstaller.h"` |
| `PDResourceBundlePath()` | 硬编码路径 → **越狱根展开 + 结构完整度打分**（`live/model.json` 100 分、`originals/model.json` 50 分、`originals` 20、`clips.plist` 10、`frames` 10；同分按 mtime） |
| 新增 `PDInstallCombinedArchive()` | 进程内安装器优先，失败只记日志（不再 spawn unzip） |
| `-start` 第 2.5 步 | 建窗前先导入投递目录里的新 ZIP，再建窗（保证 `PDResourceBundlePath()` 拿到新根） |
| 新增 `-pd_startAssetImportPolling` | 每 3 秒轮询；安装成功后 `discardAssetViews` → `setStarted:NO` → `start` |

### 2. `src/Core/PDOverlayController.h`
`+ - (void)pd_startAssetImportPolling;`（前向调用需要声明）

### 3. `Makefile`
```
- PetDFY_LDFLAGS = -Wl,-undefined,dynamic_lookup
+ # -lz：PDZipExtract 的进程内 ZIP 解压依赖 libz（iOS SDK 自带 libz.tbd）
+ PetDFY_LDFLAGS = -Wl,-undefined,dynamic_lookup -lz
```

### 4. `control` / `layout/DEBIAN/control`
- `Version: 0.1.8-e2+build.077` → `0.1.9-merge1`
- 删除 `Installed-Size`（theos 的 `dm.pl` 会自动追加，手写会 **duplicate value → dpkg fatal**，见 `MEMORY/04` 的 P2）

---

## 四、新增构建设施

| 文件 | 作用 |
|---|---|
| `tools/build-layout.sh` | 从 `vendor/base/*.deb` 解出偏好包 / `Whale.metal` / 本地化，放入 `petdfy-voice` 与素材，生成 RootHide `postinst`，做 layout 自检 |
| `tools/verify-deb.sh` | deb 元数据 / 三个 dylib / 架构 / 偏好包 / 素材 / voice / 合并标识 全检 |
| `tools/precheck.py` | 静态自检：import 闭环、括号（真实词法）、依赖、接入点、Makefile |
| `tools/balance_check.py` | 括号精确诊断（定位第一个不匹配位置） |
| `.github/workflows/build.yml` | ubuntu + theos + 匹配版本 clang/lld + 出 deb + 上传 artifact |
| `vendor/base/` | `PetDFY_1.2.1_RootHide.deb`（1.93 MB）+ `petdfy-voice`（5.32 MB） |

---

## 五、静态自检结果

```
源文件 156（.m 84 / .h 72）

=== import 闭环缺失 ===      (无)
=== 括号不配平 ===           (无)
=== 缺失文件 ===             (无)
=== 依赖缺失 ===             (无)
=== PDOverlayController 接入点缺失 === (无)
=== Makefile 缺少项 ===      (无)

=== 结论: PASS ===
```

> 第一轮 `precheck.py` 报的 11 个"括号不配平"是**检查器误报**（`strip_code` 把字符字面量 `'{'` 一起删了）。
> 用真实词法扫描（`tools/balance_check.py`）复核：5 个文件全部 `BALANCED`。

---

## 六、遗留项（合并没解决，需单独处理）

| # | 项 | 状态 | 说明 |
|---|---|---|---|
| 1 | 素材 `assets_src/` | **缺** | 本包是 src-only，README 说的 33 MB 素材不在包内。缺 `originals/` 与 `live/model.json` 时 `ensureWindow` 直接失败 → 桌面无角色 |
| 2 | 编译验证 | **NOT RUN** | 本机无 clang/theos/iOS SDK；`make package` 从未跑过 |
| 3 | 真机验证 | **NOT RUN** | 无越狱设备可测 |
| 4 | `B5` 换装不重建 rig | OPEN | `PDOverlayController` 只写 `liveRig.outfit` |
| 5 | `B6` 服装白名单 4 套 | OPEN | `PetDFYPrefs.bundle/Root.plist` 的 `Outfit.validValues` |
| 6 | 150 个方法待还原 | OPEN | 见 `docs/10_待还原清单.md`，证据保真度 68.0% |
| 7 | 语音 helper | **源码已补 / 缺依赖库** | `voice-src/` 有 7 个 .m（WeType 协议 + opus 封装），但需要 `vendor/opus`、`vendor/openssl`、`vendor/miniz` 才能编；当前继续用 5.3 MB 二进制 |
| 8 | 设置面板 | **源码已补 / 未编译** | `prefs-src/` 18 类 264 方法 55 C 函数，独立审计 16 条差异已修；`tools/build-prefs.sh` 编译，失败自动回退 vendor 二进制 |

---

## 七、怎么跑

### 1. 本地（需要 theos + iOS SDK）

```bash
export THEOS=$HOME/theos
bash tools/build-layout.sh        # 装配 layout（需要 vendor/base 的两个文件）
make clean all                    # 只编译
make package FINALPACKAGE=1       # 出 deb
bash tools/verify-deb.sh          # 校验
```

### 2. CI（推荐，不需要 Mac）

```bash
git init && git add -A && git commit -m "merge: build.077 + RootHide import"
git remote add origin git@github.com:<你>/PetDFY-merged.git
git push -u origin main
```

推上去自动构建，产物在 **Actions → build-deb → Artifacts → PetDFY-deb**。

### 3. 装到设备

```bash
dpkg -i PetDFY_0.1.9-merge1_iphoneos-arm64e.deb
killall -9 SpringBoard

# 看启动与导入日志
tail -f /var/mobile/Media/petdfy-diag.txt
# 期望：=== PetDFY build.077 bootstrap ... ===
#       start: begin
#       [PetDFY.Import] in-process install ok / no zip in spool
#       [PetDFY] model injected: outfit=maid parts=34 deformers=...
```

### 4. 导入素材

设置 → 大肥鱼 → 下载 → 从文件导入 ZIP，把包放进：

```
/var/mobile/Library/Application Support/PetDFY/AssetImports/
```

3 秒内自动安装并重载（无需重启 SpringBoard）。

---

## 八、已知风险

1. **`-lz` 链接**：theos 的 `tweak.mk` 对 `PetDFY_LDFLAGS` 透传，若 CI 报 `library not found for -lz`，改用 `PetDFY_LIBRARIES = z`。
2. **arm64e 切片**：`export ARCHS = arm64 arm64e`，若 CI 的 clang/ld64.lld 版本不匹配，会在 ptrauth 重定位报错——workflow 已做版本 pin 和回退。
3. **`PDStubs.m` 的兜底**：`liveRig`/`expression` 返回 `nil`，`toStage:` 恒等。编译能过，但高频路径拿到 nil 后的行为**未验证**。
4. **无 LICENSE**：两套源码都没有许可证，素材与语音 helper 都是二次分发，商用前必须重做素材 + 换 ASR。


---

## 九、第四套（reverse-full）纳入情况

来源：`petdfy-reverse-full-20261127.zip`（2.56 MB，678 文件 / 10.08 MB 解包）
内容：**PetDFYPrefs 与 petdfy-voice 的源码还原 + 380 份反汇编 + 182 个逆向工具**

### 9.1 `prefs-src/`（设置面板，新增）

| 项 | 数值 |
|---|---|
| 类 | 18（含 PDRootListController / PDChatService / PDAIMemory / PDChatMemoryController / PDMemoryEditor / 各 Cell） |
| ObjC 方法 | 264 / 264 |
| C 函数 | 55 / 55（48 在 Prefs，7 个资产复用 voice） |
| 独立审计差异 | 16 条 → 全部已修并复核 |
| 代码量 | 约 40 万字节（PDAIHelpers.m 99 KB、PDChatService.m 85 KB、PDAIMemory.m 58 KB、PDSupport.m 39 KB） |

**我在合并时修掉的两处编译阻断**（原包遗留）：

```
PDChatService.m:116  if (![[PDAIPreference(@"AIEnabled", ...) boolValue]) {
                                                  ↑ 少一个 ]，[[ 未闭合
PDChatService.m:516  if (![[PDAIPreference(@"AIAcceptImages", ...) boolValue]) {
```

两处都改成 `boolValue]])`，静态检查已 `全部配平`。

### 9.2 `voice-src/`（语音 helper，新增）

| 文件 | 作用 |
|---|---|
| `main.m` | IPC 前端（stdin 帧解析 → worker；父进程看门狗） |
| `PDVoiceWorker.m` | opus 编码 + 请求泵 + 4 条命令状态机 |
| `PDWeTypeClient.m` | wss / HTTPS 客户端（握手、签名头、音频、文本） |
| `PDWeTypeKeyAgreement.m` | ECDH（OpenSSL EC_KEY，NID 706） |
| `PDVoiceProtocol.m` | protobuf / varint / hex / MD5 / SHA-256 / AES-256-ECB / snappy / deviceCode |
| `PDVoiceOutput.m` | stdout 事件帧 |
| `PDAssetImporter.m` | 资产子系统（阶段机、状态文件、miniz 解包） |

协议细节（来自 `voice-src/docs/02-wire-protocol.md`）：

```
wss://wetype.weixin.qq.com/        子协议 wxws_pb
音频 POST https://wetype.weixin.qq.com/api_v2
opus 1.6.1 / 16 kHz 单声道 / OPUS_APPLICATION_AUDIO / 64000 bps / complexity 5
20 ms（320 采样）一帧，帧前 2 字节小端长度
首包前 16 字节流头  #!OPUS_RAW_V1\x02\x01\x00
```

**不能直接编译**：`voice-src/Makefile` 需要 `vendor/opus/{include,lib}`、`vendor/openssl/{include,lib}`、`vendor/miniz/miniz.c`，包里只有 `vendor/README.txt`。
所以语音继续用 `vendor/base/petdfy-voice` 二进制（5.3 MB，与源码 SHA256 对应）。

### 9.3 `out/`（方法学资产）

- 380 个 `.asm`（arm64 / arm64e 反汇编，按类或函数切分）
- 23 个 `.md` 文档（01 类清单 / 02 线路协议 / 03 验证 / 04 资产子系统 / 05 偏好清单 / 06 偏好审计）
- 182 个 Python 工具（`macho.py`、`objc.py`、`prefs_audit.py`、`call_coverage.py` 同类）

这批东西的价值不在产物，而在**可复用的取证方法**：以后要补 `WNMotion step:` 剩余 42% 或 `WNRenderer` 合成，直接照这套流程走。

### 9.4 合并结论

| 缺口 | 合并前 | 合并后 |
|---|---|---|
| 设置面板 | 只有 846 KB 二进制 | **有源码**（编译待验证，失败自动回退二进制） |
| 语音 helper | 只有 5.3 MB 二进制 | **有源码**（缺 vendor 库，继续用二进制） |
| 反汇编/工具链 | 无 | 380 asm + 182 py 工具 |

主基底（build.077）不变：第四套只补两块外围，不动 `src/` 的 84 个 .m。
