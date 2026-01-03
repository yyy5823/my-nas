import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';

/// 直播播放器页面
class LivePlayerPage extends ConsumerStatefulWidget {
  const LivePlayerPage({
    super.key,
    required this.channel,
  });

  final LiveChannel channel;

  @override
  ConsumerState<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends ConsumerState<LivePlayerPage> {
  late Player _player;
  late VideoController _controller;
  bool _isBuffering = true;
  bool _showControls = true;
  bool _hasError = false;
  String? _errorMessage;
  LiveChannel? _currentChannel;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _initPlayer();
    _setFullScreen();
  }

  Future<void> _initPlayer() async {
    _player = Player();
    _controller = VideoController(_player);

    // 监听播放状态
    _player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() => _isBuffering = buffering);
      }
    });

    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    });

    // 开始播放
    await _playChannel(_currentChannel!);
  }

  Future<void> _playChannel(LiveChannel channel) async {
    setState(() {
      _currentChannel = channel;
      _isBuffering = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await _player.open(
        Media(
          channel.streamUrl,
          httpHeaders: channel.headers ?? {},
        ),
      );
    } catch (e, st) {
      AppError.ignore(e, st, '播放直播流失败');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _setFullScreen() {
    // 横屏全屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    _player.dispose();
    _exitFullScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allChannels = ref.watch(allLiveChannelsProvider);
    final currentIndex = allChannels.indexWhere((c) => c.id == _currentChannel?.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            // 视频播放器
            Center(
              child: Video(
                controller: _controller,
                fill: Colors.black,
              ),
            ),

            // 缓冲指示器
            if (_isBuffering && !_hasError)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 错误显示
            if (_hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '播放失败',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _playChannel(_currentChannel!),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),

            // 控制层
            if (_showControls)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // 顶部栏
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: Colors.white,
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentChannel?.displayName ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_currentChannel?.category != null)
                                    Text(
                                      _currentChannel!.category!,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // 直播标识
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: Colors.white,
                                    size: 8,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // 底部控制栏
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 上一个频道
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: Colors.white,
                              iconSize: 36,
                              onPressed: currentIndex > 0
                                  ? () => _switchChannel(allChannels[currentIndex - 1])
                                  : null,
                            ),
                            const SizedBox(width: 32),
                            // 播放/暂停
                            StreamBuilder<bool>(
                              stream: _player.stream.playing,
                              builder: (context, snapshot) {
                                final isPlaying = snapshot.data ?? false;
                                return IconButton(
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  color: Colors.white,
                                  iconSize: 56,
                                  onPressed: () => _player.playOrPause(),
                                );
                              },
                            ),
                            const SizedBox(width: 32),
                            // 下一个频道
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded),
                              color: Colors.white,
                              iconSize: 36,
                              onPressed: currentIndex < allChannels.length - 1
                                  ? () => _switchChannel(allChannels[currentIndex + 1])
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _switchChannel(LiveChannel channel) {
    context.showToast('切换到: ${channel.displayName}');
    _playChannel(channel);
  }
}
