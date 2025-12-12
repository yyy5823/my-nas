/// PT 站点种子信息
class PTTorrent {
  const PTTorrent({
    required this.id,
    required this.name,
    required this.size,
    required this.seeders,
    required this.leechers,
    required this.snatched,
    required this.uploadTime,
    this.category,
    this.subCategory,
    this.downloadUrl,
    this.detailUrl,
    this.imdbId,
    this.doubanId,
    this.smallDescr,
    this.status = const PTTorrentStatus(),
    this.labels = const [],
  });

  /// 种子 ID
  final String id;

  /// 种子名称
  final String name;

  /// 种子大小（字节）
  final int size;

  /// 做种人数
  final int seeders;

  /// 下载人数
  final int leechers;

  /// 完成次数
  final int snatched;

  /// 上传时间
  final DateTime uploadTime;

  /// 分类（如：电影、剧集、音乐等）
  final String? category;

  /// 子分类
  final String? subCategory;

  /// 下载链接
  final String? downloadUrl;

  /// 详情页链接
  final String? detailUrl;

  /// IMDB ID
  final String? imdbId;

  /// 豆瓣 ID
  final String? doubanId;

  /// 简短描述
  final String? smallDescr;

  /// 种子状态（免费、2x上传等）
  final PTTorrentStatus status;

  /// 标签列表
  final List<String> labels;

  /// 格式化的大小显示
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 做种/下载比
  double get ratio => leechers > 0 ? seeders / leechers : seeders.toDouble();

  /// 是否热门（做种人数多）
  bool get isHot => seeders >= 10;

  /// 是否冷门（做种人数少）
  bool get isDead => seeders == 0;

  PTTorrent copyWith({
    String? id,
    String? name,
    int? size,
    int? seeders,
    int? leechers,
    int? snatched,
    DateTime? uploadTime,
    String? category,
    String? subCategory,
    String? downloadUrl,
    String? detailUrl,
    String? imdbId,
    String? doubanId,
    String? smallDescr,
    PTTorrentStatus? status,
    List<String>? labels,
  }) =>
      PTTorrent(
        id: id ?? this.id,
        name: name ?? this.name,
        size: size ?? this.size,
        seeders: seeders ?? this.seeders,
        leechers: leechers ?? this.leechers,
        snatched: snatched ?? this.snatched,
        uploadTime: uploadTime ?? this.uploadTime,
        category: category ?? this.category,
        subCategory: subCategory ?? this.subCategory,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        detailUrl: detailUrl ?? this.detailUrl,
        imdbId: imdbId ?? this.imdbId,
        doubanId: doubanId ?? this.doubanId,
        smallDescr: smallDescr ?? this.smallDescr,
        status: status ?? this.status,
        labels: labels ?? this.labels,
      );
}

/// 种子状态信息
class PTTorrentStatus {
  const PTTorrentStatus({
    this.isFree = false,
    this.isDoubleFree = false,
    this.isHalfDown = false,
    this.isDoubleUp = false,
    this.freeEndTime,
    this.discount,
  });

  /// 是否免费下载
  final bool isFree;

  /// 是否 2x 免费
  final bool isDoubleFree;

  /// 是否 50% 下载
  final bool isHalfDown;

  /// 是否 2x 上传
  final bool isDoubleUp;

  /// 免费结束时间
  final DateTime? freeEndTime;

  /// 折扣百分比（0-100，如 50 表示 50% off）
  final int? discount;

  /// 是否有促销
  bool get hasPromotion => isFree || isDoubleFree || isHalfDown || isDoubleUp;

  /// 获取促销标签
  String? get promotionLabel {
    if (isDoubleFree) return '2xFree';
    if (isFree) return 'Free';
    if (isHalfDown && isDoubleUp) return '50%↓ 2x↑';
    if (isHalfDown) return '50%↓';
    if (isDoubleUp) return '2x↑';
    if (discount != null && discount! > 0) return '$discount%↓';
    return null;
  }

  /// 获取剩余免费时间
  Duration? get remainingFreeTime {
    if (freeEndTime == null) return null;
    final now = DateTime.now();
    if (freeEndTime!.isBefore(now)) return null;
    return freeEndTime!.difference(now);
  }

  /// 格式化剩余时间
  String? get formattedRemainingTime {
    final remaining = remainingFreeTime;
    if (remaining == null) return null;
    if (remaining.inDays > 0) return '${remaining.inDays}天';
    if (remaining.inHours > 0) return '${remaining.inHours}小时';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes}分钟';
    return '即将结束';
  }
}

/// PT 站点用户信息
class PTUserInfo {
  const PTUserInfo({
    required this.username,
    required this.userId,
    this.userClass,
    this.uploaded = 0,
    this.downloaded = 0,
    this.ratio,
    this.bonus = 0,
    this.seedingCount = 0,
    this.leechingCount = 0,
    this.unreadMessages = 0,
    this.invites = 0,
    this.joinTime,
    this.lastAccess,
  });

  /// 用户名
  final String username;

  /// 用户 ID
  final String userId;

  /// 用户等级
  final String? userClass;

  /// 上传量（字节）
  final int uploaded;

  /// 下载量（字节）
  final int downloaded;

  /// 分享率
  final double? ratio;

  /// 魔力值/积分
  final double bonus;

  /// 做种数
  final int seedingCount;

  /// 下载数
  final int leechingCount;

  /// 未读消息数
  final int unreadMessages;

  /// 邀请数
  final int invites;

  /// 注册时间
  final DateTime? joinTime;

  /// 最后访问时间
  final DateTime? lastAccess;

  /// 格式化上传量
  String get formattedUploaded => _formatBytes(uploaded);

  /// 格式化下载量
  String get formattedDownloaded => _formatBytes(downloaded);

  /// 格式化分享率
  String get formattedRatio {
    if (ratio == null) return '∞';
    if (ratio!.isInfinite) return '∞';
    return ratio!.toStringAsFixed(2);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }
}

/// PT 站点统计信息
class PTSiteStats {
  const PTSiteStats({
    this.totalUsers = 0,
    this.totalTorrents = 0,
    this.totalPeers = 0,
    this.totalSeeders = 0,
    this.totalLeechers = 0,
  });

  /// 总用户数
  final int totalUsers;

  /// 总种子数
  final int totalTorrents;

  /// 总 Peer 数
  final int totalPeers;

  /// 总做种数
  final int totalSeeders;

  /// 总下载数
  final int totalLeechers;
}

/// 种子分类
class PTCategory {
  const PTCategory({
    required this.id,
    required this.name,
    this.icon,
    this.count = 0,
  });

  /// 分类 ID
  final String id;

  /// 分类名称
  final String name;

  /// 分类图标
  final String? icon;

  /// 该分类下的种子数
  final int count;
}
