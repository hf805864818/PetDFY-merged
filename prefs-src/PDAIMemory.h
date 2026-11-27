//
//  PDAIMemory.h
//  PetDFYPrefs — reconstructed from build.080 (arm64)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PDAIMemory : NSObject

+ (id)protectedFileNames;
- (id) initWithRoot:(id)a1;
- (id) path:(id)a1;
- (id) writablePath:(id)a1 error:(void *)a2;
- (BOOL) prepareWrite:(id)a1 error:(void *)a2;
- (id)files;
- (id) read:(id)a1 error:(void *)a2;
- (id) imageForHandle:(id)a1;
- (id)systemContext;
- (BOOL) isProtectedFile:(id)a1;
- (BOOL) protected:(id)a1;
- (BOOL) removeGeneratedFiles:(void *)a1;
- (BOOL) removeConversationHandoffs:(void *)a1;
- (BOOL) removeFilesForConversationOnly:(BOOL)a1 error:(void *)a2;
- (void) snapshot:(id)a1 operation:(id)a2;
- (BOOL) write:(id)a1 path:(id)a2 operation:(id)a3 error:(void *)a4;
- (NSRange) lineRange:(id)a1 args:(id)a2;
- (id) lines:(id)a1;
- (id) glob:(id)a1;
- (id) executeTool:(id)a1 arguments:(id)a2;
- (id) run:(id)a1 arguments:(id)a2;
- (id)root;

@property (nonatomic, readonly) NSString *root;

@end
