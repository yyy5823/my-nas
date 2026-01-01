import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

/// 媒体服务器适配器抽象基类
///
/// 继承自 ServiceAdapter，同时提供媒体服务器特有的功能：
/// - 媒体库浏览
/// - 视频流获取
/// - 播放状态报告
/// - 虚拟文件系统（用于文件浏览器兼容）
abstract class MediaServerAdapter implements ServiceAdapter {
  // === ServiceAdapter 接口实现 ===
  @override
  ServiceAdapterInfo get info;

  @override
  bool get isConnected;

  @override
  ServiceConnectionConfig? get connection;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config);

  @override
  Future<void> disconnect();

  @override
  Future<void> dispose();

  // === 媒体服务器特有功能 ===

  /// 服务器类型
  SourceType get serverType;

  /// 当前用户 ID
  String? get userId;

  /// 服务器名称
  String? get serverName;

  /// 服务器版本
  String? get serverVersion;

  /// 获取所有媒体库
  Future<List<MediaLibrary>> getLibraries();

  /// 获取媒体库中的项目
  ///
  /// [libraryId] 媒体库 ID，如果为 null 则获取根目录
  /// [parentId] 父项目 ID，用于获取子项目（如剧集的季/集）
  /// [startIndex] 起始索引（用于分页）
  /// [limit] 每页数量
  /// [sortBy] 排序字段
  /// [sortOrder] 排序方向
  /// [includeItemTypes] 只包含指定类型
  Future<MediaItemsResult> getItems({
    String? libraryId,
    String? parentId,
    int startIndex = 0,
    int limit = 100,
    String? sortBy,
    String? sortOrder,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取单个项目详情
  Future<MediaItem> getItemDetail(String itemId);

  /// 获取图片 URL
  ///
  /// [itemId] 项目 ID
  /// [imageType] 图片类型
  /// [maxWidth] 最大宽度（可选，用于缩放）
  /// [maxHeight] 最大高度（可选，用于缩放）
  /// [tag] 图片标签（用于缓存验证）
  String getImageUrl(
    String itemId,
    MediaImageType imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  });

  /// 获取视频流信息
  ///
  /// [itemId] 项目 ID
  /// [preferDirectPlay] 是否优先直接播放
  /// [maxStreamingBitrate] 最大码率限制
  Future<MediaStreamInfo> getStreamInfo(
    String itemId, {
    bool preferDirectPlay = true,
    int? maxStreamingBitrate,
  });

  /// 报告播放状态
  Future<void> reportPlayback(PlaybackReport report);

  /// 标记为已观看/未观看
  Future<void> setWatched(String itemId, bool watched);

  /// 标记为已观看（便捷方法）
  Future<void> markWatched(String itemId) => setWatched(itemId, true);

  /// 标记为未观看（便捷方法）
  Future<void> markUnwatched(String itemId) => setWatched(itemId, false);

  /// 切换收藏状态
  Future<bool> toggleFavorite(String itemId);

  /// 获取虚拟文件系统
  ///
  /// 将媒体库映射为文件系统结构，用于文件浏览器兼容
  NasFileSystem get virtualFileSystem;

  /// 搜索媒体
  ///
  /// [query] 搜索关键词
  /// [limit] 结果数量限制
  /// [includeItemTypes] 只搜索指定类型
  Future<MediaItemsResult> search(
    String query, {
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取推荐内容
  Future<MediaItemsResult> getRecommendations({int limit = 20});

  /// 获取最近添加的内容
  Future<MediaItemsResult> getLatestMedia({
    String? libraryId,
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取继续观看列表
  Future<MediaItemsResult> getResumeItems({int limit = 20});

  /// 获取下一集（用于连续剧）
  Future<MediaItem?> getNextUp({String? seriesId});

  /// 获取最近添加的内容（用于增量同步）
  Future<MediaItemsResult> getRecentlyAdded({int limit = 100});
}

/// 媒体服务器连接配置扩展
extension MediaServerConnectionConfig on ServiceConnectionConfig {
  /// 获取用户 ID（从 extraConfig）
  String? get userId => extraConfig?['userId'] as String?;

  /// 获取访问令牌（从 extraConfig）
  String? get accessToken => extraConfig?['accessToken'] as String?;

  /// 是否优先直接播放
  bool get preferDirectPlay =>
      extraConfig?['preferDirectPlay'] as bool? ?? true;

  /// 最大码率限制
  int? get maxStreamingBitrate =>
      extraConfig?['maxStreamingBitrate'] as int?;
}

/// 媒体服务器连接结果
sealed class MediaServerConnectionResult {
  const MediaServerConnectionResult();

  T when<T>({
    required T Function(MediaServerAdapter adapter) success,
    required T Function(String error) failure,
  }) =>
      switch (this) {
        MediaServerConnectionSuccess(:final adapter) => success(adapter),
        MediaServerConnectionFailure(:final error) => failure(error),
      };
}

class MediaServerConnectionSuccess extends MediaServerConnectionResult {
  const MediaServerConnectionSuccess(this.adapter);
  final MediaServerAdapter adapter;
}

class MediaServerConnectionFailure extends MediaServerConnectionResult {
  const MediaServerConnectionFailure(this.error);
  final String error;
}
