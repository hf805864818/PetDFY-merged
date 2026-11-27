//
//  PDVoiceProtocol.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  Wire helpers shared by the WeType (wetype.weixin.qq.com) voice channel:
//  protobuf varint encoding, a minimal protobuf field reader, hex, MD5/SHA-256,
//  AES-256/ECB/PKCS7 (CommonCrypto) and raw snappy block decode.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCryptor.h>

NS_ASSUME_NONNULL_BEGIN

/// 0x100189270  PDWTBlob(tag, data)  -> varint key (tag<<3)|2, varint len, bytes
NSMutableData *PDWTBlob(uint32_t tag, NSData *_Nullable data);

/// 0x100189374  PDWTString(tag, string) -> PDWTBlob of UTF-8 bytes
NSMutableData *PDWTString(uint32_t tag, NSString *_Nullable string);

/// 0x1001893c0  PDWTInteger(tag, value) -> varint key (tag<<3)|0, varint value
NSMutableData *PDWTInteger(uint32_t tag, uint64_t value);

/// 0x10018949c  PDWTFields(data) -> @{ @(field) : NSMutableArray of values }
/// values are NSData for length-delimited fields and NSNumber for varint/fixed32/fixed64.
/// Returns nil when the buffer is malformed (truncated varint / bad wire type).
NSDictionary<NSNumber *, NSMutableArray *> *_Nullable PDWTFields(NSData *_Nullable data);

/// 0x1001897f8  PDWTData(fields, tag) -> first value of `tag` when it is NSData
NSData *_Nullable PDWTData(NSDictionary *_Nullable fields, uint32_t tag);

/// 0x1001898a0  PDWTNumber(fields, tag) -> first value of `tag` as unsigned long long (0 when absent)
uint64_t PDWTNumber(NSDictionary *_Nullable fields, uint32_t tag);

/// 0x100189954  PDWTHex(data) -> uppercase hex string
NSString *_Nullable PDWTHex(NSData *_Nullable data);

/// 0x100189a54  PDWTUnhex(hex) -> bytes; nil when odd length, > 0x800 chars or non-hex
NSData *_Nullable PDWTUnhex(NSString *_Nullable hex);

/// 0x100189b98  PDWTMD5(data) -> uppercase hex MD5
NSString *_Nullable PDWTMD5(NSData *_Nullable data);

/// 0x100189c54  PDWTSHA256(string) -> uppercase hex SHA-256 of the UTF-8 bytes
NSString *_Nullable PDWTSHA256(NSString *_Nullable string);

/// 0x100189d10  PDWTCrypt(data, key32, op) -> AES-256/ECB/PKCS7 (kCCOptionECBMode|kCCOptionPKCS7Padding)
/// key must be exactly 32 bytes and data at most 1 MiB, otherwise nil.
NSData *_Nullable PDWTCrypt(NSData *_Nullable data, NSData *_Nullable key, CCOperation op);

/// 0x100189e74  PDWTSnappyDecode(block) -> raw snappy block format
NSData *_Nullable PDWTSnappyDecode(NSData *_Nullable block);

/// 0x10018a0f8  PDWTNewDeviceCode(seed)
/// "IOS" + seed padded with 't' to 17 bytes + 12 random [a-z] + upper MD5 of
/// (prefix + "wC4bY5nV2kE0xK0r").  64 characters total.
NSString *_Nullable PDWTNewDeviceCode(NSString *_Nullable seed);

#pragma mark - constants recovered from __cstring / __cfstring

/// App id used as the AES-256 key for /oauth_pubkey_v2 (32 ASCII bytes).
extern NSString *const PDWTAppID;          // "V0J7L5C2C1N7G9B8S4K8W8H5U5H0J5K0"
/// Signature suffix appended before SHA-256 in every Kb-Sign computation.
extern NSString *const PDWTSignSecret;     // "wC4bY5nV2kE0xK0r"
/// Kb-OsType / Kb-Version / Kb-SystemVersion / Kb-PackageType / Kb-Scene defaults.
extern NSString *const PDWTOsType;         // "2"
extern NSString *const PDWTVersion;        // "4.0.0.749"
extern NSString *const PDWTSystemVersion;  // "16.1.2"
extern NSString *const PDWTPackageType;    // "3"
extern NSString *const PDWTScene;          // "1"
extern NSString *const PDWTCmdID;          // "4547"

NS_ASSUME_NONNULL_END
