import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
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
  static const String _colLocalPosterUrl = 'local_poster_url';
  static const String _colFileSize = 'file_size';
  static const String _colFileModifiedTime = 'file_modified_time';
  static const String _colCollectionId = 'collection_id';
  static const String _colCollectionName = 'collection_name';
  static const String _colHasNfo = 'has_nfo'; // 是否检测到 NFO 文件
  static const String _colScrapePriority = 'scrape_priority'; // 刮削优先级
  static const String _colShowDirectory = 'show_directory'; // TV 剧集所属剧目录
  static const String _colMovieDirectory = 'movie_directory'; // 电影所在目录
  static const String _colResolution = 'resolution'; // 视频分辨率 (4K, 1080p, 720p 等)

  // 字幕表
  static const String _tableSubtitles = 'video_subtitles';
  static const String _subColId = 'id';
  static const String _subColSourceId = 'source_id';
  static const String _subColVideoPath = 'video_path'; // 关联的视频文件路径
  static const String _subColSubtitlePath = 'subtitle_path'; // 字幕文件路径
  static const String _subColFileName = 'file_name'; // 字幕文件名
  static const String _subColFormat = 'format'; // 字幕格式 (srt, ass, vtt)
  static const String _subColLanguage = 'language'; // 语言

  // TV 剧集分组表（预计算聚合数据，避免 GROUP BY）
  static const String _tableTvShowGroups = 'tv_show_groups';
  static const String _tvgColId = 'id';
  static const String _tvgColGroupKey = 'group_key'; // 'tmdb_123' 或 'title_xxx'
  static const String _tvgColTmdbId = 'tmdb_id';
  static const String _tvgColTitle = 'title';
  static const String _tvgColNormalizedTitle = 'normalized_title';
  static const String _tvgColOriginalTitle = 'original_title';
  static const String _tvgColYear = 'year';
  static const String _tvgColOverview = 'overview';
  static const String _tvgColPosterUrl = 'poster_url';
  static const String _tvgColBackdropUrl = 'backdrop_url';
  static const String _tvgColRating = 'rating';
  static const String _tvgColGenres = 'genres';
  static const String _tvgColSeasonCount = 'season_count';
  static const String _tvgColEpisodeCount = 'episode_count';
  static const String _tvgColRepresentativeRowid = 'representative_rowid';
  static const String _tvgColLastSynced = 'last_synced';
  static const String _tvgColLocalPosterUrl = 'local_poster_url'; // 本地海报路径（NAS 路径或 file:// 路径）

  // 电影系列分组表
  static const String _tableMovieCollectionGroups = 'movie_collection_groups';
  static const String _mcgColId = 'id';
  static const String _mcgColTmdbCollectionId = 'tmdb_collection_id';
  static const String _mcgColName = 'name';
  static const String _mcgColPosterUrl = 'poster_url';
  static const String _mcgColBackdropUrl = 'backdrop_url';
  static const String _mcgColOverview = 'overview';
  static const String _mcgColMovieCount = 'movie_count';
  static const String _mcgColLastSynced = 'last_synced';
  static const String _mcgColLocalPosterUrl = 'local_poster_url'; // 本地海报路径

  // 目录扫描状态表（用于增量扫描和断点续扫）
  static const String _tableScanProgress = 'scan_progress';
  static const String _scanColId = 'id';
  static const String _scanColSourceId = 'source_id';
  static const String _scanColPath = 'path'; // 目录路径
  static const String _scanColRootPath = 'root_path'; // 根目录路径（媒体库配置的路径）
  static const String _scanColStatus = 'status'; // 0=pending, 1=scanning, 2=completed
  static const String _scanColVideoCount = 'video_count'; // 该目录发现的视频数
  static const String _scanColLastScanned = 'last_scanned'; // 最后扫描时间

  /// 扫描状态常量
  static const int scanStatusPending = 0;
  static const int scanStatusScanning = 1;
  static const int scanStatusCompleted = 2;

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 12, // 升级版本以添加聚合表的 local_poster_url 字段
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _initialized = true;
      logger.i('VideoDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'VideoDatabaseService.init');
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
        $_colLocalPosterUrl TEXT,
        $_colFileSize INTEGER,
        $_colFileModifiedTime INTEGER,
        $_colCollectionId INTEGER,
        $_colCollectionName TEXT,
        $_colHasNfo INTEGER DEFAULT 0,
        $_colScrapePriority INTEGER DEFAULT 2,
        $_colShowDirectory TEXT,
        $_colMovieDirectory TEXT,
        $_colResolution TEXT,
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

    // 创建字幕索引表
    await _createSubtitleTable(db);

    // 创建扫描进度表
    await _createScanProgressTable(db);

    // 创建聚合表
    await _createTvShowGroupsTable(db);
    await _createMovieCollectionGroupsTable(db);

    logger.i('VideoDatabaseService: 表和索引创建完成');
  }

  /// 创建字幕索引表
  Future<void> _createSubtitleTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableSubtitles (
        $_subColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_subColSourceId TEXT NOT NULL,
        $_subColVideoPath TEXT NOT NULL,
        $_subColSubtitlePath TEXT NOT NULL,
        $_subColFileName TEXT NOT NULL,
        $_subColFormat TEXT NOT NULL,
        $_subColLanguage TEXT,
        UNIQUE($_subColSourceId, $_subColSubtitlePath)
      )
    ''');

    // 创建索引 - 用于快速查询视频对应的字幕
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_subtitle_video ON $_tableSubtitles($_subColSourceId, $_subColVideoPath)');

    logger.i('VideoDatabaseService: 字幕索引表创建完成');
  }

  /// 创建扫描进度表
  ///
  /// 用于跟踪目录扫描状态，支持增量扫描和断点续扫
  Future<void> _createScanProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableScanProgress (
        $_scanColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_scanColSourceId TEXT NOT NULL,
        $_scanColPath TEXT NOT NULL,
        $_scanColRootPath TEXT NOT NULL,
        $_scanColStatus INTEGER DEFAULT 0,
        $_scanColVideoCount INTEGER DEFAULT 0,
        $_scanColLastScanned INTEGER,
        UNIQUE($_scanColSourceId, $_scanColPath)
      )
    ''');

    // 创建索引 - 用于快速查询待扫描目录
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scan_source_status ON $_tableScanProgress($_scanColSourceId, $_scanColStatus)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scan_root ON $_tableScanProgress($_scanColSourceId, $_scanColRootPath)');

    logger.i('VideoDatabaseService: 扫描进度表创建完成');
  }

  /// 创建 TV 剧集分组表
  ///
  /// 预计算的聚合表，每部剧一行，避免 GROUP BY 查询
  Future<void> _createTvShowGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableTvShowGroups (
        $_tvgColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_tvgColGroupKey TEXT UNIQUE NOT NULL,
        $_tvgColTmdbId INTEGER,
        $_tvgColTitle TEXT NOT NULL,
        $_tvgColNormalizedTitle TEXT NOT NULL,
        $_tvgColOriginalTitle TEXT,
        $_tvgColYear INTEGER,
        $_tvgColOverview TEXT,
        $_tvgColPosterUrl TEXT,
        $_tvgColBackdropUrl TEXT,
        $_tvgColRating REAL,
        $_tvgColGenres TEXT,
        $_tvgColSeasonCount INTEGER DEFAULT 0,
        $_tvgColEpisodeCount INTEGER DEFAULT 0,
        $_tvgColRepresentativeRowid INTEGER,
        $_tvgColLastSynced INTEGER,
        $_tvgColLocalPosterUrl TEXT
      )
    ''');

    // 创建索引
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tvg_tmdb_id ON $_tableTvShowGroups($_tvgColTmdbId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tvg_rating ON $_tableTvShowGroups($_tvgColRating DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tvg_normalized_title ON $_tableTvShowGroups($_tvgColNormalizedTitle)');

    logger.i('VideoDatabaseService: TV剧集分组表创建完成');
  }

  /// 创建电影系列分组表
  Future<void> _createMovieCollectionGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMovieCollectionGroups (
        $_mcgColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_mcgColTmdbCollectionId INTEGER UNIQUE,
        $_mcgColName TEXT NOT NULL,
        $_mcgColPosterUrl TEXT,
        $_mcgColBackdropUrl TEXT,
        $_mcgColOverview TEXT,
        $_mcgColMovieCount INTEGER DEFAULT 0,
        $_mcgColLastSynced INTEGER,
        $_mcgColLocalPosterUrl TEXT
      )
    ''');

    // 创建索引
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_mcg_tmdb_id ON $_tableMovieCollectionGroups($_mcgColTmdbCollectionId)');

    logger.i('VideoDatabaseService: 电影系列分组表创建完成');
  }

  /// 迁移 TV 剧集的 show_directory 字段
  ///
  /// 从现有 TV 剧集记录的 file_path 解析出 show_directory
  /// 这是一次性迁移，在数据库升级到版本 9 时执行
  Future<void> _migrateShowDirectories(Database db) async {
    // 获取所有 TV 剧集记录
    final tvShows = await db.query(
      _tableMetadata,
      columns: [_colId, _colFilePath],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.tvShow.index],
    );

    if (tvShows.isEmpty) {
      logger.d('VideoDatabaseService: 无 TV 剧集需要迁移 show_directory');
      return;
    }

    logger.i('VideoDatabaseService: 开始迁移 ${tvShows.length} 条 TV 剧集的 show_directory');

    // 批量更新
    final batch = db.batch();
    for (final row in tvShows) {
      final id = row[_colId] as int?;
      final filePath = row[_colFilePath] as String?;
      if (id == null || filePath == null) continue;
      final showDir = extractShowDirectory(filePath);

      if (showDir != null) {
        batch.update(
          _tableMetadata,
          {_colShowDirectory: showDir},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: show_directory 迁移完成');
  }

  /// 从文件路径提取剧目录
  ///
  /// 识别常见的电视剧目录结构：
  /// - `/TV/Breaking Bad/Season 1/S01E01.mkv` → `/TV/Breaking Bad`
  /// - `/TV/剧名.S01/S01E01.mkv` → `/TV/剧名.S01`
  /// - `/TV/剧名/S01E01.mkv` → `/TV/剧名`
  ///
  /// 规则：
  /// 1. 如果父目录名匹配季目录模式（Season X, S01 等），取祖父目录
  /// 2. 否则取父目录
  static String? extractShowDirectory(String filePath) {
    if (filePath.isEmpty) return null;

    // 标准化路径分隔符
    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return null;

    // 文件名是最后一个部分
    // parts.removeLast(); // 移除文件名

    // 检查父目录是否是季目录
    final parentDir = parts.length >= 2 ? parts[parts.length - 2] : null;

    if (parentDir != null && _isSeasonDirectory(parentDir)) {
      // 父目录是季目录，取祖父目录作为剧目录
      if (parts.length >= 3) {
        // 返回从根到祖父目录的完整路径
        return '/${parts.sublist(0, parts.length - 2).join('/')}';
      }
      return null;
    }

    // 父目录不是季目录，父目录本身就是剧目录
    if (parts.length >= 2) {
      return '/${parts.sublist(0, parts.length - 1).join('/')}';
    }

    return null;
  }

  /// 检查目录名是否是季目录
  ///
  /// 季目录模式包括：
  /// - Season X, Season 01, Season1
  /// - S01, S1
  /// - 第X季, 第一季
  /// - Specials, 特典, SP
  static bool isSeasonDirectory(String dirName) {
    final name = dirName.toLowerCase().trim();

    // 常见季目录模式
    // Season 1, Season 01, Season1
    if (RegExp(r'^season\s*\d+$', caseSensitive: false).hasMatch(name)) {
      return true;
    }

    // S01, S1
    if (RegExp(r'^s\d{1,2}$', caseSensitive: false).hasMatch(name)) {
      return true;
    }

    // 第1季, 第一季
    if (RegExp(r'^第[\d一二三四五六七八九十]+季$').hasMatch(name)) {
      return true;
    }

    // Specials, 特典
    if (name == 'specials' || name == '特典' || name == 'sp') {
      return true;
    }

    return false;
  }

  // 保留私有别名以保持内部兼容性
  static bool _isSeasonDirectory(String dirName) => isSeasonDirectory(dirName);

  /// 迁移电影的 movie_directory 字段
  ///
  /// 从现有电影记录的 file_path 解析出 movie_directory
  /// 这是一次性迁移，在数据库升级到版本 10 时执行
  Future<void> _migrateMovieDirectories(Database db) async {
    // 获取所有电影记录
    final movies = await db.query(
      _tableMetadata,
      columns: [_colId, _colFilePath],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.movie.index],
    );

    if (movies.isEmpty) {
      logger.d('VideoDatabaseService: 无电影需要迁移 movie_directory');
      return;
    }

    logger.i('VideoDatabaseService: 开始迁移 ${movies.length} 条电影的 movie_directory');

    // 批量更新
    final batch = db.batch();
    for (final row in movies) {
      final id = row[_colId] as int?;
      final filePath = row[_colFilePath] as String?;
      if (id == null || filePath == null) continue;
      final movieDir = extractMovieDirectory(filePath);

      if (movieDir != null) {
        batch.update(
          _tableMetadata,
          {_colMovieDirectory: movieDir},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: movie_directory 迁移完成');
  }

  /// 从文件路径提取电影所在目录
  ///
  /// 电影目录结构比 TV 剧集简单，直接取父目录
  /// 例如：
  /// - `/Movies/漫威电影宇宙/钢铁侠.mkv` → `/Movies/漫威电影宇宙`
  /// - `/Movies/2023/Oppenheimer.mkv` → `/Movies/2023`
  static String? extractMovieDirectory(String filePath) {
    if (filePath.isEmpty) return null;

    // 标准化路径分隔符
    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return null;

    // 直接返回父目录路径
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  /// 迁移视频的 resolution 字段
  ///
  /// 从现有视频记录的 file_name 解析出分辨率
  /// 这是一次性迁移，在数据库升级到版本 11 时执行
  Future<void> _migrateResolutions(Database db) async {
    // 获取所有没有 resolution 的记录
    final videos = await db.query(
      _tableMetadata,
      columns: [_colId, _colFileName],
      where: '$_colResolution IS NULL',
    );

    if (videos.isEmpty) {
      logger.d('VideoDatabaseService: 无视频需要迁移 resolution');
      return;
    }

    logger.i('VideoDatabaseService: 开始迁移 ${videos.length} 条视频的 resolution');

    // 批量更新
    final batch = db.batch();
    for (final row in videos) {
      final id = row[_colId] as int?;
      final fileName = row[_colFileName] as String?;
      if (id == null || fileName == null) continue;

      final fileInfo = VideoFileNameParser.parse(fileName);
      if (fileInfo.resolution != null) {
        batch.update(
          _tableMetadata,
          {_colResolution: fileInfo.resolution},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: resolution 迁移完成');
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

    // 从版本4升级到版本5
    if (oldVersion < 5) {
      // 添加本地海报缓存路径字段
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colLocalPosterUrl TEXT');

      logger.i('VideoDatabaseService: 版本4->5 升级完成');
    }

    // 从版本5升级到版本6
    if (oldVersion < 6) {
      // 添加字幕索引表
      await _createSubtitleTable(db);

      logger.i('VideoDatabaseService: 版本5->6 升级完成（添加字幕索引表）');
    }

    // 从版本6升级到版本7
    if (oldVersion < 7) {
      // 添加扫描进度表
      await _createScanProgressTable(db);

      logger.i('VideoDatabaseService: 版本6->7 升级完成（添加扫描进度表）');
    }

    // 从版本7升级到版本8
    if (oldVersion < 8) {
      // 添加 TV 剧集分组表
      await _createTvShowGroupsTable(db);
      // 添加电影系列分组表
      await _createMovieCollectionGroupsTable(db);

      logger.i('VideoDatabaseService: 版本7->8 升级完成（添加聚合表）');
    }

    // 从版本8升级到版本9
    if (oldVersion < 9) {
      // 添加 show_directory 字段（TV 剧集所属剧目录，用于分组）
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colShowDirectory TEXT');
      // 创建索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_show_directory ON $_tableMetadata($_colShowDirectory)');

      // 迁移现有 TV 剧集数据：从 file_path 解析 show_directory
      // 使用 _extractShowDirectory 逻辑在 Dart 层处理
      await _migrateShowDirectories(db);

      logger.i('VideoDatabaseService: 版本8->9 升级完成（添加 show_directory 字段）');
    }

    // 从版本9升级到版本10
    if (oldVersion < 10) {
      // 添加 movie_directory 字段（电影所在目录，用于目录系列识别）
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colMovieDirectory TEXT');
      // 创建索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_movie_directory ON $_tableMetadata($_colMovieDirectory)');

      // 迁移现有电影数据：从 file_path 解析 movie_directory
      await _migrateMovieDirectories(db);

      logger.i('VideoDatabaseService: 版本9->10 升级完成（添加 movie_directory 字段）');
    }

    // 从版本10升级到版本11
    if (oldVersion < 11) {
      // 添加 resolution 字段（视频分辨率，用于质量分组）
      await db.execute(
          'ALTER TABLE $_tableMetadata ADD COLUMN $_colResolution TEXT');

      // 迁移现有数据：从文件名解析 resolution
      await _migrateResolutions(db);

      logger.i('VideoDatabaseService: 版本10->11 升级完成（添加 resolution 字段）');
    }

    // 从版本11升级到版本12
    if (oldVersion < 12) {
      // 添加 local_poster_url 列到聚合表
      await db.execute(
          'ALTER TABLE $_tableTvShowGroups ADD COLUMN $_tvgColLocalPosterUrl TEXT');
      await db.execute(
          'ALTER TABLE $_tableMovieCollectionGroups ADD COLUMN $_mcgColLocalPosterUrl TEXT');

      // 从 video_metadata 同步 local_poster_url 到 tv_show_groups
      await db.execute('''
        UPDATE $_tableTvShowGroups
        SET $_tvgColLocalPosterUrl = (
          SELECT vm.$_colLocalPosterUrl
          FROM $_tableMetadata vm
          WHERE vm.rowid = $_tableTvShowGroups.$_tvgColRepresentativeRowid
        )
      ''');

      logger.i('VideoDatabaseService: 版本11->12 升级完成（添加聚合表 local_poster_url 字段）');
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

  /// 快速获取所有视频（Infuse 风格的即时加载）
  ///
  /// 这是最快的加载方式，用于首页初始化：
  /// - 单次简单查询，无复杂 JOIN 或分组
  /// - 按文件修改时间倒序，最新内容优先
  /// - 返回所有必要字段，供 UI 立即展示
  ///
  /// 适用场景：
  /// - 应用启动时的首次加载
  /// - 需要即时响应的场景（<50ms）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  /// [limit] 返回数量限制，0 表示不限制
  Future<List<VideoMetadata>> getAllVideosQuick({
    List<({String sourceId, String path})>? enabledPaths,
    int limit = 0,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    String sql;
    List<Object> args;

    if (pathFilter.where.isEmpty) {
      sql = 'SELECT * FROM $_tableMetadata ORDER BY $_colFileModifiedTime DESC';
      args = [];
    } else {
      sql = 'SELECT * FROM $_tableMetadata${pathFilter.where} ORDER BY $_colFileModifiedTime DESC';
      args = pathFilter.args;
    }

    if (limit > 0) {
      sql += ' LIMIT ?';
      args.add(limit);
    }

    final results = await _db!.rawQuery(sql, args);
    return results.map(_fromRow).toList();
  }

  /// 批量获取视频元数据（用于增量更新）
  ///
  /// 根据 uniqueKey 列表批量获取视频，避免多次数据库查询
  /// [keys] uniqueKey 列表，格式为 "sourceId|filePath"
  Future<Map<String, VideoMetadata>> getByKeys(List<String> keys) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return {};

    final result = <String, VideoMetadata>{};

    // SQLite 的 IN 子句有参数限制（通常是 999），分批查询
    const batchSize = 500;
    for (var i = 0; i < keys.length; i += batchSize) {
      final batch = keys.skip(i).take(batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');

      // uniqueKey = sourceId || '|' || filePath
      final sql = '''
        SELECT * FROM $_tableMetadata
        WHERE ($_colSourceId || '|' || $_colFilePath) IN ($placeholders)
      ''';

      final rows = await _db!.rawQuery(sql, batch);
      for (final row in rows) {
        final metadata = _fromRow(row);
        result[metadata.uniqueKey] = metadata;
      }
    }

    return result;
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

    // 获取数据库文件大小（稳定值，不包括 WAL 波动）
    final dbSize = await _getDatabaseSize();
    final sizeText = _formatSize(dbSize);

    return '$totalCount 个影视 · $sizeText 缓存';
  }

  /// 获取数据库文件大小（字节）
  ///
  /// 只返回主数据库文件大小，不包括 WAL 和 SHM 临时文件
  /// 这样可以避免因 WAL checkpoint 机制导致的大小波动
  Future<int> _getDatabaseSize() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        // 只返回主数据库大小，WAL/SHM 是临时文件，大小会波动
        // WAL 文件会在 checkpoint 时合并到主数据库
        return await dbFile.length();
      }
    } on Exception catch (e) {
      logger.w('VideoDatabaseService: 获取数据库大小失败', e);
    }
    return 0;
  }

  /// 执行 WAL checkpoint，将 WAL 日志合并到主数据库
  ///
  /// 建议在以下时机调用：
  /// - 应用进入后台时
  /// - 大量写操作完成后（如扫描完成）
  Future<void> checkpoint() async {
    if (!_initialized) return;
    try {
      await _db!.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      logger.d('VideoDatabaseService: WAL checkpoint 完成');
    } on Exception catch (e) {
      logger.w('VideoDatabaseService: WAL checkpoint 失败', e);
    }
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

  /// 获取第一个视频的路径信息（用于诊断路径不匹配问题）
  Future<({String sourceId, String filePath})?> getFirstVideoPath() async {
    if (!_initialized) await init();

    final result = await _db!.rawQuery(
      'SELECT $_colSourceId, $_colFilePath FROM $_tableMetadata LIMIT 1',
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final sourceId = row[_colSourceId];
    final filePath = row[_colFilePath];

    if (sourceId is! String || filePath is! String) return null;

    return (sourceId: sourceId, filePath: filePath);
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

  /// 批量获取剧集分组的季集统计（用于懒加载）
  ///
  /// 返回每个分组的季数和集数，无需加载完整剧集列表
  /// 键为分组键（tmdb_XXX 或 title_xxx），值为 (seasonCount, episodeCount)
  Future<Map<String, ({int seasonCount, int episodeCount})>> getTvShowGroupStats({
    List<int>? tmdbIds,
    List<String>? titles,
  }) async {
    if (!_initialized) await init();

    final result = <String, ({int seasonCount, int episodeCount})>{};

    // 有 TMDB ID 的分组统计
    if (tmdbIds != null && tmdbIds.isNotEmpty) {
      final placeholders = List.filled(tmdbIds.length, '?').join(', ');
      final statsResult = await _db!.rawQuery('''
        SELECT 
          $_colTmdbId,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber ELSE NULL END) as season_count,
          COUNT(*) as episode_count
        FROM $_tableMetadata
        WHERE $_colTmdbId IN ($placeholders) AND $_colCategory = 1
        GROUP BY $_colTmdbId
      ''', tmdbIds);

      for (final row in statsResult) {
        final tmdbId = row[_colTmdbId] as int?;
        if (tmdbId != null) {
          final seasonCount = (row['season_count'] as int?) ?? 1;
          final episodeCount = (row['episode_count'] as int?) ?? 1;
          result['tmdb_$tmdbId'] = (seasonCount: seasonCount, episodeCount: episodeCount);
        }
      }
    }

    // 按标题分组的统计
    if (titles != null && titles.isNotEmpty) {
      final placeholders = List.filled(titles.length, '?').join(', ');
      final statsResult = await _db!.rawQuery('''
        SELECT 
          LOWER($_colTitle) as lower_title,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber ELSE NULL END) as season_count,
          COUNT(*) as episode_count
        FROM $_tableMetadata
        WHERE LOWER($_colTitle) IN ($placeholders) AND $_colCategory = 1 AND $_colTmdbId IS NULL
        GROUP BY LOWER($_colTitle)
      ''', titles.map((t) => t.toLowerCase()).toList());

      for (final row in statsResult) {
        final lowerTitle = row['lower_title'] as String?;
        if (lowerTitle != null) {
          final seasonCount = (row['season_count'] as int?) ?? 1;
          final episodeCount = (row['episode_count'] as int?) ?? 1;
          result['title_$lowerTitle'] = (seasonCount: seasonCount, episodeCount: episodeCount);
        }
      }
    }

    return result;
  }

  /// 获取剧集分组的代表性元数据（用于分页显示剧集列表）
  ///
  /// 返回每个剧集分组的一条代表性记录（按 tmdbId 或 title 分组，取评分最高的）
  /// [enabledPaths] 启用的路径列表
  ///
  /// 性能优化说明：
  /// 使用两阶段查询策略，避免 O(n²) 的关联子查询：
  /// - 阶段1：使用 GROUP BY 获取唯一分组，复杂度 O(n)
  /// - 阶段2：使用 IN 子句获取完整记录，复杂度 O(m)（m为分组数）
  Future<List<VideoMetadata>> getTvShowGroupRepresentatives({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 阶段1：使用 GROUP BY 获取每个分组的代表性 rowid
    // 按 tmdbId 分组（有值的），按 LOWER(title) 分组（tmdbId 为空的）
    // 使用 MAX(rating) 和 MIN(season_number) 等条件选择最佳代表
    //
    // 策略：分两部分查询，合并结果
    // 1a: 有 tmdb_id 的剧集 - 按 tmdb_id 分组
    // 1b: 无 tmdb_id 的剧集 - 按 title 分组

    final representativeRowIds = <int>[];

    // 1a: 有 tmdb_id 的剧集 - 使用 JOIN + GROUP BY 策略

    // 更高效的方法：使用简单分组，每个 tmdb_id 取 MAX(rating) 对应的记录
    // SQLite 的 `GROUP BY` 会返回任意一行，我们用子查询确保取评分最高的
    // 注意：使用 AS rid 显式别名，因为 SQLite 返回的列名可能是 't1.rowid' 而不是 'rowid'
    final withTmdbSqlOptimized = '''
      SELECT t1.rowid AS rid
      FROM $_tableMetadata t1
      INNER JOIN (
        SELECT $_colTmdbId, MAX($_colRating) as max_rating
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colTmdbId IS NOT NULL${pathFilter.andWhere}
        GROUP BY $_colTmdbId
      ) t2 ON t1.$_colTmdbId = t2.$_colTmdbId AND (t1.$_colRating = t2.max_rating OR (t1.$_colRating IS NULL AND t2.max_rating IS NULL))
      WHERE t1.$_colCategory = 1 AND t1.$_colTmdbId IS NOT NULL${pathFilter.andWhere}
      GROUP BY t1.$_colTmdbId
    ''';

    final withTmdbResult = await _db!.rawQuery(withTmdbSqlOptimized, [...pathFilter.args, ...pathFilter.args]);
    representativeRowIds.addAll(
      withTmdbResult
        .map((r) => r['rid'] as int?)
        .whereType<int>(),
    );

    // 1b: 无 tmdb_id 的剧集 - 按 LOWER(title) 分组
    // 同样使用 AS rid 显式别名
    final withoutTmdbSql = '''
      SELECT t1.rowid AS rid
      FROM $_tableMetadata t1
      INNER JOIN (
        SELECT LOWER($_colTitle) as lower_title, MAX($_colRating) as max_rating
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colTmdbId IS NULL AND $_colTitle IS NOT NULL${pathFilter.andWhere}
        GROUP BY LOWER($_colTitle)
      ) t2 ON LOWER(t1.$_colTitle) = t2.lower_title AND (t1.$_colRating = t2.max_rating OR (t1.$_colRating IS NULL AND t2.max_rating IS NULL))
      WHERE t1.$_colCategory = 1 AND t1.$_colTmdbId IS NULL AND t1.$_colTitle IS NOT NULL${pathFilter.andWhere}
      GROUP BY LOWER(t1.$_colTitle)
    ''';

    final withoutTmdbResult = await _db!.rawQuery(withoutTmdbSql, [...pathFilter.args, ...pathFilter.args]);
    representativeRowIds.addAll(
      withoutTmdbResult
        .map((r) => r['rid'] as int?)
        .whereType<int>(),
    );

    if (representativeRowIds.isEmpty) {
      return [];
    }

    // 阶段2：根据 rowid 列表获取完整记录，应用排序和分页
    // 注意：需要在获取完整数据后再排序
    final placeholders = List.filled(representativeRowIds.length, '?').join(', ');
    final fullDataSql = '''
      SELECT * FROM $_tableMetadata
      WHERE rowid IN ($placeholders)
      ORDER BY $_colRating DESC NULLS LAST, $_colTitle
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(
      fullDataSql,
      [...representativeRowIds, limit, offset],
    );
    return results.map(_fromRow).toList();
  }

  /// 获取未观看的视频
  ///
  /// 排除已在观看历史中的视频（通过传入已观看路径列表）
  /// [watchedPaths] 已观看的视频路径列表（从 VideoHistoryService.getAllWatchedPaths 获取）
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getUnwatched({
    required Set<String> watchedPaths,
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();


    // 如果没有观看历史，返回全部视频
    if (watchedPaths.isEmpty) {
      return getAllVideosQuick(enabledPaths: enabledPaths, limit: limit);
    }

    // 构建排除条件：排除已观看的视频
    // 使用 sourceId + '|' + filePath 作为唯一标识
    final allVideos = await getAllVideosQuick(enabledPaths: enabledPaths);
    final unwatched = allVideos
        .where((v) => !watchedPaths.contains(v.filePath))
        .take(limit)
        .toList();

    return unwatched;
  }

  /// 获取所有存在的影片类型（去重）
  ///
  /// 返回数据库中所有视频的类型标签列表
  Future<List<String>> getAllGenres() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colGenres],
      where: '$_colGenres IS NOT NULL AND $_colGenres != ?',
      whereArgs: [''],
      distinct: true,
    );

    // 收集所有类型并去重
    final genreSet = <String>{};
    for (final row in results) {
      final genresStr = row[_colGenres] as String?;
      if (genresStr != null && genresStr.isNotEmpty) {
        final genres = genresStr.split(',').map((g) => g.trim());
        genreSet.addAll(genres.where((g) => g.isNotEmpty));
      }
    }

    // 按出现频率排序（可选：先统计每个类型的数量）
    final sortedGenres = genreSet.toList()..sort();
    return sortedGenres;
  }

  /// 根据类型获取电影
  ///
  /// [genre] 类型名称（如：动作、科幻、喜剧）
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getMoviesByGenre(
    String genre, {
    int limit = 30,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    var where = '$_colCategory = 0 AND $_colGenres LIKE ?';
    final whereArgs = <Object>['%$genre%'];

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

  /// 根据类型获取剧集（去重，每个剧只返回一条代表记录）
  ///
  /// [genre] 类型名称
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getTvShowsByGenre(
    String genre, {
    int limit = 30,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 使用子查询获取每个剧集的代表性记录
    // 注意：子查询也需要应用路径过滤，否则可能返回其他源的记录导致 rowid 不匹配
    final sql = '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1 AND $_colGenres LIKE ?${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1 AND m2.$_colGenres LIKE ?${pathFilter.andWhere}
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

    final results = await _db!.rawQuery(
      sql,
      ['%$genre%', ...pathFilter.args, '%$genre%', ...pathFilter.args, limit, offset],
    );
    return results.map(_fromRow).toList();
  }

  /// 根据类型获取所有视频（电影+剧集）
  ///
  /// 用于类型分类显示，合并电影和剧集
  Future<List<VideoMetadata>> getByGenreCombined(
    String genre, {
    int limit = 30,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    // 获取电影
    final movies = await getMoviesByGenre(
      genre,
      limit: limit ~/ 2,
      enabledPaths: enabledPaths,
    );

    // 获取剧集
    final tvShows = await getTvShowsByGenre(
      genre,
      limit: limit ~/ 2,
      enabledPaths: enabledPaths,
    );

    // 合并并按评分排序
    final combined = [...movies, ...tvShows]
    ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    return combined.take(limit).toList();
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

  /// 清空所有数据（包括所有聚合表）
  Future<void> clearAll() async {
    if (!_initialized) await init();

    // 清空所有视频相关表
    await _db!.delete(_tableMetadata);
    await _db!.delete(_tableTvShowGroups);
    await _db!.delete(_tableMovieCollectionGroups);
    await _db!.delete(_tableScanProgress);

    logger.i('VideoDatabaseService: 已清空所有数据（包括聚合表和扫描进度）');
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
        _colLocalPosterUrl: m.localPosterUrl,
        _colFileSize: m.fileSize,
        _colFileModifiedTime: m.fileModifiedTime?.millisecondsSinceEpoch,
        _colCollectionId: m.collectionId,
        _colCollectionName: m.collectionName,
        _colShowDirectory: m.showDirectory,
        _colMovieDirectory: m.movieDirectory,
        _colResolution: m.resolution,
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
        localPosterUrl: row[_colLocalPosterUrl] as String?,
        fileSize: row[_colFileSize] as int?,
        fileModifiedTime: row[_colFileModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                row[_colFileModifiedTime] as int)
            : null,
        collectionId: row[_colCollectionId] as int?,
        collectionName: row[_colCollectionName] as String?,
        showDirectory: row[_colShowDirectory] as String?,
        movieDirectory: row[_colMovieDirectory] as String?,
        resolution: row[_colResolution] as String?,
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
  /// 优化版本：使用单次批量查询代替循环查询
  /// 复杂度从 O(n) 降为 O(1)
  Future<List<MovieCollection>> getMovieCollections({int minCount = 1}) async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 步骤1：获取所有符合条件的系列 ID 和名称
    final results = await _db!.rawQuery('''
      SELECT $_colCollectionId, $_colCollectionName, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colCollectionId IS NOT NULL
        AND $_colCategory = 0
      GROUP BY $_colCollectionId
      HAVING COUNT(*) >= ?
      ORDER BY count DESC
    ''', [minCount]);

    if (results.isEmpty) {
      stopwatch.stop();
      logger.d('VideoDB: getMovieCollections - 无电影系列，耗时 ${stopwatch.elapsedMilliseconds}ms');
      return [];
    }

    // 步骤2：收集所有系列 ID
    final collectionIds = <int>[];
    final collectionNames = <int, String>{};
    for (final row in results) {
      final id = row[_colCollectionId]! as int;
      collectionIds.add(id);
      collectionNames[id] = row[_colCollectionName] as String? ?? '未知系列';
    }

    // 步骤3：单次批量查询获取所有系列的电影
    final placeholders = List.filled(collectionIds.length, '?').join(', ');
    final allMoviesResult = await _db!.rawQuery('''
      SELECT * FROM $_tableMetadata
      WHERE $_colCollectionId IN ($placeholders)
        AND $_colCategory = 0
      ORDER BY $_colCollectionId, $_colYear ASC
    ''', collectionIds);

    // 步骤4：在内存中按系列分组
    final moviesByCollection = <int, List<VideoMetadata>>{};
    for (final row in allMoviesResult) {
      final collectionId = row[_colCollectionId]! as int;
      moviesByCollection.putIfAbsent(collectionId, () => []).add(_fromRow(row));
    }

    // 步骤5：构建结果列表（保持原有顺序）
    final collections = <MovieCollection>[];
    for (final id in collectionIds) {
      collections.add(MovieCollection(
        id: id,
        name: collectionNames[id] ?? '未知系列',
        movies: moviesByCollection[id] ?? [],
      ));
    }

    stopwatch.stop();
    logger.d('VideoDB: getMovieCollections - 系列=${collections.length}, '
        '总电影=${allMoviesResult.length}, 耗时 ${stopwatch.elapsedMilliseconds}ms');

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
  ///
  /// 优化版本：使用 tv_show_groups 聚合表避免 O(n²) 相关子查询
  Future<List<VideoMetadata>> getTvShowGroupRepresentativesFiltered({
    String? genre,
    int? year,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    // 构建筛选条件（基于聚合表）
    var filterWhere = '';
    final filterArgs = <Object>[];

    if (genre != null && genre.isNotEmpty) {
      filterWhere += ' AND g.$_tvgColGenres LIKE ?';
      filterArgs.add('%$genre%');
    }

    if (year != null) {
      filterWhere += ' AND g.$_tvgColYear = ?';
      filterArgs.add(year);
    }

    // 基于聚合表字段的排序
    final orderBy = _buildOrderByForAggTable(sortOption);

    // 优化查询：使用聚合表的 representative_rowid 进行 JOIN
    // 复杂度从 O(n²) 降为 O(n)
    final sql = '''
      SELECT m.* FROM $_tableTvShowGroups g
      INNER JOIN $_tableMetadata m ON g.$_tvgColRepresentativeRowid = m.rowid
      WHERE g.$_tvgColRepresentativeRowid IS NOT NULL$filterWhere
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(sql, [...filterArgs, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 为聚合表构建排序条件
  String _buildOrderByForAggTable(VideoSortOption sortOption) {
    switch (sortOption) {
      case VideoSortOption.ratingDesc:
        return 'g.$_tvgColRating DESC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.ratingAsc:
        return 'g.$_tvgColRating ASC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.yearDesc:
        return 'g.$_tvgColYear DESC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.yearAsc:
        return 'g.$_tvgColYear ASC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.titleAsc:
        return 'g.$_tvgColTitle ASC';
      case VideoSortOption.titleDesc:
        return 'g.$_tvgColTitle DESC';
      case VideoSortOption.addedDesc:
      case VideoSortOption.addedAsc:
        // 聚合表没有添加时间，使用评分代替
        return 'g.$_tvgColRating DESC NULLS LAST, g.$_tvgColTitle';
    }
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

  /// 修复现有视频的分类（基于文件名模式）
  ///
  /// 用于修复已扫描但分类不正确的视频。会检测文件名中的剧集模式
  /// （如 S01E01、1x01、第X集）并更新 category 字段。
  ///
  /// 返回修复的视频数量。
  Future<int> repairCategoriesFromFilenames() async {
    if (!_initialized) await init();

    var fixedCount = 0;

    // 获取所有分类为 unknown（2）的视频
    final unknownVideos = await _db!.query(
      _tableMetadata,
      columns: [_colSourceId, _colFilePath, _colFileName],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.unknown.index],
    );

    logger.i('VideoDatabaseService: 发现 ${unknownVideos.length} 个未分类视频，开始修复');

    // 批量更新
    final tvShowUpdates = <({String sourceId, String filePath})>[];
    final movieUpdates = <({String sourceId, String filePath})>[];

    for (final row in unknownVideos) {
      final sourceId = row[_colSourceId] as String?;
      final filePath = row[_colFilePath] as String?;
      final fileName = row[_colFileName] as String?;
      if (sourceId == null || filePath == null || fileName == null) continue;

      // 使用正则表达式检测剧集模式（与 VideoFileNameParser 相同的逻辑）
      final tvShowPattern = RegExp(
        r'[Ss](\d{1,2})[Ee](\d{1,2})|(\d{1,2})x(\d{1,2})|第(\d+)季.*?第(\d+)集|第(\d+)集',
        caseSensitive: false,
      );

      if (tvShowPattern.hasMatch(fileName)) {
        tvShowUpdates.add((sourceId: sourceId, filePath: filePath));
      } else {
        // 检测年份模式判断是否为电影
        final yearPattern = RegExp(r'[\[\(]?((?:19|20)\d{2})[\]\)]?');
        if (yearPattern.hasMatch(fileName)) {
          movieUpdates.add((sourceId: sourceId, filePath: filePath));
        }
      }
    }

    // 批量更新为 tvShow
    if (tvShowUpdates.isNotEmpty) {
      await _db!.transaction((txn) async {
        final batch = txn.batch();
        for (final item in tvShowUpdates) {
          batch.update(
            _tableMetadata,
            {_colCategory: MediaCategory.tvShow.index},
            where: '$_colSourceId = ? AND $_colFilePath = ?',
            whereArgs: [item.sourceId, item.filePath],
          );
        }
        await batch.commit(noResult: true);
      });
      fixedCount += tvShowUpdates.length;
      logger.i('VideoDatabaseService: 已将 ${tvShowUpdates.length} 个视频修复为剧集');
    }

    // 批量更新为 movie
    if (movieUpdates.isNotEmpty) {
      await _db!.transaction((txn) async {
        final batch = txn.batch();
        for (final item in movieUpdates) {
          batch.update(
            _tableMetadata,
            {_colCategory: MediaCategory.movie.index},
            where: '$_colSourceId = ? AND $_colFilePath = ?',
            whereArgs: [item.sourceId, item.filePath],
          );
        }
        await batch.commit(noResult: true);
      });
      fixedCount += movieUpdates.length;
      logger.i('VideoDatabaseService: 已将 ${movieUpdates.length} 个视频修复为电影');
    }

    logger.i('VideoDatabaseService: 分类修复完成，共修复 $fixedCount 个视频');
    return fixedCount;
  }

  // ============ 字幕索引方法 ============

  /// 批量保存字幕索引
  ///
  /// 在视频扫描时调用，将发现的字幕文件索引到数据库
  Future<void> upsertSubtitlesBatch(List<SubtitleIndex> subtitles) async {
    if (!_initialized) await init();
    if (subtitles.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final subtitle in subtitles) {
        batch.insert(
          _tableSubtitles,
          {
            _subColSourceId: subtitle.sourceId,
            _subColVideoPath: subtitle.videoPath,
            _subColSubtitlePath: subtitle.subtitlePath,
            _subColFileName: subtitle.fileName,
            _subColFormat: subtitle.format,
            _subColLanguage: subtitle.language,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });

    logger.d('VideoDatabaseService: 批量保存 ${subtitles.length} 条字幕索引');
  }

  /// 获取视频对应的字幕列表（毫秒级响应）
  ///
  /// 从本地数据库查询，不需要访问文件系统
  Future<List<SubtitleIndex>> getSubtitlesForVideo(
    String sourceId,
    String videoPath,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath = ?',
      whereArgs: [sourceId, videoPath],
    );

    return results.map(_subtitleFromRow).toList();
  }

  /// 删除视频对应的所有字幕索引
  Future<void> deleteSubtitlesForVideo(String sourceId, String videoPath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath = ?',
      whereArgs: [sourceId, videoPath],
    );
  }

  /// 根据 sourceId 删除所有字幕索引
  Future<int> deleteSubtitlesBySourceId(String sourceId) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 根据 sourceId 和路径前缀删除字幕索引
  Future<int> deleteSubtitlesByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );
  }

  /// 从数据库行转换为 SubtitleIndex
  SubtitleIndex _subtitleFromRow(Map<String, dynamic> row) => SubtitleIndex(
        sourceId: row[_subColSourceId] as String,
        videoPath: row[_subColVideoPath] as String,
        subtitlePath: row[_subColSubtitlePath] as String,
        fileName: row[_subColFileName] as String,
        format: row[_subColFormat] as String,
        language: row[_subColLanguage] as String?,
      );

  // ============ 扫描进度方法 ============

  /// 批量保存待扫描目录
  ///
  /// 在扫描开始时，将发现的所有子目录添加到待扫描队列
  Future<void> addPendingDirectories(
    String sourceId,
    String rootPath,
    List<String> directories,
  ) async {
    if (!_initialized) await init();
    if (directories.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final dir in directories) {
        batch.insert(
          _tableScanProgress,
          {
            _scanColSourceId: sourceId,
            _scanColPath: dir,
            _scanColRootPath: rootPath,
            _scanColStatus: scanStatusPending,
            _scanColVideoCount: 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore, // 已存在则跳过
        );
      }
      await batch.commit(noResult: true);
    });

    logger.d('VideoDatabaseService: 添加 ${directories.length} 个待扫描目录');
  }

  /// 获取待扫描的目录列表
  ///
  /// 返回状态为 pending 或 scanning 的目录（scanning 表示上次中断）
  Future<List<ScanProgressItem>> getPendingDirectories(
    String sourceId,
    String rootPath, {
    int limit = 100,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      where: '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus < ?',
      whereArgs: [sourceId, rootPath, scanStatusCompleted],
      orderBy: _scanColId,
      limit: limit,
    );

    return results.map(_scanProgressFromRow).toList();
  }

  /// 标记目录开始扫描
  Future<void> markDirectoryScanning(String sourceId, String path) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableScanProgress,
      {_scanColStatus: scanStatusScanning},
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
    );
  }

  /// 标记目录扫描完成
  ///
  /// [videoCount] 该目录发现的视频数量
  Future<void> markDirectoryCompleted(
    String sourceId,
    String path, {
    int videoCount = 0,
  }) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableScanProgress,
      {
        _scanColStatus: scanStatusCompleted,
        _scanColVideoCount: videoCount,
        _scanColLastScanned: DateTime.now().millisecondsSinceEpoch,
      },
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
    );
  }

  /// 批量标记目录扫描完成
  Future<void> markDirectoriesCompletedBatch(
    List<({String sourceId, String path, int videoCount})> items,
  ) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableScanProgress,
          {
            _scanColStatus: scanStatusCompleted,
            _scanColVideoCount: item.videoCount,
            _scanColLastScanned: now,
          },
          where: '$_scanColSourceId = ? AND $_scanColPath = ?',
          whereArgs: [item.sourceId, item.path],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 获取扫描进度统计
  Future<ScanProgressStats> getScanProgressStats(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    final total = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?',
      [sourceId, rootPath],
    )) ?? 0;

    final completed = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      [sourceId, rootPath, scanStatusCompleted],
    )) ?? 0;

    final scanning = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      [sourceId, rootPath, scanStatusScanning],
    )) ?? 0;

    final totalVideos = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT SUM($_scanColVideoCount) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?',
      [sourceId, rootPath],
    )) ?? 0;

    return ScanProgressStats(
      totalDirectories: total,
      completedDirectories: completed,
      scanningDirectories: scanning,
      totalVideosFound: totalVideos,
    );
  }

  /// 清除扫描进度（用于重新扫描）
  Future<void> clearScanProgress(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableScanProgress,
      where: '$_scanColSourceId = ? AND $_scanColRootPath = ?',
      whereArgs: [sourceId, rootPath],
    );

    logger.i('VideoDatabaseService: 已清除扫描进度 (sourceId: $sourceId, rootPath: $rootPath)');
  }

  /// 清除源的所有扫描进度
  Future<void> clearScanProgressBySourceId(String sourceId) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableScanProgress,
      where: '$_scanColSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 重置中断的扫描（将 scanning 状态重置为 pending）
  Future<int> resetInterruptedScans(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    return _db!.update(
      _tableScanProgress,
      {_scanColStatus: scanStatusPending},
      where: '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      whereArgs: [sourceId, rootPath, scanStatusScanning],
    );
  }

  /// 检查是否有未完成的扫描
  Future<bool> hasUnfinishedScan(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    final count = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus < ?',
      [sourceId, rootPath, scanStatusCompleted],
    ));

    return (count ?? 0) > 0;
  }

  /// 获取已完成目录的路径集合（用于增量扫描时跳过）
  Future<Set<String>> getCompletedDirectoryPaths(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      columns: [_scanColPath],
      where: '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      whereArgs: [sourceId, rootPath, scanStatusCompleted],
    );

    return results.map((r) => r[_scanColPath]! as String).toSet();
  }

  /// 从数据库行转换为 ScanProgressItem
  ScanProgressItem _scanProgressFromRow(Map<String, dynamic> row) =>
      ScanProgressItem(
        sourceId: row[_scanColSourceId] as String,
        path: row[_scanColPath] as String,
        rootPath: row[_scanColRootPath] as String,
        status: row[_scanColStatus] as int,
        videoCount: row[_scanColVideoCount] as int? ?? 0,
        lastScanned: row[_scanColLastScanned] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_scanColLastScanned] as int)
            : null,
      );

  // ============================================
  // 聚合表同步方法
  // ============================================

  /// 同步 TV 剧集分组表
  ///
  /// 新分组策略（基于 show_directory）：
  /// 1. 优先按 show_directory 分组（最可靠，基于目录结构）
  /// 2. 在同目录组内，选择众数 tmdbId（处理部分集刮削成功的情况）
  /// 3. 合并相同 tmdbId 的不同目录（处理跨路径的同一部剧）
  ///
  /// 分组键优先级：
  /// 1. tmdb_{id} - 有 tmdbId 时使用
  /// 2. dir_{show_directory_hash} - 无 tmdbId 但有目录结构
  Future<int> syncTvShowGroups() async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 步骤 1: 清空旧数据
    await _db!.delete(_tableTvShowGroups);

    // 步骤 2: 按 show_directory 聚合，找出每个目录的众数 tmdbId
    // 这样可以处理同一目录下部分集有 tmdbId、部分没有的情况
    final directoryGroups = await _db!.rawQuery('''
      SELECT 
        $_colShowDirectory as show_directory,
        $_colTmdbId as tmdb_id,
        COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colShowDirectory IS NOT NULL
      GROUP BY $_colShowDirectory, $_colTmdbId
      ORDER BY $_colShowDirectory, count DESC
    ''');

    // 构建目录到最佳 tmdbId 的映射（取众数）
    final directoryTmdbMap = <String, int?>{};
    String? lastDir;
    for (final row in directoryGroups) {
      final dir = row['show_directory'] as String?;
      if (dir == null) continue;

      // 每个目录只取第一个（count 最大的）
      if (dir != lastDir) {
        lastDir = dir;
        final tmdbId = row['tmdb_id'] as int?;
        directoryTmdbMap[dir] = tmdbId;
      }
    }

    // 步骤 3: 收集需要合并的目录（相同 tmdbId）
    final tmdbDirectories = <int, List<String>>{};
    final orphanDirectories = <String>[]; // 没有 tmdbId 的目录

    for (final entry in directoryTmdbMap.entries) {
      if (entry.value != null) {
        tmdbDirectories.putIfAbsent(entry.value!, () => []).add(entry.key);
      } else {
        orphanDirectories.add(entry.key);
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    var insertedCount = 0;

    // 步骤 4: 为每个有 tmdbId 的分组创建记录
    for (final entry in tmdbDirectories.entries) {
      final tmdbId = entry.key;
      final directories = entry.value;

      // 构建 WHERE 子句来匹配所有相关目录
      final placeholders = directories.map((_) => '?').join(', ');

      final aggregated = await _db!.rawQuery('''
        SELECT 
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid,
          MAX($_colLocalPosterUrl) as local_poster_url
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory IN ($placeholders)
      ''', directories);

      if (aggregated.isEmpty) continue;

      final row = aggregated.first;
      final title = row['title'] as String?;
      if (title == null) continue;

      final groupKey = 'tmdb_$tmdbId';

      await _db!.rawInsert('''
        INSERT OR REPLACE INTO $_tableTvShowGroups (
          $_tvgColGroupKey,
          $_tvgColTmdbId,
          $_tvgColTitle,
          $_tvgColNormalizedTitle,
          $_tvgColOriginalTitle,
          $_tvgColYear,
          $_tvgColOverview,
          $_tvgColPosterUrl,
          $_tvgColBackdropUrl,
          $_tvgColRating,
          $_tvgColGenres,
          $_tvgColSeasonCount,
          $_tvgColEpisodeCount,
          $_tvgColRepresentativeRowid,
          $_tvgColLastSynced,
          $_tvgColLocalPosterUrl
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        groupKey,
        tmdbId,
        title,
        row['normalized_title'] as String? ?? title.toLowerCase(),
        row['original_title'] as String?,
        row['year'] as int?,
        row['overview'] as String?,
        row['poster_url'] as String?,
        row['backdrop_url'] as String?,
        row['rating'] as double?,
        row['genres'] as String?,
        row['season_count'] as int? ?? 1,
        row['episode_count'] as int? ?? 1,
        row['representative_rowid'] as int?,
        now,
        row['local_poster_url'] as String?,
      ]);

      insertedCount++;
    }

    // 步骤 5: 为没有 tmdbId 的目录单独创建分组
    for (final directory in orphanDirectories) {
      final aggregated = await _db!.rawQuery('''
        SELECT 
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid,
          MAX($_colLocalPosterUrl) as local_poster_url
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory = ?
      ''', [directory]);

      if (aggregated.isEmpty) continue;

      final row = aggregated.first;
      final title = row['title'] as String?;
      if (title == null) continue;

      // 使用目录路径的哈希作为 group_key
      final groupKey = 'dir_${directory.hashCode.abs()}';

      await _db!.rawInsert('''
        INSERT OR REPLACE INTO $_tableTvShowGroups (
          $_tvgColGroupKey,
          $_tvgColTmdbId,
          $_tvgColTitle,
          $_tvgColNormalizedTitle,
          $_tvgColOriginalTitle,
          $_tvgColYear,
          $_tvgColOverview,
          $_tvgColPosterUrl,
          $_tvgColBackdropUrl,
          $_tvgColRating,
          $_tvgColGenres,
          $_tvgColSeasonCount,
          $_tvgColEpisodeCount,
          $_tvgColRepresentativeRowid,
          $_tvgColLastSynced,
          $_tvgColLocalPosterUrl
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        groupKey,
        null, // no tmdbId
        title,
        row['normalized_title'] as String? ?? title.toLowerCase(),
        row['original_title'] as String?,
        row['year'] as int?,
        row['overview'] as String?,
        row['poster_url'] as String?,
        row['backdrop_url'] as String?,
        row['rating'] as double?,
        row['genres'] as String?,
        row['season_count'] as int? ?? 1,
        row['episode_count'] as int? ?? 1,
        row['representative_rowid'] as int?,
        now,
        row['local_poster_url'] as String?,
      ]);

      insertedCount++;
    }

    // 步骤 6: 处理没有 show_directory 的剧集（兼容旧数据）
    final noDirectoryCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(DISTINCT COALESCE($_colTmdbId, $_colTitle))
      FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colShowDirectory IS NULL
    ''')) ?? 0;

    if (noDirectoryCount > 0) {
      // 按 tmdbId 或 title 分组（旧逻辑兜底）
      final fallbackResult = await _db!.rawQuery('''
        SELECT 
          $_colTmdbId as tmdb_id,
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory IS NULL
        GROUP BY COALESCE($_colTmdbId, LOWER($_colTitle))
      ''');

      for (final row in fallbackResult) {
        final tmdbId = row['tmdb_id'] as int?;
        final title = row['title'] as String?;
        if (title == null) continue;

        final groupKey = tmdbId != null
            ? 'tmdb_$tmdbId'
            : 'title_${(row['normalized_title'] as String? ?? title.toLowerCase()).hashCode.abs()}';

        await _db!.rawInsert('''
          INSERT OR IGNORE INTO $_tableTvShowGroups (
            $_tvgColGroupKey,
            $_tvgColTmdbId,
            $_tvgColTitle,
            $_tvgColNormalizedTitle,
            $_tvgColOriginalTitle,
            $_tvgColYear,
            $_tvgColOverview,
            $_tvgColPosterUrl,
            $_tvgColBackdropUrl,
            $_tvgColRating,
            $_tvgColGenres,
            $_tvgColSeasonCount,
            $_tvgColEpisodeCount,
            $_tvgColRepresentativeRowid,
            $_tvgColLastSynced
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          groupKey,
          tmdbId,
          title,
          row['normalized_title'] as String? ?? title.toLowerCase(),
          row['original_title'] as String?,
          row['year'] as int?,
          row['overview'] as String?,
          row['poster_url'] as String?,
          row['backdrop_url'] as String?,
          row['rating'] as double?,
          row['genres'] as String?,
          row['season_count'] as int? ?? 1,
          row['episode_count'] as int? ?? 1,
          row['representative_rowid'] as int?,
          now,
        ]);

        insertedCount++;
      }
    }

    stopwatch.stop();
    logger.i('VideoDatabaseService: TV剧集分组同步完成, '
        '插入/更新 $insertedCount 条, 耗时 ${stopwatch.elapsedMilliseconds}ms');

    return insertedCount;
  }

  /// 同步电影系列分组表
  ///
  /// 新策略：
  /// 1. 聚合 TMDB collection_id 系列（官方系列）
  /// 2. 识别目录系列（同目录下 ≥2 部电影且无 TMDB 系列）
  Future<int> syncMovieCollectionGroups() async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 步骤 1: 清空旧数据
    await _db!.delete(_tableMovieCollectionGroups);

    final now = DateTime.now().millisecondsSinceEpoch;
    var insertedCount = 0;

    // 步骤 2: 聚合有 collection_id 的电影（TMDB 官方系列）
    final tmdbCollections = await _db!.rawQuery('''
      SELECT 
        $_colCollectionId,
        MAX($_colCollectionName) as name,
        MAX($_colPosterUrl) as poster_url,
        MAX($_colBackdropUrl) as backdrop_url,
        MAX($_colOverview) as overview,
        COUNT(*) as movie_count
      FROM $_tableMetadata
      WHERE $_colCategory = 0 AND $_colCollectionId IS NOT NULL
      GROUP BY $_colCollectionId
    ''');

    for (final row in tmdbCollections) {
      final collectionId = row[_colCollectionId] as int?;
      if (collectionId == null) continue;

      await _db!.rawInsert('''
        INSERT OR REPLACE INTO $_tableMovieCollectionGroups (
          $_mcgColTmdbCollectionId,
          $_mcgColName,
          $_mcgColPosterUrl,
          $_mcgColBackdropUrl,
          $_mcgColOverview,
          $_mcgColMovieCount,
          $_mcgColLastSynced
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        collectionId,
        row['name'] as String? ?? '未知系列',
        row['poster_url'] as String?,
        row['backdrop_url'] as String?,
        row['overview'] as String?,
        row['movie_count'] as int? ?? 1,
        now,
      ]);

      insertedCount++;
    }

    // 步骤 3: 识别目录系列（同目录下多部电影且无 TMDB 系列）
    // 条件：
    // - 电影分类（category = 0）
    // - 有 movie_directory
    // - 无 collection_id（避免与 TMDB 系列重复）
    // - 同目录下至少 2 部电影
    final directoryCollections = await _db!.rawQuery('''
      SELECT 
        $_colMovieDirectory as directory,
        COUNT(*) as movie_count,
        MAX($_colPosterUrl) as poster_url,
        MAX($_colBackdropUrl) as backdrop_url
      FROM $_tableMetadata
      WHERE $_colCategory = 0 
        AND $_colMovieDirectory IS NOT NULL 
        AND $_colCollectionId IS NULL
      GROUP BY $_colMovieDirectory
      HAVING COUNT(*) >= 2
    ''');

    for (final row in directoryCollections) {
      final directory = row['directory'] as String?;
      if (directory == null) continue;

      // 从目录路径提取系列名（取最后一级目录名）
      final parts = directory.split('/').where((p) => p.isNotEmpty).toList();
      final collectionName = parts.isNotEmpty ? parts.last : '未知系列';

      // 使用目录哈希作为负数 ID（与 TMDB 正数 ID 区分）
      final dirCollectionId = -1 * directory.hashCode.abs();

      await _db!.rawInsert('''
        INSERT OR REPLACE INTO $_tableMovieCollectionGroups (
          $_mcgColTmdbCollectionId,
          $_mcgColName,
          $_mcgColPosterUrl,
          $_mcgColBackdropUrl,
          $_mcgColOverview,
          $_mcgColMovieCount,
          $_mcgColLastSynced
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        dirCollectionId,
        collectionName,
        row['poster_url'] as String?,
        row['backdrop_url'] as String?,
        null, // 目录系列没有 overview
        row['movie_count'] as int? ?? 2,
        now,
      ]);

      insertedCount++;
    }

    stopwatch.stop();
    logger.i('VideoDatabaseService: 电影系列分组同步完成, '
        'TMDB: ${tmdbCollections.length}, 目录: ${directoryCollections.length}, '
        '总计 $insertedCount 条, 耗时 ${stopwatch.elapsedMilliseconds}ms');

    return insertedCount;
  }

  /// 获取 TV 剧集分组列表（从聚合表读取）
  ///
  /// 这是首页使用的高性能查询，无需 GROUP BY
  Future<List<TvShowGroupRow>> getTvShowGroupList({
    int limit = 50,
    int offset = 0,
    String orderBy = 'rating DESC',
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableTvShowGroups,
      orderBy: '$_tvgColRating DESC NULLS LAST, $_tvgColTitle',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => TvShowGroupRow(
      id: row[_tvgColId]! as int,
      groupKey: row[_tvgColGroupKey]! as String,
      tmdbId: row[_tvgColTmdbId] as int?,
      title: row[_tvgColTitle]! as String,
      normalizedTitle: row[_tvgColNormalizedTitle]! as String,
      originalTitle: row[_tvgColOriginalTitle] as String?,
      year: row[_tvgColYear] as int?,
      overview: row[_tvgColOverview] as String?,
      posterUrl: row[_tvgColPosterUrl] as String?,
      backdropUrl: row[_tvgColBackdropUrl] as String?,
      rating: row[_tvgColRating] as double?,
      genres: row[_tvgColGenres] as String?,
      seasonCount: row[_tvgColSeasonCount] as int? ?? 0,
      episodeCount: row[_tvgColEpisodeCount] as int? ?? 0,
      representativeRowid: row[_tvgColRepresentativeRowid] as int?,
      localPosterUrl: row[_tvgColLocalPosterUrl] as String?,
    )).toList();
  }

  /// 获取 TV 剧集分组总数（从聚合表读取）
  Future<int> getTvShowGroupListCount() async {
    if (!_initialized) await init();

    return Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM $_tableTvShowGroups'),
    ) ?? 0;
  }

  /// 获取电影系列分组列表（从聚合表读取）
  Future<List<MovieCollectionGroupRow>> getMovieCollectionGroupList({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMovieCollectionGroups,
      orderBy: '$_mcgColMovieCount DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((row) => MovieCollectionGroupRow(
      id: row[_mcgColId]! as int,
      tmdbCollectionId: row[_mcgColTmdbCollectionId] as int?,
      name: row[_mcgColName]! as String,
      posterUrl: row[_mcgColPosterUrl] as String?,
      backdropUrl: row[_mcgColBackdropUrl] as String?,
      overview: row[_mcgColOverview] as String?,
      movieCount: row[_mcgColMovieCount] as int? ?? 0,
    )).toList();
  }

  /// 获取电影系列分组总数（从聚合表读取）
  Future<int> getMovieCollectionGroupListCount() async {
    if (!_initialized) await init();

    return Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM $_tableMovieCollectionGroups'),
    ) ?? 0;
  }
}

/// 字幕索引实体
class SubtitleIndex {
  const SubtitleIndex({
    required this.sourceId,
    required this.videoPath,
    required this.subtitlePath,
    required this.fileName,
    required this.format,
    this.language,
  });

  /// 源ID
  final String sourceId;

  /// 关联的视频文件路径
  final String videoPath;

  /// 字幕文件路径
  final String subtitlePath;

  /// 字幕文件名
  final String fileName;

  /// 字幕格式 (srt, ass, vtt 等)
  final String format;

  /// 语言
  final String? language;
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

/// TV 剧集分组行数据（从聚合表读取）
class TvShowGroupRow {
  const TvShowGroupRow({
    required this.id,
    required this.groupKey,
    this.tmdbId,
    required this.title,
    required this.normalizedTitle,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.genres,
    required this.seasonCount,
    required this.episodeCount,
    this.representativeRowid,
    this.localPosterUrl,
  });

  final int id;
  final String groupKey;
  final int? tmdbId;
  final String title;
  final String normalizedTitle;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final double? rating;
  final String? genres;
  final int seasonCount;
  final int episodeCount;
  final int? representativeRowid;
  final String? localPosterUrl; // 本地海报路径（NAS 路径或 file://）

  /// 获取类型列表
  List<String> get genreList =>
      genres?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 显示用的海报 URL（优先本地缓存）
  String? get displayPosterUrl => localPosterUrl ?? posterUrl;

  /// 显示用的背景 URL
  String? get displayBackdropUrl => backdropUrl;
}

/// 电影系列分组行数据（从聚合表读取）
class MovieCollectionGroupRow {
  const MovieCollectionGroupRow({
    required this.id,
    this.tmdbCollectionId,
    required this.name,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    required this.movieCount,
  });

  final int id;
  final int? tmdbCollectionId;
  final String name;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final int movieCount;
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

/// 扫描进度项
class ScanProgressItem {
  const ScanProgressItem({
    required this.sourceId,
    required this.path,
    required this.rootPath,
    required this.status,
    this.videoCount = 0,
    this.lastScanned,
  });

  /// 源ID
  final String sourceId;

  /// 目录路径
  final String path;

  /// 根目录路径
  final String rootPath;

  /// 扫描状态: 0=pending, 1=scanning, 2=completed
  final int status;

  /// 该目录发现的视频数量
  final int videoCount;

  /// 最后扫描时间
  final DateTime? lastScanned;

  /// 是否待扫描
  bool get isPending => status == VideoDatabaseService.scanStatusPending;

  /// 是否正在扫描
  bool get isScanning => status == VideoDatabaseService.scanStatusScanning;

  /// 是否已完成
  bool get isCompleted => status == VideoDatabaseService.scanStatusCompleted;
}

/// 扫描进度统计
class ScanProgressStats {
  const ScanProgressStats({
    required this.totalDirectories,
    required this.completedDirectories,
    required this.scanningDirectories,
    required this.totalVideosFound,
  });

  /// 总目录数
  final int totalDirectories;

  /// 已完成目录数
  final int completedDirectories;

  /// 正在扫描的目录数
  final int scanningDirectories;

  /// 已发现的视频总数
  final int totalVideosFound;

  /// 待扫描目录数
  int get pendingDirectories =>
      totalDirectories - completedDirectories - scanningDirectories;

  /// 进度百分比 (0-1)
  double get progress =>
      totalDirectories > 0 ? completedDirectories / totalDirectories : 0;

  /// 是否全部完成
  bool get isAllDone =>
      totalDirectories > 0 && completedDirectories == totalDirectories;

  /// 是否有未完成的扫描
  bool get hasUnfinished => pendingDirectories > 0 || scanningDirectories > 0;
}
