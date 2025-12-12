import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 视频排序选项
enum VideoSortOption {
  /// 评分从高到低
  ratingDesc,
  /// 评分从低到高
  ratingAsc,
  /// 年份从新到旧
  yearDesc,
  /// 年份从旧到新
  yearAsc,
  /// 名称 A-Z
  titleAsc,
  /// 名称 Z-A
  titleDesc,
  /// 添加时间从新到旧
  addedDesc,
  /// 添加时间从旧到新
  addedAsc,
}

/// 排序选项显示名称
extension VideoSortOptionExtension on VideoSortOption {
  String get displayName {
    switch (this) {
      case VideoSortOption.ratingDesc:
        return '评分最高';
      case VideoSortOption.ratingAsc:
        return '评分最低';
      case VideoSortOption.yearDesc:
        return '最新上映';
      case VideoSortOption.yearAsc:
        return '最早上映';
      case VideoSortOption.titleAsc:
        return '名称 A-Z';
      case VideoSortOption.titleDesc:
        return '名称 Z-A';
      case VideoSortOption.addedDesc:
        return '最近添加';
      case VideoSortOption.addedAsc:
        return '最早添加';
    }
  }

  IconData get icon {
    switch (this) {
      case VideoSortOption.ratingDesc:
      case VideoSortOption.ratingAsc:
        return Icons.star_rounded;
      case VideoSortOption.yearDesc:
      case VideoSortOption.yearAsc:
        return Icons.calendar_today_rounded;
      case VideoSortOption.titleAsc:
      case VideoSortOption.titleDesc:
        return Icons.sort_by_alpha_rounded;
      case VideoSortOption.addedDesc:
      case VideoSortOption.addedAsc:
        return Icons.access_time_rounded;
    }
  }
}

/// 视频数据库服务 - 使用 SQLite 支持大规模数据和索引查询
class VideoDatabaseService {
  factory VideoDatabaseService() => _instance ??= VideoDatabaseService._();
  VideoDatabaseService._();

  static VideoDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  // 表名和列名常量
  static const String _tableMetadata = 'video_metadata';
  static const String _colId = 'id';
  static const String _colSourceId = 'source_id';
  static const String _colFilePath = 'file_path';
  static const String _colFileName = 'file_name';
  static const String _colCategory = 'category';
  static const String _colScrapeStatus = 'scrape_status';
  static const String _colTmdbId = 'tmdb_id';
  static const String _colTitle = 'title';
  static const String _colOriginalTitle = 'original_title';
  static const String _colYear = 'year';
  static const String _colOverview = 'overview';
  static const String _colPosterUrl = 'poster_url';
  static const String _colBackdropUrl = 'backdrop_url';
  static const String _colRating = 'rating';
  static const String _colRuntime = 'runtime';
  static const String _colGenres = 'genres';
  static const String _colDirector = 'director';
  static const String _colCast = 'cast_members';
  static const String _colSeasonNumber = 'season_number';
  static const String _colEpisodeNumber = 'episode_number';
  static const String _colEpisodeTitle = 'episode_title';
  static const String _colLastUpdated = 'last_updated';
  static const String _colThumbnailUrl = 'thumbnail_url';
  static const String _colGeneratedThumbnailUrl = 'generated_thumbnail_url';
  static const String _colFileSize = 'file_size';
  static const String _colFileModifiedTime = 'file_modified_time';
  static const String _colCollectionId = 'collection_id';
  static const String _colCollectionName = 'collection_name';
  static const String _colHasNfo = 'has_nfo'; // 是否检测到 NFO 文件
  static const String _colScrapePriority = 'scrape_priority'; // 刮削优先级

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 4, // 升级版本以添加刮削优先级字段
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _initialized = true;
      logger.i('VideoDatabaseService: 数据库初始化完成');
    } catch (e) {
      logger.e('VideoDatabaseService: 数据库初始化失败', e);
      rethrow;
    }
  }

  /// 数据库配置 - 启用 WAL 模式和安全设置
  ///
  /// WAL (Write-Ahead Logging) 模式的优势：
  /// - 更好的并发性能：读写可以同时进行
  /// - 更安全的写入：写入中断时自动回滚到一致状态
  /// - 更快的恢复：应用崩溃后恢复更快
  Future<void> _onConfigure(Database db) async {
    // 使用 rawQuery 获取 PRAGMA 结果，避免 iOS 上 "not an error" 异常
    // 启用 WAL 模式
    await db.rawQuery('PRAGMA journal_mode=WAL');
    // 设置同步模式为 NORMAL（平衡安全性和性能）
    // FULL 更安全但性能较低，NORMAL 在大多数情况下足够安全
    await db.rawQuery('PRAGMA synchronous=NORMAL');
    // 设置忙等待超时（5秒），避免锁冲突时立即失败
    await db.rawQuery('PRAGMA busy_timeout=5000');
    // 启用外键约束
    await db.rawQuery('PRAGMA foreign_keys=ON');
    logger.d('VideoDatabaseService: 数据库配置完成 (WAL模式)');
  }

  /// 创建表和索引
  Future<void> _onCreate(Database db, int version) async {
    // 创建主表
    await db.execute('''
      CREATE TABLE $_tableMetadata (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colSourceId TEXT NOT NULL,
        $_colFilePath TEXT NOT NULL,
        $_colFileName TEXT NOT NULL,
        $_colCategory INTEGER DEFAULT 2,
        $_colScrapeStatus INTEGER DEFAULT 0,
        $_colTmdbId INTEGER,
        $_colTitle TEXT,
        $_colOriginalTitle TEXT,
        $_colYear INTEGER,
        $_colOverview TEXT,
        $_colPosterUrl TEXT,
        $_colBackdropUrl TEXT,
        $_colRating REAL,
        $_colRuntime INTEGER,
        $_colGenres TEXT,
        $_colDirector TEXT,
        $_colCast TEXT,
        $_colSeasonNumber INTEGER,
        $_colEpisodeNumber INTEGER,
        $_colEpisodeTitle TEXT,
        $_colLastUpdated INTEGER,
        $_colThumbnailUrl TEXT,
        $_colGeneratedThumbnailUrl TEXT,
        $_colFileSize INTEGER,
        $_colFileModifiedTime INTEGER,
        $_colCollectionId INTEGER,
        $_colCollectionName TEXT,
        $_colHasNfo INTEGER DEFAULT 0,
        $_colScrapePriority INTEGER DEFAULT 2,
        UNIQUE($_colSourceId, $_colFilePath)
      )
    ''');

    // 创建索引 - 用于快速查询
    await db.execute(
        'CREATE INDEX idx_tmdb_id ON $_tableMetadata($_colTmdbId)');
    await db.execute(
        'CREATE INDEX idx_category ON $_tableMetadata($_colCategory)');
    await db.execute(
        'CREATE INDEX idx_scrape_status ON $_tableMetadata($_colScrapeStatus)');
    await db.execute(
        'CREATE INDEX idx_year ON $_tableMetadata($_colYear)');
    await db.execute(
        'CREATE INDEX idx_rating ON $_tableMetadata($_colRating DESC)');
    await db.execute(
        'CREATE INDEX idx_source_id ON $_tableMetadata($_colSourceId)');
    await db.execute(
        'CREATE INDEX idx_last_updated ON $_tableMetadata($_colLastUpdated DESC)');
    // 复合索引 - 用于剧集查询
    await db.execute(
        'CREATE INDEX idx_tmdb_season_episode ON $_tableMetadata($_colTmdbId, $_colSeasonNumber, $_colEpisodeNumber)');
    // 电影系列索引
    await db.execute(
        'CREATE INDEX idx_collection_id ON $_tableMetadata($_colCollectionId)');
    // 刮削优先级索引（用于智能排序）
    await db.execute(
        'CREATE INDEX idx_scrape_priority ON $_tableMetadata($_colScrapePriority, $_colScrapeStatus)');

    logger.i('VideoDatabaseService: 表和索引创建完成');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('VideoDatabaseService: 数据库升级 $oldVersion -> $newVersion');

    // 从版本1升级到版本2
    if (oldVersion < 2) {
      // 添加刮削状态字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colScrapeStatus INTEGER DEFAULT 0');
      // 添加文件大小字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colFileSize INTEGER');
      // 添加文件修改时间字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colFileModifiedTime INTEGER');
      // 创建刮削状态索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_scrape_status ON $_tableMetadata($_colScrapeStatus)');

      // 将现有已有TMDB数据的记录标记为已刮削完成
      await db.execute('''
        UPDATE $_tableMetadata
        SET $_colScrapeStatus = 2
        WHERE $_colTmdbId IS NOT NULL
      ''');

      logger.i('VideoDatabaseService: 版本1->2 升级完成');
    }

    // 从版本2升级到版本3
    if (oldVersion < 3) {
      // 添加电影系列字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionId INTEGER');
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionName TEXT');
      // 创建电影系列索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_collection_id ON $_tableMetadata($_colCollectionId)');

      logger.i('VideoDatabaseService: 版本2->3 升级完成');
    }

    // 从版本3升级到版本4
    if (oldVersion < 4) {
      // 添加 NFO 检测标志
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colHasNfo INTEGER DEFAULT 0');
      // 添加刮削优先级字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colScrapePriority INTEGER DEFAULT 2');
      // 创建刮削优先级索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_scrape_priority ON $_tableMetadata($_colScrapePriority, $_colScrapeStatus)');

      logger.i('VideoDatabaseService: 版本3->4 升级完成');
    }
  }

  /// 插入或更新元数据
  Future<void> upsert(VideoMetadata metadata) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableMetadata,
      _toRow(metadata),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  ///
  /// 使用事务保护确保原子性：要么全部成功，要么全部回滚
  /// 这样即使应用在写入过程中被终止，数据库也不会处于不一致状态
  Future<void> upsertBatch(List<VideoMetadata> metadataList) async {
    if (!_initialized) await init();
    if (metadataList.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final metadata in metadataList) {
        batch.insert(
          _tableMetadata,
          _toRow(metadata),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    logger.d('VideoDatabaseService: 批量插入 ${metadataList.length} 条');
  }

  /// 根据 sourceId 和 filePath 获取元数据
  Future<VideoMetadata?> get(String sourceId, String filePath) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 批量获取元数据
  Future<Map<String, VideoMetadata>> getBatch(
      List<({String sourceId, String filePath})> keys) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return {};

    final result = <String, VideoMetadata>{};

    // 分批查询，避免 SQL 语句过长
    const batchSize = 100;
    for (var i = 0; i < keys.length; i += batchSize) {
      final batchKeys = keys.skip(i).take(batchSize).toList();

      // 构建 OR 条件
      final conditions = batchKeys
          .map((_) => '($_colSourceId = ? AND $_colFilePath = ?)')
          .join(' OR ');
      final args = batchKeys.expand((k) => [k.sourceId, k.filePath]).toList();

      final results = await _db!.query(
        _tableMetadata,
        where: conditions,
        whereArgs: args,
      );

      for (final row in results) {
        final metadata = _fromRow(row);
        result[metadata.uniqueKey] = metadata;
      }
    }

    return result;
  }

  /// 根据 TMDB ID 获取所有匹配的元数据（使用索引）
  Future<List<VideoMetadata>> getByTmdbId(int tmdbId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colTmdbId = ?',
      whereArgs: [tmdbId],
    );

    return results.map(_fromRow).toList();
  }

  /// 根据 TMDB ID 获取剧集映射（使用索引）
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByTmdbId(
      int tmdbId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where:
          '$_colTmdbId = ? AND $_colSeasonNumber IS NOT NULL AND $_colEpisodeNumber IS NOT NULL',
      whereArgs: [tmdbId],
      orderBy: '$_colSeasonNumber, $_colEpisodeNumber',
    );

    final episodeMap = <int, Map<int, VideoMetadata>>{};
    for (final row in results) {
      final metadata = _fromRow(row);
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        episodeMap
            .putIfAbsent(metadata.seasonNumber!, () => {})[metadata.episodeNumber!] = metadata;
      }
    }

    return episodeMap;
  }

  /// 获取所有 TMDB ID 集合（使用索引）
  Future<Set<int>> getAllTmdbIds() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colTmdbId],
      where: '$_colTmdbId IS NOT NULL',
      distinct: true,
    );

    return results.map((r) => r[_colTmdbId]! as int).toSet();
  }

  /// 根据 TMDB ID 获取第一个匹配的元数据
  Future<VideoMetadata?> getFirstByTmdbId(int tmdbId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colTmdbId = ?',
      whereArgs: [tmdbId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 根据分类获取元数据（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  Future<List<VideoMetadata>> getByCategory(
    MediaCategory category, {
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    var where = '$_colCategory = ?';
    final whereArgs = <Object>[category.index];

    if (pathFilter.andWhere.isNotEmpty) {
      where += pathFilter.andWhere;
      whereArgs.addAll(pathFilter.args);
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: '$_colRating DESC, $_colTitle',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据年份获取元数据（分页）
  Future<List<VideoMetadata>> getByYear(
    int year, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colYear = ?',
      whereArgs: [year],
      orderBy: '$_colRating DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据类型获取元数据（分页，使用 LIKE 搜索）
  Future<List<VideoMetadata>> getByGenre(
    String genre, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colGenres LIKE ?',
      whereArgs: ['%$genre%'],
      orderBy: '$_colRating DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取最近更新的元数据（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  Future<List<VideoMetadata>> getRecentlyUpdated({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    if (pathFilter.where.isEmpty) {
      final results = await _db!.query(
        _tableMetadata,
        orderBy: '$_colLastUpdated DESC',
        limit: limit,
        offset: offset,
      );
      return results.map(_fromRow).toList();
    }

    final results = await _db!.rawQuery(
      'SELECT * FROM $_tableMetadata${pathFilter.where} ORDER BY $_colLastUpdated DESC LIMIT ? OFFSET ?',
      [...pathFilter.args, limit, offset],
    );

    return results.map(_fromRow).toList();
  }

  /// 获取高评分内容（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  Future<List<VideoMetadata>> getTopRated({
    double minRating = 7.0,
    MediaCategory? category,
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    var where = '$_colRating >= ?';
    final whereArgs = <Object>[minRating];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (pathFilter.andWhere.isNotEmpty) {
      where += pathFilter.andWhere;
      whereArgs.addAll(pathFilter.args);
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: '$_colRating DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 分页获取所有元数据
  Future<List<VideoMetadata>> getPage({
    int limit = 50,
    int offset = 0,
    String? orderBy,
    MediaCategory? category,
  }) async {
    if (!_initialized) await init();

    String? where;
    List<Object>? whereArgs;

    if (category != null) {
      where = '$_colCategory = ?';
      whereArgs = [category.index];
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy ?? '$_colRating DESC, $_colTitle',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 搜索元数据
  Future<List<VideoMetadata>> search(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    if (query.isEmpty) return [];

    final searchPattern = '%$query%';
    final results = await _db!.query(
      _tableMetadata,
      where: '$_colTitle LIKE ? OR $_colOriginalTitle LIKE ? OR $_colFileName LIKE ?',
      whereArgs: [searchPattern, searchPattern, searchPattern],
      orderBy: '$_colRating DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取统计信息
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的视频
  Future<Map<String, dynamic>> getStats({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final totalCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata${pathFilter.where}',
        pathFilter.args));

    final movieCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 0${pathFilter.andWhere}',
        pathFilter.args));

    final tvShowCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1${pathFilter.andWhere}',
        pathFilter.args));

    // 其他视频（未识别为电影或剧集，category = 2 即 MediaCategory.unknown）
    final othersCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 2${pathFilter.andWhere}',
        pathFilter.args));

    final withMetadataCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colTmdbId IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    return {
      'total': totalCount ?? 0,
      'movies': movieCount ?? 0,
      'tvShows': tvShowCount ?? 0,
      'others': othersCount ?? 0,
      'withMetadata': withMetadataCount ?? 0,
    };
  }

  /// 构建路径过滤条件
  ({String where, String andWhere, List<Object> args}) _buildPathFilter(
    List<({String sourceId, String path})>? enabledPaths,
  ) {
    if (enabledPaths == null || enabledPaths.isEmpty) {
      return (where: '', andWhere: '', args: []);
    }

    // 构建 (source_id = ? AND file_path LIKE ?) OR ... 条件
    final conditions = enabledPaths
        .map((_) => '($_colSourceId = ? AND $_colFilePath LIKE ?)')
        .join(' OR ');
    final args = enabledPaths
        .expand((p) => [p.sourceId, '${p.path}%'])
        .toList();

    return (
      where: ' WHERE ($conditions)',
      andWhere: ' AND ($conditions)',
      args: args,
    );
  }

  /// 获取统计信息文本（用于空状态显示）
  ///
  /// 返回格式如: "123 个影视 · 2.5 MB 缓存"
  Future<String> getStatsInfo() async {
    if (!_initialized) await init();

    final totalCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata')) ?? 0;

    if (totalCount == 0) {
      return '无缓存';
    }

    // 获取数据库文件大小
    final dbSize = await _getDatabaseSize();
    final sizeText = _formatSize(dbSize);

    return '$totalCount 个影视 · $sizeText 缓存';
  }

  /// 获取数据库文件大小（字节）
  Future<int> _getDatabaseSize() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final mainSize = await dbFile.length();
        // 检查 WAL 和 SHM 文件
        var walSize = 0;
        var shmSize = 0;
        final walFile = File('$dbPath-wal');
        final shmFile = File('$dbPath-shm');
        if (await walFile.exists()) {
          walSize = await walFile.length();
        }
        if (await shmFile.exists()) {
          shmSize = await shmFile.length();
        }
        return mainSize + walSize + shmSize;
      }
    } on Exception catch (e) {
      logger.w('VideoDatabaseService: 获取数据库大小失败', e);
    }
    return 0;
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 获取总数量
  Future<int> getCount({MediaCategory? category}) async {
    if (!_initialized) await init();

    var sql = 'SELECT COUNT(*) FROM $_tableMetadata';
    List<Object>? args;

    if (category != null) {
      sql += ' WHERE $_colCategory = ?';
      args = [category.index];
    }

    return Sqflite.firstIntValue(await _db!.rawQuery(sql, args)) ?? 0;
  }

  /// 获取剧集分组数量（按 tmdbId 或 title 去重）
  ///
  /// [enabledPaths] 启用的路径列表
  Future<int> getTvShowGroupCount({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 统计不同的 tmdbId 数量（有 tmdbId 的）
    final withTmdbIdCount = Sqflite.firstIntValue(await _db!.rawQuery(
      '''
      SELECT COUNT(DISTINCT $_colTmdbId) FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colTmdbId IS NOT NULL${pathFilter.andWhere}
      ''',
      pathFilter.args,
    )) ?? 0;

    // 统计没有 tmdbId 的不同 title 数量
    final withoutTmdbIdCount = Sqflite.firstIntValue(await _db!.rawQuery(
      '''
      SELECT COUNT(DISTINCT LOWER($_colTitle)) FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colTmdbId IS NULL${pathFilter.andWhere}
      ''',
      pathFilter.args,
    )) ?? 0;

    return withTmdbIdCount + withoutTmdbIdCount;
  }

  /// 获取剧集分组的代表性元数据（用于分页显示剧集列表）
  ///
  /// 返回每个剧集分组的一条代表性记录（按 tmdbId 或 title 分组，取评分最高的）
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getTvShowGroupRepresentatives({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 使用子查询获取每个分组的代表性记录
    // 优先使用 tmdbId 分组，否则使用 title
    final sql = '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL AND LOWER(m2.$_colTitle) = LOWER(m1.$_colTitle))
            )
          ORDER BY m2.$_colRating DESC NULLS LAST, m2.$_colSeasonNumber ASC, m2.$_colEpisodeNumber ASC
          LIMIT 1
        )
      ORDER BY $_colRating DESC NULLS LAST, $_colTitle
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(sql, [...pathFilter.args, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 删除元数据
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 根据 sourceId 删除所有
  Future<int> deleteBySourceId(String sourceId) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    // 使用 LIKE 匹配路径前缀
    final count = await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );

    logger.i('VideoDatabaseService: 已删除 $count 个视频 (sourceId: $sourceId, path: $pathPrefix)');
    return count;
  }

  /// 清空所有数据
  Future<void> clearAll() async {
    if (!_initialized) await init();
    await _db!.delete(_tableMetadata);
    logger.i('VideoDatabaseService: 已清空所有数据');
  }

  /// 安全关闭数据库
  ///
  /// 在应用终止前调用，确保所有写入操作完成
  /// WAL 模式下会执行 checkpoint，确保数据安全持久化
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      // WAL checkpoint - 确保所有写入都持久化到主数据库文件
      try {
        await _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        logger.d('VideoDatabaseService: WAL checkpoint 完成');
      } on Exception catch (e) {
        logger.w('VideoDatabaseService: WAL checkpoint 失败', e);
      }
      await _db!.close();
      _db = null;
      _initialized = false;
      logger.i('VideoDatabaseService: 数据库已安全关闭');
    }
  }

  /// 转换为数据库行
  Map<String, dynamic> _toRow(VideoMetadata m) => {
        _colSourceId: m.sourceId,
        _colFilePath: m.filePath,
        _colFileName: m.fileName,
        _colCategory: m.category.index,
        _colScrapeStatus: m.scrapeStatus.index,
        _colTmdbId: m.tmdbId,
        _colTitle: m.title,
        _colOriginalTitle: m.originalTitle,
        _colYear: m.year,
        _colOverview: m.overview,
        _colPosterUrl: m.posterUrl,
        _colBackdropUrl: m.backdropUrl,
        _colRating: m.rating,
        _colRuntime: m.runtime,
        _colGenres: m.genres,
        _colDirector: m.director,
        _colCast: m.cast,
        _colSeasonNumber: m.seasonNumber,
        _colEpisodeNumber: m.episodeNumber,
        _colEpisodeTitle: m.episodeTitle,
        _colLastUpdated: m.lastUpdated?.millisecondsSinceEpoch,
        _colThumbnailUrl: m.thumbnailUrl,
        _colGeneratedThumbnailUrl: m.generatedThumbnailUrl,
        _colFileSize: m.fileSize,
        _colFileModifiedTime: m.fileModifiedTime?.millisecondsSinceEpoch,
        _colCollectionId: m.collectionId,
        _colCollectionName: m.collectionName,
      };

  /// 从数据库行转换
  VideoMetadata _fromRow(Map<String, dynamic> row) => VideoMetadata(
        sourceId: row[_colSourceId] as String,
        filePath: row[_colFilePath] as String,
        fileName: row[_colFileName] as String,
        category: row[_colCategory] != null
            ? MediaCategory.values[row[_colCategory] as int]
            : MediaCategory.unknown,
        scrapeStatus: row[_colScrapeStatus] != null
            ? ScrapeStatus.values[row[_colScrapeStatus] as int]
            : ScrapeStatus.pending,
        tmdbId: row[_colTmdbId] as int?,
        title: row[_colTitle] as String?,
        originalTitle: row[_colOriginalTitle] as String?,
        year: row[_colYear] as int?,
        overview: row[_colOverview] as String?,
        posterUrl: row[_colPosterUrl] as String?,
        backdropUrl: row[_colBackdropUrl] as String?,
        rating: row[_colRating] as double?,
        runtime: row[_colRuntime] as int?,
        genres: row[_colGenres] as String?,
        director: row[_colDirector] as String?,
        cast: row[_colCast] as String?,
        seasonNumber: row[_colSeasonNumber] as int?,
        episodeNumber: row[_colEpisodeNumber] as int?,
        episodeTitle: row[_colEpisodeTitle] as String?,
        lastUpdated: row[_colLastUpdated] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colLastUpdated] as int)
            : null,
        thumbnailUrl: row[_colThumbnailUrl] as String?,
        generatedThumbnailUrl: row[_colGeneratedThumbnailUrl] as String?,
        fileSize: row[_colFileSize] as int?,
        fileModifiedTime: row[_colFileModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                row[_colFileModifiedTime] as int)
            : null,
        collectionId: row[_colCollectionId] as int?,
        collectionName: row[_colCollectionName] as String?,
      );

  /// 获取刮削统计信息
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<ScrapeStats> getScrapeStats({
    String? sourceId,
    String? pathPrefix,
  }) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var whereClause = '';
    var andWhereClause = '';
    final args = <Object>[];

    if (sourceId != null && pathPrefix != null) {
      whereClause = ' WHERE $_colSourceId = ? AND $_colFilePath LIKE ?';
      andWhereClause = ' AND $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      whereClause = ' WHERE $_colSourceId = ?';
      andWhereClause = ' AND $_colSourceId = ?';
      args.add(sourceId);
    }

    final total = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata$whereClause', args)) ??
        0;

    final pending = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 0$andWhereClause',
            args)) ??
        0;

    final scraping = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 1$andWhereClause',
            args)) ??
        0;

    final completed = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 2$andWhereClause',
            args)) ??
        0;

    final failed = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 3$andWhereClause',
            args)) ??
        0;

    final skipped = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 4$andWhereClause',
            args)) ??
        0;

    final movies = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 0$andWhereClause',
            args)) ??
        0;

    final tvShows = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1$andWhereClause',
            args)) ??
        0;

    return ScrapeStats(
      total: total,
      pending: pending,
      scraping: scraping,
      completed: completed,
      failed: failed,
      skipped: skipped,
      movies: movies,
      tvShows: tvShows,
    );
  }

  /// 获取待刮削的视频列表（智能优先级排序）
  ///
  /// 优先级策略（通过 scrape_priority 字段和 SQL CASE 表达式实现）：
  /// 0. 已检测到 NFO 文件的视频 - 几乎瞬间完成
  /// 1. 文件名格式规范的视频（包含年份、剧集信息如 S01E01）- 最容易匹配 TMDB
  /// 2. 普通视频文件 - 需要解析文件名匹配 TMDB
  /// 3. 特殊字符较多的文件名 - 可能难以匹配，需要抽帧
  ///
  /// 这样可以让容易刮削的视频优先完成，用户能更快看到有元数据的内容
  Future<List<VideoMetadata>> getPendingScrape({int limit = 50}) async {
    if (!_initialized) await init();

    // 优先使用预设的 scrape_priority 字段（在扫描时设置）
    // 如果没有预设，使用 SQL CASE 表达式动态计算
    // 分数越小优先级越高
    final sql = '''
      SELECT *,
        CASE
          -- 优先级 0：已检测到 NFO 文件（扫描时标记）
          WHEN $_colHasNfo = 1 THEN 0

          -- 优先级 1：文件名包含年份（如 Movie.2023）或剧集信息（如 S01E01）
          -- 这类文件名格式规范，TMDB 匹配成功率高
          WHEN $_colFileName GLOB '*[12][09][0-9][0-9]*'
               OR $_colFileName GLOB '*[Ss][0-9][0-9][Ee][0-9][0-9]*'
               OR $_colFileName GLOB '*[0-9]x[0-9][0-9]*'
          THEN 1

          -- 优先级 2：普通文件名（没有太多特殊字符）
          WHEN LENGTH($_colFileName) - LENGTH(REPLACE(REPLACE(REPLACE($_colFileName, '[', ''), ']', ''), '.', '')) < 5
          THEN 2

          -- 优先级 3：其他文件（特殊字符较多，可能需要更复杂的解析）
          ELSE 3
        END AS priority
      FROM $_tableMetadata
      WHERE $_colScrapeStatus = ?
      ORDER BY priority ASC, $_colId ASC
      LIMIT ?
    ''';

    final results = await _db!.rawQuery(sql, [ScrapeStatus.pending.index, limit]);
    return results.map(_fromRow).toList();
  }

  /// 更新视频的 NFO 检测标志和刮削优先级
  Future<void> updateNfoFlag(String sourceId, String filePath, {required bool hasNfo}) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {
        _colHasNfo: hasNfo ? 1 : 0,
        _colScrapePriority: hasNfo ? 0 : 2, // 有 NFO 的优先级最高
      },
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 批量更新 NFO 检测标志
  Future<void> updateNfoFlagBatch(List<({String sourceId, String filePath, bool hasNfo})> items) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableMetadata,
          {
            _colHasNfo: item.hasNfo ? 1 : 0,
            _colScrapePriority: item.hasNfo ? 0 : 2,
          },
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [item.sourceId, item.filePath],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 获取需要重试的视频列表
  ///
  /// 包括：
  /// - 刮削失败的 (failed)
  /// - 刮削完成但没有 TMDB 数据的（只有封面或连封面都没有）
  Future<List<VideoMetadata>> getRetryableVideos({int limit = 50}) async {
    if (!_initialized) await init();

    // 获取失败的和完成但无 TMDB ID 的视频
    final results = await _db!.query(
      _tableMetadata,
      where: '''
        $_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL)
      ''',
      whereArgs: [
        ScrapeStatus.failed.index,
        ScrapeStatus.completed.index,
      ],
      orderBy: _colId,
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取需要重试的视频数量
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getRetryableCount({
    String? sourceId,
    String? pathPrefix,
  }) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var pathFilter = '';
    final args = <Object>[ScrapeStatus.failed.index, ScrapeStatus.completed.index];

    if (sourceId != null && pathPrefix != null) {
      pathFilter = ' AND $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      pathFilter = ' AND $_colSourceId = ?';
      args.add(sourceId);
    }

    final count = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tableMetadata
      WHERE ($_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL))$pathFilter
    ''', args));

    return count ?? 0;
  }

  /// 重置失败和无TMDB数据的视频状态为待刮削
  Future<int> resetRetryableVideos() async {
    if (!_initialized) await init();

    final count = await _db!.rawUpdate('''
      UPDATE $_tableMetadata
      SET $_colScrapeStatus = ?
      WHERE $_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL)
    ''', [
      ScrapeStatus.pending.index,
      ScrapeStatus.failed.index,
      ScrapeStatus.completed.index,
    ]);

    logger.i('VideoDatabaseService: 重置 $count 个视频为待刮削状态');
    return count;
  }

  /// 更新刮削状态
  Future<void> updateScrapeStatus(
    String sourceId,
    String filePath,
    ScrapeStatus status,
  ) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {_colScrapeStatus: status.index},
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 批量更新刮削状态
  Future<void> updateScrapeStatusBatch(
    List<({String sourceId, String filePath})> items,
    ScrapeStatus status,
  ) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableMetadata,
          {_colScrapeStatus: status.index},
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [item.sourceId, item.filePath],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 重置所有刮削中状态为待刮削（用于应用重启后恢复）
  Future<void> resetScrapingToPending() async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {_colScrapeStatus: ScrapeStatus.pending.index},
      where: '$_colScrapeStatus = ?',
      whereArgs: [ScrapeStatus.scraping.index],
    );
  }

  /// 获取所有电影系列（按系列分组，返回每个系列的电影列表）
  ///
  /// 只返回有2部或更多电影的系列
  Future<List<MovieCollection>> getMovieCollections({int minCount = 2}) async {
    if (!_initialized) await init();

    // 先获取所有有 collectionId 的电影，按系列分组
    final results = await _db!.rawQuery('''
      SELECT $_colCollectionId, $_colCollectionName, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colCollectionId IS NOT NULL
        AND $_colCategory = 0
      GROUP BY $_colCollectionId
      HAVING COUNT(*) >= ?
      ORDER BY count DESC
    ''', [minCount]);

    final collections = <MovieCollection>[];

    for (final row in results) {
      final collectionId = row[_colCollectionId]! as int;
      final collectionName = row[_colCollectionName] as String? ?? '未知系列';

      // 获取该系列的所有电影
      final moviesResult = await _db!.query(
        _tableMetadata,
        where: '$_colCollectionId = ?',
        whereArgs: [collectionId],
        orderBy: '$_colYear ASC',
      );

      final movies = moviesResult.map(_fromRow).toList();

      collections.add(MovieCollection(
        id: collectionId,
        name: collectionName,
        movies: movies,
      ));
    }

    return collections;
  }

  /// 根据 collectionId 获取同系列的电影
  Future<List<VideoMetadata>> getByCollectionId(int collectionId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colCollectionId = ?',
      whereArgs: [collectionId],
      orderBy: '$_colYear ASC',
    );

    return results.map(_fromRow).toList();
  }

  /// 获取所有可用的年份列表（按分类筛选）
  Future<List<int>> getAvailableYears({MediaCategory? category}) async {
    if (!_initialized) await init();

    var sql = '''
      SELECT DISTINCT $_colYear FROM $_tableMetadata
      WHERE $_colYear IS NOT NULL
    ''';
    final args = <Object>[];

    if (category != null) {
      sql += ' AND $_colCategory = ?';
      args.add(category.index);
    }

    sql += ' ORDER BY $_colYear DESC';

    final results = await _db!.rawQuery(sql, args);
    return results.map((r) => r[_colYear]! as int).toList();
  }

  /// 获取所有可用的类型列表（按分类筛选）
  Future<List<String>> getAvailableGenres({MediaCategory? category}) async {
    if (!_initialized) await init();

    var sql = '''
      SELECT DISTINCT $_colGenres FROM $_tableMetadata
      WHERE $_colGenres IS NOT NULL AND $_colGenres != ''
    ''';
    final args = <Object>[];

    if (category != null) {
      sql += ' AND $_colCategory = ?';
      args.add(category.index);
    }

    final results = await _db!.rawQuery(sql, args);

    // 解析所有类型并去重
    final genreSet = <String>{};
    for (final row in results) {
      final genres = row[_colGenres] as String?;
      if (genres != null && genres.isNotEmpty) {
        genreSet.addAll(genres.split(',').map((g) => g.trim()));
      }
    }

    final genreList = genreSet.toList()..sort();
    return genreList;
  }

  /// 根据分类、类型、年份筛选获取元数据（支持组合筛选和排序）
  Future<List<VideoMetadata>> getFiltered({
    MediaCategory? category,
    String? genre,
    int? year,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    var where = '1 = 1';
    final whereArgs = <Object>[];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (genre != null && genre.isNotEmpty) {
      where += ' AND $_colGenres LIKE ?';
      whereArgs.add('%$genre%');
    }

    if (year != null) {
      where += ' AND $_colYear = ?';
      whereArgs.add(year);
    }

    final orderBy = _buildOrderBy(sortOption);

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 构建排序 SQL
  String _buildOrderBy(VideoSortOption sortOption) {
    switch (sortOption) {
      case VideoSortOption.ratingDesc:
        return '$_colRating DESC NULLS LAST, $_colTitle';
      case VideoSortOption.ratingAsc:
        return '$_colRating ASC NULLS LAST, $_colTitle';
      case VideoSortOption.yearDesc:
        return '$_colYear DESC NULLS LAST, $_colTitle';
      case VideoSortOption.yearAsc:
        return '$_colYear ASC NULLS LAST, $_colTitle';
      case VideoSortOption.titleAsc:
        return '$_colTitle ASC';
      case VideoSortOption.titleDesc:
        return '$_colTitle DESC';
      case VideoSortOption.addedDesc:
        return '$_colLastUpdated DESC NULLS LAST, $_colTitle';
      case VideoSortOption.addedAsc:
        return '$_colLastUpdated ASC NULLS LAST, $_colTitle';
    }
  }

  /// 获取筛选后的数量
  Future<int> getFilteredCount({
    MediaCategory? category,
    String? genre,
    int? year,
  }) async {
    if (!_initialized) await init();

    var where = '1 = 1';
    final whereArgs = <Object>[];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (genre != null && genre.isNotEmpty) {
      where += ' AND $_colGenres LIKE ?';
      whereArgs.add('%$genre%');
    }

    if (year != null) {
      where += ' AND $_colYear = ?';
      whereArgs.add(year);
    }

    final result = await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableMetadata WHERE $where',
      whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 获取剧集分组的代表性元数据（带筛选条件和排序）
  Future<List<VideoMetadata>> getTvShowGroupRepresentativesFiltered({
    String? genre,
    int? year,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    var filterWhere = '';
    final filterArgs = <Object>[];

    if (genre != null && genre.isNotEmpty) {
      filterWhere += ' AND $_colGenres LIKE ?';
      filterArgs.add('%$genre%');
    }

    if (year != null) {
      filterWhere += ' AND $_colYear = ?';
      filterArgs.add(year);
    }

    final orderBy = _buildOrderBy(sortOption);

    // 使用子查询获取每个分组的代表性记录
    final sql = '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1$filterWhere
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL AND LOWER(m2.$_colTitle) = LOWER(m1.$_colTitle))
            )
          ORDER BY m2.$_colRating DESC NULLS LAST, m2.$_colSeasonNumber ASC, m2.$_colEpisodeNumber ASC
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(sql, [...filterArgs, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 获取筛选后的剧集分组数量
  Future<int> getTvShowGroupCountFiltered({
    String? genre,
    int? year,
  }) async {
    if (!_initialized) await init();

    var filterWhere = '';
    final filterArgs = <Object>[];

    if (genre != null && genre.isNotEmpty) {
      filterWhere += ' AND $_colGenres LIKE ?';
      filterArgs.add('%$genre%');
    }

    if (year != null) {
      filterWhere += ' AND $_colYear = ?';
      filterArgs.add(year);
    }

    // 统计不同的 tmdbId 数量（有 tmdbId 的）
    final withTmdbIdCount = Sqflite.firstIntValue(await _db!.rawQuery(
      '''
      SELECT COUNT(DISTINCT $_colTmdbId) FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colTmdbId IS NOT NULL$filterWhere
      ''',
      filterArgs,
    )) ?? 0;

    // 统计没有 tmdbId 的不同 title 数量
    final withoutTmdbIdCount = Sqflite.firstIntValue(await _db!.rawQuery(
      '''
      SELECT COUNT(DISTINCT LOWER($_colTitle)) FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colTmdbId IS NULL$filterWhere
      ''',
      filterArgs,
    )) ?? 0;

    return withTmdbIdCount + withoutTmdbIdCount;
  }
}

/// 电影系列
class MovieCollection {
  const MovieCollection({
    required this.id,
    required this.name,
    required this.movies,
  });

  final int id;
  final String name;
  final List<VideoMetadata> movies;

  /// 系列中电影数量
  int get movieCount => movies.length;

  /// 代表电影（第一部）
  VideoMetadata? get representative => movies.isNotEmpty ? movies.first : null;

  /// 系列海报（使用第一部电影的海报）
  String? get posterUrl => representative?.posterUrl;

  /// 系列背景图（使用评分最高的电影的背景图）
  String? get backdropUrl {
    if (movies.isEmpty) return null;
    final sortedByRating = List<VideoMetadata>.from(movies)
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    return sortedByRating.first.backdropUrl;
  }
}

/// 刮削统计信息
class ScrapeStats {
  const ScrapeStats({
    required this.total,
    required this.pending,
    required this.scraping,
    required this.completed,
    required this.failed,
    required this.skipped,
    required this.movies,
    required this.tvShows,
  });

  final int total;
  final int pending;
  final int scraping;
  final int completed;
  final int failed;
  final int skipped;
  final int movies;
  final int tvShows;

  /// 已处理的数量（完成+失败+跳过）
  int get processed => completed + failed + skipped;

  /// 进度百分比 (0-1)
  double get progress => total > 0 ? processed / total : 0;

  /// 是否全部完成
  bool get isAllDone => pending == 0 && scraping == 0;
}
