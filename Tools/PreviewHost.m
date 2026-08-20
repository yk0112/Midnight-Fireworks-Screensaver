#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 && argc != 4) {
            fprintf(stderr, "usage: PreviewHost SAVER_PATH OUTPUT_PNG [SETTINGS_PNG]\n");
            return 2;
        }
        setenv("MIDNIGHT_SAVER_TEST_MODE", "1", 1);
        [NSApplication sharedApplication];
        NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [NSString stringWithUTF8String:argv[2]];
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"Could not load screen saver: %@", error);
            return 3;
        }
        Class principalClass = bundle.principalClass;
        if (!principalClass || ![principalClass isSubclassOfClass:ScreenSaverView.class]) {
            NSLog(@"Invalid principal class: %@", principalClass);
            return 4;
        }
        ScreenSaverView *view = [[principalClass alloc] initWithFrame:NSMakeRect(0, 0, 1280, 720) isPreview:NO];
        if (!view) {
            return 5;
        }
        NSWindow *window = [[NSWindow alloc] initWithContentRect:view.frame
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.contentView = view;
        for (NSInteger frame = 0; frame < 75; frame++) {
            [view animateOneFrame];
        }
        [view display];
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![pngData writeToFile:outputPath atomically:YES]) {
            return 6;
        }
        for (NSInteger frame = 75; frame < 1650; frame++) {
            [view animateOneFrame];
        }
        NSWindow *settingsWindow = view.configureSheet;
        if (!view.hasConfigureSheet || !settingsWindow) {
            NSLog(@"Missing configuration sheet");
            return 7;
        }
        NSPopUpButton *intervalPopup = [view valueForKey:@"intervalPopup"];
        NSArray<NSString *> *expectedTitles = @[@"賑やか（4〜6秒）", @"静か（20〜45秒）", @"とても静か（35〜70秒）"];
        NSArray<NSNumber *> *expectedTags = @[@2, @0, @1];
        if (intervalPopup.numberOfItems != expectedTitles.count) {
            return 8;
        }
        for (NSInteger index = 0; index < expectedTitles.count; index++) {
            if (![[intervalPopup itemTitleAtIndex:index] isEqualToString:expectedTitles[index]] ||
                [intervalPopup itemAtIndex:index].tag != expectedTags[index].integerValue) {
                return 9;
            }
        }
        if (argc == 4) {
            [intervalPopup selectItemAtIndex:0];
            [settingsWindow center];
            [settingsWindow makeKeyAndOrderFront:nil];
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            CGImageRef settingsImage = CGWindowListCreateImage(
                CGRectNull,
                kCGWindowListOptionIncludingWindow,
                (CGWindowID)settingsWindow.windowNumber,
                kCGWindowImageDefault
            );
#pragma clang diagnostic pop
            if (!settingsImage) {
                return 10;
            }
            NSBitmapImageRep *settingsBitmap = [[NSBitmapImageRep alloc] initWithCGImage:settingsImage];
            CGImageRelease(settingsImage);
            NSData *settingsPNG = [settingsBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *settingsPath = [NSString stringWithUTF8String:argv[3]];
            if (![settingsPNG writeToFile:settingsPath atomically:YES]) {
                return 11;
            }
            [settingsWindow orderOut:nil];
        }
        [view setValue:@NO forKey:@"testMode"];
        [view setValue:@NO forKey:@"previewMode"];
        NSArray<NSNumber *> *modes = @[@2, @0, @1];
        NSArray<NSNumber *> *minimumFrames = @[@120, @600, @1050];
        NSArray<NSNumber *> *maximumFrames = @[@180, @1350, @2100];
        SEL scheduleSelector = NSSelectorFromString(@"scheduleNextLaunch");
        for (NSInteger index = 0; index < modes.count; index++) {
            [view setValue:modes[index] forKey:@"intervalMode"];
            [view setValue:@1000 forKey:@"frameNumber"];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[view methodSignatureForSelector:scheduleSelector]];
            invocation.selector = scheduleSelector;
            [invocation invokeWithTarget:view];
            NSInteger delta = [[view valueForKey:@"nextLaunchFrame"] integerValue] - 1000;
            if (delta < minimumFrames[index].integerValue || delta > maximumFrames[index].integerValue) {
                return 11;
            }
        }
        [view setValue:@YES forKey:@"testMode"];
        [view startAnimation];
        if ([[view valueForKey:@"nextLaunchFrame"] integerValue] != 210) {
            return 12;
        }
        NSDate *runUntil = [NSDate dateWithTimeIntervalSinceNow:4.0];
        while (runUntil.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if (!view.isAnimating) {
            return 13;
        }
        [view stopAnimation];
        NSLog(@"Screen saver preview OK: %@", outputPath);
    }
    return 0;
}
