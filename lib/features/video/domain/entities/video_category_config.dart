/// 视频首页分类类型
///
/// 定义所有可以在视频首页显示的分类区块
/// 用户可以调整这些分类的显示顺序和可见性
enum VideoHomeCategory {
  /// 顶部轮播推荐（Hero Banner）
  heroBanner,

  /// 继续观看
  continueWatching,

  /// 最近添加
  recentlyAdded,

  /// 电影
  movies,

  /// 剧集
  tvShows,

  /// 电影系列/合集
  movieCollections,

  /// 高分推荐
  topRated,

  /// 未观看
  unwatched,

  /// 其他（未识别的视频）
  others,

  /// 按类型分类（动态生成）
  /// 这是一个特殊类型，实际会根据 genreFilter 字段展开为多个分类
  byGenre,
}

/// 分类类型的扩展方法
extension VideoHomeCategoryExtension on VideoHomeCategory {
  /// 显示名称
  String get displayName {
    switch (this) {
      case VideoHomeCategory.heroBanner:
        return '精选推荐';
      case VideoHomeCategory.continueWatching:
        return '继续观看';
      case VideoHomeCategory.recentlyAdded:
        return '最近添加';
      case VideoHomeCategory.movies:
        return '电影';
      case VideoHomeCategory.tvShows:
        return '剧集';
      case VideoHomeCategory.movieCollections:
        return '电影系列';
      case VideoHomeCategory.topRated:
        return '高分推荐';
      case VideoHomeCategory.unwatched:
        return '未观看';
      case VideoHomeCategory.others:
        return '其他';
      case VideoHomeCategory.byGenre:
        return '按类型';
    }
  }

  /// 图标
  String get iconName {
    switch (this) {
      case VideoHomeCategory.heroBanner:
        return 'featured_play_list';
      case VideoHomeCategory.continueWatching:
        return 'play_circle';
      case VideoHomeCategory.recentlyAdded:
        return 'schedule';
      case VideoHomeCategory.movies:
        return 'movie';
      case VideoHomeCategory.tvShows:
        return 'live_tv';
      case VideoHomeCategory.movieCollections:
        return 'collections_bookmark';
      case VideoHomeCategory.topRated:
        return 'star';
      case VideoHomeCategory.unwatched:
        return 'visibility_off';
      case VideoHomeCategory.others:
        return 'video_file';
      case VideoHomeCategory.byGenre:
        return 'category';
    }
  }

  /// 是否为动态分类（需要额外配置）
  bool get isDynamic => this == VideoHomeCategory.byGenre;
}

/// 单个分类区块的配置
class VideoCategorySectionConfig {
  VideoCategorySectionConfig({
    required this.category,
    required this.order,
    this.visible = true,
    this.genreFilter,
  });

  /// 从 Map 创建
  factory VideoCategorySectionConfig.fromMap(Map<String, dynamic> map) =>
      VideoCategorySectionConfig(
        category: VideoHomeCategory.values[map['category'] as int],
        order: map['order'] as int,
        visible: map['visible'] as bool? ?? true,
        genreFilter: map['genreFilter'] as String?,
      );

  /// 分类类型
  final VideoHomeCategory category;

  /// 排序顺序（数字越小越靠前）
  final int order;

  /// 是否可见
  final bool visible;

  /// 类型筛选（仅用于 byGenre 类型）
  /// 例如：'动作', '科幻', '喜剧'
  final String? genreFilter;

  /// 获取显示名称（考虑类型筛选）
  String get displayName {
    if (category == VideoHomeCategory.byGenre && genreFilter != null) {
      return genreFilter!;
    }
    return category.displayName;
  }

  /// 生成唯一标识（用于 Map key）
  String get uniqueKey {
    if (category == VideoHomeCategory.byGenre && genreFilter != null) {
      return 'genre_$genreFilter';
    }
    return category.name;
  }

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'category': category.index,
        'order': order,
        'visible': visible,
        'genreFilter': genreFilter,
      };

  /// 复制并修改
  VideoCategorySectionConfig copyWith({
    VideoHomeCategory? category,
    int? order,
    bool? visible,
    String? genreFilter,
  }) =>
      VideoCategorySectionConfig(
        category: category ?? this.category,
        order: order ?? this.order,
        visible: visible ?? this.visible,
        genreFilter: genreFilter ?? this.genreFilter,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoCategorySectionConfig &&
          runtimeType == other.runtimeType &&
          uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}

/// 完整的分类设置
class VideoCategorySettings {
  VideoCategorySettings({
    required this.sections,
  });

  /// 从 Map 创建
  factory VideoCategorySettings.fromMap(Map<String, dynamic> map) {
    final sectionsData = map['sections'] as List<dynamic>? ?? [];
    final sections = sectionsData
        .map((s) => VideoCategorySectionConfig.fromMap(s as Map<String, dynamic>))
        .toList();
    return VideoCategorySettings(sections: sections);
  }

  /// 默认配置
  factory VideoCategorySettings.defaults() => VideoCategorySettings(
        sections: [
          VideoCategorySectionConfig(
            category: VideoHomeCategory.heroBanner,
            order: 0,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.continueWatching,
            order: 1,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.recentlyAdded,
            order: 2,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.movies,
            order: 3,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.tvShows,
            order: 4,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.movieCollections,
            order: 5,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.topRated,
            order: 6,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.unwatched,
            order: 7,
            visible: false, // 默认不显示
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.others,
            order: 8,
            visible: false, // 默认不显示
          ),
        ],
      );

  /// 所有分类配置
  final List<VideoCategorySectionConfig> sections;

  /// 获取可见的分类（已排序）
  List<VideoCategorySectionConfig> get visibleSections {
    final visible = sections.where((s) => s.visible).toList();
    visible.sort((a, b) => a.order.compareTo(b.order));
    return visible;
  }

  /// 获取所有分类（已排序）
  List<VideoCategorySectionConfig> get sortedSections {
    final sorted = List<VideoCategorySectionConfig>.from(sections);
    sorted.sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  /// 获取所有类型分类
  List<VideoCategorySectionConfig> get genreSections => sections
      .where((s) => s.category == VideoHomeCategory.byGenre)
      .toList();

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'sections': sections.map((s) => s.toMap()).toList(),
      };

  /// 复制并修改
  VideoCategorySettings copyWith({
    List<VideoCategorySectionConfig>? sections,
  }) =>
      VideoCategorySettings(
        sections: sections ?? this.sections,
      );

  /// 更新单个分类的可见性
  VideoCategorySettings toggleVisibility(String uniqueKey) {
    final newSections = sections.map((s) {
      if (s.uniqueKey == uniqueKey) {
        return s.copyWith(visible: !s.visible);
      }
      return s;
    }).toList();
    return copyWith(sections: newSections);
  }

  /// 重新排序分类
  VideoCategorySettings reorder(int oldIndex, int newIndex) {
    final sorted = sortedSections;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);

    // 更新所有 order 值
    final newSections = <VideoCategorySectionConfig>[];
    for (var i = 0; i < sorted.length; i++) {
      newSections.add(sorted[i].copyWith(order: i));
    }

    return copyWith(sections: newSections);
  }

  /// 添加类型分类
  VideoCategorySettings addGenre(String genre) {
    // 检查是否已存在
    if (sections.any((s) =>
        s.category == VideoHomeCategory.byGenre && s.genreFilter == genre)) {
      return this;
    }

    final maxOrder = sections.fold<int>(
      0,
      (max, s) => s.order > max ? s.order : max,
    );

    final newSection = VideoCategorySectionConfig(
      category: VideoHomeCategory.byGenre,
      order: maxOrder + 1,
      genreFilter: genre,
    );

    return copyWith(sections: [...sections, newSection]);
  }

  /// 移除类型分类
  VideoCategorySettings removeGenre(String genre) {
    final newSections = sections
        .where((s) =>
            !(s.category == VideoHomeCategory.byGenre && s.genreFilter == genre))
        .toList();
    return copyWith(sections: newSections);
  }
}
