import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 3, // 升级版本以添加 collection 字段
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      _initialized = true;
      logger.i('VideoDatabaseService: 数据库初始化完成');
    } catch (e) {
      logger.e('VideoDatabaseService: 数据库初始化失败', e);
      rethrow;
    }
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
  Future<void> upsertBatch(List<VideoMetadata> metadataList) async {
    if (!_initialized) await init();
    if (metadataList.isEmpty) return;

    final batch = _db!.batch();
    for (final metadata in metadataList) {
      batch.insert(
        _tableMetadata,
        _toRow(metadata),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
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

    final withMetadataCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colTmdbId IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    return {
      'total': totalCount ?? 0,
      'movies': movieCount ?? 0,
      'tvShows': tvShowCount ?? 0,
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

  /// 关闭数据库
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _initialized = false;
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
  Future<ScrapeStats> getScrapeStats() async {
    if (!_initialized) await init();

    final total = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tableMetadata')) ??
        0;

    final pending = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 0')) ??
        0;

    final scraping = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 1')) ??
        0;

    final completed = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 2')) ??
        0;

    final failed = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 3')) ??
        0;

    final skipped = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 4')) ??
        0;

    final movies = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 0')) ??
        0;

    final tvShows = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1')) ??
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

  /// 获取待刮削的视频列表
  Future<List<VideoMetadata>> getPendingScrape({int limit = 50}) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colScrapeStatus = ?',
      whereArgs: [ScrapeStatus.pending.index],
      orderBy: _colId,
      limit: limit,
    );

    return results.map(_fromRow).toList();
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
  Future<int> getRetryableCount() async {
    if (!_initialized) await init();

    final count = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tableMetadata
      WHERE $_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL)
    ''', [ScrapeStatus.failed.index, ScrapeStatus.completed.index]));

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

    final batch = _db!.batch();
    for (final item in items) {
      batch.update(
        _tableMetadata,
        {_colScrapeStatus: status.index},
        where: '$_colSourceId = ? AND $_colFilePath = ?',
        whereArgs: [item.sourceId, item.filePath],
      );
    }
    await batch.commit(noResult: true);
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
      final collectionId = row[_colCollectionId] as int;
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
    return results.map((r) => r[_colYear] as int).toList();
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

  /// 根据分类、类型、年份筛选获取元数据（支持组合筛选）
  Future<List<VideoMetadata>> getFiltered({
    MediaCategory? category,
    String? genre,
    int? year,
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

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: '$_colRating DESC NULLS LAST, $_colTitle',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
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

  /// 获取剧集分组的代表性元数据（带筛选条件）
  Future<List<VideoMetadata>> getTvShowGroupRepresentativesFiltered({
    String? genre,
    int? year,
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
      ORDER BY $_colRating DESC NULLS LAST, $_colTitle
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
