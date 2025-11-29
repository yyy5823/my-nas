import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';

/// 视频历史服务 Provider
final videoHistoryServiceProvider = Provider<VideoHistoryService>((ref) {
  return VideoHistoryService.instance;
});

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

/// 刷新播放历史
Future<void> refreshVideoHistory(WidgetRef ref) async {
  ref.invalidate(videoHistoryProvider);
  ref.invalidate(continueWatchingProvider);
}
