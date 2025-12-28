#import "./include/audio_service/AudioServicePlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// If you'd like to help, please see the TODO comments below, then open a
// GitHub issue to announce your intention to work on a particular feature, and
// submit a pull request. We have an open discussion over at issue #10 about
// all things iOS if you'd like to discuss approaches or ask for input. Thank
// you for your support!

static NSHashTable<AudioServicePlugin *> *plugins = nil;
static FlutterMethodChannel *handlerChannel = nil;
static FlutterResult startResult = nil;
static MPRemoteCommandCenter *commandCenter = nil;
static NSMutableDictionary *mediaItem = nil;
static long actionBits = 0;
static NSMutableArray *commands;
static BOOL _controlsUpdated = NO;
static enum AudioProcessingState processingState = ApsIdle;
static BOOL playing = NO;
static NSNumber *position = nil;
static NSNumber *bufferedPosition = nil;
static NSNumber *updateTime = nil;
static NSNumber *speed = nil;
static NSNumber *repeatMode = nil;
static NSNumber *shuffleMode = nil;
static NSNumber *fastForwardInterval = nil;
static NSNumber *rewindInterval = nil;
static MPMediaItemArtwork* artwork = nil;
static NSMutableDictionary *nowPlayingInfo = nil;
static int forceUpdateCounter = 0;  // 用于强制刷新的计数器

@implementation AudioServicePlugin {
    FlutterMethodChannel *_channel;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    @synchronized(self) {
        if (!plugins) {
            plugins = [NSHashTable weakObjectsHashTable];
        }
        AudioServicePlugin *instance = [[AudioServicePlugin alloc] initWithRegistrar:registrar];
        [registrar addMethodCallDelegate:instance channel:instance.channel];
        [plugins addObject:instance];
        if (!handlerChannel) {
            processingState = ApsIdle;
            position = @(0);
            bufferedPosition = @(0);
            long long msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
            updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
            speed = [NSNumber numberWithDouble: 1.0];
            repeatMode = @(0);
            shuffleMode = @(0);
            nowPlayingInfo = [NSMutableDictionary new];
            handlerChannel = [FlutterMethodChannel
                methodChannelWithName:@"com.ryanheise.audio_service.handler.methods"
                      binaryMessenger:[registrar messenger]];
            [registrar addMethodCallDelegate:instance channel:handlerChannel];

#if TARGET_OS_IPHONE
            // 监听 app 生命周期事件，自动刷新 nowPlayingInfo
            // 这是解决"第二次进入后台灵动岛不显示"问题的关键
            // 由于 Dart 层的 MethodChannel 调用可能在 app 被挂起前未完成，
            // 所以我们直接在原生层监听生命周期事件

            // 使用 __weak 避免循环引用
            __weak AudioServicePlugin *weakInstance = instance;

            // 注意：使用 NSOperationQueue.mainQueue 确保在主线程处理
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                AudioServicePlugin *strongInstance = weakInstance;
                if (!strongInstance) return;

                NSLog(@"audio_service: [Block] applicationWillResignActive - playing=%d, hasNowPlayingInfo=%d",
                      playing, (nowPlayingInfo != nil && nowPlayingInfo.count > 0));
                if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
                    [strongInstance forceRefreshNowPlayingInfo];
                }
            }];

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                AudioServicePlugin *strongInstance = weakInstance;
                if (!strongInstance) return;

                NSLog(@"audio_service: [Block] applicationDidEnterBackground - playing=%d, hasNowPlayingInfo=%d",
                      playing, (nowPlayingInfo != nil && nowPlayingInfo.count > 0));
                if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
                    [strongInstance forceRefreshNowPlayingInfo];
                }
            }];

            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification * _Nonnull note) {
                AudioServicePlugin *strongInstance = weakInstance;
                if (!strongInstance) return;

                NSLog(@"audio_service: [Block] applicationDidBecomeActive - playing=%d", playing);
                // 当 app 从后台回到前台时，刷新 nowPlayingInfo
                // 这对于下一次进入后台时能正确触发灵动岛很重要
                if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
                    // 刷新一次 nowPlayingInfo，确保 iOS 系统知道我们仍在播放
                    [strongInstance forceRefreshNowPlayingInfo];
                }
            }];

            NSLog(@"audio_service: 已注册 app 生命周期监听 (block-based observers)");
#endif
        }
    }
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _channel = [FlutterMethodChannel
        methodChannelWithName:@"com.ryanheise.audio_service.client.methods"
              binaryMessenger:[registrar messenger]];
    return self;
}

- (FlutterMethodChannel *)channel {
    return _channel;
}

- (void)invokeClientMethod:(NSString *)method arguments:(id _Nullable)arguments {
    for (AudioServicePlugin *plugin in plugins) {
        [plugin.channel invokeMethod:method arguments:arguments];
    }
}

- (void)invokeClientMethod:(NSString *)method arguments:(id _Nullable)arguments result:(FlutterResult)result {
    for (AudioServicePlugin *plugin in plugins) {
        [plugin.channel invokeMethod:method arguments:arguments result:result];
    }
}

- (void)activateCommandCenter {
    //NSLog(@"### activateCommandCenter");
    commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    commands = [NSMutableArray new];
    [commands addObjectsFromArray:@[
        commandCenter.stopCommand,
        commandCenter.pauseCommand,
        commandCenter.playCommand,
        commandCenter.skipBackwardCommand,
        commandCenter.previousTrackCommand,
        commandCenter.nextTrackCommand,
        commandCenter.skipForwardCommand,
        [NSNull null],
        [NSNull null], // changePlaybackPositionCommand, put below
        commandCenter.togglePlayPauseCommand,
        [NSNull null],
        [NSNull null],
        [NSNull null],
        [NSNull null],
        [NSNull null],
        [NSNull null],
        [NSNull null],
        [NSNull null],
        commandCenter.changeRepeatModeCommand,
        [NSNull null],
        [NSNull null],
        commandCenter.changeShuffleModeCommand,
        commandCenter.seekBackwardCommand,
        commandCenter.seekForwardCommand,
        commandCenter.changePlaybackRateCommand,
    ]];
    if (@available(iOS 9.1, macOS 10.12.2, *)) {
        commands[8] = commandCenter.changePlaybackPositionCommand;
    }
    [commandCenter.changePlaybackRateCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPause:)];
    // TODO: enable more commands
    // Language options
    if (@available(iOS 9.0, macOS 10.12.2, *)) {
        [commandCenter.enableLanguageOptionCommand setEnabled:NO];
        [commandCenter.disableLanguageOptionCommand setEnabled:NO];
    }
    // Rating
    [commandCenter.ratingCommand setEnabled:NO];
    // Feedback
    [commandCenter.likeCommand setEnabled:NO];
    [commandCenter.dislikeCommand setEnabled:NO];
    [commandCenter.bookmarkCommand setEnabled:NO];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"configure" isEqualToString:call.method]) {
        NSDictionary *args = (NSDictionary *)call.arguments;
        NSDictionary *configMap = (NSDictionary *)args[@"config"];
        fastForwardInterval = configMap[@"fastForwardInterval"];
        rewindInterval = configMap[@"rewindInterval"];
        result(@{});
    } else if ([@"setState" isEqualToString:call.method]) {
        NSDictionary *args = (NSDictionary *)call.arguments;
        NSDictionary *stateMap = (NSDictionary *)args[@"state"];
        long long msSinceEpoch;
        if (stateMap[@"updateTime"] != [NSNull null]) {
            msSinceEpoch = [stateMap[@"updateTime"] longLongValue];
        } else {
            msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        }
        actionBits = 0;
        NSArray *controlsArray = stateMap[@"controls"];
        for (int i = 0; i < controlsArray.count; i++) {
            NSDictionary *control = (NSDictionary *)controlsArray[i];
            NSNumber *actionIndex = (NSNumber *)control[@"action"];
            int actionCode = 1 << [actionIndex intValue];
            actionBits |= actionCode;
        }
        NSArray *systemActionsArray = stateMap[@"systemActions"];
        for (int i = 0; i < systemActionsArray.count; i++) {
            NSNumber *actionIndex = (NSNumber *)systemActionsArray[i];
            int actionCode = 1 << [actionIndex intValue];
            actionBits |= actionCode;
        }
        processingState = [stateMap[@"processingState"] intValue];
        BOOL oldPlaying = playing;
        NSNumber *oldSpeed = speed;
        NSNumber *oldPosition = position;
        playing = [stateMap[@"playing"] boolValue];
        position = stateMap[@"updatePosition"];
        bufferedPosition = stateMap[@"bufferedPosition"];
        speed = stateMap[@"speed"];
        repeatMode = stateMap[@"repeatMode"];
        shuffleMode = stateMap[@"shuffleMode"];
        updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
        if (playing && !commandCenter) {
#if TARGET_OS_IPHONE
            [AVAudioSession sharedInstance];
#endif
            [self activateCommandCenter];
        }
        [self updateControls];
        if (playing != oldPlaying ||
            speed.doubleValue != oldSpeed.doubleValue ||
            position.longLongValue != oldPosition.longLongValue) {
            [self updateNowPlayingInfo];
        }
        result(@{});
    } else if ([@"setQueue" isEqualToString:call.method]) {
        result(@{});
    } else if ([@"setMediaItem" isEqualToString:call.method]) {
        NSDictionary *args = (NSDictionary *)call.arguments;
        mediaItem = args[@"mediaItem"];
        NSString* artUri = mediaItem[@"artUri"];
        artwork = nil;
        if (![artUri isEqual: [NSNull null]]) {
            NSString* artCacheFilePath = (NSString *)[NSNull null];
            NSDictionary* extras = mediaItem[@"extras"];
            if (![extras isEqual: [NSNull null]]) {
                artCacheFilePath = extras[@"artCacheFile"];
            }
            if (![artCacheFilePath isEqual: [NSNull null]]) {
#if TARGET_OS_IPHONE
                UIImage* artImage = [UIImage imageWithContentsOfFile:artCacheFilePath];
#else
                NSImage* artImage = [[NSImage alloc] initWithContentsOfFile:artCacheFilePath];
#endif
                if (artImage != nil) {
#if TARGET_OS_IPHONE
                    artwork = [[MPMediaItemArtwork alloc] initWithImage: artImage];
#else
                    artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artImage.size requestHandler:^NSImage* _Nonnull(CGSize aSize) {
                        return artImage;
                    }];
#endif
                }
            }
        }
        [self updateNowPlayingInfo];
        result(@{});
    } else if ([@"setPlaybackInfo" isEqualToString:call.method]) {
        result(@{});
    } else if ([@"notifyChildrenChanged" isEqualToString:call.method]) {
        result(@{});
    } else if ([@"androidForceEnableMediaButtons" isEqualToString:call.method]) {
        result(@{});
    } else if ([@"stopService" isEqualToString:call.method]) {
        [commandCenter.changePlaybackRateCommand setEnabled:NO];
        [commandCenter.togglePlayPauseCommand setEnabled:NO];
        [commandCenter.togglePlayPauseCommand removeTarget:nil];
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        processingState = ApsIdle;
        actionBits = 0;
        [self updateControls];
        _controlsUpdated = NO;
        startResult = nil;
        commandCenter = nil;
        result(@{});
    } else if ([@"forceUpdateNowPlayingInfo" isEqualToString:call.method]) {
        // 强制刷新 nowPlayingInfo，绕过 iOS 去重机制
        // 注意：现在主要依赖原生层的生命周期监听来触发刷新
        // 这个方法作为备用，仍可从 Dart 层调用
#if TARGET_OS_IPHONE
        [self forceRefreshNowPlayingInfo];
#endif
        result(@{});
    }
}

- (MPRemoteCommandHandlerStatus) play: (MPRemoteCommandEvent *) event {
    //NSLog(@"play");
    [handlerChannel invokeMethod:@"play" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) pause: (MPRemoteCommandEvent *) event {
    //NSLog(@"pause");
    [handlerChannel invokeMethod:@"pause" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (BOOL)updateNowPlayingField:(NSString *)field value:(id)value {
    if (![value isEqual:nowPlayingInfo[field]]) {
        if (value != nil && value != [NSNull null]) {
            //NSLog(@"### %@ = '%@'", field, value);
            nowPlayingInfo[field] = value;
        } else {
            //NSLog(@"### %@ = nil", field);
            [nowPlayingInfo removeObjectForKey:field];
        }
        return YES;
    }
    return NO;
}

- (void) updateNowPlayingInfo {
    // 注意：Apple 推荐的做法是始终设置整个 nowPlayingInfo 字典
    // 参考: https://developer.apple.com/forums/thread/32475
    // "maintain a dictionary with the current info in your model object,
    //  and always set the entire dictionary"
    //
    // 原因：iOS 的去重机制会跳过"相同"的更新，但只有当我们实际调用
    // center.nowPlayingInfo = ... 时，iOS 才会重新评估是否显示灵动岛

    if (mediaItem) {
        [self updateNowPlayingField:MPMediaItemPropertyTitle value:mediaItem[@"title"]];
        [self updateNowPlayingField:MPMediaItemPropertyAlbumTitle value:mediaItem[@"album"]];
        [self updateNowPlayingField:MPMediaItemPropertyArtist value:mediaItem[@"artist"]];
        NSNumber *duration = mediaItem[@"duration"];
        if (duration == (id)[NSNull null]) duration = @(0);
        [self updateNowPlayingField:MPMediaItemPropertyPlaybackDuration value:([NSNumber numberWithDouble: ([duration doubleValue] / 1000)])];
        if (@available(iOS 3.0, macOS 10.13.2, *)) {
            [self updateNowPlayingField:MPMediaItemPropertyArtwork value:artwork];
        }
    }

    if (@available(iOS 10.0, macOS 10.12.2, *)) {
        [self updateNowPlayingField:MPNowPlayingInfoPropertyMediaType value:@(MPNowPlayingInfoMediaTypeAudio)];
    }
    [self updateNowPlayingField:MPNowPlayingInfoPropertyPlaybackRate value:(playing ? speed : [NSNumber numberWithDouble: 0.0])];
    [self updateNowPlayingField:MPNowPlayingInfoPropertyDefaultPlaybackRate value:(playing ? speed : [NSNumber numberWithDouble: 0.0])];
    [self updateNowPlayingField:MPNowPlayingInfoPropertyElapsedPlaybackTime value:[NSNumber numberWithDouble:([position doubleValue] / 1000)]];

    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];

    // Fix for iOS: playbackState must be set on iOS 13+ for Dynamic Island and Control Center
    // See: https://github.com/ryanheise/audio_service/issues/1139
    if (@available(iOS 13.0, macOS 10.12.2, *)) {
        center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
    }

    if (@available(iOS 10.0, macOS 10.12.2, *)) {
        [self updateNowPlayingField:MPNowPlayingInfoPropertyIsLiveStream value:mediaItem[@"isLive"]];
    }

    // 始终设置 nowPlayingInfo，不检查是否有变化
    // 这是解决"第二次进入后台灵动岛不显示"问题的关键
    // iOS 系统会在内部处理去重，但只有当我们调用这个方法时，
    // 系统才会重新评估是否需要显示灵动岛
    center.nowPlayingInfo = nowPlayingInfo;
  
    // TODO: List of all unused "nowPlayingInfo" keys, we might want to use these at some point:
    //
    // * MPNowPlayingInfoCollectionIdentifier
    // * MPNowPlayingInfoPropertyAvailableLanguageOptions
    // * MPNowPlayingInfoPropertyAssetURL
    // * MPNowPlayingInfoPropertyChapterCount
    // * MPNowPlayingInfoPropertyChapterNumber
    // * MPNowPlayingInfoPropertyCurrentLanguageOptions
    // * MPNowPlayingInfoPropertyDefaultPlaybackRate
    // * MPNowPlayingInfoPropertyCurrentPlaybackDate
    // * MPNowPlayingInfoPropertyExternalContentIdentifier
    // * MPNowPlayingInfoPropertyExternalUserProfileIdentifier
    // * MPNowPlayingInfoPropertyPlaybackProgress
    // * MPNowPlayingInfoPropertyPlaybackQueueCount
    // * MPNowPlayingInfoPropertyPlaybackQueueIndex
    // * MPNowPlayingInfoPropertyServiceIdentifier
}

- (void) updateControls {
    if (!commandCenter) return;
    for (enum MediaAction action = AStop; action <= ASetSpeed; action++) {
        [self updateControl:action];
    }
    _controlsUpdated = YES;
}

- (void) updateControl:(enum MediaAction)action {
    MPRemoteCommand *command = commands[action];
    if (command == (id)[NSNull null]) return;
    // Shift the actionBits right until the least significant bit is the tested action bit, and AND that with a 1 at the same position.
    // All bytes become 0, other than the tested action bit, which will be 0 or 1 according to its status in the actionBits long.
    BOOL enable = ((actionBits >> action) & 1);
    if (_controlsUpdated && enable == command.enabled) return;
    //NSLog(@"## updateControl %@ enable=%@", @(action), @(enable));
    [command setEnabled:enable];
    switch (action) {
        case AStop:
            if (enable) {
                [commandCenter.stopCommand addTarget:self action:@selector(stop:)];
            } else {
                [commandCenter.stopCommand removeTarget:nil];
            }
            break;
        case APause:
            if (enable) {
                [commandCenter.pauseCommand addTarget:self action:@selector(pause:)];
            } else {
                [commandCenter.pauseCommand removeTarget:nil];
            }
            break;
        case APlay:
            if (enable) {
                [commandCenter.playCommand addTarget:self action:@selector(play:)];
            } else {
                [commandCenter.playCommand removeTarget:nil];
            }
            break;
        case ARewind:
            if (rewindInterval.integerValue > 0) {
                if (enable) {
                    [commandCenter.skipBackwardCommand addTarget: self action:@selector(skipBackward:)];
                    int rewindIntervalInSeconds = [rewindInterval intValue]/1000;
                    NSNumber *rewindIntervalInSec = [NSNumber numberWithInt: rewindIntervalInSeconds];
                    commandCenter.skipBackwardCommand.preferredIntervals = @[rewindIntervalInSec];
                } else {
                    [commandCenter.skipBackwardCommand removeTarget:nil];
                }
            }
            break;
        case ASkipToPrevious:
            if (enable) {
                [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack:)];
            } else {
                [commandCenter.previousTrackCommand removeTarget:nil];
            }
            break;
        case ASkipToNext:
            if (enable) {
                [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack:)];
            } else {
                [commandCenter.nextTrackCommand removeTarget:nil];
            }
            break;
        case AFastForward:
            if (fastForwardInterval.integerValue > 0) {
                if (enable) {
                    [commandCenter.skipForwardCommand addTarget: self action:@selector(skipForward:)];
                    int fastForwardIntervalInSeconds = [fastForwardInterval intValue]/1000;
                    NSNumber *fastForwardIntervalInSec = [NSNumber numberWithInt: fastForwardIntervalInSeconds];
                    commandCenter.skipForwardCommand.preferredIntervals = @[fastForwardIntervalInSec];
                } else {
                    [commandCenter.skipForwardCommand removeTarget:nil];
                }
            }
            break;
        case ASetRating:
            // TODO:
            // commandCenter.ratingCommand
            // commandCenter.dislikeCommand
            // commandCenter.bookmarkCommand
            break;
        case ASeekTo:
            if (@available(iOS 9.1, macOS 10.12.2, *)) {
                if (enable) {
                    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changePlaybackPosition:)];
                } else {
                    [commandCenter.changePlaybackPositionCommand removeTarget:nil];
                }
            }
            break;
        case APlayPause:
            // Automatically enabled.
            break;
        case ASetRepeatMode:
            if (enable) {
                [commandCenter.changeRepeatModeCommand addTarget:self action:@selector(changeRepeatMode:)];
            } else {
                [commandCenter.changeRepeatModeCommand removeTarget:nil];
            }
            break;
        case ASetShuffleMode:
            if (enable) {
                [commandCenter.changeShuffleModeCommand addTarget:self action:@selector(changeShuffleMode:)];
            } else {
                [commandCenter.changeShuffleModeCommand removeTarget:nil];
            }
            break;
        case ASeekBackward:
            if (enable) {
                [commandCenter.seekBackwardCommand addTarget:self action:@selector(seekBackward:)];
            } else {
                [commandCenter.seekBackwardCommand removeTarget:nil];
            }
            break;
        case ASeekForward:
            if (enable) {
                [commandCenter.seekForwardCommand addTarget:self action:@selector(seekForward:)];
            } else {
                [commandCenter.seekForwardCommand removeTarget:nil];
            }
            break;
        case ASetSpeed:
            if (enable) {
//                [commandCenter.changePlaybackRateCommand setSupportedPlaybackRates:@[@(1),@(1.5),@(2)]]
                [commandCenter.changePlaybackRateCommand addTarget:self action:@selector(changePlaybackRate:)];
            } else {
                [commandCenter.changePlaybackRateCommand removeTarget:nil];
            }
            break;
        default:
            break;
    }
}

- (MPRemoteCommandHandlerStatus) togglePlayPause: (MPRemoteCommandEvent *) event {
    //NSLog(@"togglePlayPause");
    [handlerChannel invokeMethod:@"click" arguments:@{
        @"button":@(0)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) stop: (MPRemoteCommandEvent *) event {
    //NSLog(@"stop");
    [handlerChannel invokeMethod:@"stop" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) nextTrack: (MPRemoteCommandEvent *) event {
    //NSLog(@"nextTrack");
    [handlerChannel invokeMethod:@"skipToNext" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) previousTrack: (MPRemoteCommandEvent *) event {
    //NSLog(@"previousTrack");
    [handlerChannel invokeMethod:@"skipToPrevious" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changePlaybackPosition: (MPChangePlaybackPositionCommandEvent *) event {
    //NSLog(@"changePlaybackPosition");
    [handlerChannel invokeMethod:@"seek" arguments: @{
        @"position":@((long long) (event.positionTime * 1000000.0))
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) skipForward: (MPRemoteCommandEvent *) event {
    //NSLog(@"skipForward");
    [handlerChannel invokeMethod:@"fastForward" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) skipBackward: (MPRemoteCommandEvent *) event {
    //NSLog(@"skipBackward");
    [handlerChannel invokeMethod:@"rewind" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) seekForward: (MPSeekCommandEvent *) event {
    //NSLog(@"seekForward");
    BOOL begin = event.type == MPSeekCommandEventTypeBeginSeeking;
    [handlerChannel invokeMethod:@"seekForward" arguments:@{
        @"begin":@(begin)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) seekBackward: (MPSeekCommandEvent *) event {
    //NSLog(@"seekBackward");
    BOOL begin = event.type == MPSeekCommandEventTypeBeginSeeking;
    [handlerChannel invokeMethod:@"seekBackward" arguments:@{
        @"begin":@(begin)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changeRepeatMode: (MPChangeRepeatModeCommandEvent *) event {
    //NSLog(@"changeRepeatMode");
    int modeIndex;
    switch (event.repeatType) {
        case MPRepeatTypeOff:
            modeIndex = 0;
            break;
        case MPRepeatTypeOne:
            modeIndex = 1;
            break;
        // MPRepeatTypeAll
        default:
            modeIndex = 2;
            break;
    }
    [handlerChannel invokeMethod:@"setRepeatMode" arguments:@{
        @"repeatMode":@(modeIndex)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changePlaybackRate: (MPChangePlaybackRateCommandEvent *) event {
    //NSLog(@"changePlaybackRate");
    [handlerChannel invokeMethod:@"setSpeed" arguments:@{
        @"speed":@(event.playbackRate)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changeShuffleMode: (MPChangeShuffleModeCommandEvent *) event {
    //NSLog(@"changeShuffleMode");
    int modeIndex;
    switch (event.shuffleType) {
        case MPShuffleTypeOff:
            modeIndex = 0;
            break;
        case MPShuffleTypeItems:
            modeIndex = 1;
            break;
        // MPShuffleTypeCollections
        default:
            modeIndex = 2;
            break;
    }
    [handlerChannel invokeMethod:@"setShuffleMode" arguments:@{
        @"shuffleMode":@(modeIndex)
    }];
    return MPRemoteCommandHandlerStatusSuccess;
}

#if TARGET_OS_IPHONE
/// 强制刷新 nowPlayingInfo，绕过 iOS 去重机制
/// 使用多种策略确保 iOS 正确显示灵动岛
- (void)forceRefreshNowPlayingInfo {
    if (nowPlayingInfo == nil || nowPlayingInfo.count == 0) {
        NSLog(@"audio_service: forceRefreshNowPlayingInfo - no nowPlayingInfo to refresh");
        return;
    }

    forceUpdateCounter++;
    NSLog(@"audio_service: forceRefreshNowPlayingInfo starting (counter=%d)", forceUpdateCounter);

    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];

    // 策略1: 先清空 nowPlayingInfo，强制 iOS 认为这是新的会话
    // 这是解决"第二次进入后台灵动岛不显示"的关键
    center.nowPlayingInfo = nil;

    // 策略2: 重置播放状态
    if (@available(iOS 13.0, *)) {
        center.playbackState = MPNowPlayingPlaybackStateUnknown;
    }

    // 策略3: 微调 elapsedPlaybackTime，确保值有变化
    NSNumber *currentElapsed = nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    double elapsedSeconds = currentElapsed ? [currentElapsed doubleValue] : 0.0;
    double adjustedElapsed = elapsedSeconds + (0.001 * (forceUpdateCounter % 1000));
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(adjustedElapsed);

    // 策略4: 确保 Remote Commands 处于激活状态
    if (commandCenter) {
        [commandCenter.playCommand setEnabled:YES];
        [commandCenter.pauseCommand setEnabled:YES];
        [commandCenter.togglePlayPauseCommand setEnabled:YES];
        [commandCenter.nextTrackCommand setEnabled:YES];
        [commandCenter.previousTrackCommand setEnabled:YES];
    }

    // 策略5: 重新设置 nowPlayingInfo
    // 注意：必须在主线程同步执行，不能使用 dispatch_async
    center.nowPlayingInfo = nowPlayingInfo;

    // 策略6: 设置正确的播放状态
    if (@available(iOS 13.0, *)) {
        center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
    }

    NSLog(@"audio_service: forceRefreshNowPlayingInfo completed (playing=%d, elapsed=%.3f, counter=%d)",
          playing, adjustedElapsed, forceUpdateCounter);
}

// 注意：生命周期监听现在使用 block-based observers，
// 在 registerWithRegistrar 中注册，不再需要 selector-based 方法
#endif

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
