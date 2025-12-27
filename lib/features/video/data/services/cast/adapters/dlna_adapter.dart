import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';

/// DLNA 协议适配器
/// 负责 DLNA 设备发现和媒体投屏控制
class DlnaAdapter {
  DlnaAdapter();

  /// DLNA 搜索器
  DLNAManager? _manager;

  /// 是否正在搜索
  bool _isSearching = false;

  /// 当前设备缓存
  final List<DLNADevice> _dlnaDevices = [];

  /// 当前播放的设备
  DLNADevice? _currentDevice;

  /// 设备发现控制器
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  /// 设备发现流
  Stream<List<CastDevice>> get deviceStream => _deviceController.stream;

  /// 是否正在投屏
  bool get isCasting => _currentDevice != null;

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isSearching) {
      logger.i('DLNA 设备搜索已在进行中');
      return;
    }

    _isSearching = true;
    _dlnaDevices.clear();

    try {
      _manager = DLNAManager();

      logger.i('开始搜索 DLNA 设备...');

      // 搜索设备
      final searcher = _manager!.search();

      // 设置超时
      Timer(timeout, () {
        if (_isSearching) {
          stopDiscovery();
        }
      });

      await for (final device in searcher) {
        if (!_isSearching) break;

        // 只关注渲染器（可以接收视频的设备）
        if (device.info.deviceType.contains('MediaRenderer')) {
          logger.i('发现 DLNA 设备: ${device.info.friendlyName}');
          _dlnaDevices.add(device);

          // 发送更新
          _deviceController.add(_convertToCastDevices());
        }
      }
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaStartDiscovery');
    } finally {
      _isSearching = false;
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _isSearching = false;
    logger.i('停止 DLNA 设备搜索');
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() => _convertToCastDevices();

  /// 转换为 CastDevice 列表
  List<CastDevice> _convertToCastDevices() => _dlnaDevices.map((device) {
        final info = device.info;
        return CastDevice(
          id: info.usn ?? info.urlBase ?? info.friendlyName,
          name: info.friendlyName,
          protocol: CastProtocol.dlna,
          address: _extractAddress(info.urlBase ?? ''),
          port: _extractPort(info.urlBase ?? ''),
          modelName: info.modelName,
          manufacturer: info.manufacturer,
          iconUrl: info.iconList.isNotEmpty ? info.iconList.first.url : null,
        );
      }).toList();

  /// 从 URL 提取地址
  String _extractAddress(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return '';
    }
  }

  /// 从 URL 提取端口
  int _extractPort(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.port;
    } catch (e) {
      return 0;
    }
  }

  /// 投屏视频
  Future<bool> castVideo({
    required String deviceId,
    required String videoUrl,
    required String title,
    String? subtitleUrl,
  }) async {
    // 找到对应的 DLNA 设备
    final device = _dlnaDevices.firstWhere(
      (d) => (d.info.usn ?? d.info.urlBase ?? d.info.friendlyName) == deviceId,
      orElse: () => throw Exception('设备未找到: $deviceId'),
    );

    try {
      _currentDevice = device;

      logger.i('开始投屏到 ${device.info.friendlyName}');
      logger.i('视频URL: $videoUrl');

      // 设置媒体 URL
      await device.setUrl(videoUrl);

      // 播放
      await device.play();

      logger.i('投屏成功');
      return true;
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaCastVideo', {'deviceId': deviceId, 'videoUrl': videoUrl});
      _currentDevice = null;
      return false;
    }
  }

  /// 播放
  Future<void> play() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.play();
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.pause();
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaPause');
    }
  }

  /// 停止
  Future<void> stop() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.stop();
      _currentDevice = null;
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaStop');
    }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.seekTo(position);
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(int volume) async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.setVolume(volume);
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSetVolume');
    }
  }

  /// 获取当前播放位置
  Future<Duration?> getPosition() async {
    if (_currentDevice == null) return null;

    try {
      final positionInfo = await _currentDevice!.position();
      return _parseDuration(positionInfo.relTime);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放位置失败（正常情况下可能未开始播放）');
      return null;
    }
  }

  /// 获取播放时长
  Future<Duration?> getDuration() async {
    if (_currentDevice == null) return null;

    try {
      final positionInfo = await _currentDevice!.position();
      return _parseDuration(positionInfo.trackDuration);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放时长失败');
      return null;
    }
  }

  /// 获取播放状态
  Future<CastPlaybackState> getPlaybackState() async {
    if (_currentDevice == null) return CastPlaybackState.idle;

    try {
      final transportInfo = await _currentDevice!.transportInfo();
      return _convertTransportState(transportInfo.currentTransportState);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放状态失败');
      return CastPlaybackState.idle;
    }
  }

  /// 转换传输状态
  CastPlaybackState _convertTransportState(String state) => switch (state.toUpperCase()) {
        'PLAYING' => CastPlaybackState.playing,
        'PAUSED_PLAYBACK' || 'PAUSED' => CastPlaybackState.paused,
        'STOPPED' => CastPlaybackState.stopped,
        'TRANSITIONING' => CastPlaybackState.loading,
        'NO_MEDIA_PRESENT' => CastPlaybackState.idle,
        _ => CastPlaybackState.idle,
      };

  /// 解析时间字符串为 Duration
  Duration? _parseDuration(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;

    try {
      // 格式: HH:MM:SS 或 HH:MM:SS.mmm
      final parts = timeStr.split(':');
      if (parts.length != 3) return null;

      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);

      // 处理秒和毫秒
      final secondsParts = parts[2].split('.');
      final seconds = int.parse(secondsParts[0]);
      final milliseconds = secondsParts.length > 1 ? int.parse(secondsParts[1].padRight(3, '0').substring(0, 3)) : 0;

      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
    } catch (e) {
      return null;
    }
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    _deviceController.close();
    _currentDevice = null;
    _dlnaDevices.clear();
  }
}
