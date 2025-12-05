import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';

/// 视频历史服务 Provider
final videoHistoryServiceProvider = Provider<VideoHistoryService>((ref) => VideoHistoryService.instance);

/// 播放历史 Provider
final videoHistoryProvider = FutureProvider<List<VideoHistoryItem>>((ref) async {
  final service = ref.watch(videoHistoryServiceProvider);
  await service.init();
  return service.getHistory();
});

/// 继续观看 Provider
final continueWatchingProvider = FutureProvider<List<VideoHistoryItem>>((ref) async {
  final service = ref.watch(videoHistoryServiceProvider);
  await service.init();
  return service.getContinueWatching();
});

/// 视频进度 Provider - 用于获取单个视频的播放进度
final videoProgressProvider = FutureProvider.family<VideoProgress?, String>((ref, videoPath) async {
  final service = ref.watch(videoHistoryServiceProvider);
  await service.init();
  return service.getProgress(videoPath);
});

/// 所有视频进度 Provider - 优化：单次批量读取
final allVideoProgressProvider = FutureProvider<Map<String, VideoProgress>>((ref) async {
  final service = ref.watch(videoHistoryServiceProvider);
  await service.init();
  // 使用批量读取，避免 N+1 查询问题
  return service.getAllProgress();
});

/// 刷新播放历史
Future<void> refreshVideoHistory(WidgetRef ref) async {
  ref.invalidate(videoHistoryProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(allVideoProgressProvider);
}
