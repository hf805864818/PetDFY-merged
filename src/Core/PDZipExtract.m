//
//  PDZipExtract.m — 进程内 ZIP 解压实现（zlib）
//

#import "PDZipExtract.h"
#import <zlib.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <stdlib.h>

@interface PDZipExtract ()
+ (long long)findEOCD:(NSData *)data;
+ (BOOL)inflateBytes:(const uint8_t *)src
              length:(uint32_t)srcLen
      expectedLength:(uint32_t)expected
               toPath:(NSString *)path;
@end

#pragma mark - ZIP 结构

#define PDZIP_LOCAL_SIG      0x04034b50u
#define PDZIP_CENTRAL_SIG    0x02014b50u
#define PDZIP_EOCD_SIG       0x06054b50u
#define PDZIP_EOCD64_SIG     0x06064b50u
#define PDZIP_EOCD64LOC_SIG  0x07064b50u

typedef struct {
    uint32_t sig;
    uint32_t compSize;
    uint32_t uncompSize;
    uint32_t nameLen;
    uint16_t method;
    uint16_t flags;
    uint32_t crc;
    uint32_t localOffset;
} PDZipCentralEntry;

static uint16_t pdzip_u16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t pdzip_u32(const uint8_t *p) {
    return (uint32_t)(p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24));
}
static uint64_t pdzip_u64(const uint8_t *p) {
    return (uint64_t)pdzip_u32(p) | ((uint64_t)pdzip_u32(p + 4) << 32);
}

/// CP437（仅 0x80-0xFF 段）→ Unicode，用于未置 UTF-8 标志位的旧 ZIP 文件名
static const uint16_t kPDCP437[128] = {
    0x00C7,0x00FC,0x00E9,0x00E2,0x00E4,0x00E0,0x00E5,0x00E7,0x00EA,0x00EB,0x00E8,0x00EF,0x00EE,0x00EC,0x00C4,0x00C5,
    0x00C9,0x00E6,0x00C6,0x00F4,0x00F6,0x00F2,0x00FB,0x00F9,0x00FF,0x00D6,0x00DC,0x00A2,0x00A3,0x00A5,0x20A7,0x0192,
    0x00E1,0x00ED,0x00F3,0x00FA,0x00F1,0x00D1,0x00AA,0x00BA,0x00BF,0x2310,0x00AC,0x00BD,0x00BC,0x00A1,0x00AB,0x00BB,
    0x2591,0x2592,0x2593,0x2502,0x2524,0x2561,0x2562,0x2556,0x2555,0x2563,0x2551,0x2557,0x255D,0x255C,0x255B,0x2510,
    0x2514,0x2534,0x252C,0x251C,0x2500,0x253C,0x255E,0x255F,0x255A,0x2554,0x2569,0x2566,0x2560,0x2550,0x256C,0x2567,
    0x2568,0x2564,0x2565,0x2559,0x2558,0x2552,0x2553,0x256B,0x256A,0x2518,0x250C,0x2588,0x2584,0x258C,0x2590,0x2580,
    0x03B1,0x00DF,0x0393,0x03C0,0x03A3,0x03C3,0x00B5,0x03C4,0x03A6,0x0398,0x03A9,0x03B4,0x221E,0x03C6,0x03B5,0x2229,
    0x2261,0x00B1,0x2265,0x2264,0x2320,0x2321,0x00F7,0x2248,0x00B0,0x2219,0x00B7,0x221A,0x207F,0x00B2,0x25A0,0x00A0
};

static NSString *PDZipNameFromBytes(const uint8_t *bytes, NSUInteger length, BOOL utf8) {
    if (length == 0) return nil;
    NSData *d = [NSData dataWithBytes:bytes length:length];
    NSString *s = nil;
    if (utf8) {
        s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    } else {
        // 先按 UTF-8 试（大量工具实际写 UTF-8 但不置标志位）
        s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s) {
            NSMutableString *m = [NSMutableString stringWithCapacity:length];
            for (NSUInteger i = 0; i < length; i++) {
                uint8_t b = bytes[i];
                if (b < 0x80) [m appendFormat:@"%C", (unichar)b];
                else [m appendFormat:@"%C", (unichar)kPDCP437[b - 0x80]];
            }
            s = m;
        }
    }
    if (!s) s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    return s;
}

/// 规范化条目名：统一 '/'，去掉前导 '/'，拒绝 '..'
static NSString *PDZipSafeRelative(NSString *name, NSString **rejectReason) {
    if (![name isKindOfClass:[NSString class]] || name.length == 0) return nil;
    NSString *n = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([n hasPrefix:@"/"]) n = [n substringFromIndex:1];
    NSArray<NSString *> *parts = [n componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length == 0 || [p isEqualToString:@"."]) continue;
        if ([p isEqualToString:@".."]) {
            if (rejectReason) *rejectReason = name;
            return nil;
        }
        [kept addObject:p];
    }
    if (kept.count == 0) return nil;
    return [kept componentsJoinedByString:@"/"];
}

@implementation PDZipExtract

#pragma mark - EOCD 定位

/// 从尾部向前找 EOCD，返回其文件偏移；找不到返回 -1
+ (long long)findEOCD:(NSData *)data {
    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger len = data.length;
    if (len < 22) return -1;
    NSUInteger maxScan = MIN((NSUInteger)65557 + 22, len);   // 注释最长 65535
    for (NSUInteger back = 22; back <= maxScan; back++) {
        NSUInteger pos = len - back;
        if (pdzip_u32(b + pos) == PDZIP_EOCD_SIG) return (long long)pos;
    }
    return -1;
}

+ (NSString *)singleTopLevelDirectoryOfArchive:(NSString *)zipPath {
    NSData *data = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedIfSafe error:NULL];
    if (!data.length) return nil;
    long long eocd = [self findEOCD:data];
    if (eocd < 0) return nil;

    const uint8_t *b = (const uint8_t *)data.bytes;
    uint16_t count = pdzip_u16(b + eocd + 10);
    uint32_t cdOffset = pdzip_u32(b + eocd + 16);
    if (count == 0 || (NSUInteger)cdOffset >= data.length) return nil;

    NSUInteger p = cdOffset;
    NSString *root = nil;
    for (uint16_t i = 0; i < count; i++) {
        if (p + 46 > data.length || pdzip_u32(b + p) != PDZIP_CENTRAL_SIG) return nil;
        uint16_t flags = pdzip_u16(b + p + 8);
        uint16_t nameLen = pdzip_u16(b + p + 28);
        uint16_t extraLen = pdzip_u16(b + p + 30);
        uint16_t commentLen = pdzip_u16(b + p + 32);
        if (p + 46 + nameLen > data.length) return nil;
        NSString *name = PDZipNameFromBytes(b + p + 46, nameLen, (flags & 0x0800) != 0);
        if (name.length) {
            NSString *norm = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
            if (![norm hasPrefix:@"__MACOSX"]) {
                NSRange slash = [norm rangeOfString:@"/"];
                if (slash.location == NSNotFound) return nil;   // 根层直接有文件 → 不能 strip
                NSString *first = [norm substringToIndex:slash.location];
                if (!root) root = first;
                else if (![root isEqualToString:first]) return nil;  // 多个顶层目录
            }
        }
        p += 46 + nameLen + extraLen + commentLen;
    }
    return root;
}

#pragma mark - 解压

+ (NSInteger)extractArchiveAtPath:(NSString *)zipPath
                      toDirectory:(NSString *)destination
                 stripSingleRoot:(BOOL)stripSingleRoot
                          error:(NSString **)errorDescription {

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:zipPath]) {
        if (errorDescription) *errorDescription = @"zip not found";
        return -1;
    }

    NSData *data = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedIfSafe error:NULL];
    if (!data.length) {
        if (errorDescription) *errorDescription = @"zip unreadable";
        return -1;
    }

    long long eocd = [self findEOCD:data];
    if (eocd < 0) {
        if (errorDescription) *errorDescription = @"EOCD not found";
        return -1;
    }

    const uint8_t *b = (const uint8_t *)data.bytes;
    NSUInteger fileLen = data.length;

    uint16_t entryCount = pdzip_u16(b + eocd + 10);
    uint64_t cdOffset = pdzip_u32(b + eocd + 16);
    uint64_t cdSize = pdzip_u32(b + eocd + 12);

    // ZIP64：若计数或偏移为哨兵值，读 ZIP64 EOCD
    if (entryCount == 0xFFFF || cdOffset == 0xFFFFFFFFu || cdSize == 0xFFFFFFFFu) {
        for (long long back = 22; back < 22 + 65557 && (NSUInteger)back < fileLen; back++) {
            long long pos = (long long)eocd - back;
            if (pos < 0) break;
            if (pdzip_u32(b + pos) == PDZIP_EOCD64_SIG) {
                uint64_t total64 = pdzip_u64(b + pos + 32);
                uint64_t cdSize64 = pdzip_u64(b + pos + 40);
                uint64_t cdOff64 = pdzip_u64(b + pos + 48);
                if (total64 > 0 && total64 < 1000000) entryCount = (uint16_t)MIN(total64, 0xFFFFu);
                if (cdOff64) cdOffset = cdOff64;
                if (cdSize64) cdSize = cdSize64;
                break;
            }
        }
    }

    if (cdOffset >= fileLen) {
        if (errorDescription) *errorDescription = @"central directory offset out of range";
        return -1;
    }

    // 目录准备
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:destination isDirectory:&isDir]) {
        if (!isDir) {
            if (errorDescription) *errorDescription = @"destination is a file";
            return -1;
        }
    } else {
        NSError *e = nil;
        if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&e]) {
            if (errorDescription) *errorDescription = e.localizedDescription ?: @"mkdir failed";
            return -1;
        }
    }

    NSString *stripPrefix = nil;
    if (stripSingleRoot) {
        NSString *root = [self singleTopLevelDirectoryOfArchive:zipPath];
        if (root.length) stripPrefix = [root stringByAppendingString:@"/"];
    }

    NSInteger written = 0;
    NSUInteger p = (NSUInteger)cdOffset;

    for (uint16_t i = 0; i < entryCount; i++) {
        if (p + 46 > fileLen || pdzip_u32(b + p) != PDZIP_CENTRAL_SIG) break;

        uint16_t flags        = pdzip_u16(b + p + 8);
        uint16_t method       = pdzip_u16(b + p + 10);
        uint32_t crc          = pdzip_u32(b + p + 16); (void)crc;
        uint32_t compSize     = pdzip_u32(b + p + 20);
        uint32_t uncompSize   = pdzip_u32(b + p + 24);
        uint16_t nameLen      = pdzip_u16(b + p + 28);
        uint16_t extraLen     = pdzip_u16(b + p + 30);
        uint16_t commentLen   = pdzip_u16(b + p + 32);
        uint32_t extAttr      = pdzip_u32(b + p + 38);
        uint32_t localOffset  = pdzip_u32(b + p + 42);

        if (p + 46 + nameLen > fileLen) break;
        NSString *name = PDZipNameFromBytes(b + p + 46, nameLen, (flags & 0x0800) != 0);

        const uint8_t *extra = b + p + 46 + nameLen;

        // ZIP64 extra field：0x0001
        if (uncompSize == 0xFFFFFFFFu || compSize == 0xFFFFFFFFu || localOffset == 0xFFFFFFFFu) {
            uint16_t off = 0;
            while (off + 4 <= extraLen) {
                uint16_t tag = pdzip_u16(extra + off);
                uint16_t sz = pdzip_u16(extra + off + 2);
                if (tag == 0x0001) {
                    uint16_t q = off + 4;
                    if (uncompSize == 0xFFFFFFFFu && q + 8 <= off + 4 + sz) { uncompSize = (uint32_t)pdzip_u64(extra + q); q += 8; }
                    if (compSize == 0xFFFFFFFFu && q + 8 <= off + 4 + sz) { compSize = (uint32_t)pdzip_u64(extra + q); q += 8; }
                    if (localOffset == 0xFFFFFFFFu && q + 8 <= off + 4 + sz) { localOffset = (uint32_t)pdzip_u64(extra + q); q += 8; }
                    break;
                }
                off += 4 + sz;
            }
        }

        p += 46 + nameLen + extraLen + commentLen;

        if (!name.length) continue;
        NSString *lower = name.lowercaseString;
        if ([lower hasPrefix:@"__macosx/"] || [lower isEqualToString:@".ds_store"] ||
            [lower hasSuffix:@"/.ds_store"]) {
            continue;
        }

        BOOL isDirectoryEntry = (extAttr & 0x10) != 0 || [name hasSuffix:@"/"] || [name hasSuffix:@"\\"];

        NSString *reject = nil;
        NSString *rel = PDZipSafeRelative(name, &reject);
        if (!rel) continue;                 // 路径穿越 / 空名，跳过
        if (stripPrefix && [rel hasPrefix:stripPrefix]) {
            rel = [rel substringFromIndex:stripPrefix.length];
            if (rel.length == 0) continue;
        }

        NSString *outPath = [destination stringByAppendingPathComponent:rel];

        if (isDirectoryEntry) {
            [fm createDirectoryAtPath:outPath withIntermediateDirectories:YES attributes:nil error:NULL];
            continue;
        }

        // 读本地头，跳过 name/extra
        if ((uint64_t)localOffset + 30 > fileLen) continue;
        const uint8_t *lh = b + localOffset;
        if (pdzip_u32(lh) != PDZIP_LOCAL_SIG) continue;
        uint16_t lNameLen = pdzip_u16(lh + 26);
        uint16_t lExtraLen = pdzip_u16(lh + 28);
        uint64_t dataOff = (uint64_t)localOffset + 30 + lNameLen + lExtraLen;
        if (dataOff + compSize > fileLen) continue;

        const uint8_t *src = b + dataOff;

        [fm createDirectoryAtPath:[outPath stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:NULL];

        BOOL ok = NO;
        if (method == 0) {
            NSData *chunk = [NSData dataWithBytes:src length:compSize];
            ok = [chunk writeToFile:outPath atomically:YES];
        } else if (method == 8) {
            ok = [self inflateBytes:src
                             length:compSize
                   expectedLength:uncompSize
                            toPath:outPath];
        } else {
            // 其它压缩方法（bzip2/lzma）不支持，跳过但不中断
            continue;
        }

        if (ok) {
            written++;
        } else {
            NSLog(@"[PetDFY.Import] entry failed: %@ method=%u comp=%u", rel, method, compSize);
        }
    }

    return written;
}

/// deflate 解压单个条目到文件
+ (BOOL)inflateBytes:(const uint8_t *)src
              length:(uint32_t)srcLen
      expectedLength:(uint32_t)expected
               toPath:(NSString *)path {

    if (expected == 0 || expected > (uint32_t)(512u * 1024u * 1024u)) return NO;

    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return NO;

    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) { close(fd); return NO; }

    strm.next_in = (Bytef *)src;
    strm.avail_in = srcLen;

    const size_t kChunk = 256 * 1024;
    uint8_t *outBuf = (uint8_t *)malloc(kChunk);
    if (!outBuf) { inflateEnd(&strm); close(fd); return NO; }

    BOOL ok = YES;
    uint64_t total = 0;

    while (1) {
        strm.next_out = outBuf;
        strm.avail_out = (uInt)kChunk;
        int rc = inflate(&strm, Z_NO_FLUSH);
        size_t produced = kChunk - strm.avail_out;
        if (produced) {
            ssize_t w = write(fd, outBuf, produced);
            if (w != (ssize_t)produced) { ok = NO; break; }
            total += produced;
            if (total > (uint64_t)expected + 4096) { ok = NO; break; }   // 防御性上限
        }
        if (rc == Z_STREAM_END) break;
        if (rc != Z_OK && rc != Z_BUF_ERROR) { ok = NO; break; }
        if (rc == Z_BUF_ERROR && strm.avail_in == 0) { ok = NO; break; }
    }

    free(outBuf);
    inflateEnd(&strm);
    close(fd);

    if (ok && total != (uint64_t)expected) {
        // 尺寸不符不视为致命（少数打包器元数据不准），保留产物
        ok = YES;
    }
    if (!ok) [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    return ok;
}

@end
