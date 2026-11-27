# PetDFY 语音服务 · 资产子系统还原（arm64 / iOS 16 / ARC）

> 输入：`out\asm\*.asm`（104 个函数片段）。
> 样本：`extract\slices\petdfy-voice_arm64`，2611040 字节，SHA-256 `26a4377eee89d5ed0484d99038aecce66440aef63e26001b3373d7a6fa323047`。
> 所有地址为未签名 ARM64 slice 的链接地址（`__TEXT` 起始 `0x100000000`）。
> 依据等级：`Observed` = 指令直接可见；`Inferred` = 由调用形状/常量推出；`Assumed` = 需实测确认，文内标注。

---

## 0 全局事实（本文件的前提）

| 项 | 值 | 依据 |
|---|---|---|
| 段布局 | `__TEXT` 0x100000000 (2 MiB) / `__DATA_CONST` 0x100200000 / `__DATA` 0x100268000 / `__LINKEDIT` 0x1002C8000 | Mach-O load command 解析 |
| 指针编码 | dyld chained fixups；rebase `target = 0x100000000 + (raw & 0xFFFFFFFFF)`，bind `symbol = imports[raw & 0xFFFFF]` | `LC_DYLD_CHAINED_FIXUPS` @0x26C000，253 条 import |
| ObjC 类 | 仅 4 个：`PDAssetDownloader`(0x1002697A8)、`PDVoiceWorker`、`PDWeTypeClient`、`PDWeTypeKeyAgreement` | `__objc_classlist` 0x1002649C0 |
| 常量字符串 | `__DATA_CONST,__cfstring` 共 127 条（0x1002639E0…0x1002649A0） | 32 字节/条，chained rebase 解出 |
| 静态链接 | miniz（`mz_zip_*`/`mz_`）、zlib（`inflate`/`crc32`）、CommonCrypto、OpenSSL 3.5.9（仅 PDWeTypeClient 侧） | 导入符号表 |
| 编译方式 | ARC（`objc_retainAutoreleasedReturnValue` / `objc_storeStrong` / `-fobjc-arc` 特征），C 与 ObjC 混编 | 全量函数 |
| 资产子系统构成 | 1 个 ObjC 类（`PDAssetDownloader`）+ 7 个导出 C 函数 + 约 12 个文件内 static helper | 符号表 + 调用图 |

---

## 1 关键常量表（重写时直接抄）

### 1.1 路径 / 文件名 / 阶段名（`__cfstring`）

| 地址 | 值 | 用途 |
|---|---|---|
| 0x100264180 | `/var/mobile/Library/Application Support/PetDFY/AssetImports` | 导入暂存根（硬编码绝对路径） |
| 0x100263CA0 | `.asset-state` | 状态目录名（拼在 bundle 根下） |
| 0x100263CC0 | `install.lock` | 互斥锁文件（`flock`） |
| 0x100263A00 | `download.zip` | 下载落地文件名 |
| 0x100263D00 | `unpacking` | 解包暂存目录名 |
| 0x100263E80 | `ready.json` | 就绪标记文件 |
| 0x100263EA0 | `imported.json` | 导入完成标记 |
| 0x100263EC0 | `.partial` | 临时文件后缀 |
| 0x100264100 | `status.json` | 进度状态文件 |
| 0x100264140 | `asset-spec.json` | bundle 内规格文件（`schema` / `asset_version`） |
| 0x100263BA0 | `asset-manifest.json` | bundle 内清单（`files` 映射） |
| 0x100264020 | `checking` `downloading` `needs-url` `invalid-url` | 阶段名 |
| 0x1002640C0… | `status` / `progress` / `asset-progress` | status.json 与回调字典字段 |
| 0x100263A20 | `permissions` | 通用权限/落盘失败阶段名 |
| 0x100263A40 | `download-failed` | 下载失败 |
| 0x100263AA0…0x100263B20 | `check` `install` `prepare` `import` `remove` | 支持的 operation |
| 0x100263CE0 | `busy` | 锁竞争失败 |
| 0x100263D60 / 0x100263D80 / 0x100263DA0 | `stage` / `ready` / `removed` | 结果字段 |
| 0x100263D20 / 0x100263D40 / 0x100263DC0 / 0x100263DE0 / 0x100263E00 | `type` / `error` / `domain` / `PetDFY.Assets` / `code` | 错误字典 |
| 0x100263F60 / 0x100263F80 | `archive` / `unpack` | 解包失败阶段名 |
| 0x100263F20 / 0x100263F40 | `importing` / `installing` | 导入 / 安装阶段名 |
| 0x100263E60 | `removing` | 清理阶段名 |
| 0x100264160 / 0x100263C00 / 0x100263BE0 | `schema` / `asset_version` / `files` | manifest / spec 字段 |

### 1.2 常量数组（`__objc_arrayobj`，运行时字面量）

| 地址 | 内容 | 使用者 |
|---|---|---|
| 0x100264C08 | `@[@"check", @"install", @"prepare", @"import", @"remove"]` | operation 白名单（入口校验） |
| 0x100264C20 | `@[@"originals", @"live", @"licenses"]` | manifest `files` 键的顶层目录白名单 |
| 0x100264C50 | `@[@"originals", @"live"]` | 资产可见根（解包/安装目标目录） |
| 0x100264C68 | `@[@"ready.json", @"imported.json", @"download.zip", @"unpacking"]` | 保留名/清理名单 |
| 0x100264C80 | `@[@"http", @"https"]` | URL scheme 白名单 |

### 1.3 常量 NSNumber（`__objc_intobj`，24 字节/条）

| 地址 | 值 | 含义 |
|---|---|---|
| 0x100264A08 | `@384` | `0600` → 文件权限（`NSFilePosixPermissions`） |
| 0x100264A20 | `@1` | 错误字典 `code` 值 |
| 0x100264A38 | `@448` | `0700` → 目录权限 |

### 1.4 数值常量（`__TEXT,__const`）

| 地址 | 值 | 用途 |
|---|---|---|
| 0x1001C9CD8 | `99.0` | 下载百分比上限（进度封顶 99，完成时才给 100） |
| 0x1001C9CE0 | `45.0` | `timeoutIntervalForRequest` |
| 0x1001C9CE8 | `600.0` | `timeoutIntervalForResource` |

---

## 2 磁盘布局（由函数拼出，全部 Observed）

```
<exe realpath> ─ dirname ─ dirname ─ /PetDFY.bundle        ← PDAssetSpecification 的入参 bundleRoot
├── asset-spec.json                 { "schema": 1, "asset_version": "<非空字符串>" }
├── asset-manifest.json             { "asset_version": ..., "files": { "<相对路径>": ... } }
├── originals/  live/  licenses/    ← 资产落地目录（白名单）
└── .asset-state/                   ← PDAssetStatePath(bundleRoot)
    ├── install.lock                ← flock 互斥
    ├── download.zip                ← 下载产物，0600
    ├── unpacking/                  ← 解包暂存（0700）
    ├── status.json                 ← { "status": <NSString>, "progress": <NSInteger> }
    └── ready.json                  ← { "asset_version": <NSString> }

/var/mobile/Library/Application Support/PetDFY/AssetImports/
└── <uuid>.zip/                     ← 以包名当目录名（contentsOfDirectoryAtPath 作用其上）
    ├── imported.json               ← { "token": <NSString> }
    └── <uuid>.zip.partial
```

`Assumed:` `<uuid>.zip` 实为目录（`PDAssetImportPath` 用 `stringByAppendingPathExtension:@"zip"` 造名，但后续以 `contentsOfDirectoryAtPath:`/`stringByAppendingPathComponent:` 当目录用）；依据是 0x100181F8C 与 0x1001824CC 两处用法矛盾中的后者更具体。

---

## 3 数据结构

### 3.1 入参 `request`（NSDictionary）

| 键 | 类型 | 必需 | 说明 |
|---|---|---|---|
| `operation` | NSString | 是 | ∈ {check, install, prepare, import, remove} |
| `url` | NSString | install/prepare 需要 | 下载地址，经 `PDAssetDownloadURL` 过滤 |
| `token` | NSString | import 需要 | UUID 字符串，决定 `AssetImports/<uuid>.zip` |

### 3.2 返回值（NSDictionary）

```objc
// 错误
@{ @"type": @"error", @"domain": @"PetDFY.Assets", @"code": @1, @"stage": <stageName> }
// 成功
@{ @"ready": @YES }        // ← 0x100181A08 读取 result[@"ready"].boolValue
```
`Assumed:` 成功字典可能额外带 `asset_version`（安装成功后写 `ready.json` 用到同名字段），主流程只读 `ready`，因此不影响重写。

### 3.3 `PDAssetDownloader` 实例变量（由 getter/setter 偏移定死）

```objc
@interface PDAssetDownloader : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic)          BOOL        downloaded;    // @0x08  ldrb
@property (nonatomic, strong)  NSString   *root;          // @0x10  目标目录（= .asset-state）
@property (nonatomic, strong)  NSError    *failure;       // @0x18
@property (nonatomic, strong)  NSURLSession *session;     // @0x20
@property (nonatomic, strong)  NSURLSessionDownloadTask *task; // @0x28
@property (nonatomic, strong)  dispatch_semaphore_t finished;  // @0x30
@property (nonatomic, copy)    void (^progress)(NSInteger);    // @0x38 (objc_setProperty_nonatomic_copy)
@property (nonatomic)          NSInteger lastProgress;    // @0x40
@end
```
`-dcxx_destruct`(0x100181050) 依次 `objc_storeStrong(nil)` 于 0x38/0x30/0x28/0x20/0x18/0x10，与上表一一对应。

---

## 4 函数分节

### 4.0 `PDAssetImportDirectory`

```c
NSString *PDAssetImportDirectory(void);          // 0x100183E58，3 条指令
```
作用：返回硬编码导入目录常量。无参数、无分支。

```c
NSString *PDAssetImportDirectory(void)
{
    return @"/var/mobile/Library/Application Support/PetDFY/AssetImports";
}
```
外部 API：无。

---

### 4.1 `PDAssetStatePath`

```c
NSString *PDAssetStatePath(NSString *root);      // 0x100183E4C，3 条指令（尾调用）
```
作用：把 `.asset-state` 拼到 bundle 根后。

```c
NSString *PDAssetStatePath(NSString *root)
{
    // adrp/add → CFSTR ".asset-state" @0x100263CA0，x2 即第二参数
    return [root stringByAppendingPathComponent:@".asset-state"];   // 尾跳 sel:stringByAppendingPathComponent:
}
```
外部 API：`-[NSString stringByAppendingPathComponent:]`。

---

### 4.2 `PDAssetImportPath`

```c
NSString *PDAssetImportPath(NSString *uuidString);   // 0x100183E64，42 条
```
作用：UUID 字符串 → `AssetImports/<uuid>.zip`；非法 UUID 返回 nil。

```c
NSString *PDAssetImportPath(NSString *uuidString)
{
    if (![uuidString isKindOfClass:[NSString class]])       // 0x100183E90
        return nil;

    NSUUID *u = [[NSUUID alloc] initWithUUIDString:uuidString];   // 0x100183EA0
    if (!u) return nil;                                     // 0x100183EB4 cbz x20

    NSString *name = [uuidString stringByAppendingPathExtension:@"zip"];  // 注意：用原串，不用 NSUUID
    return [PDAssetImportDirectory() stringByAppendingPathComponent:name];
}
```
外部 API：`objc_retain/release`、`objc_opt_class`、`objc_opt_isKindOfClass`、`-[NSUUID initWithUUIDString:]`、`-[NSString stringByAppendingPathExtension:]`、`-[NSString stringByAppendingPathComponent:]`。

---

### 4.3 `PDAssetSafeRelativePath`

```c
BOOL PDAssetSafeRelativePath(NSString *rel);     // 0x100183F0C，133 条
```
作用：相对路径合法性闸门（长度、绝对路径、反斜杠、控制字符、`.`/`..`/空段）。**整个资产子系统的路径安全检查都走它。**

```c
BOOL PDAssetSafeRelativePath(NSString *rel)
{
    NSString *backslash = [NSString stringWithFormat:@"%c", 0x5C];  // '\'  0x100183F4C/0x100183F58

    if (![rel isKindOfClass:[NSString class]]) return NO;                     // 0x100183F7C
    if (rel.length == 0)                       return NO;                     // 0x100183F88
    if (rel.length > 0x200)                    return NO;                     // 0x100183F94  上限 512
    if ([rel isAbsolutePath])                  return NO;                     // 0x100183FA0
    if ([rel containsString:backslash])        return NO;                     // 0x100183FB0
    if ([rel rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location
        != NSNotFound)                         return NO;                     // 0x100183FD4

    for (NSString *c in [rel componentsSeparatedByString:@"/"]) {              // 0x100183FF8
        if (c.length == 0)      return NO;   // 首尾 '/' 或 "//"   0x10018406C
        if ([c isEqual:@"."])   return NO;   // 0x100184078
        if ([c isEqual:@".."])  return NO;   // 0x100184088
    }
    return YES;                                                              // 0x100184110
}
```
栈保护：`___stack_chk_guard` / `___stack_chk_fail`。外部 API：`objc_retain/release`、`objc_opt_class`、`objc_opt_isKindOfClass`、`+[NSString stringWithFormat:]`、`-[NSString length/isAbsolutePath/containsString:componentsSeparatedByString:isEqual:]`、`+[NSCharacterSet controlCharacterSet]`、`-[NSString rangeOfCharacterFromSet:]`、`-[NSArray countByEnumeratingWithState:objects:count:]`、`objc_enumerationMutation`、`___stack_chk_fail`。

---

### 4.4 `PDAssetRegularPath`

```c
BOOL PDAssetRegularPath(NSString *root, NSString *rel, BOOL wantDir);   // 0x100184120，83 条
```
作用：在 `root` 下逐段拼接 `rel`，用 `lstat` 校验每一层真实存在、非符号链接、中间层必为目录、末层按 `wantDir` 要求文件或目录。**这是防符号链接穿越与 TOCTOU 的第一道墙。**

```c
BOOL PDAssetRegularPath(NSString *root, NSString *rel, BOOL wantDir)
{
    if (!PDAssetSafeRelativePath(rel)) return NO;                    // 0x100184154

    NSString *path  = root;
    NSArray  *comps = [rel componentsSeparatedByString:@"/"];        // 0x100184170
    if (comps.count == 0) return YES;                                // 0x100184180

    struct stat st;                                                  // 栈上 0x90 字节
    for (NSUInteger i = 0; ; ) {
        NSString *c = comps[i];                                      // 0x100184190
        path = [path stringByAppendingPathComponent:c];              // 0x1001841A4
        if (lstat(path.fileSystemRepresentation, &st) != 0)          // 0x1001841CC
            return NO;                                               //   0x100184238
        mode_t t = st.st_mode & S_IFMT;                              // 0x1001841D4
        if (t == S_IFLNK)          return NO;                        //  0x1001841E0
        i++;
        if (i < comps.count) {                                       // 中间层
            if (t != S_IFDIR)      return NO;                        //  0x100184210
        } else {                                                     // 末层
            if (!wantDir) { if (t != S_IFREG) return NO; }            //  0x100184204
            else          { if (t != S_IFDIR) return NO; }            //  0x100184210
            break;
        }
    }
    return YES;                                                      // 0x100184228
}
```
外部 API：`PDAssetSafeRelativePath`、`lstat`、`-[NSString fileSystemRepresentation/componentsSeparatedByString:stringByAppendingPathComponent:]`、`objc_retainAutorelease`、`objc_claimAutoreleasedReturnValue`、`___stack_chk_fail`。

---

### 4.5 `PDAssetSpecification`

```c
NSDictionary *PDAssetSpecification(NSString *bundleRoot);   // 0x100183CFC，84 条
```
作用：读并校验 `<bundleRoot>/asset-spec.json`，返回原始字典（不做深拷贝）。任一校验失败返回 nil。

```c
NSDictionary *PDAssetSpecification(NSString *bundleRoot)
{
    NSString *p = [bundleRoot stringByAppendingPathComponent:@"asset-spec.json"]; // 0x100183D1C
    NSData   *d = [NSData dataWithContentsOfFile:p];                              // 0x100183D34
    if (!d) return nil;                                                          // 0x100183D44

    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];    // 0x100183D5C
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;                    // 0x100183D88

    if ([[obj objectForKeyedSubscript:@"schema"] integerValue] != 1) return nil;  // 0x100183DB0
    id v = obj[@"asset_version"];                                                 // 0x100263C00
    if (![v isKindOfClass:[NSString class]]) return nil;                          // 0x100183DE8
    if ([obj[@"asset_version"] length] == 0) return nil;                          // 0x100183E14
    return obj;                                                                  // 0x100183E1C autoreleaseReturnValue
}
```
外部 API：`+[NSData dataWithContentsOfFile:]`、`+[NSJSONSerialization JSONObjectWithData:options:error:]`、`objc_opt_class`、`objc_opt_isKindOfClass`、`-[NSDictionary objectForKeyedSubscript:]`、`-[NSNumber integerValue]`、`-[NSString length]`、`objc_retain/release`。

---

### 4.6 `PDAssetDownloadURL`

```c
NSURL *PDAssetDownloadURL(NSString *s);      // 0x10018426C，104 条
```
作用：把外部给的 URL 字符串净化为 NSURL：限长、无空白、scheme 白名单、必须有 host、不得带 user/password/fragment（挡 `http://user@host`、`#…` 之类注入）。

```c
NSURL *PDAssetDownloadURL(NSString *s)
{
    if (![s isKindOfClass:[NSString class]]) return nil;                   // 0x1001842A8
    if (s.length == 0 || s.length > 0x2000)  return nil;                   // 0x1001842B4/0x1001842B8 (8192 上限)

    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;  // 0x1001842C4
    if ([s rangeOfCharacterFromSet:ws].location != NSNotFound) return nil; // 0x1001842EC

    NSURLComponents *c = [NSURLComponents componentsWithString:s];         // 0x1001842FC
    NSString *scheme = [c.scheme lowercaseString];                         // 0x100184314
    if (![@[@"http", @"https"] containsObject:scheme]) return nil;         // 0x10018432C 数组 @0x100264C80

    if (c.host.length == 0)     return nil;                                // 0x100184344
    if (c.user.length != 0)     return nil;                                // 0x10018435C
    if (c.password.length != 0) return nil;                                // 0x100184374
    if (c.fragment.length != 0) return nil;                                // 0x1001843F4
    return c.URL;                                                          // 0x1001843FC
}
```
外部 API：`objc_opt_class`、`objc_opt_isKindOfClass`、`+[NSCharacterSet whitespaceAndNewlineCharacterSet]`、`-[NSString rangeOfCharacterFromSet:/lowercaseString/length]`、`+[NSURLComponents componentsWithString:]`、`-[NSURLComponents scheme/host/user/password/fragment/URL]`、`-[NSArray containsObject:]`。

---

### 4.7 `PDAssetDownloader` 的 URLSession 回调

#### 4.7.1 `willPerformHTTPRedirection:`

```objc
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)newRequest
        completionHandler:(void (^)(NSURLRequest *))completionHandler;   // 0x1001809C8，97 条
```
作用：只放行「跳转后仍是合法直链、且不许 https→http 降级」的重定向。

```objc
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
  willPerformHTTPRedirection:(NSHTTPURLResponse *)response
  newRequest:(NSURLRequest *)newRequest
  completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSURL *allowed = PDAssetDownloadURL(newRequest.URL.absoluteString);   // 0x100180A3C
    BOOL downgrade = NO;
    NSString *origScheme = [task.originalRequest.URL.scheme lowercaseString];  // 0x100180A8C
    if ([origScheme isEqual:@"https"])                                     // 0x100180AA0
        downgrade = ![[newRequest.URL.scheme lowercaseString] isEqual:@"https"];  // 0x100180ADC

    completionHandler((allowed != nil && !downgrade) ? newRequest : nil);  // 0x100180B04-B20
}
```
外部 API：`-[NSURLSessionTask originalRequest]`、`-[NSURLRequest URL]`、`-[NSURL absoluteString/scheme]`、`-[NSString lowercaseString/isEqual:]`、`PDAssetDownloadURL`、block 调用（`ldr x8,[blk,#0x10]; blr x8`）。

#### 4.7.2 `didWriteData:totalBytesWritten:totalBytesExpectedToWrite:`

```objc
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t
        didWriteData:(int64_t)written
   totalBytesWritten:(int64_t)total
totalBytesExpectedToWrite:(int64_t)expected;    // 0x100180B4C，65 条
```
作用：把字节数折成 0–99 的整数百分比，**每跨一个 10% 台阶才回调一次**，避免刷屏。

```objc
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t
      didWriteData:(int64_t)written
  totalBytesWritten:(int64_t)total
 totalBytesExpectedToWrite:(int64_t)expected
{
    NSInteger pct = 0;
    if (expected >= 1) {                                   // 0x100180B68
        double v = (double)total * 100.0 / (double)expected;   // 0x100180B6C 立即数 0x4059000000000000 = 100.0
        if (v < 0)   v = 0;                                // fmaxnm
        if (v > 99.0) v = 99.0;                            // 0x1001C9CD8
        pct = (NSInteger)v;                                // fcvtzs
    }
    if (pct / 10 == self.lastProgress / 10 && self.lastProgress >= 0)   // 0x100180BD0/0x100180BE0
        return;
    self.lastProgress = pct;
    void (^blk)(NSInteger) = self.progress;
    if (blk) blk(pct);                                     // 0x100180C1C
}
```
外部 API：`-[PDAssetDownloader lastProgress/setLastProgress:/progress]`、block 调用。

#### 4.7.3 `didFinishDownloadingToURL:`

```objc
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
        didFinishDownloadingToURL:(NSURL *)location;   // 0x100180C50，177 条
```
作用：HTTP 200 且文件非空时，把临时文件搬成 `<.asset-state>/download.zip` 并 `chmod 0600`；任何一步失败写 `failure = @"permissions"`。

```objc
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
        didFinishDownloadingToURL:(NSURL *)location
{
    NSHTTPURLResponse *resp = (id)task.response;
    if (![resp isKindOfClass:[NSHTTPURLResponse class]]) return;   // 0x100180CB8
    if (resp.statusCode != 200) return;                           // 0x100180CC4

    id size = nil;
    [location getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];  // 0x100180CE8  _NSURLFileSizeKey @0x100200038
    if ([size longLongValue] < 1) return;                          // 0x100180D00 空文件直接放弃

    NSString *stateDir = PDAssetStatePath(self.root);              // 0x100180D14
    NSString *zipPath  = [stateDir stringByAppendingPathComponent:@"download.zip"];  // 0x100180D28
    NSFileManager *fm  = [NSFileManager defaultManager];           // 0x100180D44

    NSError *err = nil;
    if ([fm fileExistsAtPath:zipPath]) {                           // 0x100180D54
        if (![fm removeItemAtPath:zipPath error:&err]) {           // 0x100180D6C
            self.failure = @"permissions"; return;                 // 0x100180EB0
        }
    }
    self.downloaded = [fm moveItemAtURL:location
                                 toURL:[NSURL fileURLWithPath:zipPath]
                                 error:&err];                      // 0x100180DBC / setDownloaded: 0x100180DDC
    if (self.downloaded) {
        NSDictionary *attr = @{ NSFilePosixPermissions: @384 };     // 0600，常量 0x100264A08
        err = nil;
        self.downloaded = [fm setAttributes:attr ofItemAtPath:zipPath error:&err];  // 0x100180E3C
    }
    if (!self.downloaded) {                                        // 0x100180E70
        self.failure = @"permissions";
        return;
    }
    if (self.progress) self.progress(100);                          // 0x100180EA0  mov w1,#0x64
}
```
外部 API：`-[NSURLSessionTask response]`、`-[NSHTTPURLResponse statusCode]`、`objc_opt_class`、`objc_opt_isKindOfClass`、`-[NSURL getResourceValue:forKey:error:]`、`-[NSNumber longLongValue]`、`PDAssetStatePath`、`+[NSFileManager defaultManager]`、`-[NSFileManager fileExistsAtPath:/removeItemAtPath:error:/moveItemAtURL:toURL:error:/setAttributes:ofItemAtPath:error:]`、`+[NSURL fileURLWithPath:]`、`+[NSDictionary dictionaryWithObjects:forKeys:count:]`、`___stack_chk_fail`。

#### 4.7.4 `didCompleteWithError:`

```objc
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        didCompleteWithError:(NSError *)error;   // 0x100180F14，44 条
```
作用：收尾，保证等待线程一定被唤醒。

```objc
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        didCompleteWithError:(NSError *)error
{
    if (error != nil || !self.downloaded) {          // 0x100180F4C / 0x100180F58
        if (self.failure == nil) self.failure = @"download-failed";   // 0x100180F70-F80
    }
    [session finishTasksAndInvalidate];              // 0x100180F88
    dispatch_semaphore_signal(self.finished);        // 0x100180F9C
}
```
外部 API：`-[PDAssetDownloader downloaded/failure]`、`-[NSURLSession finishTasksAndInvalidate]`、`dispatch_semaphore_signal`。

#### 4.7.5 存取器与析构

`root`(0x10)、`failure`(0x18)、`session`(0x20)、`task`(0x28)、`finished`(0x30)、`progress`(0x38,copy)、`downloaded`(0x08,BOOL+`strb`)、`lastProgress`(0x40,整型) 全部 2–3 条指令，直接读写偏移；`-dcxx_destruct` 见 §3.3。外部 API：`objc_setProperty_nonatomic_copy`、`objc_storeStrong`。

---

### 4.8 `PDDownloadAssetArchive`

```c
NSError *PDDownloadAssetArchive(NSString *stateDir, NSURL *url, void (^progress)(NSInteger));
// 0x1001810B0，142 条；返回 nil 表示成功，否则为 failure 描述（字符串，非 NSError 实例）
```
作用：一次性的「同步下载」封装——建 session、建任务、`dispatch_semaphore_wait` 阻塞等回调，回调线程负责落盘，主线程只读结果。

```c
NSError *PDDownloadAssetArchive(NSString *stateDir, NSURL *url, void (^progress)(NSInteger))
{
    PDAssetDownloader *d = [PDAssetDownloader new];        // 0x1001810F0
    d.root         = stateDir;                             // 0x1001810FC setRoot:
    d.progress     = progress;                             // 0x10018110C setProgress:（copy）
    d.lastProgress = -1;                                   // 0x10018111C
    d.finished     = dispatch_semaphore_create(0);         // 0x100181124
    d.finished     = d.finished;                           // 0x100181134 setFinished:

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration]; // 0x100181144
    cfg.URLCache              = nil;                       // 0x100181154
    cfg.requestCachePolicy    = 1;                         // 0x100181160 == NSURLRequestReloadIgnoringLocalCacheData
    cfg.timeoutIntervalForRequest  = 45.0;                 // 0x1001C9CE0
    cfg.timeoutIntervalForResource = 600.0;                // 0x1001C9CE8
    cfg.HTTPShouldSetCookies  = NO;                        // 0x10018118C
    cfg.HTTPCookieStorage     = nil;                       // 0x100181198
    cfg.URLCredentialStorage  = nil;                       // 0x1001811A4

    NSOperationQueue *q = [NSOperationQueue new];          // 0x1001811B0
    q.maxConcurrentOperationCount = 1;                     // 0x1001811BC
    d.session = [NSURLSession sessionWithConfiguration:cfg delegate:d delegateQueue:q];  // 0x1001811D4

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];   // 0x1001811FC
    [req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];      // 0x100181220（value=identity 即「不要压缩」）

    d.task = [d.session downloadTaskWithRequest:req];       // 0x100181238
    [d.task resume];                                        // 0x100181268
    dispatch_semaphore_wait(d.finished, DISPATCH_TIME_FOREVER);   // 0x100181284

    NSError *failure = d.failure;                           // 0x100181290
    d.task = nil; d.session = nil; d.progress = nil;        // 0x1001812A4/12B0/12BC
    return failure;                                        // 0x1001812E4 autoreleaseReturnValue
}
```
外部 API：`objc_opt_new`、`dispatch_semaphore_create/wait`、`+[NSURLSessionConfiguration ephemeralSessionConfiguration]`、`-[NSURLSessionConfiguration setURLCache:/setRequestCachePolicy:/setTimeoutIntervalForRequest:/setTimeoutIntervalForResource:/setHTTPShouldSetCookies:/setHTTPCookieStorage:/setURLCredentialStorage:]`、`+[NSOperationQueue new]`、`-[NSOperationQueue setMaxConcurrentOperationCount:]`、`+[NSURLSession sessionWithConfiguration:delegate:delegateQueue:]`、`+[NSMutableURLRequest requestWithURL:]`、`-[NSMutableURLRequest setValue:forHTTPHeaderField:]`、`-[NSURLSession downloadTaskWithRequest:]`、`-[NSURLSessionDownloadTask resume]`。

> 注：返回值语义是「成功返回 nil」。调用方按 `if (err) → 失败` 使用，与 `NSError**` 习惯相反，重写时别搞混。

---

### 4.9 `PDRunAssetRequestWithProgress`（主干）

```c
NSDictionary *PDRunAssetRequestWithProgress(NSDictionary *request,
                                           void (^report)(NSDictionary *dict));
// 0x1001812E8 .. 0x100183CFC，2693 条
```
作用：资产子系统唯一入口。**同步**执行一条资产操作，阶段与进度通过 `report` 回调（参数是「进度字典」，不是数字）向外播报；返回值是结果字典。

#### 4.9.1 主干伪代码（按基本块归纳，非逐条转写）

```objc
NSDictionary *PDRunAssetRequestWithProgress(NSDictionary *request, void (^report)(NSDictionary *))
{
    @autoreleasepool {                                                       // 0x10018132C
        // ── ① 入口校验 ───────────────────────────────────────────────
        static NSArray *kOps = @[@"check", @"install", @"prepare", @"import", @"remove"]; // 0x100264C08
        if (![request isKindOfClass:[NSDictionary class]] ||                 // 0x100181348
            ![kOps containsObject:request[@"operation"]])                    // 0x100181374
            return PDAssetError(@"request");                                 // 0x1001813F8

        NSString *op       = request[@"operation"];
        BOOL      isRemove = [op isEqual:@"remove"];                         // 0x1001813A4 → sp+0x2C
        BOOL      isImport = [op isEqual:@"import"];                         // 0x100181908

        // ── ② 定位 bundle 根（可执行文件 realpath 上溯两级 + /PetDFY.bundle）──
        uint32_t sz = 0; char *exe = NULL;
        _NSGetExecutablePath(NULL, &sz);                                     // 0x1001813BC
        exe = calloc(sz, 1);                                                 // 0x1001813C8
        NSString *bundleRoot = nil;
        if (exe && _NSGetExecutablePath(exe, &sz) == 0) {                     // 0x1001813D8
            NSString *p = [[NSString stringWithUTF8String:exe] stringByResolvingSymlinksInPath];
            bundleRoot  = [[[p stringByDeletingLastPathComponent]
                              stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent:@"PetDFY.bundle"];   // 0x10018145C
        }
        free(exe);

        NSDictionary *spec = PDAssetSpecification(bundleRoot);                // 0x10018147C → sp+0x30
        // 无根 或 (无 spec 且 不是 remove) → 失败
        if (!bundleRoot || (!spec && !isRemove))                              // 0x100181498/0x10018149C
            return PDAssetError(@"specification");                            // 0x1001817C4

        // ── ③ 读 manifest，建立「声明文件表」────────────────────────────
        NSString *manifestPath = [bundleRoot stringByAppendingPathComponent:@"asset-manifest.json"];
        if (!isRemove && !PDAssetRegularPath(bundleRoot, @"asset-manifest.json", NO))
            return PDAssetError(@"manifest");                                 // 0x1001814D4 → 0x1001818AC
        NSDictionary *manifest = PDReadJSONObject(manifestPath);              // 0x1001814DC helper
        NSDictionary *files    = manifest[@"files"];                          // 0x1001814F4
        if (isRemove) files = @{};                                            // 0x100181510

        NSMutableDictionary *store = [NSMutableDictionary new];               // 0x100181524 → sp+0x10
        for (NSString *rel in files) {                                        // 0x100181550
            NSString *top = [[rel componentsSeparatedByString:@"/"] firstObject];
            if (!PDAssetSafeRelativePath(rel))                       return PDAssetError(@"manifest");
            if (![@[@"originals",@"live",@"licenses"] containsObject:top]) return PDAssetError(@"manifest");
            id v = files[rel];
            // 逐条登记（值类型校验、licenses 分支略）       ← 归纳段，见 §4.9.4 注
            store[rel] = v;
        }

        // ── ④ 建状态目录 + 抢锁 ─────────────────────────────────────
        NSString *stateDir = PDAssetStatePath(bundleRoot);                    // 0x1001816A4
        // 前置：PDAssetRegularPath(bundleRoot, ".asset-state", YES) 保证目录存在
        NSString *lockPath = [stateDir stringByAppendingPathComponent:@"install.lock"];  // 0x1001816B8
        int fd  = open(lockPath.fileSystemRepresentation, /*O_CREAT|O_RDWR*/ 0x602, 0600); // 0x1001816D8
        int rc  = flock(fd, LOCK_EX | LOCK_NB);                               // 0x100181720
        while (rc != 0 && errno == EWOULDBLOCK) {                              // 0x100181734..
            usleep(50 * 1000);                                                // 0x100181768
            rc = flock(fd, LOCK_EX);                                          // 0x100181774
        }
        if (rc != 0) { close(fd); return PDAssetError(@"busy"); }              // 0x100181948

        // ── ⑤ 阶段分派 ──────────────────────────────────────────────
        NSDictionary *result = isImport
            ? PDImportFlow     (request, bundleRoot, stateDir, lockPath, spec, store, report)  // 0x100182424
            : PDCheckOrInstall (request, bundleRoot, stateDir, lockPath, spec, store, report); // 0x100182828
        if (!result) result = PDAssetError(@"install");                        // 0x10018198C

        // ── ⑥ 结果 → 状态文件/进度回调 ──────────────────────────────
        if ([result[@"type"] isEqual:@"error"])
            PDWriteStatus(stateDir, result[@"stage"], 0, report);              // 0x1001819F0
        else if ([result[@"ready"] boolValue])
            PDWriteStatus(stateDir, @"ready", 100, report);                    // 0x100181A38
        else if (isRemove)
            PDWriteStatus(stateDir, @"removed", 0, report);                    // 0x100181A5C

        // ── ⑦ 清理 ─────────────────────────────────────────────────
        [[NSFileManager defaultManager] removeItemAtPath:lockPath error:NULL];  // 0x100181A7C
        if (![op isEqual:@"check"])                                            // 0x100181AA4
            [[NSFileManager defaultManager]
                removeItemAtPath:[stateDir stringByAppendingPathComponent:@"download.zip"]
                         error:NULL];                                          // 0x100181AE8
        flock(fd, LOCK_UN); close(fd);                                          // 0x100181AFC/0x100181B04
        return result;
    }
    // @catch(NSException) → return PDAssetError(@"install")                    // 0x100181BA4..0x100181BC4
}
```

#### 4.9.2 阶段机（状态取值与触发点，全部 Observed）

| stage | 写入点 | progress | 触发条件 |
|---|---|---|---|
| `request` | 0x1001813F8 | — | request 不是字典 / operation 不在白名单 |
| `specification` | 0x1001817C4 | — | 无 bundle 根，或 install 系操作缺 `asset-spec.json` / `schema != 1` |
| `manifest` | 0x10018186C / 0x1001818AC / 0x1001818C4 / 0x1001818DC | — | manifest 缺失、路径非法、顶层目录不在白名单 |
| `busy` | 0x10018194C | — | `flock` 抢锁失败 |
| `checking` | 0x100182950 | 0 | 进入 check 分支 |
| `downloading` | 0x100182A48（起始）+ 0x100183C9C（每 10% 一次） | 0…99 | URL 合法且需要下载 |
| `needs-url` / `invalid-url` | 0x100182AC8 / 0x100182AD4 | — | 缺 `url` / `url` 净化失败 |
| `download-failed` | `PDAssetDownloader` 0x100180F80 | — | 传输层错误 |
| `permissions` | 0x100180EB0 / 0x100183450 | — | 落盘/改名/chmod 失败 |
| `archive` | 0x100183438 | — | zip 打不开（`mz_zip_reader_open_file` 失败或遍历出错） |
| `unpack` | 0x1001834D0 | — | 解包中途失败 |
| `importing` | 0x1001825F8 | 0 | import 分支开始拷贝 |
| `installing` | 0x100182694 / 0x1001828D4 | 0 | 进入安装 |
| `removing` | 0x100181EE8 | 0 | 清理旧的 import 暂存 |
| `ready` | 0x100181A38 | 100 | 结果 `ready == YES` |
| `removed` | 0x100181A5C | 0 | remove 成功 |

> `remove` / `install` / `import` / `check` / `prepare` 同时是 **operation 取值**与 **失败 stage 名**（如 `remove` 失败回落成 `PDAssetError(@"remove")`，见 0x100182320/0x10018234C/0x100182368）。重写时这两套语义要分开存放。

#### 4.9.3 内部 helper 清单（同一地址区间内的 static 函数 / block）

| 地址 | 拟名 | 作用 | 外部 API 要点 |
|---|---|---|---|
| 0x100181BF0 | `PDAssetError(NSString *stage)` | 造错误字典 `{type:error, domain:"PetDFY.Assets", code:@1, stage:stage}` | `+[NSDictionary dictionaryWithObjects:forKeys:count:]` |
| 0x100181CB8 | `PDReadJSONObject(NSString *path)` | 读文件 → JSON → 必须是 NSDictionary，否则 nil | `+[NSData dataWithContentsOfFile:]`、`+[NSJSONSerialization JSONObjectWithData:options:error:]`、`objc_opt_isKindOfClass` |
| 0x100181D50 | `PDCleanupStale(stateDir, stagingPath, request, spec, report)` | 清理历史 import 暂存：枚举 `importTokens` / `AssetImports`、删 `<uuid>.zip`、删 `*.partial`、`removing` 阶段播报、失效 `ready.json` | `contentsOfDirectoryAtPath:error:`、`PDAssetImportPath`、`removeItemAtPath:error:`、`lstat`、`unlink`、`PDAssetRegularPath` |
| 0x100182424 | `PDImportFlow(request, root, stateDir, lockPath, spec, store, report)` | import 分支：校验 `imported.json` 的 token → 拷 `download.zip` 到 `<AssetImports>/<uuid>.zip/` → `chmod 0600` → 转 `PDCheckOrInstall` | `copyItemAtPath:toPath:error:`、`chmod`、`PDAssetImportPath`、`PDReadJSONObject` |
| 0x100182828 | `PDCheckOrInstall(request, root, stateDir, lockPath, spec, store, report)` | check / prepare / install / remove 主分流：install → `installing` 后直接解包安装；否则 `checking` → 校验 → 需要则 `downloading` → 解包安装 | `PDWriteStatus`、`PDDownloadAssetArchive`、`PDAssetDownloadURL`、`unlink` |
| 0x100182CE0 | `PDUnpackAndInstall(request, root, stateDir, spec, store, report)` | 解包 + 安装 + 校验 + 写 `ready.json` 的复合流程（见 §4.9.5） | miniz 全套、`NSFileManager`、`mkdir`、`rename`、`chmod` |
| 0x10018356C | `PDInstallFiles(root, stagingDir, dict)` | 把暂存目录里的文件按表落到 `originals/live` 等真实目录：建父目录（`0700`）、`chmod`、`rename` | `enumeratorAtPath:`、`componentsSeparatedByString:`、`mkdir`、`rename`、`chmod`、`PDAssetRegularPath` |
| 0x10018394C | `PDVerifyInstalled(root, store)` | 逐个 `lstat` 校验落地结果，返回 BOOL | `lstat`、`PDAssetRegularPath` |
| 0x100183ADC | `PDWriteReadyJSON(root, spec)` | 写 `<.asset-state>/ready.json` = `{asset_version: spec[@"asset_version"]}` | `+[NSJSONSerialization dataWithJSONObject:options:error:]`、`writeToFile:options:error:` |
| 0x100183BF0 | `PDIsManagedTexture(NSString *rel)` | 判断是否「必须存在的两张探针资源」：`originals/props/toy-ball.png`，或前缀 `originals/outfits/jk-sailor/` 且扩展名 `png` | `isEqual:`、`hasPrefix:`、`pathExtension`、`lowercaseString` |
| 0x100182B1C | `PDWriteStatus(stateDir, stage, progress, report)` | 写 `status.json` 并回调 `report`（见 §4.9.6） | 见下 |

#### 4.9.4 manifest 登记段（0x1001815D8–0x10018166C，归纳）

`Observed`：对 `files` 每个键做「以 `/` 切分取首段 → 是否在 `@[originals, live, licenses]` → 取 `files[rel]` → 值类型判断（`objc_opt_isKindOfClass`）→ `licenses` 分支特殊处理（0x10018160C）→ `setObject:forKeyedSubscript:`（0x100181638）」。完成后 `store.count` 参与后续比对（0x100181680/0x100182018 段）。
`Assumed:` 值类型是 NSString（尺寸/摘要）或 NSNumber，`licenses` 走独立登记键；该段不改变「路径白名单 + 存在性」这一主干语义，重写时按 `NSDictionary<NSString*, id>` 保存即可。

#### 4.9.5 解包段（0x100182CE0–0x100183560，miniz，归纳）

```c
// 前置
zipPath = [stateDir stringByAppendingPathComponent:@"download.zip"];        // 0x100182D70
if (!PDAssetRegularPath(stateDir, @"download.zip", NO)) return PDAssetError(@"unpack");  // 0x100182D88
lstat(zip); 若已存在旧的 unpacking/ 或文件占位 → NSFileManager removeItemAtPath:      // 0x100182DD4

// 暂存目录（0700）
mkdir(stateDir/unpacking);                                                 // 0x100182E28 createDirectoryAtPath:…

mz_zip_archive zip = {0};
mz_zip_reader_create(&zip);                                                // 0x100182E58
if (!mz_zip_reader_open_file(&zip, zipPath.fileSystemRepresentation))      // 0x100182E9C
    return PDAssetError(@"archive");
int st = mz_zip_reader_goto_first_entry(&zip);                             // 0x100182EB0
while (st == MZ_OK) {                                                      // 0x100182EC8
    @autoreleasepool {
        mz_zip_archive_file_stat info;
        if (!mz_zip_reader_entry_get_info(&zip, &info)) { st = MZ_ERROR; break; }   // 0x100182EDC
        BOOL isDir = mz_zip_reader_entry_is_dir(&zip);                     // 0x100182EFC
        NSString *name = [[NSString alloc] initWithBytes:info.m_filename
                                                  length:strlen(info.m_filename)
                                                encoding:NSUTF8StringEncoding];  // 0x100182F20
        if ([name hasSuffix:@"/"]) name = [name substringToIndex:name.length - 1];  // 0x100182F38

        if (!PDAssetSafeRelativePath(name))                     goto next;  // 0x100182F78
        if ([kReservedNames containsObject:name])               goto next;  // 0x100182F88（保留名，Assumed: @[ready.json,imported.json,download.zip,unpacking]）
        if ((info.m_external_attr & 0x00010000) /* dos dir 位 */) goto next;  // 0x100182F98
        if (info.m_external_attr >> 16) {                                  // 0x100182F9C
            // 有 UNIX 权限位时按类型过滤，见下
        }
        if (mz_zip_attrib_is_symlink(info.m_external_attr, info.m_version_made_by))  // 0x100182FB4
            goto next;                                                     // 挡符号链接条目

        uint32_t want = isDirLike ? 0040000 : 0100000;                     // 0x100182FC8/0x100182FD0
        uint32_t have = (info.m_external_attr >> 16) & 0xF000;             // 0x100182FD4
        if (have != 0 && have != want) goto next;                          // 0x100182FDC

        if (store[name] == nil && !PDIsManagedTexture(name))                // 0x100182FF4/0x10018300C
            goto notInManifest;                                            // 0x100183218

        // 仅当是文件且未压缩大小 >= 1 才写盘
        if (info.m_uncomp_size < 1) goto next;                             // 0x100183024
        NSString *dst    = [stagingDir stringByAppendingPathComponent:name];   // 0x100183038
        NSString *parent = [dst stringByDeletingLastPathComponent];            // 0x100183044
        [fm createDirectoryAtPath:parent withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions:@448} error:NULL]; // 0x10018308C（0700）
        int fd = open(dst.fileSystemRepresentation, O_CREAT|O_WRONLY|O_TRUNC, 0600);  // 0x1001830DC
        mz_zip_reader_entry_open(&zip);                                    // 0x1001830EC
        char buf[65536];                                                   // mov w2,#0x10000
        int n;
        while ((n = mz_zip_reader_entry_read(&zip, buf, 0x10000)) > 0)      // 0x100183108/0x100183184
            write(fd, buf, n);                                             // 0x10018314C
        close(fd);                                                         // 0x1001831B0
        mz_zip_reader_entry_close(&zip);                                   // 0x1001831B8
        [written addObject:name];                                          // 0x10018322C
    }
next:
    st = mz_zip_reader_goto_next_entry(&zip);                              // 0x100183234
}
if (st != MZ_END_OF_LIST) { close; mz_zip_reader_delete; return PDAssetError(@"archive"); }  // 0x100183250/0x1001834A8
mz_zip_reader_close(&zip); mz_zip_reader_delete(&zip);                     // 0x100183270/0x100183278

unlink(stateDir/ready.json);                                               // 0x1001832C0（安装前先失效旧标记）
PDInstallFiles(root, stagingDir, dict);                                    // 0x1001832D4
PDVerifyInstalled(...);                                                    // 0x100183408
PDWriteReadyJSON(...);                                                     // 0x10018341C
```
`Assumed:` 上面 `isDirLike`/`want` 的映射方向（`0x4000` 对目录、`0x8000` 对常规文件）来自 0x100182FC8 的 `csel`，`w26` 来源未逐条追到；`m_external_attr & 0x10000` 视为 DOS 目录位。缓冲区 65536 与 `MZ_END_OF_LIST == -100`（`cmn w25,#0x64`）为 `Observed`。
外部 API：`mz_zip_reader_create/open_file/goto_first_entry/entry_get_info/entry_is_dir/entry_open/entry_read/entry_close/goto_next_entry/close/delete`、`mz_zip_attrib_is_symlink`、`open/write/close/lstat/unlink/mkdir/rename/chmod`、`+[NSFileManager defaultManager]`、`-[NSFileManager createDirectoryAtPath:withIntermediateDirectories:attributes:error:/removeItemAtPath:error:/enumeratorAtPath:]`、`+[NSString stringWithUTF8String:]`、`-[NSString initWithBytes:length:encoding:/hasSuffix:/substringToIndex:/stringByAppendingPathComponent:/stringByDeletingLastPathComponent:]`。

#### 4.9.6 状态文件写入 `PDWriteStatus`

```c
void PDWriteStatus(NSString *stateDir, NSString *stage, NSInteger progress,
                   void (^report)(NSDictionary *));      // 0x100182B1C，~70 条
```
作用：把阶段写进 `status.json`（原子写），并向调用方回调一个 `asset-progress` 字典。

```c
void PDWriteStatus(NSString *stateDir, NSString *stage, NSInteger progress,
                   void (^report)(NSDictionary *))
{
    NSDictionary *d = @{ @"status": stage, @"progress": @(progress) };         // 0x100182BBC
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL]; // 0x100182BE0
    NSString *p  = [stateDir stringByAppendingPathComponent:@"status.json"];   // 0x100182BF8
    [json writeToFile:p options:NSDataWritingAtomic error:NULL];                // options=1, 0x100182C18

    if (report) {                                                              // 0x100182C20
        NSDictionary *ev = @{ @"type": @"asset-progress",
                              @"status": stage,
                              @"progress": @(progress) };                       // 0x100182C70
        report(ev);                                                            // 0x100182C88 blr
    }
}
```
外部 API：`+[NSDictionary dictionaryWithObjects:forKeys:count:]`、`+[NSNumber numberWithInteger:]`、`+[NSJSONSerialization dataWithJSONObject:options:error:]`、`-[NSData writeToFile:options:error:]`、`-[NSString stringByAppendingPathComponent:]`、`objc_retain/release`、`___stack_chk_fail`。

> 注意：`status.json` 与回调是**两套字典**——文件里只有 `status`/`progress`，回调里多一个 `type: asset-progress`。重写时别合并。

---

## 5 调用图（资产子系统）

```
main ─▶ PDRunAssetRequestWithProgress
        ├─ PDAssetSpecification ── +[NSData dataWithContentsOfFile:] / NSJSONSerialization
        ├─ PDAssetRegularPath ── PDAssetSafeRelativePath ── lstat
        ├─ PDAssetStatePath / PDAssetImportDirectory / PDAssetImportPath
        ├─ PDReadJSONObject
        ├─ PDWriteStatus                     （status.json + report 回调）
        ├─ PDImportFlow      ─▶ PDCheckOrInstall（递归回流）
        └─ PDCheckOrInstall
              ├─ PDWriteStatus(checking)
              ├─ PDVerifyInstalled / PDWriteReadyJSON
              ├─ PDAssetDownloadURL
              ├─ PDDownloadAssetArchive ─▶ PDAssetDownloader ─▶ URLSession 回调×4
              │        └─ 落地 <stateDir>/download.zip（0600）
              └─ PDUnpackAndInstall ── miniz 解包 ─▶ PDInstallFiles ─▶ PDVerifyInstalled ─▶ PDWriteReadyJSON
```

---

## 6 重写实现建议（miniz vs libarchive）

**结论：继续用 miniz（`mz_zip_reader_*`），不要换 libarchive。**

理由（按权重）：

1. **行为对齐成本最低**。原实现只用到 `create / open_file / goto_first_entry / entry_get_info / entry_is_dir / attrib_is_symlink / entry_open / entry_read / entry_close / goto_next_entry / close / delete` 这 12 个符号，全部在 miniz 单文件里，语义一一对应。libarchive 没有等价「按条目流式读 + 独立 symlink 判定」的组合，得自己搭 `archive_read_*` 状态机，还会引入 bzip2/lzma 等无用依赖。
2. **体积与许可**。miniz 是单文件 + MIT；libarchive 静态链入要 300KB+ 且需处理 `archive_entry_*` 的一堆属性。目标是个 iOS 命令行 helper，二进制尺寸敏感。
3. **安全语义可控**。本项目真正防穿越的不是解包库，而是自研两道闸：`PDAssetSafeRelativePath`（拒 `..`/绝对路径/反斜杠/控制字符/超长）+ `PDAssetRegularPath`（逐段 `lstat`、拒 symlink、中间层必须目录）。换库也躲不开这两道，反而要重新对齐 miniz 的 `m_external_attr >> 16` 与 `mz_zip_attrib_is_symlink` 判定口径。
4. **可复现性**。原实现缓冲区 65536、`MZ_END_OF_LIST == -100` 的终止判定、`entry_get_info` 失败即整体失败——这些细节用 miniz 能 1:1 照抄，命令行行为（含失败 stage 名）完全一致。

实现要点清单：
- 解包**只**落到 `<stateDir>/unpacking/`，绝不直接写 `originals/`；`PDInstallFiles` 用 `rename(2)` 做同卷原子落位，避免半装状态。
- 目录一律 `0700`、zip 一律 `0600`（对应常量 `@448` / `@384`）。
- 每条目都过 `PDAssetSafeRelativePath` 与 symlink 判定，且必须命中 `manifest["files"]` 或两张探针资源（`PDIsManagedTexture`），否则跳过并计入「非清单条目」。
- `ready.json` 在安装前 `unlink`、校验通过后再写，作为「本次安装完整」的唯一凭据。
- 锁用 `flock(LOCK_EX)` + `.asset-state/install.lock`，失败即 `busy`（不要 sleep 重试到底，原实现只做一次 `usleep(50ms)` 的退让）。
- 唯一需要替代的 API 是 `_NSGetExecutablePath`：非 Apple 平台换成 `readlink("/proc/self/exe")` 或 `realpath(getprogname())`，语义等价（realpath → dirname ×2 → `/PetDFY.bundle`）。

---

## 7 未决项 / 需要实测的点

| # | 事项 | 等级 | 建议验证动作 |
|---|---|---|---|
| 1 | `__objc_intobj` 三常量与地址的对应（`0600`/`@1`/`0700` 三个值的排布）按 24 字节步长推断 | Inferred | `nm`/`lldb` 打印 `0x100264A20` 处 `NSNumber.integerValue` |
| 2 | 解包条目过滤里 `w26`（期望文件/目录类型来源） | Assumed | 断点 0x100182FC8，检查 `w26` 与 `entry_is_dir` 返回值关系 |
| 3 | `open(lockPath, flags, 0600)` 的 flags 具体值 | Assumed | 断点 0x1001816D8 读 `x1` |
| 4 | manifest 登记段的值类型与 `licenses` 分支语义 | Assumed | 断点 0x10018160C 观察 `store` 内容 |
| 5 | `<AssetImports>/<uuid>.zip` 是目录还是文件 | Assumed（判为目录） | 真机跑一次 import，`ls -la` 该路径 |
| 6 | 成功结果字典是否含 `asset_version` 之外的字段 | Assumed | 断点 0x1001819F0 前打印 `x25` |
| 7 | 未在真机/模拟器运行任何代码，本文全部结论来自静态读码 | NOT RUN | 用 §4 伪代码写最小复现工程后可对拍 `status.json` |

## 8 证据索引

| 结论 | 地址 |
|---|---|
| operation 白名单 | 0x10018136C（数组 0x100264C08，5 元素） |
| bundle 根推导 | 0x1001813B4–0x100181474 |
| spec 校验 | 0x100183DB0（`schema != 1`）、0x100183E14（空 `asset_version`） |
| manifest 顶层白名单 | 0x1001815BC（数组 0x100264C20） |
| 锁 | 0x1001816D8 open / 0x100181720 flock / 0x100181948 `busy` / 0x100181AFC `LOCK_UN` |
| 下载 | 0x1001810B0（PDDownloadAssetArchive）、0x100180C50（落盘 + 0600） |
| 解包 | 0x100182E58（miniz create）、0x100183104（`#0x10000` 缓冲）、0x100183250（`-100` 终止） |
| 探针资源 | 0x100183BF0（`toy-ball.png` / `jk-sailor` + `png`） |
| 状态写盘 | 0x100182B1C（`status.json` + `asset-progress`） |
| 阶段播报点 | 0x100182950 / 0x100182A48 / 0x100182694 / 0x1001825F8 / 0x100181EE8 / 0x100181A38 / 0x100181A5C |
