import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/music_tag_write_queue_service.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 音乐标签写入队列 Provider
///
/// 提供后台写入队列服务，用于异步写入音乐标签到 NAS 文件
final musicTagWriteQueueProvider = Provider<MusicTagWriteQueueService>((ref) {
  final service = MusicTagWriteQueueService(
    tagWriter: MusicTagWriterService(),
  )
    // 初始化服务
    ..init()
    // 设置文件系统提供者
    ..setFileSystemProvider((sourceId) {
      if (sourceId == null) return null;
      final connections = ref.read(activeConnectionsProvider);
      final connection = connections[sourceId];
      if (connection?.status == SourceStatus.connected) {
        return connection!.adapter.fileSystem;
      }
      return null;
    });

  // 在 Provider 销毁时清理资源
  ref.onDispose(service.dispose);

  return service;
});

/// 写入队列状态 Provider
///
/// 提供队列状态流，用于 UI 显示后台写入进度
final musicTagWriteQueueStatusProvider = StreamProvider<QueueStatusUpdate>((ref) {
  final service = ref.watch(musicTagWriteQueueProvider);
  return service.statusStream;
});
