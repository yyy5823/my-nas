# iOS 灵动岛 (Dynamic Island) 修复记录

## 问题描述

音乐模块在 iPhone 上存在灵动岛显示问题：

1. **问题一（闪烁）**：第一次 app 切到后台，灵动岛触发后会消失一下然后再出现
2. **问题二（不触发）**：从后台返回前台，再次切到后台时，灵动岛完全不显示
3. **问题三（上一首/下一首无法播放）**：在灵动岛直接操作上一首/下一首时无法播放，进入 app 后界面变了但歌曲一直在 loading

## 相关文件

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m` - iOS 原生音频服务插件
- `lib/features/music/data/services/music_audio_handler.dart` - Dart 层音频处理器

## 问题分析

### 日志关键发现

```
[NowPlayingInfo] Setting identical nowPlayingInfo, skipping update.
```

iOS 的 MediaRemote 框架内部有**去重机制**，当检测到 `nowPlayingInfo` 与之前相同时，会跳过更新。

另一个关键日志：
```
[MRNowPlaying] Ignoring setPlaybackState because application does not contain entitlement
```

这表明可能存在权限问题，但主要问题仍是去重机制。

## 修复尝试

### 尝试一：Dart 层调用 forceUpdateNowPlayingInfo

**方案**：在 `MusicAudioHandler` 的 `didChangeAppLifecycleState` 中，当 app 进入 `paused` 状态时调用原生方法刷新 `nowPlayingInfo`。

**原生实现**：
```objc
- (void)forceUpdateNowPlayingInfo {
    // 清空 nowPlayingInfo
    center.nowPlayingInfo = nil;
    // 延迟 150ms 后重新设置
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), ..., ^{
        center.nowPlayingInfo = nowPlayingInfo;
    });
}
```

**结果**：❌ 失败

**原因**：
1. Dart 的 `didChangeAppLifecycleState` 是同步的，无法 await MethodChannel 调用
2. MethodChannel 是异步的，app 在调用完成前就被挂起
3. `dispatch_after` 延迟执行的代码在 app 被挂起后不会执行

### 尝试二：原生层 Selector-based 生命周期监听

**方案**：在原生层直接监听 `UIApplicationDidEnterBackgroundNotification`，不依赖 Dart 层。

**实现**：
```objc
[[NSNotificationCenter defaultCenter] addObserver:instance
                                         selector:@selector(applicationDidEnterBackground:)
                                             name:UIApplicationDidEnterBackgroundNotification
                                           object:nil];
```

**结果**：❌ 部分失败

**原因**：
1. 日志显示 `applicationDidEnterBackground` 只触发了一次
2. `applicationWillResignActive` 日志完全没有出现
3. 注册确认日志 "已注册 app 生命周期监听" 也没有出现
4. 可能是 selector-based observer 的引用问题

### 尝试三：Block-based 生命周期监听

**方案**：改用 block-based observer，使用 `NSOperationQueue.mainQueue` 确保主线程执行。

**实现**：
```objc
__weak AudioServicePlugin *weakInstance = instance;

[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
                                                  object:nil
                                                   queue:[NSOperationQueue mainQueue]
                                              usingBlock:^(NSNotification * _Nonnull note) {
    AudioServicePlugin *strongInstance = weakInstance;
    if (!strongInstance) return;
    [strongInstance forceRefreshNowPlayingInfo];
}];
```

**同时添加三个监听**：
- `UIApplicationWillResignActiveNotification` - app 即将进入非活跃状态
- `UIApplicationDidEnterBackgroundNotification` - app 已进入后台
- `UIApplicationDidBecomeActiveNotification` - app 已回到前台

**结果**：❌ 待验证

**问题**：日志中完全没有我们的 `audio_service:` 日志，说明代码可能没有被编译进去。

### 尝试四：改进 forceRefreshNowPlayingInfo 策略（使用 Interrupted 状态）

**之前的策略问题**：
1. 清空 `center.nowPlayingInfo = nil` 导致灵动岛先消失再出现（闪烁）
2. 微调 `elapsedPlaybackTime` 0.001 秒太小，iOS 可能忽略

**新策略**：使用 `MPNowPlayingPlaybackStateInterrupted` 状态触发重新评估

**结果**：❌ 失败

**日志验证**（2024-12-28 14:00:19）：
```
audio_service: [Block] applicationDidEnterBackground - playing=1, hasNowPlayingInfo=1
audio_service: forceRefreshNowPlayingInfo starting (counter=2)
audio_service: forceRefreshNowPlayingInfo completed (playing=1, elapsed=1.302, counter=2)
```

代码确实在执行，但 **闪烁问题仍然存在**！

**原因分析**：
- 使用 `MPNowPlayingPlaybackStateInterrupted` 状态会导致 iOS 认为播放被中断
- 灵动岛在收到 Interrupted 状态时会消失
- 然后恢复 Playing 状态时重新出现
- **这本身就是闪烁的根源！**

### 尝试五：简化策略，移除 Interrupted 状态

**方案**：不使用任何会导致灵动岛消失的状态变化

**实现**：
```objc
- (void)forceRefreshNowPlayingInfo {
    // 重要：不要清空 nowPlayingInfo
    // 重要：不要使用 Interrupted 状态

    // 使用当前时间戳作为 elapsedPlaybackTime，确保每次都不同
    long long msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(msSinceEpoch / 1000.0);

    // 确保 playbackRate 正确
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(playing ? 1.0 : 0.0);

    // 直接设置 nowPlayingInfo
    center.nowPlayingInfo = nowPlayingInfo;

    // 设置播放状态（直接设置，不经过 Interrupted）
    center.playbackState = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
}
```

**结果**：❌ 失败

**日志分析**（14:16:07）：
```
audio_service: forceRefreshNowPlayingInfo completed (playing=1, elapsed=5.473, counter=4)
[NowPlayingInfo] Setting nowPlayingInfo with mergePolicy Replace: NULL
[NowPlayingInfo] Clearing nowPlayingInfo
```

**问题发现**：原生层刚设置完 nowPlayingInfo，立刻被清空为 NULL！

### 尝试六：发现 Dart 层与原生层冲突（根本原因）

**日志关键证据**：
```
Dec 28 14:16:07.402867 audio_service: [Block] applicationWillResignActive
Dec 28 14:16:07.402917 audio_service: forceRefreshNowPlayingInfo starting (counter=4)
Dec 28 14:16:07.403157 audio_service: forceRefreshNowPlayingInfo completed
Dec 28 14:16:07.403316 [NowPlayingInfo] Setting nowPlayingInfo with mergePolicy Replace: NULL
Dec 28 14:16:07.403824 [NowPlayingInfo] Clearing nowPlayingInfo
```

**根本原因分析**：

查看 `music_audio_handler.dart` 中的 `didChangeAppLifecycleState`：

```dart
case AppLifecycleState.inactive:
  _resetMediaItemForNowPlaying();  // 问题在这里！

case AppLifecycleState.hidden:
  _resetMediaItemForNowPlaying();  // 这里也有！
```

**冲突链条**：
1. iOS `UIApplicationWillResignActiveNotification` 触发 → 原生层调用 `forceRefreshNowPlayingInfo()` 设置 nowPlayingInfo
2. Flutter `AppLifecycleState.inactive` 同时触发 → Dart 层调用 `_resetMediaItemForNowPlaying()`
3. `_resetMediaItemForNowPlaying()` 调用 `mediaItem.add()` → 触发 audio_service 更新 nowPlayingInfo
4. audio_service 内部处理覆盖了原生层刚设置的值，导致 nowPlayingInfo 被清空

**解决方案**：移除 Dart 层 `inactive` 和 `hidden` 状态下的 `_resetMediaItemForNowPlaying()` 调用

**修改文件**：`lib/features/music/data/services/music_audio_handler.dart`

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.inactive:
      // 不在这里刷新！原生层会通过 UIApplicationWillResignActiveNotification 处理
      logger.d('MusicAudioHandler: App 进入 inactive 状态，等待原生层处理');

    case AppLifecycleState.hidden:
      // 不在这里刷新！避免与原生层冲突
      logger.d('MusicAudioHandler: App 进入 hidden 状态，等待原生层处理');

    case AppLifecycleState.paused:
      // Dart 层只广播播放状态，不调用 _resetMediaItemForNowPlaying()
      if (mediaItem.value != null) {
        _broadcastStateWithPlaying(_player.playing);
      }
    // ...
  }
}
```

**结果**：✅ 修复闪烁问题（问题一）

### 尝试七：发现 elapsedPlaybackTime 使用错误值

**问题**：尝试五中使用 Unix 时间戳作为 `elapsedPlaybackTime`

```objc
// 错误代码：
long long msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(msSinceEpoch / 1000.0);
// 这会设置 elapsedPlaybackTime 为 ~1735430000 秒（约 55 年）！
```

**解决方案**：使用正确的播放位置 + 微小偏移量

**结果**：❌ 未验证 - 代码未被重新编译

---

### 尝试六 & 七 验证失败

**日志分析**（14:30 日志）：

1. 日志中完全没有 `audio_service:` 前缀的输出
2. 说明原生层的代码修改**没有被编译进 app 中**
3. 用户测试的仍然是旧版本

**关键证据**：
```
# 搜索 audio_service 日志 - 无结果
grep "audio_service:" combined_all.log  # 空
```

**结论**：尝试六和尝试七的修改需要重新构建 iOS 应用才能生效

---

### 尝试八：分析灵动岛闪烁的真正原因

**日志时间线分析**（14:30:37）：

```
14:30:35.909 - 第一次 setNowPlayingInfo
14:30:37.434 - 第二次 setNowPlayingInfo（间隔 1.5 秒）
14:30:37.447361 - 收到 clientSettings 更新
14:30:37.447484 - Invalidate layout mode (reason: client)
14:30:37.447515 - Assertion invalidate (preferredLayoutMode: none)
14:30:37.447574 - Created assertion (preferredLayoutMode: compact)
14:30:37.447604 - 再次 Invalidate (reason: client) ⚠️ 问题在这里！
14:30:37.447638 - Assertion invalidate (compact)
14:30:37.447695 - Created assertion (compact)
14:30:40.543 - App 进入后台
```

**问题发现**：
1. 灵动岛在 14:30:37.447 时就开始闪烁，此时 app **还在前台**
2. 在 13ms 内发生了两次 invalidate + create 循环
3. 闪烁发生在第二次 `setNowPlayingInfo` 调用后约 13ms

**可能原因**：Dart 层的延迟刷新代码

查看 `music_audio_handler.dart` 的 `setCurrentMusic` 方法：
```dart
// 延迟刷新：等待 audio_service 初始化完成后刷新一次
if (Platform.isIOS) {
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mediaItem.value?.id == music.id) {
      _resetMediaItemForNowPlaying();  // 这会触发第二次更新！
    }
  });
}
```

这个 500ms 延迟刷新会在歌曲开始播放后触发第二次 `mediaItem.add()`，导致灵动岛闪烁。

**解决方案**：移除 `setCurrentMusic` 中的 500ms 延迟刷新代码

**修改文件**：`lib/features/music/data/services/music_audio_handler.dart`

```dart
// 移除以下代码：
if (Platform.isIOS) {
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mediaItem.value?.id == music.id) {
      _resetMediaItemForNowPlaying();
    }
  });
}
```

**结果**：⏳ 待验证（与尝试九一起验证）

---

### 尝试九：修复返回前台刷新和 paused 状态广播问题

**分析流程**：

```
首次进入后台:
1. WillResignActive → forceRefreshNowPlayingInfo → 灵动岛显示

返回前台:
2. DidBecomeActive → forceRefreshNowPlayingInfo ⚠️ 问题点！

第二次进入后台:
3. WillResignActive → forceRefreshNowPlayingInfo → iOS 可能认为没有变化而跳过
```

**问题分析**：

1. **applicationDidBecomeActive 刷新问题**：当用户从后台返回前台时，`forceRefreshNowPlayingInfo` 被调用。当用户再次进入后台时，iOS 可能认为 nowPlayingInfo 刚刚更新过（在返回前台时），没有实质变化，从而跳过灵动岛的显示。

2. **Dart 层 paused 状态广播问题**：在 `paused` 状态下调用 `_broadcastStateWithPlaying()` 可能触发 audio_service 原生层更新 nowPlayingInfo，与我们的 `forceRefreshNowPlayingInfo` 冲突，导致闪烁。

**解决方案**：

#### 原生层修改

**文件**：`AudioServicePlugin.m`

1. 移除 `applicationDidBecomeActive` 中的 `forceRefreshNowPlayingInfo` 调用
2. 增大偏移量（从 0.001 秒改为 0.1 秒），确保 iOS 识别变化

```objc
// 返回前台时不刷新
[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                              object:nil
                                               queue:[NSOperationQueue mainQueue]
                                          usingBlock:^(NSNotification * _Nonnull note) {
    // 重要：返回前台时 *不* 刷新 nowPlayingInfo
    // 原因：如果在返回前台时刷新，iOS 可能认为下一次进入后台时
    // nowPlayingInfo 没有变化（刚刚更新过），从而跳过灵动岛的显示
    // 只在进入后台时（WillResignActive/DidEnterBackground）刷新
}];

// 增大偏移量
double offsetInSeconds = forceUpdateCounter * 0.1;  // 每次增加 100 毫秒偏移（原来是 1 毫秒）
```

#### Dart 层修改

**文件**：`music_audio_handler.dart`

移除 `paused` 状态下的 `_broadcastStateWithPlaying()` 调用：

```dart
case AppLifecycleState.paused:
  // Dart 层在 paused 状态下 *不做任何操作*：
  // - 不调用 _resetMediaItemForNowPlaying()（避免 mediaItem 冲突）
  // - 不调用 _broadcastStateWithPlaying()（避免 playbackState 冲突）
  // 原因：任何 Dart 层的状态更新都可能触发 audio_service 原生层
  // 更新 nowPlayingInfo，与我们的 forceRefreshNowPlayingInfo 冲突，导致闪烁
  logger.d('MusicAudioHandler: App 已进入后台 (paused)，等待原生层处理灵动岛');
```

**核心原则**：灵动岛刷新**完全**由原生层控制，Dart 层在生命周期变化时不做任何可能触发 nowPlayingInfo 更新的操作。

**结果**：⏳ 待验证

---

## 当前修改总结（需要重新构建）

以下修改需要重新构建 iOS 应用才能生效：

### 1. Dart 层修改

**文件**：`lib/features/music/data/services/music_audio_handler.dart`

- ✅ 移除 `didChangeAppLifecycleState` 中 `inactive` 和 `hidden` 状态的 `_resetMediaItemForNowPlaying()` 调用
- ✅ 移除 `setCurrentMusic` 中的 500ms 延迟刷新代码
- ✅ **（新）** 移除 `paused` 状态下的 `_broadcastStateWithPlaying()` 调用

### 2. 原生层修改

**文件**：`AudioServicePlugin.m`

- ✅ 修复 `forceRefreshNowPlayingInfo` 中错误使用 Unix 时间戳的问题
- ✅ 使用正确的播放位置 + 微小偏移量绕过 iOS 去重机制
- ✅ **（新）** 移除 `applicationDidBecomeActive` 中的 `forceRefreshNowPlayingInfo` 调用
- ✅ **（新）** 增大偏移量从 0.001 秒到 0.1 秒，确保 iOS 识别变化

### 重新构建命令

```bash
cd /Volumes/od/my-nas
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --debug
```

## 关键技术点

### iOS MediaRemote 去重机制

iOS 的 `MPNowPlayingInfoCenter` 内部会对 `nowPlayingInfo` 进行去重：
- 如果新设置的信息与当前信息"相同"，会跳过更新
- 日志表现为：`[NowPlayingInfo] Setting identical nowPlayingInfo, skipping update.`

### 灵动岛显示条件

1. 有效的 `nowPlayingInfo` 字典
2. `playbackState` 设置为 `MPNowPlayingPlaybackStatePlaying`
3. Remote Commands 正确配置
4. 活跃的 Audio Session

### App 生命周期事件顺序

```
前台 → 后台:
1. UIApplicationWillResignActiveNotification (即将失去活跃状态)
2. UIApplicationDidEnterBackgroundNotification (已进入后台)

后台 → 前台:
1. UIApplicationWillEnterForegroundNotification (即将进入前台)
2. UIApplicationDidBecomeActiveNotification (已变为活跃状态)
```

## 修复总结

### 问题一（闪烁）- ✅ 已修复

**根本原因**：

1. **Dart 层延迟刷新**：`setCurrentMusic` 中的 500ms 延迟刷新会触发第二次 `mediaItem.add()`
2. **Dart 与原生层冲突**：`inactive` 状态下的 `_resetMediaItemForNowPlaying()` 与原生层的 `forceRefreshNowPlayingInfo()` 冲突
3. **paused 状态广播冲突**：`paused` 状态下的 `_broadcastStateWithPlaying()` 触发 audio_service 更新 nowPlayingInfo

**修复方案**：
1. 移除 `setCurrentMusic` 中的 500ms 延迟刷新代码
2. 移除 `inactive` 和 `hidden` 状态下的 `_resetMediaItemForNowPlaying()` 调用
3. 移除 `paused` 状态下的 `_broadcastStateWithPlaying()` 调用
4. 让原生层**完全**控制灵动岛的刷新

### 问题二（第二次不触发）- ✅ 已修复

**根本原因**：

1. **MXSession ClientType = None**：iOS 在创建新的 MXSession 时，检测到 `ClientIsPlaying = STOPPED`，将 ClientType 设置为 `None`
2. **DoesntActuallyPlayAudio = YES**：由于 ClientType = None，iOS 认为应用不会实际播放音频
3. **NowPlayingInfo 被跳过更新**：iOS 的去重机制跳过了"相同"的 nowPlayingInfo 更新

**修复方案**（尝试十四）：
1. 在原生层添加 `reactivateAudioSession` 方法，直接调用 AVAudioSession 激活音频会话
2. 在 `applicationWillResignActive` 时调用 `reactivateAudioSessionAndRefresh`
3. 在 `applicationDidBecomeActive` 时调用 `reactivateAudioSession`
4. 确保 iOS 创建新的 MXSession 时能正确识别音频播放状态

## 验证结果

1. ✅ **问题一（闪烁）**：已修复
2. ✅ **问题二（第二次不触发）**：已修复
3. ⏳ **问题三（上一首/下一首无法播放）**：待验证（尝试十五）
4. ℹ️ **entitlement 警告**：日志显示 `[MRNowPlaying] Ignoring setPlaybackState because application does not contain entitlement`
   - 这是 iOS 的正常警告，不影响灵动岛功能
   - 可以忽略

## 参考资料

- [Apple Developer Forums - Now Playing Info](https://developer.apple.com/forums/thread/32475)
- [audio_service Issue #1139](https://github.com/ryanheise/audio_service/issues/1139)
- Apple 推荐：始终设置完整的 `nowPlayingInfo` 字典，而不是只更新部分字段

## 更新日志

| 日期 | 修改内容 |
|------|----------|
| 2024-12-28 | 初始问题分析，尝试 Dart 层调用 |
| 2024-12-28 | 尝试原生层 selector-based 监听 |
| 2024-12-28 | 改用 block-based 监听 + 改进刷新策略 |
| 2024-12-28 | 日志分析确认代码执行；发现 Interrupted 状态导致闪烁 |
| 2024-12-28 | 尝试五：移除 Interrupted 状态，简化刷新策略 |
| 2024-12-28 | 尝试六：修复 Dart 层与原生层生命周期处理冲突 |
| 2024-12-28 | 尝试七：修复 elapsedPlaybackTime 使用错误的 Unix 时间戳 |
| 2024-12-28 | **验证失败**：日志显示代码未被重新编译，没有 audio_service: 输出 |
| 2024-12-28 | **尝试八**：分析日志发现 500ms 延迟刷新导致闪烁，移除该代码 |
| 2024-12-28 | **尝试九**：进一步分析，发现返回前台时刷新和 paused 状态广播导致问题 |
| 2024-12-28 | **重要发现**：验证代码修改未被编译进应用，需完全重新构建 |
| 2024-12-28 | ✅ **问题一修复**：闪烁问题已解决 |
| 2024-12-28 | **尝试十一**：发现返回前台时 iOS 将播放状态重置为 NOT PLAYING，导致问题二 |
| 2024-12-28 | **尝试十二**：Dart 层 + 原生层双重广播播放状态，确保状态同步 |
| 2024-12-28 | **尝试十三**：Dart 层重新激活 AudioSession（失败）|
| 2024-12-28 | ✅ **尝试十四**：原生层重新激活 AVAudioSession - 问题二修复成功！ |
| 2024-12-28 | **尝试十五**：修复灵动岛上一首/下一首无法播放 - 处理程序未注册问题 |

---

### 尝试十：验证代码编译问题

**日期**：2024-12-28

**分析过程**：

用户提供的日志中完全没有 `audio_service:` 前缀的任何输出。我们在 `AudioServicePlugin.m` 第38行添加了：

```objc
NSLog(@"audio_service: ===== AudioServicePlugin registerWithRegistrar called =====");
```

这行日志应该在**应用启动时**（插件注册时）就输出。但日志中（15:20:46 - 15:20:53）虽然显示 Runner 进程启动，却没有任何 `audio_service:` 输出。

**验证步骤**：

1. 检查符号链接：
   ```bash
   ls -la ios/.symlinks/plugins/audio_service
   # 结果：正确指向 packages/audio_service_fixed/
   ```

2. 检查源代码：
   ```bash
   grep "audio_service:" packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m
   # 结果：确认存在多个 NSLog(@"audio_service:...") 语句
   ```

**根本原因**：

CocoaPods/Xcode 使用了缓存的编译产物，没有重新编译我们修改的 `AudioServicePlugin.m`。即使源文件已更新，Pod 的编译缓存仍指向旧版本。

**解决方案**：

执行完整的缓存清理和重新构建：

```bash
# 1. 清理所有缓存
rm -rf ios/Pods
rm -rf ios/.symlinks
rm -rf ~/Library/Developer/Xcode/DerivedData/*my_nas*

# 2. 重新获取依赖
flutter clean
flutter pub get

# 3. 重新安装 Pods
cd ios && pod install --repo-update && cd ..

# 4. 重新构建应用
flutter run -d <device_id>
```

**当前状态**：

已执行上述清理步骤，符号链接已重新创建并正确指向 `packages/audio_service_fixed/`。需要用户重新构建应用并测试。

**验证方法**：

测试新构建的应用时，日志中应该能看到：
1. 启动时出现 `audio_service: ===== AudioServicePlugin registerWithRegistrar called =====`
2. 进入后台时出现 `audio_service: [Block] applicationWillResignActive`
3. 返回前台时出现 `audio_service: [Block] applicationDidBecomeActive`

如果这些日志出现，说明代码修改已生效，可以进行问题验证。

**结果**：✅ 代码已生效，问题一（闪烁）已修复

---

### 尝试十一：修复返回前台时播放状态被重置

**日期**：2024-12-28

**问题现象**：问题一（闪烁）已修复，但问题二（第二次进入后台灵动岛不触发）仍然存在。

**日志分析**：

```
15:49:19.108144 Runner(audio_service)[43795]: audio_service: [Block] applicationDidBecomeActive - playing=1
15:49:19.108639 audiomxd(MediaExperience)[119]: Posting nowPlayingAppIsPlayingDidChange to: NOT PLAYING
```

关键发现：
1. 我们的 `applicationDidBecomeActive` 正常触发，`playing=1` 说明我们认为自己在播放
2. 但仅 0.5ms 后，iOS 系统（audiomxd）将播放状态设置为 `NOT PLAYING`！

**根本原因**：

当应用从后台返回前台时，iOS 系统会自动将应用的播放状态重置为 `NOT PLAYING`。这是 iOS 的默认行为。

后果：
1. 第一次进入后台 → 灵动岛正常显示（此时系统知道我们在播放）
2. 返回前台 → iOS 系统将我们标记为 NOT PLAYING
3. 第二次进入后台 → 系统认为我们没有在播放，不显示灵动岛

**解决方案**：

在 `applicationDidBecomeActive` 时，如果应用仍在播放状态，需要延迟 100ms 后重新设置播放状态，覆盖 iOS 的重置。

**代码修改**：

```objc
[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                              object:nil
                                               queue:[NSOperationQueue mainQueue]
                                          usingBlock:^(NSNotification * _Nonnull note) {
    // ... 原有代码 ...

    // 关键修复：当应用返回前台时，iOS 系统会将播放状态重置为 NOT PLAYING
    // 我们需要延迟一小段时间后重新设置播放状态，确保系统识别我们仍在播放
    if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
        // 延迟 100ms 后重新设置播放状态
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
                MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
                center.nowPlayingInfo = nowPlayingInfo;
                if (@available(iOS 13.0, *)) {
                    center.playbackState = MPNowPlayingPlaybackStatePlaying;
                }
            }
        });
    }
}];
```

**为什么需要延迟 100ms**：

iOS 系统在应用返回前台时会执行一系列内部状态更新。如果我们立即设置播放状态，可能会被系统的后续更新覆盖。延迟 100ms 可以确保 iOS 完成其内部处理后，我们再重新设置播放状态。

**结果**：❌ 失败 - iOS 系统在 2 秒后仍将 playbackState 覆盖为 Paused

---

### 尝试十二：Dart 层 + 原生层双重广播播放状态

**日期**：2024-12-28

**问题分析**：

日志显示尝试十一的修复没有效果：

```
16:01:42 - forceRefreshNowPlayingInfo completed (playing=1)
16:01:44 - playbackState: playing → paused (iOS 系统覆盖)
16:01:45 - NOT PLAYING
```

iOS 系统在我们设置 playbackState = Playing 后约 2 秒，将其覆盖为 Paused。

**网络搜索结果**：

根据 [audio_service Issue #684](https://github.com/ryanheise/audio_service/issues/684) 和 [Apple Developer Forums](https://developer.apple.com/forums/thread/756082)：

1. **已知问题**：`playbackState` 和 `mediaItem` 状态变化转发到 iOS 平台侧后，不能一致地反映在控制中心
2. **第一次更新可能有效**，但后续更新可能不生效
3. **可能存在 nowPlayingInfo 竞态条件**阻止更新
4. **iOS 上 `MPNowPlayingInfoCenter.playbackState` 的效果可能不如 macOS**

**根本原因假设**：

我们只在原生层设置了 `MPNowPlayingInfoCenter.playbackState`，但 Dart 层的 `playbackState` 没有同步广播。audio_service 内部可能检测到 Dart 层状态与原生层不一致，导致 iOS 系统覆盖我们的设置。

**解决方案**：

在返回前台时，同时在原生层和 Dart 层重新广播播放状态：

1. **原生层**（已在尝试十一实现）：延迟 100ms 后设置 `MPNowPlayingInfoCenter.playbackState = Playing`
2. **Dart 层**（新增）：延迟 200ms 后调用 `_broadcastStateWithPlaying(true)`

**代码修改**：

```dart
// music_audio_handler.dart - didChangeAppLifecycleState
case AppLifecycleState.resumed:
  logger.i('MusicAudioHandler: App 返回前台 (resumed), playing=${_player.playing}');

  // 关键修复：当应用返回前台时，iOS 系统会将播放状态重置为 NOT PLAYING
  // 我们需要在 Dart 层也重新广播播放状态，确保 audio_service 的状态同步
  if (_player.playing && mediaItem.value != null) {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_player.playing && mediaItem.value != null) {
        logger.i('MusicAudioHandler: 返回前台后重新广播播放状态');
        _broadcastStateWithPlaying(true);
      }
    });
  }
```

**时序设计**：

```
返回前台 (t=0)
    ↓
原生层设置 playbackState = Playing (t=100ms)
    ↓
Dart 层广播 playbackState.playing = true (t=200ms)
    ↓
iOS 系统检测到一致的播放状态，保持 Playing
```

**参考资料**：

- [audio_service Issue #684 - iOS control center issues](https://github.com/ryanheise/audio_service/issues/684)
- [Apple Developer Forums - Command Center / Dynamic Island](https://developer.apple.com/forums/thread/756082)
- [MPNowPlayingInfoCenter Documentation](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)

**结果**：❌ 失败 - iOS 系统仍然将 playbackState 覆盖为 Paused

---

### 尝试十三：返回前台时重新激活 AudioSession

**日期**：2024-12-28

**问题分析**：

深入分析日志发现了**根本原因**：

```
16:18:17.688648 - IsPlayingOutput = NO, DoesntActuallyPlayAudio = NO
16:18:17.697631 - setting DoesntActuallyPlayAudio = YES  ← mediaplaybackd 设置
16:18:19.570849 - IsPlayingOutput:NO  ← 没有实际音频输出！
16:18:20.369114 - setting AudioToolboxIsPlaying and IsPlayingOutput to false
16:18:20.793348 - NOT PLAYING
16:18:30.431567 - canBeNowPlayingApplication=NO
```

**关键发现**：

1. **`IsPlayingOutput:NO`** - iOS 检测到没有实际的音频输出
2. **`DoesntActuallyPlayAudio = YES`** - 系统认为应用不会实际播放音频
3. **`AudioToolboxIsPlaying = false`** - AudioToolbox 层的播放状态为 false
4. **`canBeNowPlayingApplication = NO`** - 系统认为应用无法成为 Now Playing 应用

**根本原因**：

iOS 不仅检查 `MPNowPlayingInfoCenter.playbackState`，还检查 **实际的音频输出状态**（`IsPlayingOutput`）。我们设置的 `playbackState = Playing` 无法覆盖 `IsPlayingOutput:NO` 的检测。

问题是：**音频会话（AudioSession）在应用返回前台时可能被系统自动停用**，导致 iOS 检测不到实际音频输出。

**Apple 文档确认**：

根据 [Apple Audio Session Programming Guide](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html)：

> "Your audio session can be deactivated automatically if your app is no longer active. So if you want your policy to be obeyed under all circumstances, **you must explicitly activate your audio session each time your app becomes active**. The best place to do this is in `applicationDidBecomeActive:`."

**解决方案**：

在应用返回前台时，**重新激活 AudioSession**：

1. 导入 `audio_session` 包
2. 在 `didChangeAppLifecycleState` 的 `resumed` case 中调用 `session.setActive(true)`
3. 延迟 200ms 后重新广播播放状态

**代码修改**：

```dart
// music_audio_handler.dart - 导入
import 'package:audio_session/audio_session.dart';

// didChangeAppLifecycleState - resumed case
case AppLifecycleState.resumed:
  logger.i('MusicAudioHandler: App 返回前台 (resumed), playing=${_player.playing}');

  // 关键修复（尝试十三）：
  // 根据 Apple 文档：音频会话可能在应用不活跃时被系统自动停用
  // 必须在应用每次激活时显式重新激活音频会话
  if (_player.playing && Platform.isIOS) {
    unawaited(_reactivateAudioSessionOnResumed());
  }

// 新增方法
Future<void> _reactivateAudioSessionOnResumed() async {
  try {
    final session = await AudioSession.instance;

    // 重新激活音频会话
    final success = await session.setActive(true);
    logger.i('MusicAudioHandler: 返回前台后重新激活 AudioSession, success=$success');

    // 延迟 200ms 后重新广播播放状态
    await Future<void>.delayed(const Duration(milliseconds: 200));

    if (_player.playing && mediaItem.value != null) {
      logger.i('MusicAudioHandler: 返回前台后重新广播播放状态');
      _broadcastStateWithPlaying(true);
    }
  } on Exception catch (e) {
    logger.w('MusicAudioHandler: 返回前台后重新激活 AudioSession 失败: $e');
  }
}
```

**时序设计**：

```
应用进入后台 (t=0)
    ↓
音频继续播放（后台）
    ↓
应用返回前台 (t=T)
    ↓
AudioSession 可能已被系统停用
    ↓
重新激活 AudioSession (t=T+0ms)
    ↓
原生层设置 playbackState = Playing (t=T+100ms)
    ↓
Dart 层广播 playbackState.playing = true (t=T+200ms)
    ↓
应用再次进入后台 (t=T+X)
    ↓
iOS 检测到 IsPlayingOutput = YES → 触发灵动岛
```

**排除的方案**：

- **ActivityKit 直接控制灵动岛**：用户明确排除此方案

**参考资料**：

- [Apple Audio Session Programming Guide - Activating an Audio Session](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html)
- [AVAudioSession Documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [Audio Guidelines By App Type](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioGuidelinesByAppType/AudioGuidelinesByAppType.html)

**结果**：❌ 失败 - 尝试十四继续分析

---

### 尝试十四：原生层重新激活 AVAudioSession

**日期**：2024-12-28

**问题分析**：

尝试十三在 Dart 层重新激活 AudioSession 没有解决问题。深入分析日志发现更根本的原因：

```
Dec 28 16:40:27.527844 - Creating MXSession = <ID: 196f, ClientIsPlaying = STOPPED, AudioToolboxIsPlaying = STOPPED>
Dec 28 16:40:27.527854 - MXSession with ID 196f for Runner(44231) setting ClientType = None  ← 根本问题！
Dec 28 16:40:30.401914 - MXSession(196f) of type None setting DoesntActuallyPlayAudio = YES
Dec 28 16:40:32.259543 - [NowPlayingInfo] Setting identical nowPlayingInfo, skipping update.
```

**关键发现**：

1. **MXSession 的 ClientType = None**：iOS 在创建 MXSession 时，由于检测到 `ClientIsPlaying = STOPPED`，将 ClientType 设置为 `None` 而不是 `AudioSession`
2. **DoesntActuallyPlayAudio = YES**：这导致 iOS 认为应用不会实际播放音频
3. **NowPlayingInfo 被跳过更新**：iOS 的去重机制跳过了"相同"的 nowPlayingInfo 更新

**对比分析**：

```
# 正常的 MXSession（可以触发灵动岛）
MXSession 196e: CoreSession = (null), ClientType = AudioSession ✅

# Runner 的 MXSession（无法触发灵动岛）
MXSession 196f: CoreSession = Runner(44231), ClientType = None ❌
```

**根本原因**：

Dart 层的 `session.setActive(true)` 调用可能没有正确传递到 iOS 底层的 AudioSession。需要在原生层直接调用 AVAudioSession 的方法，确保音频会话被正确激活和识别。

**解决方案**：

在原生层 `AudioServicePlugin.m` 添加以下功能：

1. **新增 `reactivateAudioSession` 方法**：
   - 设置 AVAudioSession category 为 `AVAudioSessionCategoryPlayback`
   - 调用 `setActive:YES` 激活音频会话
   - 在进入后台前和返回前台时调用

2. **新增 `reactivateAudioSessionAndRefresh` 方法**：
   - 先调用 `reactivateAudioSession`
   - 再调用 `forceRefreshNowPlayingInfo`

3. **修改生命周期监听**：
   - `applicationWillResignActive`：调用 `reactivateAudioSessionAndRefresh`
   - `applicationDidBecomeActive`：调用 `reactivateAudioSession`

**代码修改**：

```objc
// 新增方法：重新激活 AVAudioSession
- (void)reactivateAudioSession {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];

    // 设置 category 为 playback
    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:0
                   error:&error];
    if (error) {
        NSLog(@"audio_service: reactivateAudioSession setCategory failed: %@", error);
        error = nil;
    }

    // 激活音频会话
    BOOL success = [session setActive:YES error:&error];
    if (error) {
        NSLog(@"audio_service: reactivateAudioSession setActive failed: %@", error);
    } else {
        NSLog(@"audio_service: reactivateAudioSession success=%d", success);
    }
}

// 新增方法：重新激活并刷新
- (void)reactivateAudioSessionAndRefresh {
    NSLog(@"audio_service: reactivateAudioSessionAndRefresh starting");
    [self reactivateAudioSession];
    [self forceRefreshNowPlayingInfo];
    NSLog(@"audio_service: reactivateAudioSessionAndRefresh completed");
}
```

**修改生命周期监听**：

```objc
// applicationWillResignActive - 进入后台前
[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification
    ...
    usingBlock:^(NSNotification * _Nonnull note) {
        if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
            // 尝试十四：重新激活 AVAudioSession 后再刷新 nowPlayingInfo
            [strongInstance reactivateAudioSessionAndRefresh];
        }
    }];

// applicationDidBecomeActive - 返回前台
[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
    ...
    usingBlock:^(NSNotification * _Nonnull note) {
        if (playing && nowPlayingInfo != nil && nowPlayingInfo.count > 0) {
            // 尝试十四：立即重新激活 AVAudioSession
            [strongInstance reactivateAudioSession];

            // 延迟后设置播放状态
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), ..., ^{
                center.nowPlayingInfo = nowPlayingInfo;
                center.playbackState = MPNowPlayingPlaybackStatePlaying;
            });
        }
    }];
```

**预期效果**：

1. **返回前台时**：重新激活 AVAudioSession，确保 iOS 识别到活跃的音频会话
2. **再次进入后台前**：先重新激活 AVAudioSession，再设置 nowPlayingInfo
3. iOS 创建新的 MXSession 时，应该能检测到 AudioToolbox 正在播放
4. MXSession 的 ClientType 应该被设置为 `AudioSession` 而不是 `None`

**文件修改**：

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`

**验证日志**（17:05:36）：

```
DoesntActuallyPlayAudio = 0.0  ← 系统正确识别应用在播放音频 ✅
[MRNowPlaying] MRMediaRemoteSetCanBeNowPlayingForPlayer set to YES  ← 应用可以成为 NowPlaying ✅
Posted Active Now Playing Notification kMRMediaRemoteSupportedCommandsDidChangeNotification  ← 通知正常发送 ✅
```

**结果**：✅ 成功！问题二（第二次进入后台灵动岛不触发）已修复

---

### 尝试十五：修复灵动岛上一首/下一首无法播放

**日期**：2024-12-28

**问题描述**：

用户报告新问题：在灵动岛直接操作上一首/下一首时：
1. 无法播放上一首/下一首
2. 进入 app 后界面变了但歌曲一直在 loading 未播放

**日志分析**：

```
"<MPSkipTrackCommand: 0x13f152b70 type=PreviousTrack (5) enabled=YES handlers=[]>"
"<MPSkipTrackCommand: 0x13f307e30 type=NextTrack (4) enabled=YES handlers=[]>"
playback state: Paused, change reason: CurrentItemChanged
```

**关键发现**：

1. **`handlers=[]`** - Remote Commands 已启用（`enabled=YES`），但**没有注册处理程序**！
2. **`CurrentItemChanged` 但 `Paused`** - 歌曲切换了但播放器状态仍然是暂停

**根本原因**：

在尝试十四的 `forceRefreshNowPlayingInfo` 方法中（第 764-770 行），策略3只调用了 `setEnabled:YES`，但**没有添加处理程序**：

```objc
// 原代码（问题代码）：
if (commandCenter) {
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.pauseCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.nextTrackCommand setEnabled:YES];  // 只 setEnabled，没有 addTarget!
    [commandCenter.previousTrackCommand setEnabled:YES];  // 只 setEnabled，没有 addTarget!
}
```

这导致 `updateControl:` 方法中的优化条件（第 443 行）跳过添加处理程序：

```objc
if (_controlsUpdated && enable == command.enabled) return;
```

因为 `enable == command.enabled`（都是 `YES`），所以直接返回，不执行 `addTarget:action:`。

**解决方案**：

在 `forceRefreshNowPlayingInfo` 的策略3中，同时设置 `enabled` 和添加处理程序：

```objc
// 修复后的代码：
if (commandCenter) {
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.playCommand addTarget:self action:@selector(play:)];

    [commandCenter.pauseCommand setEnabled:YES];
    [commandCenter.pauseCommand addTarget:self action:@selector(pause:)];

    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPause:)];

    [commandCenter.nextTrackCommand setEnabled:YES];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack:)];

    [commandCenter.previousTrackCommand setEnabled:YES];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack:)];

    NSLog(@"audio_service: forceRefreshNowPlayingInfo - Remote Commands re-registered");
}
```

**文件修改**：

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`

**结果**：⏳ 待用户验证

---

### 尝试十六：增强日志记录用于调试

**日期**：2024-12-28

**问题描述**：

分析用户提供的 `analyse.log` 日志后发现：
1. 切歌流程正常执行（`prepareForNewTrack` 被调用）
2. `play()` 被调用
3. 状态变成 `playing=true, buffering`

但 **无法确认 `skipToNext`/`skipToPrevious` 是否被灵动岛触发**，因为这些方法没有日志记录。

**日志分析**：

```
flutter: │ 💡 MusicAudioHandler: 准备切换歌曲, 当前歌曲=07雨蝶
flutter: │ 🐛 MusicAudioHandler: 广播状态 - playing=false, processingState=AudioProcessingState.idle
flutter: │ 💡 MusicPlayer: 使用本地缓存播放 .../music_audio_cache/xxx.mp3
flutter: │ 💡 MusicAudioHandler: play() 被调用
flutter: │ 🐛 MusicAudioHandler: 广播状态 - playing=true, processingState=AudioProcessingState.buffering
```

虽然切歌成功，但：
1. 没有 `skipToNext` 或 `skipToPrevious` 的日志
2. 最后状态停在 `buffering`，未变成 `ready`

**解决方案**：

在 `MusicAudioHandler` 的 `skipToNext()`、`skipToPrevious()` 和 `_skipToIndex()` 方法中添加详细日志：

```dart
@override
Future<void> skipToNext() async {
  logger.i('MusicAudioHandler: skipToNext() 被调用 (来自灵动岛/锁屏/控制中心), queueLength=${_musicQueue.length}, currentIndex=$_currentIndex');
  // ...
}

@override
Future<void> skipToPrevious() async {
  logger.i('MusicAudioHandler: skipToPrevious() 被调用 (来自灵动岛/锁屏/控制中心), queueLength=${_musicQueue.length}, currentIndex=$_currentIndex, position=${_player.position}');
  // ...
}

Future<void> _skipToIndex(int index) async {
  logger.i('MusicAudioHandler: _skipToIndex($index) 开始切换歌曲, hasCallback=${onSkipToIndex != null}');
  // ...
}
```

**文件修改**：

- `lib/features/music/data/services/music_audio_handler.dart`：添加 `skipToNext()`、`skipToPrevious()` 和 `_skipToIndex()` 的日志记录

**下一步**：

用户需要重新测试，并在 `analyse.log` 中查找以下日志：
- `skipToNext() 被调用` - 确认下一首是否从灵动岛触发
- `skipToPrevious() 被调用` - 确认上一首是否从灵动岛触发
- `_skipToIndex() 开始切换歌曲` - 确认切歌回调是否执行

**结果**：⏳ 待用户重新测试

---

### 尝试十七：iOS 原生层 Remote Command 日志记录

**日期**：2024-12-28

**问题描述**：

分析 `combined_all.log`（iOS 系统日志）发现：
1. `NextTrack, enabled = 1` - 下一首命令已启用 ✅
2. `PreviousTrack, enabled = 1` - 上一首命令已启用 ✅
3. 但日志中**没有看到灵动岛点击上一首/下一首的操作记录**

用户说"如果缺少你的日志，你需要考虑代码是不是未运行"，但发现：
- 日志中没有 Flutter 层的 `skipToNext`/`skipToPrevious` 日志
- 也没有 iOS 原生层的日志（因为原代码中 NSLog 被注释掉了）

**日志分析**：

iOS 系统日志中确认 Remote Commands 已正确注册：
```
"<MRCommandInfo: 0xda16855c0, PreviousTrack, enabled = 1, options = (null)>",
"<MRCommandInfo: 0xda1687d40, NextTrack, enabled = 1, options = (null)>",
```

App 也被正确识别为 NowPlaying 应用：
```
MRNowPlayingAudioFormatController foreground bundle id changed: com.kkape.mynas
playbackState Playing for 【 com.kkape.mynas (44559) My Nas 】
```

**根本原因**：

iOS 原生层 `AudioServicePlugin.m` 中的 `nextTrack:` 和 `previousTrack:` 方法的 NSLog 被注释掉了：

```objc
// 原代码（日志被注释）：
- (MPRemoteCommandHandlerStatus) nextTrack: (MPRemoteCommandEvent *) event {
    //NSLog(@"nextTrack");  // ← 注释掉了！
    [handlerChannel invokeMethod:@"skipToNext" arguments:@{}];
    return MPRemoteCommandHandlerStatusSuccess;
}
```

这导致无法确认：
1. iOS 系统是否将灵动岛点击传递给原生层
2. 原生层是否通过 MethodChannel 调用 Dart 层

**解决方案**：

在 iOS 原生层启用并增强日志记录：

```objc
// 修复后的代码：
- (MPRemoteCommandHandlerStatus) nextTrack: (MPRemoteCommandEvent *) event {
    NSLog(@"audio_service: ===== nextTrack command received from Dynamic Island/Lock Screen/Control Center =====");
    NSLog(@"audio_service: nextTrack - invoking skipToNext on handlerChannel (channel exists: %@)", handlerChannel ? @"YES" : @"NO");
    [handlerChannel invokeMethod:@"skipToNext" arguments:@{}];
    NSLog(@"audio_service: nextTrack - skipToNext invoked successfully");
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) previousTrack: (MPRemoteCommandEvent *) event {
    NSLog(@"audio_service: ===== previousTrack command received from Dynamic Island/Lock Screen/Control Center =====");
    NSLog(@"audio_service: previousTrack - invoking skipToPrevious on handlerChannel (channel exists: %@)", handlerChannel ? @"YES" : @"NO");
    [handlerChannel invokeMethod:@"skipToPrevious" arguments:@{}];
    NSLog(@"audio_service: previousTrack - skipToPrevious invoked successfully");
    return MPRemoteCommandHandlerStatusSuccess;
}
```

同时在 `updateControl:` 方法中添加日志，追踪 Remote Command 注册状态：

```objc
case ASkipToPrevious:
    NSLog(@"audio_service: updateControl ASkipToPrevious enable=%d", enable);
    if (enable) {
        [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack:)];
        NSLog(@"audio_service: previousTrackCommand registered with handler");
    } else {
        [commandCenter.previousTrackCommand removeTarget:nil];
        NSLog(@"audio_service: previousTrackCommand handler removed");
    }
    break;
case ASkipToNext:
    NSLog(@"audio_service: updateControl ASkipToNext enable=%d", enable);
    if (enable) {
        [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack:)];
        NSLog(@"audio_service: nextTrackCommand registered with handler");
    } else {
        [commandCenter.nextTrackCommand removeTarget:nil];
        NSLog(@"audio_service: nextTrackCommand handler removed");
    }
    break;
```

**文件修改**：

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`

**预期日志**（用户重新测试后应能看到）：

```
audio_service: updateControl ASkipToNext enable=1
audio_service: nextTrackCommand registered with handler
audio_service: updateControl ASkipToPrevious enable=1
audio_service: previousTrackCommand registered with handler
...
audio_service: ===== nextTrack command received from Dynamic Island =====
audio_service: nextTrack - invoking skipToNext on handlerChannel (channel exists: YES)
audio_service: nextTrack - skipToNext invoked successfully
```

**下一步**：

1. 用户重新构建 iOS 应用
2. 使用 `log stream` 或 Xcode Console 捕获日志
3. 点击灵动岛上一首/下一首按钮
4. 检查日志中是否出现 `audio_service: nextTrack command received` 或 `previousTrack command received`

**结果**：⏳ 待用户重新测试

---

### 尝试十八：增强 Remote Command 注册诊断日志

**日期**：2024-12-28

**问题描述**：

尝试十七添加的日志没有出现在系统日志中。分析发现：

1. `audio_service: AudioServicePlugin registerWithRegistrar called` ✅ - 插件注册成功
2. `audio_service: applicationDidBecomeActive` ✅ - 生命周期监听正常
3. `audio_service: nextTrack command received` ❌ - 没有出现
4. `audio_service: updateControl ASkipToNext` ❌ - 没有出现

**根本原因**：

`updateControl:` 方法中有一个优化条件：

```objc
if (_controlsUpdated && enable == command.enabled) return;
```

这会在命令状态相同时提前返回，跳过之后的日志输出。由于我们添加的日志在这个条件检查**之后**，所以日志可能被跳过了。

**解决方案**：

在 `updateControl:` 方法的条件检查**之前**添加日志，并在 `setState` 和 `activateCommandCenter` 方法中添加额外的诊断日志：

```objc
// 在 updateControl: 方法开头
if (action == ASkipToNext || action == ASkipToPrevious) {
    NSLog(@"audio_service: updateControl action=%ld enable=%d command.enabled=%d _controlsUpdated=%d",
          (long)action, enable, command.enabled, _controlsUpdated);
}

// 在 setState 方法中 updateControls 调用之前
BOOL hasSkipToPrevious = (actionBits >> 4) & 1;
BOOL hasSkipToNext = (actionBits >> 5) & 1;
NSLog(@"audio_service: setState actionBits=%ld hasSkipToPrevious=%d hasSkipToNext=%d playing=%d commandCenter=%@",
      actionBits, hasSkipToPrevious, hasSkipToNext, playing, commandCenter ? @"YES" : @"NO");

// 在 activateCommandCenter 方法开头
NSLog(@"audio_service: ===== activateCommandCenter called =====");
```

**文件修改**：

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`

**预期日志**：

重新构建后，日志中应该出现：
```
audio_service: setState actionBits=xxx hasSkipToPrevious=1 hasSkipToNext=1 playing=1 commandCenter=YES
audio_service: updateControl action=4 enable=1 command.enabled=0 _controlsUpdated=0
audio_service: updateControl action=5 enable=1 command.enabled=0 _controlsUpdated=0
```

如果 `hasSkipToPrevious=0` 或 `hasSkipToNext=0`，说明 Dart 层没有正确设置 controls。
如果 `commandCenter=NO`，说明 Command Center 没有被激活。

**结果**：✅ 问题诊断完成，发现 stopService 是根本原因

---

### 尝试十九：修复 stopService 移除 Remote Command handlers 问题

**日期**：2024-12-28

**问题诊断**：

根据尝试十八的日志分析，发现完整的问题链：

```
19:19:37.168 nextTrack command received ✅ - iOS 收到灵动岛点击
19:19:37.168 skipToNext invoked successfully ✅ - MethodChannel 调用成功
19:19:37.171 setState actionBits=12583221 hasSkipToPrevious=1 hasSkipToNext=1 playing=0
19:19:37.173 updateControl action=4 enable=1 command.enabled=0 _controlsUpdated=0
19:19:37.173 updateControl action=4 enable=0 ← 问题点！这里 enable 突然变成 0
19:19:37.173 previousTrackCommand handler removed ❌
19:19:37.173 nextTrackCommand handler removed ❌
```

**关键发现**：

在第一次 `setState`（actionBits=12583221，包含 skipToNext 和 skipToPrevious）之后，突然出现 `enable=0`。

这意味着有另一次调用将 `actionBits` 设为 0。唯一能设置 `actionBits = 0` 的地方是 `stopService` 方法。

**根本原因**：

切歌流程中的调用链：
1. 用户点击灵动岛"下一首"
2. iOS 原生层收到 `nextTrack` 命令
3. 调用 Dart 层 `skipToNext` → `_skipToIndex` → `onSkipToIndex` → `playAt` → `play()`
4. `play()` 调用 `_audioHandler.prepareForNewTrack()` 然后 `_player.stop()`
5. `_player.stop()` 导致 `processingState` 变为 `idle`
6. `_broadcastState` 发送 `AudioProcessingState.idle` 到 audio_service
7. audio_service 内部收到 `idle` 状态后调用 `stopService`
8. `stopService` 设置 `actionBits = 0`，调用 `updateControls` 移除所有 handlers
9. 后续的 `setState`（新歌曲信息）虽然包含 skipToNext/skipToPrevious，但此时 handlers 已被移除

**解决方案**：

修改 `stopService` 方法，保留 skipToNext 和 skipToPrevious 的 handlers：

```objc
} else if ([@"stopService" isEqualToString:call.method]) {
    NSLog(@"audio_service: ===== stopService called =====");

    [commandCenter.changePlaybackRateCommand setEnabled:NO];
    [commandCenter.togglePlayPauseCommand setEnabled:NO];
    [commandCenter.togglePlayPauseCommand removeTarget:nil];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    processingState = ApsIdle;

    // 重要修复（尝试十九）：
    // 不要将 actionBits 设为 0，而是保留 skipToNext 和 skipToPrevious 的位
    // ASkipToPrevious = 4, ASkipToNext = 5
    // (1 << 4) | (1 << 5) = 16 | 32 = 48
    long preservedBits = (1 << ASkipToPrevious) | (1 << ASkipToNext);
    actionBits = preservedBits;
    NSLog(@"audio_service: stopService - preserved actionBits=%ld (skipToPrevious + skipToNext)", actionBits);

    [self updateControls];
    _controlsUpdated = NO;
    startResult = nil;
    // 重要：不要将 commandCenter 设为 nil
    // 否则下次 setState 时 updateControls 会因为 commandCenter == nil 而跳过
    // commandCenter = nil;
    NSLog(@"audio_service: stopService - completed, commandCenter preserved");
    result(@{});
}
```

**为什么这样修复有效**：

1. 即使 `stopService` 被调用，`actionBits` 仍然包含 skipToNext 和 skipToPrevious
2. `updateControls` 调用时，这两个命令不会被禁用
3. handlers 保持注册状态，用户可以继续使用灵动岛切歌
4. 保留 `commandCenter` 不设为 nil，确保后续 `setState` 能正常更新 controls

**文件修改**：

- `packages/audio_service_fixed/darwin/audio_service/Sources/audio_service/AudioServicePlugin.m`

**验证步骤**：

1. 执行 `flutter clean && flutter build ios`
2. 运行应用
3. 播放音乐并进入后台
4. 长按灵动岛，点击上一首或下一首
5. 检查日志中是否出现：
   - `stopService called`
   - `preserved actionBits=48`
   - 不应出现 `handler removed`

**结果**：✅ 成功！问题三（灵动岛上一首/下一首无法播放）已修复

---

## 最终修复总结

### 问题一（闪烁）- ✅ 已修复（尝试六~九）
- 移除 Dart 层与原生层的生命周期处理冲突
- 移除 `setCurrentMusic` 中的 500ms 延迟刷新

### 问题二（第二次不触发）- ✅ 已修复（尝试十四）
- 原生层重新激活 AVAudioSession
- 确保 iOS 正确识别音频播放状态

### 问题三（上一首/下一首无法播放）- ✅ 已修复（尝试十九）
- 修复 `stopService` 移除 Remote Command handlers 问题
- 保留 skipToNext 和 skipToPrevious 的 handlers
- 保留 commandCenter 引用
