import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';

/// DLNA 协议适配器
/// 负责 DLNA 设备发现和媒体投屏控制
class DlnaAdapter {
  DlnaAdapter();

  /// DLNA 管理器
  DLNAManager? _manager;

  /// 设备管理器
  DeviceManager? _deviceManager;

  /// 是否正在搜索
  bool _isSearching = false;

  /// 当前设备缓存
  final Map<String, DLNADevice> _dlnaDevices = {};

  /// 当前播放的设备
  DLNADevice? _currentDevice;

  /// 设备发现控制器
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  /// 设备流订阅
  StreamSubscription<Map<String, DLNADevice>>? _deviceSubscription;

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

      // 启动设备管理器
      _deviceManager = await _manager!.start();

      // 监听设备发现
      _deviceSubscription = _deviceManager!.devices.stream.listen((deviceMap) {
        _dlnaDevices.clear();

        for (final entry in deviceMap.entries) {
          final device = entry.value;
          // 只关注渲染器（可以接收视频的设备）
          if (device.info.deviceType.contains('MediaRenderer')) {
            logger.i('发现 DLNA 设备: ${device.info.friendlyName}');
            _dlnaDevices[entry.key] = device;
          }
        }

        // 发送更新
        _deviceController.add(_convertToCastDevices());
      });

      // 设置超时
      Timer(timeout, () {
        if (_isSearching) {
          stopDiscovery();
        }
      });
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaStartDiscovery');
      _isSearching = false;
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _isSearching = false;
    _deviceSubscription?.cancel();
    _deviceSubscription = null;
    _manager?.stop();
    _manager = null;
    _deviceManager = null;
    logger.i('停止 DLNA 设备搜索');
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() => _convertToCastDevices();

  /// 转换为 CastDevice 列表
  List<CastDevice> _convertToCastDevices() => _dlnaDevices.values.map((device) {
        final info = device.info;
        return CastDevice(
          id: info.URLBase,
          name: info.friendlyName,
          protocol: CastProtocol.dlna,
          address: _extractAddress(info.URLBase),
          port: _extractPort(info.URLBase),
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
    final device = _dlnaDevices[deviceId];
    if (device == null) {
      throw Exception('设备未找到: $deviceId');
    }

    try {
      _currentDevice = device;

      logger.i('开始投屏到 ${device.info.friendlyName}');
      logger.i('视频URL: $videoUrl');

      // 设置媒体 URL
      await device.setUrl(videoUrl, title: title, type: PlayType.Video);

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
      // 转换为 HH:MM:SS 格式
      final timeStr = _formatDurationToString(position);
      await _currentDevice!.seek(timeStr);
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(int volume) async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.volume(volume.clamp(0, 100));
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSetVolume');
    }
  }

  /// 获取当前播放位置
  Future<Duration?> getPosition() async {
    if (_currentDevice == null) return null;

    try {
      final positionXml = await _currentDevice!.position();
      final parser = PositionParser(positionXml);
      return Duration(seconds: parser.RelTimeInt);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放位置失败（正常情况下可能未开始播放）');
      return null;
    }
  }

  /// 获取播放时长
  Future<Duration?> getDuration() async {
    if (_currentDevice == null) return null;

    try {
      final positionXml = await _currentDevice!.position();
      final parser = PositionParser(positionXml);
      return Duration(seconds: parser.TrackDurationInt);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放时长失败');
      return null;
    }
  }

  /// 获取播放状态
  Future<CastPlaybackState> getPlaybackState() async {
    if (_currentDevice == null) return CastPlaybackState.idle;

    try {
      final transportXml = await _currentDevice!.getTransportInfo();
      final parser = TransportInfoParser(transportXml);
      return _convertTransportState(parser.CurrentTransportState);
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

  /// 将 Duration 转换为 HH:MM:SS 格式字符串
  String _formatDurationToString(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    _deviceController.close();
    _currentDevice = null;
    _dlnaDevices.clear();
  }
}
