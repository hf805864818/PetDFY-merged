//
//  PDWeTypeKeyAgreement.m
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//

#import "PDWeTypeKeyAgreement.h"
#import "PDVoiceProtocol.h"

#import <openssl/ec.h>
#import <openssl/obj_mac.h>
#import <openssl/bn.h>
#import <openssl/crypto.h>

/// NID used by the shipped helper (0x2c2). See the note in the header.
static const int kPDWTCurveNID = 706;

@implementation PDWeTypeKeyAgreement {
    EC_KEY *_key;                       // ivar 0x08 ^{ec_key_st=}
}

- (instancetype)init {
    if ((self = [super init])) {
        _key = EC_KEY_new_by_curve_name(kPDWTCurveNID);
        if (_key == NULL || EC_KEY_generate_key(_key) != 1) {
            return nil;                 // the original returns nil from -init
        }
    }
    return self;
}

- (void)dealloc {
    if (_key != NULL) {
        EC_KEY_free(_key);
        _key = NULL;
    }
}

- (NSString *)publicKey {
    if (_key == NULL) {
        return nil;
    }
    const EC_GROUP *group = EC_KEY_get0_group(_key);
    const EC_POINT *point = EC_KEY_get0_public_key(_key);
    unsigned char buf[0x21];
    // POINT_CONVERSION_UNCOMPRESSED == 4
    size_t written = EC_POINT_point2oct(group, point, POINT_CONVERSION_UNCOMPRESSED, buf, sizeof(buf), NULL);
    if (written != sizeof(buf)) {
        return nil;
    }
    return PDWTHex([NSData dataWithBytes:buf length:sizeof(buf)]);
}

- (NSData *)deriveKey:(NSString *)peerPublicKeyHex {
    NSData *peer = PDWTUnhex(peerPublicKeyHex);
    if (peer == nil || peer.length != 0x21) {
        return nil;
    }
    const uint8_t *peerBytes = (const uint8_t *)peer.bytes;
    if (peerBytes[0] != 4) {             // uncompressed point required
        return nil;
    }
    const EC_GROUP *group = EC_KEY_get0_group(_key);
    EC_POINT *point = EC_POINT_new(group);
    if (point == NULL) {
        return nil;
    }
    NSData *result = nil;
    // 0x1000580f4 -> EC_POINT_oct2point 必须 == 1
    // 0x100055880 -> EC_POINT_is_on_curve 必须 == 1
    // 0x100055a54 -> EC_POINT_is_at_infinity 必须 == 0（原实现用这个，不是 EC_KEY_set_public_key）
    if (EC_POINT_oct2point(group, point, peerBytes, peer.length, NULL) == 1 &&
        EC_POINT_is_on_curve(group, point, NULL) == 1 &&
        EC_POINT_is_at_infinity(group, point) == 0) {
        unsigned char secret[16];
        int n = ECDH_compute_key(secret, sizeof(secret), point, _key, NULL);
        if (n == (int)sizeof(secret)) {
            NSString *hex = PDWTHex([NSData dataWithBytes:secret length:sizeof(secret)]);
            result = [hex dataUsingEncoding:NSASCIIStringEncoding];
        }
        OPENSSL_cleanse(secret, sizeof(secret));
    }
    EC_POINT_free(point);
    return result;
}

@end
