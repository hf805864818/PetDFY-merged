//
//  PDChatService.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class PDAIMemory;

@interface PDChatService : NSObject

+ (void) requestDataMaintenance:(id)a1 path:(id)a2 completion:(id)a3;
+ (id)defaultPromptTemplate;
+ (id) normalizedPromptTemplate:(id)a1;
+ (id)promptVariables;
+ (id) renderedPromptForTemplate:(id)a1;
+ (void) fetchModelsAtBaseURL:(id)a1 apiKey:(id)a2 completion:(id)a3;
+ (void) fetchModelCatalogAtBaseURL:(id)a1 apiKey:(id)a2 completion:(id)a3;
- (void) handleDataMaintenanceRequest:(id)a1;
- (id)init;
- (id) initWithDataDirectory:(id)a1 sessionConfiguration:(id)a2;
- (id)history;
- (id) error:(id)a1 code:(NSInteger)a2;
- (BOOL)isConfigured;
- (id) stamp:(id)a1;
- (void) sendText:(id)a1 completion:(id)a2;
- (void) enqueueEvent:(id)a1 wake:(BOOL)a2 preempt:(BOOL)a3;
- (void)persistHistory;
- (void)appendPendingEvents;
- (void)startTurn;
- (void) enqueueUserText:(id)a1 images:(id)a2;
- (void)requestRound;
- (void) sendPreparedRequest:(id)a1 settings:(id)a2 retryBytes:(id)a3 sentImages:(id)a4 endpoint:(id)a5 generation:(NSUInteger)a6 recovering:(BOOL)a7;
- (void) handleMessage:(id)a1;
- (void) recordTool:(id)a1 receipt:(id)a2;
- (void)runNextTool;
- (id) saveImage:(id)a1;
- (void) skipRemaining:(id)a1;
- (void) finish:(id)a1;
- (void)cancel;
- (void)clearHistory;
- (void) performDataMaintenance:(id)a1 path:(id)a2 completion:(id)a3;
- (id)historyURL;
- (void) setHistoryURL:(id)a1;
- (BOOL)busy;
- (void) setBusy:(BOOL)a1;
- (id)stateProvider;
- (void) setStateProvider:(id)a1;
- (id)toolHandler;
- (void) setToolHandler:(id)a1;
- (id)deviceToolHandler;
- (void) setDeviceToolHandler:(id)a1;
- (id)turnStateHandler;
- (void) setTurnStateHandler:(id)a1;
- (id)interruptionHandler;
- (void) setInterruptionHandler:(id)a1;
- (id)historyClearedHandler;
- (void) setHistoryClearedHandler:(id)a1;
- (id)mutableHistory;
- (void) setMutableHistory:(id)a1;
- (id)pendingEvents;
- (void) setPendingEvents:(id)a1;
- (id)pendingAttachments;
- (void) setPendingAttachments:(id)a1;
- (id)dataDirectory;
- (void) setDataDirectory:(id)a1;
- (id)session;
- (void) setSession:(id)a1;
- (id)task;
- (void) setTask:(id)a1;
- (id)storageQueue;
- (void) setStorageQueue:(id)a1;
- (id)memory;
- (void) setMemory:(id)a1;
- (id)calls;
- (void) setCalls:(id)a1;
- (id)toolMedia;
- (void) setToolMedia:(id)a1;
- (id)refusedImages;
- (void) setRefusedImages:(id)a1;
- (NSUInteger)callIndex;
- (void) setCallIndex:(NSUInteger)a1;
- (NSUInteger)round;
- (void) setRound:(NSUInteger)a1;
- (NSUInteger)generation;
- (void) setGeneration:(NSUInteger)a1;
- (BOOL)wakePending;
- (void) setWakePending:(BOOL)a1;
- (BOOL)maintainingData;
- (void) setMaintainingData:(BOOL)a1;
- (id)lastMaintenanceID;
- (void) setLastMaintenanceID:(id)a1;
- (NSUInteger)contextStart;
- (void) setContextStart:(NSUInteger)a1;
- (id)handoffFile;
- (void) setHandoffFile:(id)a1;
- (id)handoffText;
- (void) setHandoffText:(id)a1;
- (id)lastStampDay;
- (void) setLastStampDay:(id)a1;
- (id)lastText;
- (void) setLastText:(id)a1;
- (id)legacyCompletion;
- (void) setLegacyCompletion:(id)a1;

@property (nonatomic, strong) NSMutableArray *mutableHistory;
@property (nonatomic, strong) NSMutableArray *pendingEvents;
@property (nonatomic, strong) NSMutableArray *pendingAttachments;
@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, strong) NSURL *historyURL;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSObject<OS_dispatch_queue> *storageQueue;
@property (nonatomic, strong) PDAIMemory *memory;
@property (nonatomic, strong) NSArray *calls;
@property (nonatomic, strong) NSMutableDictionary *toolMedia;
@property (nonatomic, strong) NSMutableDictionary *refusedImages;
@property (nonatomic, assign) NSUInteger callIndex;
@property (nonatomic, assign) NSUInteger round;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL wakePending;
@property (nonatomic, assign) BOOL maintainingData;
@property (nonatomic, copy) NSString *lastMaintenanceID;
@property (nonatomic, assign) NSUInteger contextStart;
@property (nonatomic, copy) NSString *handoffFile;
@property (nonatomic, copy) NSString *handoffText;
@property (nonatomic, copy) NSString *lastStampDay;
@property (nonatomic, copy) NSString *lastText;
@property (nonatomic, copy) id legacyCompletion;
@property (nonatomic, readonly) NSArray *history;
@property (nonatomic, copy) id stateProvider;
@property (nonatomic, copy) id toolHandler;
@property (nonatomic, copy) id deviceToolHandler;
@property (nonatomic, copy) id turnStateHandler;
@property (nonatomic, copy) id interruptionHandler;
@property (nonatomic, copy) id historyClearedHandler;

@end
