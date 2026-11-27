//
//  PDAssetImporter.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  Fidelity note: the path helpers, the specification/URL validation and the
//  stage machine are transcribed from the disassembly (see out/notes/asset.md,
//  sections 4.3-4.9).  The per-entry manifest bookkeeping and the unzip loop are
//  reproduced behaviourally: the shipped helper used miniz (mz_zip_reader_*),
//  64 KiB buffers and mz_zip_attrib_is_symlink(); this file keeps that shape.
//  Build with vendor/miniz/miniz.c dropped next to it.
//

#import "PDAssetImporter.h"
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

#import "miniz.h"

NSString *const PDAssetErrorDomain = @"PetDFY.Assets";
NSString *const PDAssetImportRoot =
    @"/var/mobile/Library/Application Support/PetDFY/AssetImports";

static NSString *const kPDStateDirName = @".asset-state";
static NSString *const kPDLockName = @"install.lock";
static NSString *const kPDArchiveName = @"download.zip";
static NSString *const kPDUnpackDirName = @"unpacking";
static NSString *const kPDReadyName = @"ready.json";
static NSString *const kPDStatusName = @"status.json";
static NSString *const kPDSpecName = @"asset-spec.json";
static NSString *const kPDManifestName = @"asset-manifest.json";

static NSString *const kPDStagePermissions = @"permissions";
static NSString *const kPDStageBusy = @"busy";
static NSString *const kPDStageChecking = @"checking";
static NSString *const kPDStageDownloading = @"downloading";
static NSString *const kPDStageArchive = @"archive";
static NSString *const kPDStageUnpack = @"unpack";
static NSString *const kPDStageImporting = @"importing";
static NSString *const kPDStageInstalling = @"installing";
static NSString *const kPDStageRemoving = @"removing";
static NSString *const kPDStageReady = @"ready";
static NSString *const kPDStageRemoved = @"removed";
static NSString *const kPDStageManifest = @"manifest";
static NSString *const kPDStageSpecification = @"specification";
static NSString *const kPDStageRequest = @"request";
static NSString *const kPDStageInstall = @"install";

static NSDictionary *PDAssetResult(BOOL ready) {
    // 常量字典 0x100264d10 / 0x100264d38 / 0x100264d60 / 0x100264d88 / 0x100264dd8 都是
    // { @"ready": <__kCFBooleanTrue/False>, @"type": @"asset-result" }。
    return @{ @"ready": @(ready), @"type": @"asset-result" };
}

static NSDictionary *PDAssetError(NSString *stage) {
    return @{
        @"type": @"error",
        @"domain": PDAssetErrorDomain,
        @"code": @1,
        @"stage": stage ?: kPDStageInstall,
    };
}

#pragma mark - path helpers

BOOL PDAssetSafeRelativePath(NSString *relative) {
    if (![relative isKindOfClass:[NSString class]]) {
        return NO;
    }
    if (relative.length == 0 || relative.length > 0x200) {
        return NO;
    }
    if (relative.isAbsolutePath) {
        return NO;
    }
    if ([relative containsString:@"\\"]) {
        return NO;
    }
    if ([relative rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        return NO;
    }
    for (NSString *component in [relative componentsSeparatedByString:@"/"]) {
        if (component.length == 0 || [component isEqual:@"."] || [component isEqual:@".."]) {
            return NO;
        }
    }
    return YES;
}

BOOL PDAssetRegularPath(NSString *root, NSString *relative, BOOL wantDirectory) {
    if (!PDAssetSafeRelativePath(relative)) {
        return NO;
    }
    NSArray<NSString *> *components = [relative componentsSeparatedByString:@"/"];
    if (components.count == 0) {
        return YES;
    }
    NSString *path = root;
    struct stat info;
    for (NSUInteger i = 0; i < components.count; i++) {
        path = [path stringByAppendingPathComponent:components[i]];
        if (lstat(path.fileSystemRepresentation, &info) != 0) {
            return NO;
        }
        mode_t type = info.st_mode & S_IFMT;
        if (type == S_IFLNK) {
            return NO;                                  // never follow a link
        }
        BOOL last = (i + 1 == components.count);
        if (!last) {
            if (type != S_IFDIR) {
                return NO;
            }
        } else if (wantDirectory) {
            if (type != S_IFDIR) {
                return NO;
            }
        } else if (type != S_IFREG) {
            return NO;
        }
    }
    return YES;
}

NSString *PDAssetStatePath(NSString *bundleRoot) {
    return [bundleRoot stringByAppendingPathComponent:kPDStateDirName];
}

NSString *PDAssetImportDirectory(void) {
    return PDAssetImportRoot;
}

NSString *PDAssetImportPath(NSString *token) {
    // 0x100183e64: 先 [[NSUUID alloc] initWithUUIDString:token] 校验，非法返回 nil。
    if (![token isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:token];
    if (uuid == nil) {
        return nil;
    }
    NSString *name = [token stringByAppendingPathExtension:@"zip"];
    return [PDAssetImportRoot stringByAppendingPathComponent:name];
}

#pragma mark - validation helpers

static NSDictionary *PDReadJSONDictionary(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:[NSDictionary class]] ? (NSDictionary *)object : nil;
}

NSDictionary *PDAssetSpecification(NSString *bundleRoot) {
    if (bundleRoot == nil) {
        return nil;
    }
    NSDictionary *spec = PDReadJSONDictionary([bundleRoot stringByAppendingPathComponent:kPDSpecName]);
    if (spec == nil) {
        return nil;
    }
    if ([spec[@"schema"] integerValue] != 1) {
        return nil;
    }
    id version = spec[@"asset_version"];
    if (![version isKindOfClass:[NSString class]] || [version length] == 0) {
        return nil;
    }
    return spec;
}

NSURL *PDAssetDownloadURL(NSString *string) {
    if (![string isKindOfClass:[NSString class]]) {
        return nil;
    }
    if (string.length == 0 || string.length > 0x2000) {
        return nil;
    }
    if ([string rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
        return nil;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:string];
    NSString *scheme = [components.scheme lowercaseString];
    if (![@[@"http", @"https"] containsObject:scheme]) {
        return nil;
    }
    if (components.host.length == 0 || components.user.length != 0 ||
        components.password.length != 0 || components.fragment.length != 0) {
        return nil;
    }
    return components.URL;
}

static NSString *PDBundleRoot(void) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *buffer = calloc(size, 1);
    if (buffer == NULL) {
        return nil;
    }
    NSString *root = nil;
    if (_NSGetExecutablePath(buffer, &size) == 0) {
        NSString *path = [[NSString stringWithUTF8String:buffer] stringByResolvingSymlinksInPath];
        root = [[[path stringByDeletingLastPathComponent]
                 stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:@"PetDFY.bundle"];
    }
    free(buffer);
    return root;
}

#pragma mark - status file

static void PDWriteStatus(NSString *stateDir, NSString *status, NSInteger progress,
                          void (^report)(NSDictionary *)) {
    NSDictionary *payload = @{ @"status": status ?: @"", @"progress": @(progress) };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSString *path = [stateDir stringByAppendingPathComponent:kPDStatusName];
    [json writeToFile:path atomically:YES];      // 0x100182be0: 原子写，无 chmod
    if (report != nil) {
        // 0x100182c28: 进度事件带 type = "asset-progress"
        report(@{ @"type": @"asset-progress", @"status": status ?: @"", @"progress": @(progress) });
    }
}

#pragma mark - downloader

// 逐条对齐 PDAssetDownloader（0x1001809c8 / 0x100180b4c / 0x100180c50 / 0x100180f14）。

@interface PDAssetDownloader : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, assign) BOOL downloaded;              // 0x08
@property (nonatomic, copy) NSString *root;                 // 0x10  bundle 根（binary: C,N）
@property (nonatomic, copy) NSString *failure;              // 0x18  失败阶段名（binary: C,N）
@property (nonatomic, strong) NSURLSession *session;        // 0x20
@property (nonatomic, strong) NSURLSessionDownloadTask *task;   // 0x28
@property (nonatomic, strong) dispatch_semaphore_t finished;    // 0x30
@property (nonatomic, copy) void (^progress)(NSInteger percent); // 0x38
@property (nonatomic, assign) NSInteger lastProgress;       // 0x40
@end

@implementation PDAssetDownloader

// 只放行「仍是合法直链、且不 https->http 降级」的重定向。
- (void)URLSession:(NSURLSession *)session
                 task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)newRequest
 completionHandler:(void (^)(NSURLRequest *_Nullable))completionHandler {
    NSURL *allowed = PDAssetDownloadURL(newRequest.URL.absoluteString);
    BOOL downgrade = NO;
    NSString *originalScheme = [task.originalRequest.URL.scheme lowercaseString];
    if ([originalScheme isEqual:@"https"]) {
        downgrade = ![[newRequest.URL.scheme lowercaseString] isEqual:@"https"];
    }
    completionHandler((allowed != nil && !downgrade) ? newRequest : nil);
}

// 百分比封顶 99，且每跨一个 10% 台阶才回调一次。
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSInteger percent = 0;
    if (totalBytesExpectedToWrite >= 1) {
        double value = (double)totalBytesWritten * 100.0 / (double)totalBytesExpectedToWrite;
        value = fmax(value, 0.0);
        value = fmin(value, 99.0);
        percent = (NSInteger)value;
    }
    if (percent / 10 == self.lastProgress / 10 && self.lastProgress >= 0) {
        return;
    }
    self.lastProgress = percent;
    void (^callback)(NSInteger) = self.progress;
    if (callback != nil) {
        callback(percent);
    }
}

// HTTP 200 且文件非空 → 搬到 <bundle>/.asset-state/download.zip，0600，最后回调 100。
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSHTTPURLResponse *http = (id)downloadTask.response;
    if (![http isKindOfClass:[NSHTTPURLResponse class]]) {
        return;
    }
    if (http.statusCode != 200) {
        return;
    }
    id size = nil;
    [location getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    if ([size longLongValue] < 1) {
        return;
    }

    NSString *stateDir = PDAssetStatePath(self.root);
    NSString *zipPath = [stateDir stringByAppendingPathComponent:kPDArchiveName];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    if ([manager fileExistsAtPath:zipPath]) {
        if (![manager removeItemAtPath:zipPath error:&error]) {
            self.failure = kPDStagePermissions;
            return;
        }
    }
    self.downloaded = [manager moveItemAtURL:location toURL:[NSURL fileURLWithPath:zipPath] error:&error];
    if (self.downloaded) {
        error = nil;
        self.downloaded = [manager setAttributes:@{NSFilePosixPermissions: @0600}
                                    ofItemAtPath:zipPath
                                           error:&error];
    }
    if (!self.downloaded) {
        self.failure = kPDStagePermissions;
        return;
    }
    if (self.progress != nil) {
        self.progress(100);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (error != nil || !self.downloaded) {
        if (self.failure == nil) {
            self.failure = @"download-failed";
        }
    }
    [session finishTasksAndInvalidate];
    dispatch_semaphore_signal(self.finished);
}

@end

/// Returns the failure stage name (nil on success), matching PDDownloadAssetArchive.
static NSString *PDDownloadAssetArchive(NSString *bundleRoot, NSURL *url, void (^progress)(NSInteger)) {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 45.0;
    configuration.timeoutIntervalForResource = 600.0;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;

    NSOperationQueue *operationQueue = [NSOperationQueue new];
    operationQueue.maxConcurrentOperationCount = 1;

    PDAssetDownloader *delegate = [PDAssetDownloader new];
    delegate.root = bundleRoot;
    delegate.progress = progress;
    delegate.lastProgress = -1;
    delegate.finished = dispatch_semaphore_create(0);
    delegate.session = [NSURLSession sessionWithConfiguration:configuration
                                                     delegate:delegate
                                                delegateQueue:operationQueue];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];   // 不要压缩

    delegate.task = [delegate.session downloadTaskWithRequest:request];
    [delegate.task resume];
    dispatch_semaphore_wait(delegate.finished, DISPATCH_TIME_FOREVER);

    NSString *failure = delegate.failure;
    delegate.task = nil;
    delegate.session = nil;
    delegate.progress = nil;
    return failure;
}

#pragma mark - unzip

/// 探针资源：即使不在 manifest 里也必须安装（0x100183bf0）
static BOOL PDIsManagedTexture(NSString *relative) {
    if ([relative isEqual:@"originals/props/toy-ball.png"]) {
        return YES;
    }
    if ([relative hasPrefix:@"originals/outfits/jk-sailor/"] &&
        [[relative pathExtension].lowercaseString isEqual:@"png"]) {
        return YES;
    }
    return NO;
}

/// 解包到 staging。返回阶段名（nil=成功）。
/// 门的顺序照 0x100182edc–0x100183218：
///   条目信息/filename → PDAssetSafeRelativePath → seen 重复 → bit_flag&1(加密)
///   → 条目注释非空 → symlink → (不在 manifest 且不是探针) 跳过并记入 seen
///   → 目录条目失败 → m_uncomp_size < 1 失败 → 写出。
static NSString *PDUnpackArchive(NSString *archive, NSString *staging, NSDictionary *store) {
    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));
    if (!mz_zip_reader_init_file(&zip, archive.fileSystemRepresentation, 0)) {
        return kPDStageArchive;
    }
    uint8_t *chunk = malloc(0x10000);
    if (chunk == NULL) {
        mz_zip_reader_end(&zip);
        return kPDStageUnpack;
    }

    NSString *stage = nil;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSFileManager *manager = [NSFileManager defaultManager];
    mz_uint count = mz_zip_reader_get_num_files(&zip);
    for (mz_uint i = 0; i < count && stage == nil; i++) {
        mz_zip_archive_file_stat info;
        if (!mz_zip_reader_file_stat(&zip, i, &info) || info.m_filename[0] == '\0') {
            stage = kPDStageUnpack;
            break;
        }
        NSString *name = [NSString stringWithUTF8String:info.m_filename];
        if (name == nil || !PDAssetSafeRelativePath(name)) {
            stage = kPDStageUnpack;
            break;
        }
        if ([seen containsObject:name]) {                  // 0x100182f8c: 重复的未登记名
            stage = kPDStageUnpack;
            break;
        }
        if ((info.m_bit_flag & 1) != 0) {                  // 0x100182f98: 加密条目
            stage = kPDStageUnpack;
            break;
        }
        if (info.m_comment[0] != '\0') {                   // 0x100182fa8: 条目注释
            stage = kPDStageUnpack;
            break;
        }
        if (((info.m_external_attr >> 16) & 0xF000) == 0xA000) {   // 0x100182fb8: symlink
            stage = kPDStageUnpack;
            break;
        }

        BOOL managed = (store[name] != nil) || PDIsManagedTexture(name);
        if (!managed) {                                    // 0x100182ff4: 跳过非清单条目
            [seen addObject:name];
            continue;
        }
        if (mz_zip_reader_is_file_a_directory(&zip, i)) {   // 0x100183014: 目录条目失败
            stage = kPDStageUnpack;
            break;
        }
        if (info.m_uncomp_size < 1) {                      // 0x100183024: 空文件失败
            stage = kPDStageUnpack;
            break;
        }

        NSString *target = [staging stringByAppendingPathComponent:name];
        // Assumed: 暂存目录的父目录用 0700 创建（二进制未定位到该调用点；最终权限由
        // PDInstallFiles 的 chmod 0644 + rename 覆盖，故不影响落位结果）。
        [manager createDirectoryAtPath:[target stringByDeletingLastPathComponent]
           withIntermediateDirectories:YES
                            attributes:@{NSFilePosixPermissions: @0700}
                                 error:NULL];
        int fd = open(target.fileSystemRepresentation,
                      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd < 0) {
            stage = kPDStageUnpack;
            break;
        }
        PDZipWriteContext context = { .fd = fd, .failed = NO };
        if (!mz_zip_reader_extract_to_callback(&zip, i, PDZipWriteCallback, &context, 0)) {
            stage = kPDStageUnpack;
        }
        close(fd);
        if (stage != nil || context.failed) {
            stage = kPDStageUnpack;
            break;
        }
    }

    free(chunk);
    mz_zip_reader_end(&zip);
    return stage;
}

#pragma mark - install / verify / ready

/// 0x1001832d4 PDInstallFiles(root, staging, store) -> BOOL
/// 逐文件：mkdir 0755（EEXIST 容错 + PDAssetRegularPath 复核）→ 目标若存在必须仍是 S_IFREG
/// → chmod(staging/rel, 0644) → rename(2) 原子落位。
static BOOL PDInstallFiles(NSString *root, NSString *staging, NSDictionary *store) {
    for (NSString *relative in store) {
        NSArray<NSString *> *components = [relative componentsSeparatedByString:@"/"];
        if (components.count < 2) {
            return NO;                                  // "<prefix>/<name>" 至少两段
        }
        NSString *accumulated = nil;
        for (NSUInteger i = 0; i + 1 < components.count; i++) {
            accumulated = accumulated ? [accumulated stringByAppendingPathComponent:components[i]]
                                      : components[i];
            NSString *directory = [root stringByAppendingPathComponent:accumulated];
            if (mkdir(directory.fileSystemRepresentation, 0755) != 0 && errno != EEXIST) {
                return NO;
            }
            if (!PDAssetRegularPath(root, accumulated, YES)) {
                return NO;                              // 目录必须是真目录、非符号链接
            }
        }

        NSString *source = [staging stringByAppendingPathComponent:relative];
        NSString *target = [root stringByAppendingPathComponent:relative];

        struct stat info;
        if (lstat(target.fileSystemRepresentation, &info) == 0) {
            if ((info.st_mode & S_IFMT) != S_IFREG) {
                return NO;                              // 目标不是常规文件 → 整包失败
            }
        }
        if (chmod(source.fileSystemRepresentation, 0644) != 0) {
            return NO;
        }
        if (rename(source.fileSystemRepresentation, target.fileSystemRepresentation) != 0) {
            return NO;
        }
    }
    return YES;
}

/// 0x10018394c PDVerifyInstalled(root, store) -> BOOL
static BOOL PDVerifyInstalled(NSString *root, NSDictionary *store) {
    for (NSString *relative in store) {
        if (!PDAssetRegularPath(root, relative, NO)) {
            return NO;
        }
        struct stat info;
        if (lstat([root stringByAppendingPathComponent:relative].fileSystemRepresentation, &info) != 0) {
            return NO;
        }
        if (info.st_size < 1) {
            return NO;
        }
    }
    return YES;
}

/// 0x100183adc PDWriteReadyJSON(stateDir, spec) -> BOOL（ready.json 只写不读）
static BOOL PDWriteReadyJSON(NSString *stateDir, NSDictionary *spec) {
    NSDictionary *payload = @{ @"asset_version": spec[@"asset_version"] ?: @"" };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (json == nil) {
        return NO;
    }
    NSString *path = [stateDir stringByAppendingPathComponent:kPDReadyName];
    return [json writeToFile:path atomically:YES];   // 只原子写，无 chmod（0x100183adc）
}

/// 解包 + 安装（0x1001832d4 起）：解包到 staging → 装清单 → 再枚举 staging 把探针资源也装上
/// → 命中数必须等于清单条数 → PDVerifyInstalled → PDWriteReadyJSON。
static NSDictionary *PDUnpackAndInstall(NSString *root, NSString *stateDir, NSString *staging,
                                        NSDictionary *spec, NSDictionary *store) {
    NSString *archive = [stateDir stringByAppendingPathComponent:kPDArchiveName];
    NSString *unpackStage = PDUnpackArchive(archive, staging, store);
    if (unpackStage != nil) {
        return PDAssetError(unpackStage);
    }
    if (!PDInstallFiles(root, staging, store)) {
        return PDAssetError(kPDStageInstall);
    }

    // 0x1001832e4: 第一次安装后枚举 staging，把探针资源收成第二个 store 再装一遍
    NSMutableDictionary<NSString *, id> *textures = [NSMutableDictionary dictionary];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSString *> *enumerator = [manager enumeratorAtPath:staging];
    BOOL isDirectory = NO;
    for (NSString *name in enumerator) {
        if ([manager fileExistsAtPath:[staging stringByAppendingPathComponent:name]
                          isDirectory:&isDirectory] && isDirectory) {
            continue;
        }
        if (PDIsManagedTexture(name)) {
            textures[name] = @YES;
        }
    }
    if (textures.count != 0 && !PDInstallFiles(root, staging, textures)) {
        return PDAssetError(kPDStageInstall);
    }

    // 0x100183298: 清单命中数必须等于 store.count
    NSUInteger installed = 0;
    for (NSString *relative in store) {
        if (PDAssetRegularPath(root, relative, NO)) {
            installed += 1;
        }
    }
    if (installed != store.count) {
        return PDAssetError(kPDStageUnpack);
    }
    if (!PDVerifyInstalled(root, store)) {
        return PDAssetError(kPDStagePermissions);
    }
    if (!PDWriteReadyJSON(stateDir, spec)) {
        return PDAssetError(kPDStagePermissions);
    }
    return PDAssetResult(YES);
}

#pragma mark - cleanup (remove)

/// 0x100181d50 PDCleanupStale(request, root, stateDir, report)
/// 注意：licenses/ 不在清理名单里，会被留下（照抄行为）。
static NSDictionary *PDCleanupStale(NSDictionary *request, NSString *root, NSString *stateDir,
                                    void (^report)(NSDictionary *)) {
    NSFileManager *manager = [NSFileManager defaultManager];
    id tokens = request[@"importTokens"] ?: @[];
    if (![tokens isKindOfClass:[NSArray class]] || [(NSArray *)tokens count] > 1000) {
        return PDAssetError(kPDStageRequest);
    }
    for (NSString *token in tokens) {
        if (PDAssetImportPath(token) == nil) {
            return PDAssetError(kPDStageRequest);
        }
    }

    PDWriteStatus(stateDir, kPDStageRemoving, 0, report);

    // 0x100181efc: 清 originals/、live/ 的子项，根目录本身保留
    for (NSString *name in @[@"originals", @"live"]) {
        if (!PDAssetRegularPath(root, name, YES)) {
            return PDAssetError(kPDStagePermissions);
        }
        NSString *base = [root stringByAppendingPathComponent:name];
        NSArray<NSString *> *children = [manager contentsOfDirectoryAtPath:base error:NULL];
        if (children == nil) {
            return PDAssetError(kPDStagePermissions);
        }
        for (NSString *child in children) {
            if (![manager removeItemAtPath:[base stringByAppendingPathComponent:child] error:NULL]) {
                return PDAssetError(@"remove");
            }
        }
    }

    // 0x1001820a0: 四个状态名，存在才删
    for (NSString *name in @[kPDReadyName, @"imported.json", kPDArchiveName, kPDUnpackDirName]) {
        NSString *path = [stateDir stringByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:path] && ![manager removeItemAtPath:path error:NULL]) {
            return PDAssetError(@"remove");
        }
    }

    // 0x1001821f4: 每个 token 的 <uuid>.zip 与其 .partial
    for (NSString *token in tokens) {
        NSString *container = PDAssetImportPath(token);
        for (NSString *path in @[container, [container stringByAppendingString:@".partial"]]) {
            struct stat info;
            if (lstat(path.fileSystemRepresentation, &info) == 0) {
                if (![manager removeItemAtPath:path error:NULL]) {
                    return PDAssetError(@"remove");
                }
            }
        }
    }
    return @{ @"ready": @NO };                          // 0x100264d10（不含 type）
}

#pragma mark - operation flows

/// `check` / `install` / `prepare`
///   0x100182828: install → installing → PDUnpackAndInstall（**不下载**，要求 download.zip 已存在）
///   check/prepare → checking → PDVerifyInstalled → 通过则重写 ready.json 并返回 ready:YES；
///   不通过则 unlink ready.json：check 直接 ready:NO，prepare 继续下载 → installing → 解包安装。
static NSDictionary *PDCheckOrInstall(NSDictionary *request, NSString *bundleRoot, NSString *stateDir,
                                      NSDictionary *spec, NSDictionary *store,
                                      void (^report)(NSDictionary *)) {
    NSString *operation = request[@"operation"];
    BOOL isInstall = [operation isEqual:@"install"];
    NSFileManager *manager = [NSFileManager defaultManager];

    if (isInstall) {
        PDWriteStatus(stateDir, kPDStageInstalling, 0, report);
        return PDUnpackAndInstall(bundleRoot, stateDir,
                                  [stateDir stringByAppendingPathComponent:kPDUnpackDirName],
                                  spec, store);
    }

    PDWriteStatus(stateDir, kPDStageChecking, 0, report);
    if (PDVerifyInstalled(bundleRoot, store)) {
        if (!PDWriteReadyJSON(stateDir, spec)) {
            return PDAssetError(kPDStagePermissions);
        }
        return PDAssetResult(YES);
    }
    [[NSFileManager defaultManager] removeItemAtPath:[stateDir stringByAppendingPathComponent:kPDReadyName]
                                               error:NULL];
    if ([operation isEqual:@"check"]) {
        return PDAssetResult(NO);
    }

    // prepare：需要下载
    id rawURL = request[@"url"];
    if (rawURL == nil || ([rawURL isKindOfClass:[NSString class]] && [(NSString *)rawURL length] == 0)) {
        return PDAssetError(@"needs-url");
    }
    NSURL *url = PDAssetDownloadURL(rawURL);
    if (url == nil) {
        return PDAssetError(@"invalid-url");
    }

    PDWriteStatus(stateDir, kPDStageDownloading, 0, report);
    NSString *downloadFailure = PDDownloadAssetArchive(bundleRoot, url, ^(NSInteger percent) {
        PDWriteStatus(stateDir, kPDStageDownloading, percent, report);   // 0x100183c88: 无条件写
    });
    if (downloadFailure != nil) {
        return PDAssetError(downloadFailure);
    }

    PDWriteStatus(stateDir, kPDStageInstalling, 0, report);
    NSString *staging = [stateDir stringByAppendingPathComponent:kPDUnpackDirName];
    [manager removeItemAtPath:staging error:NULL];
    if (![manager createDirectoryAtPath:staging
           withIntermediateDirectories:NO
                            attributes:@{NSFilePosixPermissions: @0700}
                                 error:NULL]) {
        return PDAssetError(kPDStagePermissions);
    }
    return PDUnpackAndInstall(bundleRoot, stateDir, staging, spec, store);
}

/// `import`：把 AssetImports/<uuid>.zip 拷成 download.zip 再走安装，成功后写 imported.json
static NSDictionary *PDImportFlow(NSDictionary *request, NSString *bundleRoot, NSString *stateDir,
                                  NSDictionary *spec, NSDictionary *store,
                                  void (^report)(NSDictionary *)) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *token = request[@"token"];
    NSString *container = PDAssetImportPath(token);
    if (container == nil) {
        return PDAssetError(kPDStageRequest);
    }

    // 0x1001824e0: imported.json 里已是同一个 token → 用合成的 check 请求幂等续跑
    NSDictionary *imported = PDReadJSONDictionary([stateDir stringByAppendingPathComponent:@"imported.json"]);
    if ([imported[@"token"] isEqual:token]) {
        return PDCheckOrInstall(@{ @"operation": @"check" }, bundleRoot, stateDir, spec, store, report);
    }

    // 0x100182564: <uuid>.zip 必须是常规文件
    NSString *containerName = [container lastPathComponent];
    if (!PDAssetRegularPath(PDAssetImportDirectory(), containerName, NO)) {
        return PDAssetError(kPDStageImport);
    }

    NSString *archive = [stateDir stringByAppendingPathComponent:kPDArchiveName];
    if ([manager fileExistsAtPath:archive] && ![manager removeItemAtPath:archive error:NULL]) {
        return PDAssetError(kPDStagePermissions);
    }
    PDWriteStatus(stateDir, kPDStageImporting, 0, report);
    if (![manager copyItemAtPath:container toPath:archive error:NULL]) {
        return PDAssetError(kPDStageImport);
    }
    if (chmod(archive.fileSystemRepresentation, 0600) != 0) {
        return PDAssetError(kPDStageImport);
    }

    PDWriteStatus(stateDir, kPDStageInstalling, 0, report);
    NSString *staging = [stateDir stringByAppendingPathComponent:kPDUnpackDirName];
    [manager removeItemAtPath:staging error:NULL];
    if (![manager createDirectoryAtPath:staging
           withIntermediateDirectories:NO
                            attributes:@{NSFilePosixPermissions: @0700}
                                 error:NULL]) {
        return PDAssetError(kPDStagePermissions);
    }
    NSDictionary *result = PDUnpackAndInstall(bundleRoot, stateDir, staging, spec, store);
    if ([result[@"ready"] boolValue]) {
        NSDictionary *payload = @{ @"token": token ?: @"" };
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
        if (json == nil ||
            ![json writeToFile:[stateDir stringByAppendingPathComponent:@"imported.json"] atomically:YES]) {
            return PDAssetError(kPDStagePermissions);
        }
        [manager removeItemAtPath:container error:NULL];
    }
    return result;
}

#pragma mark - entry point

NSDictionary *PDRunAssetRequestWithProgress(NSDictionary *request, void (^report)(NSDictionary *)) {
    @autoreleasepool {
        static NSArray<NSString *> *operations;
        static NSArray<NSString *> *manifestRoots;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            operations = @[@"check", @"install", @"prepare", @"import", @"remove"];
            manifestRoots = @[@"originals", @"live", @"licenses"];
        });

        if (![request isKindOfClass:[NSDictionary class]] ||
            ![operations containsObject:request[@"operation"]]) {
            return PDAssetError(kPDStageRequest);
        }
        NSString *operation = request[@"operation"];
        BOOL isRemove = [operation isEqual:@"remove"];

        NSString *bundleRoot = PDBundleRoot();
        NSDictionary *spec = PDAssetSpecification(bundleRoot);
        if (bundleRoot == nil || (spec == nil && !isRemove)) {
            return PDAssetError(kPDStageSpecification);
        }

        // ── manifest → store（只登记 originals/* 与 live/*，licenses 跳过）──
        NSMutableDictionary *store = [NSMutableDictionary dictionary];
        if (!isRemove) {
            if (!PDAssetRegularPath(bundleRoot, kPDManifestName, NO)) {
                return PDAssetError(kPDStageManifest);
            }
            NSDictionary *manifest = PDReadJSONDictionary(
                [bundleRoot stringByAppendingPathComponent:kPDManifestName]);
            id files = manifest[@"files"];
            if (![files isKindOfClass:[NSDictionary class]]) {
                return PDAssetError(kPDStageManifest);
            }
            if ([(NSDictionary *)files count] == 0 || [(NSDictionary *)files count] > 2000) {
                return PDAssetError(kPDStageManifest);
            }
            if (![manifest[@"asset_version"] isEqual:spec[@"asset_version"]]) {
                return PDAssetError(kPDStageManifest);
            }
            for (NSString *relative in (NSDictionary *)files) {
                NSString *top = [[relative componentsSeparatedByString:@"/"] firstObject];
                if (!PDAssetSafeRelativePath(relative) || ![manifestRoots containsObject:top]) {
                    return PDAssetError(kPDStageManifest);
                }
                id value = ((NSDictionary *)files)[relative];
                if (![value isKindOfClass:[NSDictionary class]]) {
                    return PDAssetError(kPDStageManifest);
                }
                if ([top isEqual:@"licenses"]) {
                    continue;                            // 0x100181604: licenses 不登记
                }
                store[relative] = value;
            }
            if (store.count == 0) {
                return PDAssetError(kPDStageManifest);
            }
        }

        NSString *stateDir = PDAssetStatePath(bundleRoot);
        if (!PDAssetRegularPath(bundleRoot, kPDStateDirName, YES)) {
            return PDAssetError(kPDStagePermissions);    // .asset-state 必须已存在
        }

        // ── 抢锁 ──
        NSString *lockPath = [stateDir stringByAppendingPathComponent:kPDLockName];
        int fd = open(lockPath.fileSystemRepresentation, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
        if (fd < 0) {
            return PDAssetError(kPDStagePermissions);
        }
        static NSArray<NSString *> *waitingOperations;
        static dispatch_once_t waitOnce;
        dispatch_once(&waitOnce, ^{
            waitingOperations = @[@"prepare", @"import", @"remove"];
        });
        NSInteger retries = [waitingOperations containsObject:operation] ? 40 : 0;
        int rc = flock(fd, LOCK_EX | LOCK_NB);
        while (rc != 0) {
            if (errno != EWOULDBLOCK || retries < 1) {
                break;
            }
            usleep(50 * 1000);
            rc = flock(fd, LOCK_EX | LOCK_NB);           // 仍然非阻塞，不永久等待
            retries -= 1;
        }
        if (rc != 0) {
            close(fd);
            return PDAssetError(kPDStageBusy);
        }

        NSDictionary *result = nil;
        @try {
            if (isRemove) {
                result = PDCleanupStale(request, bundleRoot, stateDir, report);
            } else if ([operation isEqual:@"import"]) {
                result = PDImportFlow(request, bundleRoot, stateDir, spec, store, report);
            } else {
                result = PDCheckOrInstall(request, bundleRoot, stateDir, spec, store, report);
            }
        } @catch (NSException *exception) {
            result = PDAssetError(kPDStageInstall);
        }
        if (result == nil) {
            result = PDAssetError(kPDStageInstall);
        }

        // 0x1001819c4: 分派顺序 error → ready → remove
        if ([result[@"type"] isEqual:@"error"]) {
            PDWriteStatus(stateDir, result[@"stage"], 0, report);
        } else if ([result[@"ready"] boolValue]) {
            PDWriteStatus(stateDir, kPDStageReady, 100, report);
        } else if (isRemove) {
            PDWriteStatus(stateDir, kPDStageRemoved, 0, report);
        }

        // 收尾：所有 operation 都删 staging；非 check 删 download.zip；install.lock 常驻不删
        [[NSFileManager defaultManager]
            removeItemAtPath:[stateDir stringByAppendingPathComponent:kPDUnpackDirName] error:NULL];
        if (![operation isEqual:@"check"]) {
            [[NSFileManager defaultManager]
                removeItemAtPath:[stateDir stringByAppendingPathComponent:kPDArchiveName] error:NULL];
        }
        flock(fd, LOCK_UN);
        close(fd);
        return result;
    }
}
