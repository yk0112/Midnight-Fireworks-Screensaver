#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ScreenSaver/ScreenSaver.h>

#include <math.h>

static const NSInteger MFCanvasWidth = 320;
static const NSInteger MFCanvasHeight = 180;
static const NSInteger MFFramesPerSecond = 30;
static const NSInteger MFSeaHorizon = 116;
static const NSInteger MFShoreY = 157;
static const NSInteger MFMaxParticles = 1400;
static const NSInteger MFMaxSeeds = 20;

static NSString *const MFModuleIdentifier = @"local.codex.midnight-fireworks-screensaver";
static NSString *const MFAmbientSoundKey = @"AmbientSound";
static NSString *const MFWindChimeKey = @"WindChime";
static NSString *const MFFireworkSoundKey = @"FireworkSound";
static NSString *const MFIntervalKey = @"FireworkInterval";

typedef NS_ENUM(NSInteger, MFFireworkStyle) {
    MFFireworkStylePeony,
    MFFireworkStyleChrysanthemum,
    MFFireworkStyleWillow,
    MFFireworkStyleRing,
    MFFireworkStyleStrobe,
    MFFireworkStyleSenrin,
    MFFireworkStylePalm,
};

typedef struct {
    BOOL active;
    CGFloat x;
    CGFloat y;
    CGFloat vx;
    CGFloat vy;
    CGFloat gravity;
    CGFloat drag;
    NSInteger life;
    NSInteger maxLife;
    uint8_t color;
    uint8_t fadeColor;
    NSInteger twinkle;
    NSInteger size;
    NSInteger historyCount;
    CGFloat historyX[10];
    CGFloat historyY[10];
} MFParticle;

typedef struct {
    BOOL active;
    CGFloat x;
    CGFloat startY;
    CGFloat targetY;
    CGFloat y;
    CGFloat previousY;
    NSInteger age;
    NSInteger duration;
    MFFireworkStyle style;
    uint8_t color1;
    uint8_t color2;
    CGFloat scale;
} MFRocket;

typedef struct {
    BOOL active;
    CGFloat x;
    CGFloat y;
    CGFloat vx;
    CGFloat vy;
    NSInteger timer;
    uint8_t color1;
    uint8_t color2;
    CGFloat scale;
} MFSenrinSeed;

static uint32_t MFNextRandom(uint32_t *state) {
    uint32_t value = *state;
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    *state = value ?: 0xA341316Cu;
    return *state;
}

static CGFloat MFRandomUnit(uint32_t *state) {
    return (CGFloat)(MFNextRandom(state) & 0x00FFFFFFu) / (CGFloat)0x01000000u;
}

static CGFloat MFRandomBetween(uint32_t *state, CGFloat low, CGFloat high) {
    return low + (high - low) * MFRandomUnit(state);
}

static NSInteger MFRandomInteger(uint32_t *state, NSInteger low, NSInteger high) {
    if (high <= low) {
        return low;
    }
    return low + (NSInteger)(MFNextRandom(state) % (uint32_t)(high - low + 1));
}

static inline void MFPutPixel(uint32_t *pixels, NSInteger x, NSInteger y, uint32_t color) {
    if (x >= 0 && x < MFCanvasWidth && y >= 0 && y < MFCanvasHeight) {
        pixels[y * MFCanvasWidth + x] = color;
    }
}

static void MFFillRect(uint32_t *pixels, NSInteger x, NSInteger y, NSInteger width, NSInteger height, uint32_t color) {
    NSInteger left = MAX(0, x);
    NSInteger top = MAX(0, y);
    NSInteger right = MIN(MFCanvasWidth, x + width);
    NSInteger bottom = MIN(MFCanvasHeight, y + height);
    for (NSInteger row = top; row < bottom; row++) {
        for (NSInteger column = left; column < right; column++) {
            pixels[row * MFCanvasWidth + column] = color;
        }
    }
}

static void MFDitherRect(uint32_t *pixels, NSInteger x, NSInteger y, NSInteger width, NSInteger height, uint32_t color, NSInteger density) {
    for (NSInteger row = y; row < y + height; row++) {
        for (NSInteger column = x; column < x + width; column++) {
            if (((column * 3 + row * 5) & 7) < density) {
                MFPutPixel(pixels, column, row, color);
            }
        }
    }
}

static void MFDrawLine(uint32_t *pixels, NSInteger x0, NSInteger y0, NSInteger x1, NSInteger y1, uint32_t color) {
    NSInteger dx = labs(x1 - x0);
    NSInteger sx = x0 < x1 ? 1 : -1;
    NSInteger dy = -labs(y1 - y0);
    NSInteger sy = y0 < y1 ? 1 : -1;
    NSInteger error = dx + dy;
    while (YES) {
        MFPutPixel(pixels, x0, y0, color);
        if (x0 == x1 && y0 == y1) {
            break;
        }
        NSInteger twice = error * 2;
        if (twice >= dy) {
            error += dy;
            x0 += sx;
        }
        if (twice <= dx) {
            error += dx;
            y0 += sy;
        }
    }
}

static void MFFillCircle(uint32_t *pixels, NSInteger centerX, NSInteger centerY, NSInteger radius, uint32_t color) {
    NSInteger radiusSquared = radius * radius;
    for (NSInteger y = -radius; y <= radius; y++) {
        for (NSInteger x = -radius; x <= radius; x++) {
            if (x * x + y * y <= radiusSquared) {
                MFPutPixel(pixels, centerX + x, centerY + y, color);
            }
        }
    }
}

static void MFDitherCircle(uint32_t *pixels, NSInteger centerX, NSInteger centerY, NSInteger radius, uint32_t color, NSInteger density) {
    NSInteger radiusSquared = radius * radius;
    for (NSInteger y = -radius; y <= radius; y++) {
        for (NSInteger x = -radius; x <= radius; x++) {
            if (x * x + y * y <= radiusSquared && (((centerX + x) * 3 + (centerY + y) * 5) & 7) < density) {
                MFPutPixel(pixels, centerX + x, centerY + y, color);
            }
        }
    }
}

static void MFFillEllipse(uint32_t *pixels, NSInteger x, NSInteger y, NSInteger width, NSInteger height, uint32_t color) {
    if (width <= 0 || height <= 0) {
        return;
    }
    CGFloat rx = width / 2.0;
    CGFloat ry = height / 2.0;
    CGFloat cx = x + rx;
    CGFloat cy = y + ry;
    for (NSInteger row = y; row <= y + height; row++) {
        for (NSInteger column = x; column <= x + width; column++) {
            CGFloat nx = (column - cx) / rx;
            CGFloat ny = (row - cy) / ry;
            if (nx * nx + ny * ny <= 1.0) {
                MFPutPixel(pixels, column, row, color);
            }
        }
    }
}

static void MFDitherEllipse(uint32_t *pixels, NSInteger x, NSInteger y, NSInteger width, NSInteger height, uint32_t color, NSInteger density) {
    if (width <= 0 || height <= 0) {
        return;
    }
    CGFloat rx = width / 2.0;
    CGFloat ry = height / 2.0;
    CGFloat cx = x + rx;
    CGFloat cy = y + ry;
    for (NSInteger row = y; row <= y + height; row++) {
        for (NSInteger column = x; column <= x + width; column++) {
            CGFloat nx = (column - cx) / rx;
            CGFloat ny = (row - cy) / ry;
            if (nx * nx + ny * ny <= 1.0 && (((column * 3 + row * 5) & 7) < density)) {
                MFPutPixel(pixels, column, row, color);
            }
        }
    }
}

@interface MidnightFireworksView : ScreenSaverView <AVAudioPlayerDelegate> {
    uint32_t *_backdrop;
    uint32_t *_framePixels;
    uint32_t _palette[16];
    uint32_t _randomState;
    NSInteger _frameNumber;
    NSInteger _nextLaunchFrame;
    NSInteger _nextWindChimeFrame;
    NSInteger _pendingBoomFrames;
    NSInteger _testStyleIndex;
    BOOL _testMode;
    BOOL _previewMode;
    BOOL _ambientEnabled;
    BOOL _windChimeEnabled;
    BOOL _fireworkSoundEnabled;
    NSInteger _intervalMode;
    MFRocket _rocket;
    MFParticle _particles[MFMaxParticles];
    MFSenrinSeed _seeds[MFMaxSeeds];
    ScreenSaverDefaults *_defaults;
    AVAudioPlayer *_wavePlayer;
    AVAudioPlayer *_windChimePlayer;
    AVAudioPlayer *_fireworkPlayer;
    NSWindow *_configurationWindow;
    NSButton *_ambientCheckbox;
    NSButton *_windChimeCheckbox;
    NSButton *_fireworkCheckbox;
    NSPopUpButton *_intervalPopup;
}
@end

@implementation MidnightFireworksView

+ (BOOL)performGammaFade {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (!self) {
        return nil;
    }

    self.animationTimeInterval = 1.0 / (NSTimeInterval)MFFramesPerSecond;
    _previewMode = isPreview;
    _testMode = [NSProcessInfo.processInfo.environment[@"MIDNIGHT_SAVER_TEST_MODE"] boolValue];
    _randomState = _testMode ? 2026082u : arc4random();
    _backdrop = calloc((size_t)(MFCanvasWidth * MFCanvasHeight), sizeof(uint32_t));
    _framePixels = calloc((size_t)(MFCanvasWidth * MFCanvasHeight), sizeof(uint32_t));
    if (!_backdrop || !_framePixels) {
        return nil;
    }

    [self configurePalette];
    [self buildBackdrop];
    _defaults = [ScreenSaverDefaults defaultsForModuleWithName:MFModuleIdentifier];
    [_defaults registerDefaults:@{
        MFAmbientSoundKey: @NO,
        MFWindChimeKey: @NO,
        MFFireworkSoundKey: @NO,
        MFIntervalKey: @0,
    }];
    [self loadPreferences];
    [self resetShow];
    return self;
}

- (void)dealloc {
    [_wavePlayer stop];
    [_windChimePlayer stop];
    [_fireworkPlayer stop];
    free(_backdrop);
    free(_framePixels);
}

- (BOOL)isOpaque {
    return YES;
}

- (void)configurePalette {
    const uint32_t rgb[16] = {
        0x060814, 0x0B1025, 0x111A35, 0x1D2847,
        0x303A55, 0x4D5066, 0x7A6D75, 0xB2A097,
        0xE25555, 0xEE8C55, 0xFFD166, 0xFFF1C1,
        0x5ED6C3, 0x63A8E8, 0xA980D9, 0xF08DB7,
    };
    for (NSInteger index = 0; index < 16; index++) {
        _palette[index] = 0xFF000000u | rgb[index];
    }
}

- (void)buildBackdrop {
    MFFillRect(_backdrop, 0, 0, MFCanvasWidth, MFCanvasHeight, _palette[0]);
    MFFillRect(_backdrop, 0, 54, MFCanvasWidth, MFSeaHorizon - 54, _palette[1]);
    MFDitherRect(_backdrop, 0, 44, MFCanvasWidth, 24, _palette[1], 4);
    MFDitherRect(_backdrop, 0, 96, MFCanvasWidth, MFSeaHorizon - 96, _palette[2], 4);

    uint32_t backgroundRandom = 2020082u;
    for (NSInteger index = 0; index < 178; index++) {
        NSInteger x = MFRandomInteger(&backgroundRandom, 4, MFCanvasWidth - 5);
        NSInteger y = MFRandomInteger(&backgroundRandom, 4, MFSeaHorizon - 9);
        const uint8_t starColors[] = {3, 4, 4, 6, 7, 7, 11, 11, 13};
        uint8_t color = starColors[MFRandomInteger(&backgroundRandom, 0, 8)];
        MFPutPixel(_backdrop, x, y, _palette[color]);
    }

    NSInteger moonX = 258;
    NSInteger moonY = 28;
    MFDitherCircle(_backdrop, moonX, moonY, 15, _palette[10], 1);
    MFFillCircle(_backdrop, moonX, moonY, 9, _palette[11]);
    MFDitherCircle(_backdrop, moonX - 3, moonY - 2, 2, _palette[10], 3);
    MFFillCircle(_backdrop, moonX + 3, moonY + 3, 1, _palette[7]);
    MFPutPixel(_backdrop, moonX + 3, moonY - 4, _palette[10]);

    for (NSInteger index = 0; index < 3; index++) {
        NSInteger x = MFRandomInteger(&backgroundRandom, -70, MFCanvasWidth - 1);
        NSInteger y = MFRandomInteger(&backgroundRandom, 48, 92);
        NSInteger width = MFRandomInteger(&backgroundRandom, 42, 86);
        MFDitherEllipse(_backdrop, x, y, width, 7, _palette[3], 1);
        MFDitherEllipse(_backdrop, x + width * 0.16, y - 2, width * 0.50, 7, _palette[3], 1);
    }

    MFFillRect(_backdrop, 0, MFSeaHorizon, MFCanvasWidth, MFShoreY - MFSeaHorizon, _palette[1]);
    MFDitherRect(_backdrop, 0, MFSeaHorizon + 8, MFCanvasWidth, MFShoreY - MFSeaHorizon - 8, _palette[2], 4);
    MFDitherRect(_backdrop, 0, MFSeaHorizon + 24, MFCanvasWidth, MFShoreY - MFSeaHorizon - 24, _palette[3], 2);
    MFDrawLine(_backdrop, 0, MFSeaHorizon, MFCanvasWidth - 1, MFSeaHorizon, _palette[4]);

    const uint8_t glintColors[] = {2, 3, 3, 4, 13};
    for (NSInteger index = 0; index < 115; index++) {
        NSInteger x = MFRandomInteger(&backgroundRandom, 0, MFCanvasWidth - 1);
        NSInteger y = MFRandomInteger(&backgroundRandom, MFSeaHorizon + 4, MFShoreY - 3);
        NSInteger length = MFRandomInteger(&backgroundRandom, 1, 5);
        uint8_t color = glintColors[MFRandomInteger(&backgroundRandom, 0, 4)];
        MFDrawLine(_backdrop, x, y, x + length, y, _palette[color]);
    }

    for (NSInteger y = MFSeaHorizon + 2; y < MFShoreY - 1; y += 2) {
        CGFloat depth = (CGFloat)(y - MFSeaHorizon) / (CGFloat)(MFShoreY - MFSeaHorizon);
        NSInteger halfWidth = 2 + (NSInteger)(depth * 13.0);
        for (NSInteger band = 0; band < 2; band++) {
            NSInteger offset = (NSInteger)(sin(y * (0.47 + band * 0.11) + band * 2.4) * halfWidth * 0.72);
            NSInteger length = 1 + (NSInteger)(depth * 4.0) + band;
            uint32_t color = band == 0 ? _palette[10] : _palette[11];
            for (NSInteger x = moonX + offset - length; x <= moonX + offset + length; x++) {
                if (((x + y + band) & 3) != 0) {
                    MFPutPixel(_backdrop, x, y, color);
                }
            }
        }
    }

    MFFillEllipse(_backdrop, -22, MFSeaHorizon - 7, 105, 17, _palette[0]);
    MFFillEllipse(_backdrop, 275, MFSeaHorizon - 4, 76, 14, _palette[0]);
    MFDrawLine(_backdrop, 304, MFSeaHorizon - 7, 304, MFSeaHorizon, _palette[4]);
    MFPutPixel(_backdrop, 304, MFSeaHorizon - 8, _palette[10]);

    NSInteger boatX = 152;
    MFDrawLine(_backdrop, boatX, MFSeaHorizon + 13, boatX + 14, MFSeaHorizon + 13, _palette[0]);
    MFDrawLine(_backdrop, boatX + 3, MFSeaHorizon + 14, boatX + 11, MFSeaHorizon + 14, _palette[0]);
    MFDrawLine(_backdrop, boatX + 7, MFSeaHorizon + 13, boatX + 7, MFSeaHorizon + 8, _palette[4]);
    MFPutPixel(_backdrop, boatX + 7, MFSeaHorizon + 8, _palette[9]);

    MFFillRect(_backdrop, 0, MFShoreY + 2, MFCanvasWidth, MFCanvasHeight - MFShoreY - 2, _palette[2]);
    MFDitherRect(_backdrop, 0, MFShoreY + 7, MFCanvasWidth, MFCanvasHeight - MFShoreY - 7, _palette[6], 2);
    for (NSInteger x = 0; x < MFCanvasWidth; x++) {
        NSInteger y = MFShoreY + (NSInteger)(sin(x * 0.115) * 1.6);
        if (x % 10 != 0 && x % 10 != 1 && x % 10 != 2) {
            MFPutPixel(_backdrop, x, y, _palette[x % 7 ? 11 : 13]);
        }
        if (x % 19 == 0) {
            MFPutPixel(_backdrop, x, y + 1, _palette[7]);
        }
    }
    const uint8_t shoreColors[] = {1, 2, 4, 5, 6};
    for (NSInteger index = 0; index < 145; index++) {
        NSInteger x = MFRandomInteger(&backgroundRandom, 0, MFCanvasWidth - 1);
        NSInteger y = MFRandomInteger(&backgroundRandom, MFShoreY + 5, MFCanvasHeight - 1);
        if ((x + y) % 4 != 0) {
            MFPutPixel(_backdrop, x, y, _palette[shoreColors[MFRandomInteger(&backgroundRandom, 0, 4)]]);
        }
    }
    MFFillEllipse(_backdrop, -18, MFShoreY - 2, 55, 25, _palette[0]);
    MFFillEllipse(_backdrop, MFCanvasWidth - 38, MFShoreY + 7, 60, 20, _palette[0]);
    const NSInteger grassX[] = {290, 298, 307, 314};
    for (NSInteger index = 0; index < 4; index++) {
        NSInteger x = grassX[index];
        NSInteger height = 5 + x % 7;
        MFDrawLine(_backdrop, x, MFCanvasHeight - 1, x - 2, MFCanvasHeight - height, _palette[0]);
        MFDrawLine(_backdrop, x, MFCanvasHeight - height + 3, x + 3, MFCanvasHeight - height - 1, _palette[0]);
    }
}

- (void)loadPreferences {
    _ambientEnabled = [_defaults boolForKey:MFAmbientSoundKey];
    _windChimeEnabled = [_defaults boolForKey:MFWindChimeKey];
    _fireworkSoundEnabled = [_defaults boolForKey:MFFireworkSoundKey];
    _intervalMode = [_defaults integerForKey:MFIntervalKey];
}

- (void)resetShow {
    _frameNumber = 0;
    _rocket.active = NO;
    memset(_particles, 0, sizeof(_particles));
    memset(_seeds, 0, sizeof(_seeds));
    if (_testMode) {
        _nextLaunchFrame = 20;
    } else if (_previewMode) {
        _nextLaunchFrame = MFRandomInteger(&_randomState, MFFramesPerSecond, MFFramesPerSecond * 2);
    } else {
        _nextLaunchFrame = MFRandomInteger(&_randomState, MFFramesPerSecond * 3, MFFramesPerSecond * 5);
    }
    _nextWindChimeFrame = MFRandomInteger(&_randomState, MFFramesPerSecond * 55, MFFramesPerSecond * 120);
    _pendingBoomFrames = 0;
    _testStyleIndex = 0;
}

- (void)startAnimation {
    [self loadPreferences];
    [self resetShow];
    [super startAnimation];
    [self launchFirework];
    [self updateAmbientSound];
}

- (void)stopAnimation {
    [_wavePlayer stop];
    [_windChimePlayer stop];
    [_fireworkPlayer stop];
    [super stopAnimation];
}

- (AVAudioPlayer *)playerForResource:(NSString *)name volume:(CGFloat)volume loops:(NSInteger)loops {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *url = [bundle URLForResource:name withExtension:@"wav" subdirectory:@"Audio"];
    if (!url) {
        return nil;
    }
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if (!player || error) {
        return nil;
    }
    player.volume = volume;
    player.numberOfLoops = loops;
    [player prepareToPlay];
    return player;
}

- (void)updateAmbientSound {
    [_wavePlayer stop];
    _wavePlayer = nil;
    if (_ambientEnabled && !_previewMode && !_testMode && self.isAnimating) {
        _wavePlayer = [self playerForResource:@"waves_kudaka" volume:0.24 loops:-1];
        [_wavePlayer play];
    }
}

- (void)playWindChime {
    if (!_windChimeEnabled || _previewMode || _testMode) {
        return;
    }
    _windChimePlayer = [self playerForResource:@"wind_chime" volume:0.16 loops:0];
    [_windChimePlayer play];
}

- (void)playFireworkSound {
    if (!_fireworkSoundEnabled || _previewMode || _testMode) {
        return;
    }
    NSArray<NSString *> *names = @[@"firework_atami", @"firework_boom", @"firework_crackle", @"firework_wide"];
    NSString *name = names[MFRandomInteger(&_randomState, 0, names.count - 1)];
    _fireworkPlayer = [self playerForResource:name volume:0.13 loops:0];
    [_fireworkPlayer play];
}

- (void)scheduleNextLaunch {
    if (_testMode) {
        _nextLaunchFrame = _frameNumber + MFFramesPerSecond * 7;
    } else if (_previewMode) {
        _nextLaunchFrame = _frameNumber + MFRandomInteger(&_randomState, MFFramesPerSecond * 6, MFFramesPerSecond * 10);
    } else if (_intervalMode == 2) {
        _nextLaunchFrame = _frameNumber + MFRandomInteger(&_randomState, MFFramesPerSecond * 4, MFFramesPerSecond * 6);
    } else if (_intervalMode == 1) {
        _nextLaunchFrame = _frameNumber + MFRandomInteger(&_randomState, MFFramesPerSecond * 35, MFFramesPerSecond * 70);
    } else {
        _nextLaunchFrame = _frameNumber + MFRandomInteger(&_randomState, MFFramesPerSecond * 20, MFFramesPerSecond * 45);
    }
}

- (void)launchFirework {
    if (_rocket.active) {
        return;
    }
    const uint8_t colorPairs[][2] = {{10, 9}, {13, 14}, {15, 10}, {12, 13}, {11, 9}, {8, 15}};
    MFFireworkStyle style = _testMode
        ? (MFFireworkStyle)(_testStyleIndex++ % 7)
        : (MFFireworkStyle)MFRandomInteger(&_randomState, 0, 6);
    NSInteger paletteIndex = MFRandomInteger(&_randomState, 0, 5);
    _rocket.active = YES;
    _rocket.x = MFRandomBetween(&_randomState, 46.0, MFCanvasWidth - 46.0);
    _rocket.startY = MFRandomBetween(&_randomState, MFSeaHorizon + 3.0, MFSeaHorizon + 10.0);
    _rocket.targetY = MFRandomBetween(&_randomState, 38.0, 72.0);
    _rocket.y = _rocket.startY;
    _rocket.previousY = _rocket.y;
    _rocket.age = 0;
    _rocket.duration = MFRandomInteger(&_randomState, 36, 48);
    _rocket.style = style;
    _rocket.scale = MFRandomBetween(&_randomState, 0.55, 0.70);
    if (style == MFFireworkStyleWillow || style == MFFireworkStylePalm) {
        _rocket.color1 = 10;
        _rocket.color2 = 9;
    } else {
        _rocket.color1 = colorPairs[paletteIndex][0];
        _rocket.color2 = colorPairs[paletteIndex][1];
    }
    [self scheduleNextLaunch];
}

- (MFParticle *)availableParticle {
    for (NSInteger index = 0; index < MFMaxParticles; index++) {
        if (!_particles[index].active) {
            return &_particles[index];
        }
    }
    return NULL;
}

- (void)addParticleAtX:(CGFloat)x
                      y:(CGFloat)y
                     vx:(CGFloat)vx
                     vy:(CGFloat)vy
                   life:(NSInteger)life
                  color:(uint8_t)color
              fadeColor:(uint8_t)fadeColor
                gravity:(CGFloat)gravity
                   drag:(CGFloat)drag
               twinkle:(NSInteger)twinkle
                   size:(NSInteger)size
                  trail:(NSInteger)trail {
    MFParticle *particle = [self availableParticle];
    if (!particle) {
        return;
    }
    memset(particle, 0, sizeof(MFParticle));
    particle->active = YES;
    particle->x = x;
    particle->y = y;
    particle->vx = vx;
    particle->vy = vy;
    particle->life = life;
    particle->maxLife = life;
    particle->color = color;
    particle->fadeColor = fadeColor;
    particle->gravity = gravity;
    particle->drag = drag;
    particle->twinkle = twinkle;
    particle->size = size;
    particle->historyCount = MIN(10, trail);
    for (NSInteger index = 0; index < particle->historyCount; index++) {
        particle->historyX[index] = x;
        particle->historyY[index] = y;
    }
}

- (uint8_t)dimColorForColor:(uint8_t)color fallback:(uint8_t)fallback {
    switch (color) {
        case 8: return 5;
        case 9: return 8;
        case 10: return 9;
        case 11: return 10;
        case 12: return 3;
        case 13: return 3;
        case 14: return 2;
        case 15: return 6;
        default: return fallback;
    }
}

- (void)spawnRadialAtX:(CGFloat)x
                      y:(CGFloat)y
                  count:(NSInteger)count
               minSpeed:(CGFloat)minSpeed
               maxSpeed:(CGFloat)maxSpeed
                minLife:(NSInteger)minLife
                maxLife:(NSInteger)maxLife
                gravity:(CGFloat)gravity
                   drag:(CGFloat)drag
                  color1:(uint8_t)color1
                  color2:(uint8_t)color2
                   scale:(CGFloat)scale
                    even:(BOOL)even
                twinkle:(NSInteger)twinkle
                    size:(NSInteger)size
                   trail:(NSInteger)trail {
    NSInteger scaledCount = MAX(8, (NSInteger)(count * scale));
    for (NSInteger index = 0; index < scaledCount; index++) {
        CGFloat angle = even
            ? ((CGFloat)index / (CGFloat)scaledCount) * M_PI * 2.0 + MFRandomBetween(&_randomState, -0.03, 0.03)
            : MFRandomBetween(&_randomState, 0.0, M_PI * 2.0);
        CGFloat speed = MFRandomBetween(&_randomState, minSpeed, maxSpeed) * scale;
        uint8_t color = (index % 2 == 0) ? color1 : color2;
        NSInteger life = MFRandomInteger(&_randomState, minLife, maxLife);
        [self addParticleAtX:x
                           y:y
                          vx:cos(angle) * speed
                          vy:sin(angle) * speed
                        life:life
                       color:color
                   fadeColor:[self dimColorForColor:color fallback:5]
                     gravity:gravity
                        drag:drag
                    twinkle:twinkle
                        size:size
                       trail:trail];
    }
}

- (void)addSenrinSeedsAtX:(CGFloat)x y:(CGFloat)y color1:(uint8_t)color1 color2:(uint8_t)color2 scale:(CGFloat)scale {
    NSInteger count = MFRandomInteger(&_randomState, 8, 10);
    for (NSInteger index = 0; index < count && index < MFMaxSeeds; index++) {
        CGFloat angle = ((CGFloat)index / (CGFloat)count) * M_PI * 2.0 + MFRandomBetween(&_randomState, -0.15, 0.15);
        CGFloat speed = MFRandomBetween(&_randomState, 0.38, 0.58) * scale;
        _seeds[index].active = YES;
        _seeds[index].x = x;
        _seeds[index].y = y;
        _seeds[index].vx = cos(angle) * speed;
        _seeds[index].vy = sin(angle) * speed;
        _seeds[index].timer = MFRandomInteger(&_randomState, 15, 22);
        _seeds[index].color1 = index % 3 ? color1 : color2;
        _seeds[index].color2 = index % 3 ? color2 : color1;
        _seeds[index].scale = scale;
    }
}

- (void)explodeRocket {
    CGFloat x = _rocket.x;
    CGFloat y = _rocket.targetY;
    CGFloat scale = _rocket.scale;
    uint8_t first = _rocket.color1;
    uint8_t second = _rocket.color2;
    if (_testMode) {
        NSArray<NSString *> *styleNames = @[@"peony", @"chrysanthemum", @"willow", @"ring", @"strobe", @"senrin", @"palm"];
        NSLog(@"Firework test OK: %@", styleNames[_rocket.style]);
    }
    switch (_rocket.style) {
        case MFFireworkStylePeony:
            [self spawnRadialAtX:x y:y count:76 minSpeed:0.95 maxSpeed:1.65 minLife:34 maxLife:48 gravity:0.018 drag:0.978 color1:first color2:second scale:scale even:YES twinkle:0 size:1 trail:0];
            break;
        case MFFireworkStyleChrysanthemum:
            [self spawnRadialAtX:x y:y count:118 minSpeed:1.05 maxSpeed:1.72 minLife:54 maxLife:76 gravity:0.022 drag:0.982 color1:first color2:second scale:scale even:YES twinkle:0 size:1 trail:6];
            break;
        case MFFireworkStyleWillow:
            [self spawnRadialAtX:x y:y count:68 minSpeed:0.68 maxSpeed:1.20 minLife:86 maxLife:116 gravity:0.034 drag:0.987 color1:10 color2:9 scale:scale even:YES twinkle:0 size:1 trail:9];
            break;
        case MFFireworkStyleRing:
            [self spawnRadialAtX:x y:y count:64 minSpeed:1.40 maxSpeed:1.48 minLife:44 maxLife:58 gravity:0.017 drag:0.983 color1:first color2:second scale:scale even:YES twinkle:0 size:1 trail:3];
            break;
        case MFFireworkStyleStrobe:
            [self spawnRadialAtX:x y:y count:88 minSpeed:0.92 maxSpeed:1.58 minLife:52 maxLife:72 gravity:0.021 drag:0.980 color1:first color2:second scale:scale even:YES twinkle:4 size:1 trail:2];
            break;
        case MFFireworkStyleSenrin:
            [self spawnRadialAtX:x y:y count:24 minSpeed:0.52 maxSpeed:0.82 minLife:24 maxLife:34 gravity:0.012 drag:0.986 color1:first color2:second scale:scale even:YES twinkle:0 size:1 trail:2];
            [self addSenrinSeedsAtX:x y:y color1:first color2:second scale:scale];
            break;
        case MFFireworkStylePalm: {
            NSInteger rays = 12;
            for (NSInteger ray = 0; ray < rays; ray++) {
                CGFloat angle = ((CGFloat)ray / (CGFloat)rays) * M_PI * 2.0 + MFRandomBetween(&_randomState, -0.08, 0.08);
                for (NSInteger step = 0; step < 4; step++) {
                    CGFloat speed = (0.78 + step * 0.24) * scale;
                    [self addParticleAtX:x y:y vx:cos(angle) * speed vy:sin(angle) * speed life:MFRandomInteger(&_randomState, 66, 92) color:10 fadeColor:9 gravity:0.032 drag:0.985 twinkle:0 size:step == 3 ? 2 : 1 trail:8];
                }
            }
            break;
        }
    }
    _rocket.active = NO;
    _pendingBoomFrames = 18;
}

- (void)updateRocket {
    if (!_rocket.active) {
        return;
    }
    _rocket.previousY = _rocket.y;
    _rocket.age += 1;
    CGFloat t = MIN(1.0, (CGFloat)_rocket.age / (CGFloat)_rocket.duration);
    CGFloat eased = 1.0 - pow(1.0 - t, 1.45);
    CGFloat inverse = 1.0 - eased;
    _rocket.y = _rocket.startY * inverse + _rocket.targetY * eased - sin(M_PI * t) * 2.5;
    if (_rocket.age % 2 == 0) {
        [self addParticleAtX:_rocket.x + MFRandomBetween(&_randomState, -0.5, 0.5)
                           y:_rocket.y + 1
                          vx:MFRandomBetween(&_randomState, -0.03, 0.03)
                          vy:MFRandomBetween(&_randomState, 0.08, 0.16)
                        life:7
                       color:_rocket.color1
                   fadeColor:[self dimColorForColor:_rocket.color1 fallback:5]
                     gravity:0.008
                        drag:0.98
                    twinkle:0
                        size:1
                       trail:0];
    }
    if (_rocket.age >= _rocket.duration) {
        [self explodeRocket];
    }
}

- (void)updateSeeds {
    for (NSInteger index = 0; index < MFMaxSeeds; index++) {
        MFSenrinSeed *seed = &_seeds[index];
        if (!seed->active) {
            continue;
        }
        seed->x += seed->vx;
        seed->y += seed->vy;
        seed->vy += 0.006;
        seed->timer -= 1;
        if (seed->timer <= 0) {
            [self spawnRadialAtX:seed->x y:seed->y count:24 minSpeed:0.34 maxSpeed:0.60 minLife:25 maxLife:38 gravity:0.017 drag:0.980 color1:seed->color1 color2:seed->color2 scale:seed->scale * 0.78 even:YES twinkle:0 size:1 trail:2];
            seed->active = NO;
        }
    }
}

- (void)updateParticles {
    for (NSInteger index = 0; index < MFMaxParticles; index++) {
        MFParticle *particle = &_particles[index];
        if (!particle->active) {
            continue;
        }
        if (particle->historyCount > 0) {
            for (NSInteger history = particle->historyCount - 1; history > 0; history--) {
                particle->historyX[history] = particle->historyX[history - 1];
                particle->historyY[history] = particle->historyY[history - 1];
            }
            particle->historyX[0] = particle->x;
            particle->historyY[0] = particle->y;
        }
        particle->x += particle->vx;
        particle->y += particle->vy;
        particle->vx *= particle->drag;
        particle->vy = particle->vy * particle->drag + particle->gravity;
        particle->life -= 1;
        if (particle->life <= 0 || particle->x < -12 || particle->x > MFCanvasWidth + 12 || particle->y > MFCanvasHeight + 12) {
            particle->active = NO;
        }
    }
}

- (void)animateOneFrame {
    _frameNumber += 1;
    if (_frameNumber >= _nextLaunchFrame) {
        [self launchFirework];
    }
    [self updateRocket];
    [self updateSeeds];
    [self updateParticles];

    if (_pendingBoomFrames > 0) {
        _pendingBoomFrames -= 1;
        if (_pendingBoomFrames == 0) {
            [self playFireworkSound];
        }
    }
    if (_frameNumber >= _nextWindChimeFrame) {
        [self playWindChime];
        _nextWindChimeFrame = _frameNumber + MFRandomInteger(&_randomState, MFFramesPerSecond * 55, MFFramesPerSecond * 120);
    }
    [self setNeedsDisplay:YES];
}

- (void)renderFrame {
    memcpy(_framePixels, _backdrop, (size_t)(MFCanvasWidth * MFCanvasHeight) * sizeof(uint32_t));

    for (NSInteger index = 0; index < MFMaxSeeds; index++) {
        MFSenrinSeed seed = _seeds[index];
        if (seed.active) {
            MFPutPixel(_framePixels, (NSInteger)llround(seed.x), (NSInteger)llround(seed.y), _palette[seed.color1]);
        }
    }

    for (NSInteger index = 0; index < MFMaxParticles; index++) {
        MFParticle particle = _particles[index];
        if (!particle.active) {
            continue;
        }
        CGFloat ratio = (CGFloat)particle.life / (CGFloat)MAX(1, particle.maxLife);
        uint8_t color = ratio > 0.34 ? particle.color : particle.fadeColor;
        for (NSInteger history = 1; history < particle.historyCount; history++) {
            if (history < 3 || history % 2 == 0) {
                uint8_t trailColor = history > 2 ? [self dimColorForColor:color fallback:particle.fadeColor] : color;
                MFPutPixel(_framePixels, (NSInteger)llround(particle.historyX[history]), (NSInteger)llround(particle.historyY[history]), _palette[trailColor]);
            }
        }
        if (particle.twinkle > 0 && ((_frameNumber / particle.twinkle + (NSInteger)(particle.x + particle.y)) % 3 == 1)) {
            continue;
        }
        NSInteger x = (NSInteger)llround(particle.x);
        NSInteger y = (NSInteger)llround(particle.y);
        if (particle.size > 1 && ratio > 0.25) {
            MFFillCircle(_framePixels, x, y, particle.size - 1, _palette[color]);
        } else {
            MFPutPixel(_framePixels, x, y, _palette[color]);
        }
    }

    if (_rocket.active) {
        NSInteger x = (NSInteger)llround(_rocket.x);
        NSInteger y = (NSInteger)llround(_rocket.y);
        NSInteger previousY = (NSInteger)llround(_rocket.previousY);
        MFDrawLine(_framePixels, x, previousY, x, y, _palette[_rocket.color1]);
        MFPutPixel(_framePixels, x, y - 1, _palette[11]);
        MFPutPixel(_framePixels, x, y, _palette[_rocket.color1]);
    }
}

- (void)drawRect:(NSRect)rect {
    (void)rect;
    [self renderFrame];
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSetFillColorWithColor(context, NSColor.blackColor.CGColor);
    CGContextFillRect(context, NSRectToCGRect(self.bounds));

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, _framePixels, (size_t)(MFCanvasWidth * MFCanvasHeight) * sizeof(uint32_t), NULL);
    CGImageRef image = CGImageCreate(
        MFCanvasWidth,
        MFCanvasHeight,
        8,
        32,
        MFCanvasWidth * sizeof(uint32_t),
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
        provider,
        NULL,
        false,
        kCGRenderingIntentDefault
    );

    NSRect bounds = self.bounds;
    CGFloat scale = MAX(NSWidth(bounds) / MFCanvasWidth, NSHeight(bounds) / MFCanvasHeight);
    CGFloat width = MFCanvasWidth * scale;
    CGFloat height = MFCanvasHeight * scale;
    CGRect destination = CGRectMake(NSMidX(bounds) - width / 2.0, NSMidY(bounds) - height / 2.0, width, height);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawImage(context, destination, image);

    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
}

- (BOOL)hasConfigureSheet {
    return YES;
}

- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame fontSize:(CGFloat)fontSize {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = string;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:fontSize];
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.buttonType = NSButtonTypeSwitch;
    button.title = title;
    return button;
}

- (NSWindow *)configureSheet {
    if (_configurationWindow) {
        [self loadPreferencesIntoControls];
        return _configurationWindow;
    }

    _configurationWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 450, 300)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
    _configurationWindow.title = @"午前二時の花火 — 設定";
    NSView *content = _configurationWindow.contentView;
    [content addSubview:[self labelWithString:@"静かな海辺に、ときどき単発の花火が上がります。" frame:NSMakeRect(24, 250, 402, 24) fontSize:14]];

    [content addSubview:[self labelWithString:@"花火の間隔" frame:NSMakeRect(24, 208, 120, 22) fontSize:13]];
    _intervalPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(154, 204, 250, 28) pullsDown:NO];
    [_intervalPopup addItemsWithTitles:@[@"賑やか（4〜6秒）", @"静か（20〜45秒）", @"とても静か（35〜70秒）"]];
    _intervalPopup.itemArray[0].tag = 2;
    _intervalPopup.itemArray[1].tag = 0;
    _intervalPopup.itemArray[2].tag = 1;
    [content addSubview:_intervalPopup];

    [content addSubview:[self labelWithString:@"音（スクリーンセーバー中のみ）" frame:NSMakeRect(24, 166, 300, 22) fontSize:13]];
    _ambientCheckbox = [self checkboxWithTitle:@"さざ波" frame:NSMakeRect(42, 132, 170, 24)];
    _windChimeCheckbox = [self checkboxWithTitle:@"風鈴" frame:NSMakeRect(220, 132, 170, 24)];
    _fireworkCheckbox = [self checkboxWithTitle:@"遠くの花火音" frame:NSMakeRect(42, 98, 170, 24)];
    [content addSubview:_ambientCheckbox];
    [content addSubview:_windChimeCheckbox];
    [content addSubview:_fireworkCheckbox];
    [content addSubview:[self labelWithString:@"音はすべて初期状態ではオフです。" frame:NSMakeRect(42, 70, 350, 20) fontSize:11]];

    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(254, 20, 84, 32)];
    cancelButton.title = @"キャンセル";
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.target = self;
    cancelButton.action = @selector(cancelConfiguration:);
    [content addSubview:cancelButton];

    NSButton *doneButton = [[NSButton alloc] initWithFrame:NSMakeRect(344, 20, 84, 32)];
    doneButton.title = @"完了";
    doneButton.bezelStyle = NSBezelStyleRounded;
    doneButton.keyEquivalent = @"\r";
    doneButton.target = self;
    doneButton.action = @selector(saveConfiguration:);
    [content addSubview:doneButton];

    [self loadPreferencesIntoControls];
    return _configurationWindow;
}

- (void)loadPreferencesIntoControls {
    [self loadPreferences];
    _ambientCheckbox.state = _ambientEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _windChimeCheckbox.state = _windChimeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _fireworkCheckbox.state = _fireworkSoundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSInteger itemIndex = [_intervalPopup indexOfItemWithTag:_intervalMode];
    [_intervalPopup selectItemAtIndex:itemIndex == -1 ? 1 : itemIndex];
}

- (void)saveConfiguration:(id)sender {
    (void)sender;
    [_defaults setBool:_ambientCheckbox.state == NSControlStateValueOn forKey:MFAmbientSoundKey];
    [_defaults setBool:_windChimeCheckbox.state == NSControlStateValueOn forKey:MFWindChimeKey];
    [_defaults setBool:_fireworkCheckbox.state == NSControlStateValueOn forKey:MFFireworkSoundKey];
    [_defaults setInteger:_intervalPopup.selectedItem.tag forKey:MFIntervalKey];
    [_defaults synchronize];
    [self loadPreferences];
    [self updateAmbientSound];
    [NSApp endSheet:_configurationWindow];
    [_configurationWindow orderOut:nil];
}

- (void)cancelConfiguration:(id)sender {
    (void)sender;
    [self loadPreferencesIntoControls];
    [NSApp endSheet:_configurationWindow];
    [_configurationWindow orderOut:nil];
}

@end
