//
//  PDAssetImporter.h
//  petdfy-voice — reconstructed from build.080 (arm64 slice)
//
//  The asset subsystem shares the helper process with the voice channel: IPC
//  command 4 carries an asset request dictionary and the helper answers once and
//  exits.  Behavioural notes and per-function pseudo code: out/notes/asset.md.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDAssetErrorDomain;   // "PetDFY.Assets"

/// AssetImports root (hardcoded in the original).
extern NSString *const PDAssetImportRoot;    // /var/mobile/Library/Application Support/PetDFY/AssetImports

/// Relative-path gate used by every asset file operation.
BOOL PDAssetSafeRelativePath(NSString *_Nullable relative);

/// Joins `relative` under `root` and lstat()s every component: no symlinks,
/// intermediate components must be directories, the last one a file or a dir.
BOOL PDAssetRegularPath(NSString *_Nullable root, NSString *_Nullable relative, BOOL wantDirectory);

/// `<bundleRoot>/.asset-state`, `<bundleRoot>/.asset-state/import.zip` style helpers.
NSString *_Nullable PDAssetStatePath(NSString *_Nullable bundleRoot);
NSString *_Nullable PDAssetImportPath(NSString *_Nullable token);
NSString *_Nullable PDAssetImportDirectory(void);

/// Reads and validates `<bundleRoot>/asset-spec.json` ({schema:1, asset_version:""}).
NSDictionary *_Nullable PDAssetSpecification(NSString *_Nullable bundleRoot);

/// Sanitises an externally supplied download URL (http/https, host, no user/fragment).
NSURL *_Nullable PDAssetDownloadURL(NSString *_Nullable string);

/// Runs one asset operation synchronously.  `report` receives progress
/// dictionaries (@{@"status": ..., @"progress": @(n)}); the return value is the
/// result dictionary (@{@"ready": @YES} or a typed error).
NSDictionary *_Nullable PDRunAssetRequestWithProgress(NSDictionary *_Nullable request,
                                                      void (^_Nullable report)(NSDictionary *progress));

NS_ASSUME_NONNULL_END
