//
//  PDWeTypeClient.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  WeType (wetype.weixin.qq.com) voice channel client:
//   * a NSURLSessionWebSocketTask on wss://<host>/ (subprotocol "wxws_pb") that
//     carries protobuf framed request/response pairs for /timestamp,
//     /oauth_pubkey_v2 and /gen_uin_v2,
//   * plain HTTPS POSTs to https://<host>/api_v2 carrying the encrypted audio.
//

#import <Foundation/Foundation.h>
#import "PDWeTypeKeyAgreement.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDVoiceProtocolErrorDomain;   // "PetDFY.VoiceProtocol"

/// Header "kind" values passed to -headersForBody:task:kind:token:
typedef NS_ENUM(NSInteger, PDWeTypeKind) {
    PDWeTypeKindTimestamp = 0,      // Kb-Uin only
    PDWeTypeKindGenUin = 1,         // Kb-GenUinToken
    PDWeTypeKindData = 2,           // Kb-CmdId / Kb-SubCmdId / Kb-SharedKeySuffix
};

@interface PDWeTypeClient : NSObject

@property (nonatomic, strong, nullable) dispatch_queue_t queue;
@property (nonatomic, strong, nullable) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionWebSocketTask *socket;
@property (nonatomic, strong, nullable) NSURL *identityURL;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *deviceCode;
@property (nonatomic, copy, nullable) NSString *serverPublic;
@property (nonatomic, strong, nullable) PDWeTypeKeyAgreement *agreement;
@property (nonatomic, strong, nullable) NSData *sessionKey;
@property (nonatomic, assign) uint64_t uin;
@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, assign) uint32_t task;
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, assign) uint64_t handshakeRequest;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, copy, nullable) void (^pendingHandshake)(NSDictionary *_Nullable, NSError *_Nullable);

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                  identityURL:(NSURL *)identityURL
                        model:(NSString *)model;

/// Kb-* header dictionary (12 base headers + the kind specific ones) with Kb-Sign.
- (NSDictionary<NSString *, NSString *> *)headersForBody:(NSData *)body
                                                    task:(uint32_t)task
                                                    kind:(PDWeTypeKind)kind
                                                   token:(nullable NSString *)token;

/// Sends one protobuf frame over the websocket and waits for the matching reply.
- (void)exchangePath:(NSString *)path
                task:(uint32_t)task
                body:(nullable NSData *)body
             headers:(nullable NSDictionary<NSString *, NSString *> *)headers
          completion:(void (^)(NSDictionary *_Nullable fields, NSError *_Nullable error))completion;

- (void)finishHandshake:(nullable NSDictionary *)fields error:(nullable NSError *)error;
- (void)prepare:(void (^)(NSError *_Nullable error))completion;
- (void)timestampThen:(void (^)(void))then failure:(void (^)(NSError *error))failure;
- (void)publicKeyForNewIdentity:(BOOL)newIdentity completion:(void (^)(NSError *_Nullable error))completion;
- (BOOL)saveIdentityWithError:(NSError *_Nullable *_Nullable)error;
- (void)generateUIN:(NSString *)token completion:(void (^)(NSError *_Nullable error))completion;

/// Encrypts and POSTs one opus packet, then decrypts the partial/final transcript.
- (void)sendAudio:(NSData *)audio
          voiceID:(NSString *)voiceID
         sequence:(uint32_t)sequence
              end:(BOOL)end
      traditional:(BOOL)traditional
       completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
