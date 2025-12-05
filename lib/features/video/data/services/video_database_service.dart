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

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
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
        UNIQUE($_colSourceId, $_colFilePath)
      )
    ''');

    // 创建索引 - 用于快速查询
    await db.execute(
        'CREATE INDEX idx_tmdb_id ON $_tableMetadata($_colTmdbId)');
    await db.execute(
        'CREATE INDEX idx_category ON $_tableMetadata($_colCategory)');
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

    logger.i('VideoDatabaseService: 表和索引创建完成');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级逻辑
    logger.i('VideoDatabaseService: 数据库升级 $oldVersion -> $newVersion');
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
  Future<List<VideoMetadata>> getByCategory(
    MediaCategory category, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colCategory = ?',
      whereArgs: [category.index],
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
  Future<List<VideoMetadata>> getRecentlyUpdated({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      orderBy: '$_colLastUpdated DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取高评分内容（分页）
  Future<List<VideoMetadata>> getTopRated({
    double minRating = 7.0,
    MediaCategory? category,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    var where = '$_colRating >= ?';
    final whereArgs = <Object>[minRating];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
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
  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) await init();

    final totalCount = Sqflite.firstIntValue(
        await _db!.rawQuery('SELECT COUNT(*) FROM $_tableMetadata'));

    final movieCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 0'));

    final tvShowCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1'));

    final withMetadataCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colTmdbId IS NOT NULL'));

    return {
      'total': totalCount ?? 0,
      'movies': movieCount ?? 0,
      'tvShows': tvShowCount ?? 0,
      'withMetadata': withMetadataCount ?? 0,
    };
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
      };

  /// 从数据库行转换
  VideoMetadata _fromRow(Map<String, dynamic> row) => VideoMetadata(
        sourceId: row[_colSourceId] as String,
        filePath: row[_colFilePath] as String,
        fileName: row[_colFileName] as String,
        category: row[_colCategory] != null
            ? MediaCategory.values[row[_colCategory] as int]
            : MediaCategory.unknown,
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
      );
}
