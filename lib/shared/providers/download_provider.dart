import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/services/download_service.dart';

/// 下载任务列表 Provider
final downloadTasksProvider =
    StreamProvider<List<DownloadTask>>((ref) => downloadService.tasksStream);

/// 下载服务 Provider
final downloadServiceProvider = Provider<DownloadService>((ref) => downloadService);

/// 正在下载的任务数量
final activeDownloadsCountProvider = Provider<int>((ref) {
  final tasksAsync = ref.watch(downloadTasksProvider);
  return tasksAsync.when(
    data: (tasks) => tasks.where((t) => t.status == DownloadStatus.downloading).length,
    loading: () => 0,
    error: (_, _) => 0,
  );
});
