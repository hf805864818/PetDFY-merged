//
//  PDWeTypeKeyAgreement.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  ECDH agreed on at handshake time.  The shipped helper statically linked
//  OpenSSL and used the low level EC_KEY API; the reconstruction keeps the same
//  API surface (OpenSSL 3 marks it deprecated but still ships it).
//
//  Curve: EC_KEY_new_by_curve_name(706).  706 is NID_secp128r1 in OpenSSL's
//  NID table (704 secp112r1, 705 secp112r2, 706 secp128r1, 707 secp128r2 ...).
//  This is consistent with the 33 byte / 0x04 prefixed public key the helper
//  generates and validates (33 = 1 + 2*16 for a 128 bit field).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDWeTypeKeyAgreement : NSObject

/// Uppercase hex of the uncompressed public key (33 bytes, leading 0x04).
@property (nonatomic, readonly, copy, nullable) NSString *publicKey;

/// Uppercase hex of the ECDH shared secret X coordinate, ASCII encoded.
/// Returns 32 ASCII bytes (16 byte secret in hex); nil when the peer key is
/// malformed, not on the curve, or the computation fails.
- (nullable NSData *)deriveKey:(nullable NSString *)peerPublicKeyHex;

@end

NS_ASSUME_NONNULL_END
