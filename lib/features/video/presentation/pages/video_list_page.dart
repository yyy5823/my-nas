import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';

/// 视频列表状态
final videoListProvider =
    StateNotifierProvider<VideoListNotifier, VideoListState>((ref) {
  return VideoListNotifier(ref);
});

sealed class VideoListState {}

class VideoListLoading extends VideoListState {}

class VideoListLoaded extends VideoListState {
  VideoListLoaded(this.videos);
  final List<FileItem> videos;
}

class VideoListError extends VideoListState {
  VideoListError(this.message);
  final String message;
}

class VideoListNotifier extends StateNotifier<VideoListState> {
  VideoListNotifier(this._ref) : super(VideoListLoading()) {
    loadVideos();
  }

  final Ref _ref;

  Future<void> loadVideos() async {
    state = VideoListLoading();

    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) {
      state = VideoListError('未连接到 NAS');
      return;
    }

    try {
      // 递归扫描视频文件 (简化版，只扫描根目录)
      final shares = await adapter.fileSystem.listDirectory('/');
      final videos = <FileItem>[];

      for (final share in shares) {
        if (share.isDirectory) {
          try {
            final files = await adapter.fileSystem.listDirectory(share.path);
            videos.addAll(
              files.where((f) => f.type == FileType.video),
            );
          } on Exception {
            // 忽略无法访问的目录
          }
        }
      }

      state = VideoListLoaded(videos);
    } on Exception catch (e) {
      state = VideoListError(e.toString());
    }
  }
}

class VideoListPage extends ConsumerWidget {
  const VideoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('视频'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(videoListProvider.notifier).loadVideos(),
            tooltip: '刷新',
          ),
        ],
      ),
      body: switch (state) {
        VideoListLoading() => const LoadingWidget(message: '扫描视频中...'),
        VideoListError(:final message) => AppErrorWidget(
            message: message,
            onRetry: () => ref.read(videoListProvider.notifier).loadVideos(),
          ),
        VideoListLoaded(:final videos) when videos.isEmpty => const EmptyWidget(
            icon: Icons.video_library_outlined,
            title: '暂无视频',
            message: '在 NAS 中添加视频后将显示在这里',
          ),
        VideoListLoaded(:final videos) => _buildVideoGrid(context, ref, videos),
      },
    );
  }

  Widget _buildVideoGrid(
    BuildContext context,
    WidgetRef ref,
    List<FileItem> videos,
  ) =>
      GridView.builder(
        padding: AppSpacing.paddingMd,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: context.isDesktop ? 300 : 200,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 16 / 12,
        ),
        itemCount: videos.length,
        itemBuilder: (context, index) =>
            _VideoCard(video: videos[index]),
      );
}

class _VideoCard extends ConsumerWidget {
  const _VideoCard({required this.video});

  final FileItem video;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 缩略图
              Expanded(
                child: Container(
                  color: context.colorScheme.surfaceContainerHighest,
                  child: video.thumbnailUrl != null
                      ? Image.network(
                          video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                        )
                      : _buildPlaceholder(context),
                ),
              ),
              // 标题和信息
              Padding(
                padding: AppSpacing.paddingSm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.displaySize,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildPlaceholder(BuildContext context) => Center(
        child: Icon(
          Icons.video_file_outlined,
          size: 48,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    // 获取视频 URL
    final url = await adapter.fileSystem.getFileUrl(video.path);

    if (!context.mounted) return;

    // 创建视频项并播放
    final videoItem = VideoItem.fromFileItem(video, url);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );
  }
}
