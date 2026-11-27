#import "PDFramePlayer.h"
#import "PDJailbreak.h"
#import <ImageIO/ImageIO.h>

static UIImage *PDFrameImage(NSString *path) {
    if (!path.length) return nil;
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    if (img.CGImage) return img;
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) return nil;
    CGImageRef cg = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!cg) return nil;
    img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

@interface PDFramePlayer ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSDictionary *clips;
@property (nonatomic, copy) NSArray<NSString *> *clipIDs;
@property (nonatomic, copy) NSArray<NSString *> *frames;
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *currentClip;
@property (nonatomic, assign) NSInteger frameIndex;
@property (nonatomic, assign) double frameMs;
@property (nonatomic, assign) BOOL loop;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSUInteger nextIndex;
@end

@implementation PDFramePlayer

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    self.hidden = YES;

    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.backgroundColor = [UIColor clearColor];
    _imageView.userInteractionEnabled = NO;
    [self addSubview:_imageView];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.font = [UIFont systemFontOfSize:9 weight:UIFontWeightMedium];
    _label.textColor = [UIColor colorWithWhite:0.25 alpha:0.75];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.45];
    _label.layer.cornerRadius = 4.0;
    _label.clipsToBounds = YES;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [self addGestureRecognizer:tap];

    [self loadClips];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    CGFloat h = 14.0;
    _label.frame = CGRectMake(0, CGRectGetMaxY(self.bounds) - h, self.bounds.size.width, h);
}

#pragma mark - 资源定位

- (NSArray<NSString *> *)candidateRoots {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];

    // 与 PDOverlayController 共用同一套越狱根解析，RootHide 的 jbroot 也能命中。
    for (NSString *p in PDLegacyImportedRoots()) {
        if (![roots containsObject:p]) [roots addObject:p];
    }
    for (NSString *p in PDAssetBundleRoots()) {
        if (![roots containsObject:p]) [roots addObject:p];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *base in PDImportSpoolDirectories()) {
        NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:base error:NULL];
        for (NSString *child in children) {
            NSString *p = [base stringByAppendingPathComponent:child];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
                if (![roots containsObject:p]) [roots addObject:p];
            }
        }
    }
    return roots;
}

- (void)loadClips {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in [self candidateRoots]) {
        NSString *clipsPath = [root stringByAppendingPathComponent:@"clips.plist"];
        NSString *framesDir = [root stringByAppendingPathComponent:@"frames"];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:clipsPath] ||
            ![fm fileExistsAtPath:framesDir isDirectory:&isDir] || !isDir) continue;
        NSDictionary *clips = [NSDictionary dictionaryWithContentsOfFile:clipsPath];
        if (![clips isKindOfClass:[NSDictionary class]] || clips.count == 0) continue;
        _root = [root copy];
        _clips = [clips copy];
        _clipIDs = [[clips allKeys] sortedArrayUsingSelector:@selector(compare:)];
        _nextIndex = 0;
        return;
    }
}

- (BOOL)hasClips {
    return _clips.count > 0 && _clipIDs.count > 0;
}

- (NSString *)nextClipID {
    if (_clipIDs.count == 0) return nil;
    NSString *clip = _clipIDs[_nextIndex % _clipIDs.count];
    _nextIndex++;
    return clip;
}

#pragma mark - 播放

- (void)playClip:(NSString *)clipID {
    if (![clipID isKindOfClass:[NSString class]] || !clipID.length) return;
    NSDictionary *clip = _clips[clipID];
    NSArray *frames = [clip isKindOfClass:[NSDictionary class]] ? clip[@"frames"] : nil;
    if (![frames isKindOfClass:[NSArray class]] || frames.count == 0) return;

    [self stopInternal];
    _currentClip = [clipID copy];
    _frames = [frames copy];
    _frameIndex = 0;
    double ms = [clip[@"frameMs"] doubleValue];
    if (!(ms > 0) || ms > 5000) ms = 100.0;
    _frameMs = ms;
    _loop = [clip[@"loop"] boolValue];
    _playing = YES;
    self.hidden = NO;
    [self showCurrentFrame];

    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:MAX(0.016, _frameMs / 1000.0)
                                              target:weakSelf
                                            selector:@selector(tick)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)showCurrentFrame {
    if (_frameIndex < 0 || _frameIndex >= (NSInteger)_frames.count) return;
    NSString *rel = _frames[(NSUInteger)_frameIndex];
    NSString *path = [[_root stringByAppendingPathComponent:@"frames"] stringByAppendingPathComponent:rel];
    UIImage *img = PDFrameImage(path);
    if (img) _imageView.image = img;
    _label.text = _currentClip;
}

- (void)tick {
    if (!_playing) return;
    NSInteger next = _frameIndex + 1;
    if (next >= (NSInteger)_frames.count) {
        if (_loop) next = 0;
        else { [self stop]; return; }
    }
    _frameIndex = next;
    [self showCurrentFrame];
}

- (void)stopInternal {
    [_timer invalidate];
    _timer = nil;
    _playing = NO;
}

- (void)stop {
    [self stopInternal];
    self.hidden = YES;
    _imageView.image = nil;
    _label.text = nil;
    _frames = nil;
    _currentClip = nil;
    void (^done)(void) = _completion;
    _completion = nil;
    if (done) done();
}

- (void)tapped:(id)sender {
    [self stop];
}

@end
