import 'dart:async';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/cast/adapters/dlna_adapter.dart';
import 'package:my_nas/features/video/data/services/cast/cast_media_proxy_server.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 投屏服务
/// 统一管理 DLNA 和 AirPlay 投屏
class CastService {
  CastService({
    CastMediaProxyServer? proxyServer,
    DlnaAdapter? dlnaAdapter,
  })  : _proxyServer = proxyServer ?? CastMediaProxyServer(),
        _dlnaAdapter = dlnaAdapter ?? DlnaAdapter();

  final CastMediaProxyServer _proxyServer;
  final DlnaAdapter _dlnaAdapter;

  /// 当前投屏会话
  CastSession? _currentSession;

  /// 状态更新定时器
  Timer? _statusTimer;

  /// 会话状态控制器
  final _sessionController = StreamController<CastSession?>.broadcast();

  /// 会话状态流
  Stream<CastSession?> get sessionStream => _sessionController.stream;

  /// 获取当前会话
  CastSession? get currentSession => _currentSession;

  /// 是否正在投屏
  bool get isCasting => _currentSession != null;

  /// 设备发现流（合并 DLNA 和 AirPlay）
  Stream<List<CastDevice>> get deviceStream => _dlnaAdapter.deviceStream;

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 10)}) async {
    logger.i('开始设备发现');

    // 并行启动 DLNA 和 AirPlay 搜索
    await Future.wait([
      _dlnaAdapter.startDiscovery(timeout: timeout),
      // TODO: AirPlay 搜索（Phase 3 实现）
    ]);
  }

  /// 停止设备发现
  void stopDiscovery() {
    _dlnaAdapter.stopDiscovery();
    // TODO: 停止 AirPlay 搜索
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() {
    final devices = <CastDevice>[];
    devices.addAll(_dlnaAdapter.getDiscoveredDevices());
    // TODO: 添加 AirPlay 设备
    return devices;
  }

  /// 投屏视频
  Future<CastSession?> cast({
    required CastDevice device,
    required String videoPath,
    required String videoTitle,
    required NasFileSystem fileSystem,
    String? subtitlePath,
    Duration? startPosition,
    int? fileSize,
  }) async {
    try {
      // 1. 确保代理服务器运行
      await _proxyServer.ensureRunning();

      // 2. 注册媒体流
      final token = _proxyServer.registerStream(
        path: videoPath,
        fileSystem: fileSystem,
        fileSize: fileSize,
        subtitlePath: subtitlePath,
      );

      // 3. 获取流 URL
      final videoUrl = await _proxyServer.getStreamUrl(token);
      if (videoUrl == null) {
        throw Exception('无法获取本机IP地址');
      }

      final subtitleUrl = await _proxyServer.getSubtitleUrl(token);

      logger.i('投屏URL: $videoUrl');
      if (subtitleUrl != null) {
        logger.i('字幕URL: $subtitleUrl');
      }

      // 4. 根据协议类型投屏
      bool success;
      switch (device.protocol) {
        case CastProtocol.dlna:
          success = await _dlnaAdapter.castVideo(
            deviceId: device.id,
            videoUrl: videoUrl,
            title: videoTitle,
            subtitleUrl: subtitleUrl,
          );
        case CastProtocol.airplay:
          // TODO: AirPlay 投屏（Phase 3 实现）
          throw Exception('AirPlay 暂未实现');
      }

      if (!success) {
        _proxyServer.unregisterStream(token);
        return null;
      }

      // 5. 创建会话
      _currentSession = CastSession(
        device: device,
        videoTitle: videoTitle,
        videoPath: videoPath,
        playbackState: CastPlaybackState.loading,
      );

      _sessionController.add(_currentSession);

      // 6. 启动状态轮询
      _startStatusPolling();

      // 7. 跳转到起始位置
      if (startPosition != null && startPosition > Duration.zero) {
        await Future<void>.delayed(const Duration(seconds: 1));
        await seek(startPosition);
      }

      return _currentSession;
    } catch (e, st) {
      AppError.handle(e, st, 'castVideo', {
        'device': device.name,
        'videoPath': videoPath,
      });
      return null;
    }
  }

  /// 播放
  Future<void> play() async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.play();
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.pause();
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castPause');
    }
  }

  /// 停止投屏
  Future<void> stop() async {
    _stopStatusPolling();

    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.stop();
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }

      _currentSession = null;
      _sessionController.add(null);

      logger.i('投屏已停止');
    } catch (e, st) {
      AppError.handle(e, st, 'castStop');
    }
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.seek(position);
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    if (_currentSession == null) return;

    try {
      final intVolume = (volume * 100).round();
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.setVolume(intVolume);
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }

      _currentSession = _currentSession!.copyWith(volume: volume);
      _sessionController.add(_currentSession);
    } catch (e, st) {
      AppError.handle(e, st, 'castSetVolume');
    }
  }

  /// 启动状态轮询
  void _startStatusPolling() {
    _stopStatusPolling();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollStatus());
  }

  /// 停止状态轮询
  void _stopStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  /// 轮询状态
  Future<void> _pollStatus() async {
    if (_currentSession == null) return;

    try {
      Duration? position;
      Duration? duration;
      CastPlaybackState? state;

      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          position = await _dlnaAdapter.getPosition();
          duration = await _dlnaAdapter.getDuration();
          state = await _dlnaAdapter.getPlaybackState();
        case CastProtocol.airplay:
          // TODO: AirPlay
          break;
      }

      if (position != null || duration != null || state != null) {
        _currentSession = _currentSession!.copyWith(
          position: position,
          duration: duration,
          playbackState: state,
        );
        _sessionController.add(_currentSession);
      }
    } catch (e) {
      // 忽略轮询错误
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _stopStatusPolling();
    await stop();
    await _proxyServer.stop();
    _dlnaAdapter.dispose();
    await _sessionController.close();
  }
}
