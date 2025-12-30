import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐播放 AudioHandler 抽象接口
///
/// 统一 just_audio 和 media_kit 两种播放引擎的接口，
/// 使 MusicPlayerNotifier 可以无感知地使用任一引擎。
///
/// 实现类：
/// - [MusicAudioHandler] - 基于 just_audio
/// - [MusicMediaKitAudioHandler] - 基于 media_kit
abstract class IMusicAudioHandler extends BaseAudioHandler {
  // ==================== 播放器状态 ====================

  /// 当前封面数据
  Uint8List? get currentArtworkData;

  /// 当前音乐项
  MusicItem? get currentMusicItem;

  /// 当前队列索引
  int get currentIndex;

  /// 外部切歌回调
  /// 当用户通过锁屏/控制中心/蓝牙切歌时调用
  set onSkipToIndex(Future<void> Function(int index)? callback);
  Future<void> Function(int index)? get onSkipToIndex;

  // ==================== 音频源设置 ====================

  /// 设置当前播放的音乐
  ///
  /// [music] 音乐项
  /// [artworkData] 封面数据（可选）
  Future<void> setCurrentMusic(MusicItem music, {Uint8List? artworkData});

  /// 更新封面图片
  Future<void> updateArtwork(Uint8List artworkData);

  /// 更新时长
  void updateDuration(Duration duration);

  // ==================== 播放队列 ====================

  /// 设置播放队列
  ///
  /// [items] 音乐列表
  /// [startIndex] 起始索引
  void setQueue(List<MusicItem> items, {int startIndex = 0});

  /// 更新当前索引
  void updateCurrentIndex(int index);

  // ==================== 播放控制扩展 ====================

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume);

  /// 获取当前音量
  double get volume;

  /// 准备切换到新歌曲
  Future<void> prepareForNewTrack();

  /// 强制刷新 Now Playing / 灵动岛
  Future<void> refreshNowPlaying();

  // ==================== 流订阅 ====================

  /// 播放位置流
  Stream<Duration> get positionStream;

  /// 缓冲位置流
  Stream<Duration> get bufferedPositionStream;

  /// 时长流
  Stream<Duration> get durationStream;

  /// 播放状态流
  Stream<bool> get playingStream;

  /// 缓冲状态流
  Stream<bool> get bufferingStream;

  /// 播放完成流
  Stream<bool> get completedStream;

  // ==================== 资源管理 ====================

  /// 释放资源
  Future<void> dispose();
}

/// 播放引擎类型
enum MusicPlayerEngine {
  /// just_audio 引擎（平台原生解码器）
  /// 优点：深度系统集成，灵动岛稳定
  /// 缺点：不支持 AC3/DTS 等高级格式
  justAudio,

  /// media_kit 引擎（FFmpeg/libmpv 解码）
  /// 优点：支持所有音频格式，音频直通
  /// 缺点：需手动维护系统集成
  mediaKit,
}
