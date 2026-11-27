//
//  PDVoiceProtocol.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//

#import "PDVoiceProtocol.h"
#import <stdlib.h>
#import <string.h>

NSString *const PDWTAppID = @"V0J7L5C2C1N7G9B8S4K8W8H5U5H0J5K0";
NSString *const PDWTSignSecret = @"wC4bY5nV2kE0xK0r";
NSString *const PDWTOsType = @"2";
NSString *const PDWTVersion = @"4.0.0.749";
NSString *const PDWTSystemVersion = @"16.1.2";
NSString *const PDWTPackageType = @"3";
NSString *const PDWTScene = @"1";
NSString *const PDWTCmdID = @"4547";

#pragma mark - varint

static NSUInteger PDWTVarintSize(uint64_t v) {
    NSUInteger n = 1;
    while (v > 0x7f) {
        v >>= 7;
        n++;
    }
    return n;
}

/// Appends `value` as a protobuf varint (7 bits per byte, MSB = continuation).
static void PDWTAppendVarint(NSMutableData *out, uint64_t value) {
    uint8_t buf[10];
    NSUInteger n = 0;
    do {
        uint8_t b = (uint8_t)(value & 0x7f);
        value >>= 7;
        if (value) {
            b |= 0x80;
        }
        buf[n++] = b;
    } while (value);
    [out appendBytes:buf length:n];
}

/// Reads a varint from `bytes` starting at `*cursor`; nil when out of range or > 10 bytes.
static BOOL PDWTReadVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *cursor, uint64_t *out) {
    uint64_t value = 0;
    NSUInteger shift = 0;
    NSUInteger i = *cursor;
    while (i < length) {
        uint8_t b = bytes[i++];
        // The original rejects a 10th byte that carries more than one payload bit.
        if (shift == 63) {                    // 第 10 字节：只允许 1 bit，且不能再带续位
            if (b > 1 || (b & 0x80)) {
                return NO;
            }
        }
        value |= ((uint64_t)(b & 0x7f)) << shift;
        if ((b & 0x80) == 0) {
            *cursor = i;
            *out = value;
            return YES;
        }
        shift += 7;
    }
    return NO;
}

#pragma mark - encoders

NSMutableData *PDWTBlob(uint32_t tag, NSData *data) {
    NSMutableData *out = [NSMutableData data];
    PDWTAppendVarint(out, ((uint64_t)tag << 3) | 2u);
    PDWTAppendVarint(out, (uint64_t)data.length);
    if (data.length) {
        [out appendData:data];
    }
    return out;
}

NSMutableData *PDWTString(uint32_t tag, NSString *string) {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    return PDWTBlob(tag, utf8);
}

NSMutableData *PDWTInteger(uint32_t tag, uint64_t value) {
    NSMutableData *out = [NSMutableData data];
    PDWTAppendVarint(out, ((uint64_t)tag << 3) | 0u);
    PDWTAppendVarint(out, value);
    return out;
}

#pragma mark - decoder

NSDictionary<NSNumber *, NSMutableArray *> *PDWTFields(NSData *data) {
    if (data == nil) {
        return nil;
    }
    if (data.length > 0x100000) {          // 1 MiB ceiling, as in the original
        return nil;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    if (length == 0) {
        return [NSMutableDictionary dictionary];
    }
    NSMutableDictionary<NSNumber *, NSMutableArray *> *fields = [NSMutableDictionary dictionary];
    NSUInteger cursor = 0;
    NSUInteger fieldCount = 0;
    while (cursor < length) {
        uint64_t key = 0;
        if (!PDWTReadVarint(bytes, length, &cursor, &key)) {
            return nil;
        }
        // 0x1001895a8: key < 8 或 key > 0xFFFFFFFF → 整包 nil
        if (key < 8 || key > 0xFFFFFFFFull) {
            return nil;
        }
        // 0x1001895b4: 处理到第 8193 个字段即整包 nil
        if (fieldCount >= 8192) {
            return nil;
        }
        fieldCount += 1;
        uint32_t field = (uint32_t)(key >> 3);
        uint32_t wire = (uint32_t)(key & 7);
        id value = nil;
        switch (wire) {
            case 0: {                                    // varint
                uint64_t v = 0;
                if (!PDWTReadVarint(bytes, length, &cursor, &v)) {
                    return nil;
                }
                value = @(v);
                break;
            }
            case 1:                                      // fixed64
            case 5: {                                    // fixed32
                // 0x1001895dc: 原实现只把游标推过 4/8 字节，不往字典里放值
                NSUInteger need = (wire == 1) ? 8 : 4;
                if (length - cursor < need) {
                    return nil;
                }
                cursor += need;
                continue;
            }
            case 2: {                                    // length-delimited
                uint64_t len = 0;
                if (!PDWTReadVarint(bytes, length, &cursor, &len)) {
                    return nil;
                }
                if (len > length - cursor) {
                    return nil;
                }
                value = [NSData dataWithBytes:bytes + cursor length:(NSUInteger)len];
                cursor += (NSUInteger)len;
                break;
            }
            default:                                     // groups (3/4) and 6/7 are rejected
                return nil;
        }
        NSNumber *keyNumber = @(field);
        NSMutableArray *list = fields[keyNumber];
        if (list == nil) {
            list = [NSMutableArray array];
            fields[keyNumber] = list;
        }
        [list addObject:value];
    }
    return fields;
}

NSData *PDWTData(NSDictionary *fields, uint32_t tag) {
    id first = [fields[@(tag)] firstObject];
    return [first isKindOfClass:[NSData class]] ? (NSData *)first : nil;
}

uint64_t PDWTNumber(NSDictionary *fields, uint32_t tag) {
    id first = [fields[@(tag)] firstObject];
    if (![first isKindOfClass:[NSNumber class]]) {
        return 0;
    }
    return [(NSNumber *)first unsignedLongLongValue];
}

#pragma mark - hex / digests

static NSString *const kPDWTHexUpper = @"0123456789ABCDEF";

NSString *PDWTHex(NSData *data) {
    if (data == nil) {
        return nil;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger n = data.length;
    NSMutableData *out = [NSMutableData dataWithLength:n * 2];
    uint8_t *dst = (uint8_t *)out.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        dst[i * 2] = (uint8_t)[kPDWTHexUpper characterAtIndex:(bytes[i] >> 4) & 0xf];
        dst[i * 2 + 1] = (uint8_t)[kPDWTHexUpper characterAtIndex:bytes[i] & 0xf];
    }
    return [[NSString alloc] initWithData:out encoding:NSASCIIStringEncoding];
}

NSData *PDWTUnhex(NSString *hex) {
    NSData *ascii = [hex dataUsingEncoding:NSASCIIStringEncoding];
    if (ascii.length == 0 || (ascii.length & 1) != 0 || ascii.length > 0x800) {
        return nil;
    }
    const uint8_t *bytes = (const uint8_t *)ascii.bytes;
    NSMutableData *out = [NSMutableData dataWithLength:ascii.length / 2];
    uint8_t *dst = (uint8_t *)out.mutableBytes;
    for (NSUInteger i = 0; i < ascii.length; i++) {
        uint8_t c = bytes[i];
        int nibble;
        if (c >= '0' && c <= '9') {
            nibble = c - '0';
        } else if (c >= 'A' && c <= 'F') {
            nibble = c - 'A' + 10;
        } else if (c >= 'a' && c <= 'f') {
            nibble = c - 'a' + 10;
        } else {
            return nil;
        }
        if ((i & 1) == 0) {
            dst[i >> 1] = (uint8_t)(nibble << 4);
        } else {
            dst[i >> 1] |= (uint8_t)nibble;
        }
    }
    return out;
}

NSString *PDWTMD5(NSData *data) {
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    return PDWTHex([NSData dataWithBytes:digest length:sizeof(digest)]);
}

NSString *PDWTSHA256(NSString *string) {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8.bytes, (CC_LONG)utf8.length, digest);
    return PDWTHex([NSData dataWithBytes:digest length:sizeof(digest)]);
}

#pragma mark - AES

NSData *PDWTCrypt(NSData *data, NSData *key, CCOperation op) {
    if (data == nil || key.length != 32 || data.length > 0x100000) {
        return nil;
    }
    NSMutableData *out = [NSMutableData dataWithLength:data.length + kCCBlockSizeAES128];
    size_t moved = 0;
    CCCryptorStatus status = CCCrypt(op,
                                     kCCAlgorithmAES,
                                     kCCOptionPKCS7Padding | kCCOptionECBMode,
                                     key.bytes, key.length,
                                     NULL,
                                     data.bytes, data.length,
                                     out.mutableBytes, out.length,
                                     &moved);
    if (status != kCCSuccess) {
        return nil;
    }
    [out setLength:moved];
    return out;
}

#pragma mark - snappy (raw block format)

NSData *PDWTSnappyDecode(NSData *block) {
    if (block == nil) {
        return nil;
    }
    const uint8_t *src = (const uint8_t *)block.bytes;
    NSUInteger len = block.length;
    NSUInteger cursor = 0;

    uint64_t expected = 0;
    if (!PDWTReadVarint(src, len, &cursor, &expected) || expected > 0x100000) {
        return nil;
    }
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)expected];
    uint8_t *dst = (uint8_t *)out.mutableBytes;
    NSUInteger produced = 0;

    while (cursor < len) {
        uint8_t tag = src[cursor++];
        switch (tag & 0x03) {
            case 0: {                                            // literal
                NSUInteger n = (NSUInteger)(tag >> 2) + 1;
                if (n > 60) {
                    NSUInteger extra = n - 60;                   // 1..4 length bytes
                    if (len - cursor < extra) {
                        return nil;
                    }
                    n = 0;
                    for (NSUInteger i = 0; i < extra; i++) {
                        n |= ((NSUInteger)src[cursor + i]) << (8 * i);
                    }
                    cursor += extra;
                    n += 1;
                }
                if (len - cursor < n || (NSUInteger)expected - produced < n) {
                    return nil;
                }
                memcpy(dst + produced, src + cursor, n);
                cursor += n;
                produced += n;
                break;
            }
            case 1: {                                            // copy, 1-byte offset
                if (len - cursor < 1) {
                    return nil;
                }
                NSUInteger length = 4 + ((tag >> 2) & 0x07);
                NSUInteger offset = (((NSUInteger)tag & 0xe0) << 3) | src[cursor];
                cursor += 1;
                if (offset == 0 || offset > produced || produced + length > (NSUInteger)expected) {
                    return nil;
                }
                for (NSUInteger i = 0; i < length; i++, produced++) {
                    dst[produced] = dst[produced - offset];
                }
                break;
            }
            case 2: {                                            // copy, 2-byte offset
                if (len - cursor < 2) {
                    return nil;
                }
                NSUInteger length = (NSUInteger)(tag >> 2) + 1;
                NSUInteger offset = (NSUInteger)src[cursor] | ((NSUInteger)src[cursor + 1] << 8);
                cursor += 2;
                if (offset == 0 || offset > produced || produced + length > (NSUInteger)expected) {
                    return nil;
                }
                for (NSUInteger i = 0; i < length; i++, produced++) {
                    dst[produced] = dst[produced - offset];
                }
                break;
            }
            case 3: {                                            // copy, 4-byte offset
                if (len - cursor < 4) {
                    return nil;
                }
                NSUInteger length = (NSUInteger)(tag >> 2) + 1;
                NSUInteger offset = (NSUInteger)src[cursor] |
                                    ((NSUInteger)src[cursor + 1] << 8) |
                                    ((NSUInteger)src[cursor + 2] << 16) |
                                    ((NSUInteger)src[cursor + 3] << 24);
                cursor += 4;
                if (offset == 0 || offset > produced || produced + length > (NSUInteger)expected) {
                    return nil;
                }
                for (NSUInteger i = 0; i < length; i++, produced++) {
                    dst[produced] = dst[produced - offset];
                }
                break;
            }
        }
    }
    if (produced != (NSUInteger)expected) {
        return nil;
    }
    [out setLength:produced];
    return out;
}

#pragma mark - device code

NSString *PDWTNewDeviceCode(NSString *seed) {
    NSData *ascii = [seed dataUsingEncoding:NSASCIIStringEncoding];
    if (ascii == nil) {
        return nil;
    }
    static const uint8_t kPad = '0';             // 0x30, byte at 0x1001cb0b5
    NSMutableData *prefix = [NSMutableData dataWithBytes:"IOS" length:3];
    if (ascii.length < 17) {
        for (NSUInteger i = ascii.length; i < 17; i++) {
            [prefix appendBytes:&kPad length:1];
        }
    }
    NSUInteger take = ascii.length < 17 ? ascii.length : 17;
    [prefix appendBytes:ascii.bytes length:take];

    for (int i = 0; i < 12; i++) {
        uint8_t c = (uint8_t)('a' + arc4random_uniform(0x1a));
        [prefix appendBytes:&c length:1];
    }

    NSMutableData *signedInput = [prefix mutableCopy];
    [signedInput appendData:[PDWTSignSecret dataUsingEncoding:NSASCIIStringEncoding]];

    NSString *prefixString = [[NSString alloc] initWithData:prefix encoding:NSASCIIStringEncoding];
    return [prefixString stringByAppendingString:PDWTMD5(signedInput)];
}

