import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 照片实体（用于 SQLite 存储）
class PhotoEntity {
  const PhotoEntity({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.thumbnailUrl,
    this.size = 0,
    this.modifiedTime,
    this.lastUpdated,
    this.fileHash,
    this.perceptualHash,
  });

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? thumbnailUrl;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? lastUpdated;
  /// 文件内容哈希（MD5），用于精确匹配完全相同的文件
  final String? fileHash;
  /// 感知哈希（pHash），用于检测视觉相似的图片
  final String? perceptualHash;

  String get uniqueKey => '${sourceId}_$filePath';

  /// 获取日期键（用于分组）
  DateTime get dateKey {
    if (modifiedTime == null || modifiedTime!.year <= 1970) {
      return DateTime(1970);
    }
    return DateTime(modifiedTime!.year, modifiedTime!.month, modifiedTime!.day);
  }

  /// 显示的文件大小
  String get displaySize {
    if (size <= 0) return '未知大小';
    const units = ['B', 'KB', 'MB', 'GB'];
    var unitIndex = 0;
    var displaySize = size.toDouble();
    while (displaySize >= 1024 && unitIndex < units.length - 1) {
      displaySize /= 1024;
      unitIndex++;
    }
    return '${displaySize.toStringAsFixed(displaySize < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  /// 获取文件夹名称
  String get folderName {
    final parts = filePath.split('/');
    if (parts.length > 1) {
      return parts[parts.length - 2];
    }
    return '根目录';
  }

  PhotoEntity copyWith({
    String? sourceId,
    String? filePath,
    String? fileName,
    String? thumbnailUrl,
    int? size,
    DateTime? modifiedTime,
    DateTime? lastUpdated,
    String? fileHash,
    String? perceptualHash,
  }) =>
      PhotoEntity(
        sourceId: sourceId ?? this.sourceId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        size: size ?? this.size,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        fileHash: fileHash ?? this.fileHash,
        perceptualHash: perceptualHash ?? this.perceptualHash,
      );
}

/// 照片数据库服务 - 使用 SQLite 支持大规模数据和索引查询
class PhotoDatabaseService {
  factory PhotoDatabaseService() => _instance ??= PhotoDatabaseService._();
  PhotoDatabaseService._();

  static PhotoDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  static const String _tablePhotos = 'photos';
  static const String _colSourceId = 'source_id';
  static const String _colFilePath = 'file_path';
  static const String _colFileName = 'file_name';
  static const String _colThumbnailUrl = 'thumbnail_url';
  static const String _colSize = 'size';
  static const String _colModifiedTime = 'modified_time';
  static const String _colLastUpdated = 'last_updated';
  static const String _colFileHash = 'file_hash';
  static const String _colPerceptualHash = 'perceptual_hash';

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'photo_library.db');

      _db = await openDatabase(
        dbPath,
        version: 2, // 升级版本以支持哈希字段
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tablePhotos (
              $_colSourceId TEXT NOT NULL,
              $_colFilePath TEXT NOT NULL,
              $_colFileName TEXT NOT NULL,
              $_colThumbnailUrl TEXT,
              $_colSize INTEGER DEFAULT 0,
              $_colModifiedTime INTEGER,
              $_colLastUpdated INTEGER,
              $_colFileHash TEXT,
              $_colPerceptualHash TEXT,
              PRIMARY KEY ($_colSourceId, $_colFilePath)
            )
          ''');

          // 创建索引以加速查询
          await db.execute(
              'CREATE INDEX idx_photos_modified ON $_tablePhotos ($_colModifiedTime DESC)');
          await db.execute(
              'CREATE INDEX idx_photos_filename ON $_tablePhotos ($_colFileName)');
          await db.execute(
              'CREATE INDEX idx_photos_size ON $_tablePhotos ($_colSize DESC)');
          // 哈希索引用于去重查询
          await db.execute(
              'CREATE INDEX idx_photos_file_hash ON $_tablePhotos ($_colFileHash)');
          await db.execute(
              'CREATE INDEX idx_photos_perceptual_hash ON $_tablePhotos ($_colPerceptualHash)');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // 从版本1升级到版本2：添加哈希字段
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE $_tablePhotos ADD COLUMN $_colFileHash TEXT');
            await db.execute('ALTER TABLE $_tablePhotos ADD COLUMN $_colPerceptualHash TEXT');
            await db.execute(
                'CREATE INDEX idx_photos_file_hash ON $_tablePhotos ($_colFileHash)');
            await db.execute(
                'CREATE INDEX idx_photos_perceptual_hash ON $_tablePhotos ($_colPerceptualHash)');
            logger.i('PhotoDatabaseService: 数据库升级到版本2，添加哈希字段');
          }
        },
      );

      _initialized = true;
      logger.i('PhotoDatabaseService: 数据库初始化完成');
    } catch (e) {
      logger.e('PhotoDatabaseService: 数据库初始化失败', e);
      rethrow;
    }
  }

  /// 插入或更新照片
  Future<void> upsert(PhotoEntity photo) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tablePhotos,
      _toRow(photo),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  Future<void> upsertBatch(List<PhotoEntity> photos) async {
    if (!_initialized) await init();
    if (photos.isEmpty) return;

    final batch = _db!.batch();
    for (final photo in photos) {
      batch.insert(
        _tablePhotos,
        _toRow(photo),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 获取单张照片
  Future<PhotoEntity?> get(String sourceId, String filePath) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tablePhotos,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 批量获取照片（用于构建 Map）
  Future<Map<String, PhotoEntity>> getBatch(
      List<String> uniqueKeys) async {
    if (!_initialized) await init();
    if (uniqueKeys.isEmpty) return {};

    final result = <String, PhotoEntity>{};
    final all = await getAll();
    for (final photo in all) {
      if (uniqueKeys.contains(photo.uniqueKey)) {
        result[photo.uniqueKey] = photo;
      }
    }
    return result;
  }

  /// 按日期获取（用于时间线分组）
  Future<List<PhotoEntity>> getByDate(
    DateTime date, {
    int? limit,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final results = await _db!.query(
      _tablePhotos,
      where: '$_colModifiedTime >= ? AND $_colModifiedTime < ?',
      whereArgs: [
        startOfDay.millisecondsSinceEpoch,
        endOfDay.millisecondsSinceEpoch,
      ],
      orderBy: '$_colModifiedTime DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取所有照片（分页）
  Future<List<PhotoEntity>> getPage({
    int limit = 100,
    int offset = 0,
    String orderBy = 'modified_time',
    bool descending = true,
  }) async {
    if (!_initialized) await init();

    final order = descending ? 'DESC' : 'ASC';
    final results = await _db!.query(
      _tablePhotos,
      orderBy: '$orderBy $order',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取所有照片
  Future<List<PhotoEntity>> getAll({
    String orderBy = 'modified_time',
    bool descending = true,
  }) async {
    if (!_initialized) await init();

    final order = descending ? 'DESC' : 'ASC';
    final results = await _db!.query(
      _tablePhotos,
      orderBy: '$orderBy $order',
    );

    return results.map(_fromRow).toList();
  }

  /// 获取最近添加的照片
  Future<List<PhotoEntity>> getRecentlyAdded({int limit = 50}) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tablePhotos,
      orderBy: '$_colLastUpdated DESC',
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 搜索照片
  Future<List<PhotoEntity>> search(
    String query, {
    int limit = 100,
  }) async {
    if (!_initialized) await init();
    if (query.isEmpty) return [];

    final results = await _db!.query(
      _tablePhotos,
      where: '$_colFileName LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: '$_colModifiedTime DESC',
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取日期分组列表（用于时间线视图）
  Future<List<({DateTime date, int count})>> getDateGroups() async {
    if (!_initialized) await init();

    final results = await _db!.rawQuery('''
      SELECT
        DATE($_colModifiedTime / 1000, 'unixepoch') as date_str,
        COUNT(*) as count
      FROM $_tablePhotos
      WHERE $_colModifiedTime IS NOT NULL
      GROUP BY date_str
      ORDER BY date_str DESC
    ''');

    final groups = <({DateTime date, int count})>[];
    for (final row in results) {
      final dateStr = row['date_str'] as String?;
      if (dateStr != null && dateStr.isNotEmpty) {
        try {
          final date = DateTime.parse(dateStr);
          groups.add((date: date, count: row['count']! as int));
        } on Exception catch (e) {
          logger.e('PhotoDatabaseService: 日期解析失败', e);
          // 忽略解析失败的日期
        }
      }
    }

    // 添加无日期的照片
    final unknownCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tablePhotos
      WHERE $_colModifiedTime IS NULL OR $_colModifiedTime <= 0
    '''));
    if (unknownCount != null && unknownCount > 0) {
      groups.add((date: DateTime(1970), count: unknownCount));
    }

    return groups;
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) await init();

    final totalCount = Sqflite.firstIntValue(
        await _db!.rawQuery('SELECT COUNT(*) FROM $_tablePhotos'));

    final totalSize = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT SUM($_colSize) FROM $_tablePhotos')) ??
        0;

    final dateGroupCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(DISTINCT DATE($_colModifiedTime / 1000, 'unixepoch'))
      FROM $_tablePhotos
      WHERE $_colModifiedTime IS NOT NULL AND $_colModifiedTime > 0
    '''));

    final folderCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(DISTINCT SUBSTR($_colFilePath, 1, LENGTH($_colFilePath) - LENGTH($_colFileName) - 1))
      FROM $_tablePhotos
    '''));

    return {
      'total': totalCount ?? 0,
      'totalSize': totalSize,
      'dateGroups': dateGroupCount ?? 0,
      'folders': folderCount ?? 0,
    };
  }

  /// 获取总数量
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getCount({
    String? sourceId,
    String? pathPrefix,
  }) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var whereClause = '';
    final args = <Object>[];

    if (sourceId != null && pathPrefix != null) {
      whereClause = ' WHERE $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      whereClause = ' WHERE $_colSourceId = ?';
      args.add(sourceId);
    }

    return Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tablePhotos$whereClause', args)) ??
        0;
  }

  /// 删除照片
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tablePhotos,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 清空所有数据
  Future<void> clear() async {
    if (!_initialized) await init();
    await _db!.delete(_tablePhotos);
    logger.i('PhotoDatabaseService: 已清空所有数据');
  }

  /// 按来源ID删除
  Future<int> deleteBySourceId(String sourceId) async {
    if (!_initialized) await init();

    final count = await _db!.delete(
      _tablePhotos,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
    logger.i('PhotoDatabaseService: 已删除 $count 张照片 (sourceId: $sourceId)');
    return count;
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    final count = await _db!.delete(
      _tablePhotos,
      where: '$_colSourceId = ? AND $_colFilePath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );
    logger.i('PhotoDatabaseService: 已删除 $count 张照片 (sourceId: $sourceId, path: $pathPrefix)');
    return count;
  }

  /// 关闭数据库
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _initialized = false;
  }

  /// 转换为数据库行
  Map<String, dynamic> _toRow(PhotoEntity p) => {
        _colSourceId: p.sourceId,
        _colFilePath: p.filePath,
        _colFileName: p.fileName,
        _colThumbnailUrl: p.thumbnailUrl,
        _colSize: p.size,
        _colModifiedTime: p.modifiedTime?.millisecondsSinceEpoch,
        _colLastUpdated:
            p.lastUpdated?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        _colFileHash: p.fileHash,
        _colPerceptualHash: p.perceptualHash,
      };

  /// 从数据库行转换
  PhotoEntity _fromRow(Map<String, dynamic> row) => PhotoEntity(
        sourceId: row[_colSourceId] as String,
        filePath: row[_colFilePath] as String,
        fileName: row[_colFileName] as String,
        thumbnailUrl: row[_colThumbnailUrl] as String?,
        size: row[_colSize] as int? ?? 0,
        modifiedTime: row[_colModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colModifiedTime] as int)
            : null,
        lastUpdated: row[_colLastUpdated] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colLastUpdated] as int)
            : null,
        fileHash: row[_colFileHash] as String?,
        perceptualHash: row[_colPerceptualHash] as String?,
      );

  /// 更新照片的哈希值
  Future<void> updateHash(
    String sourceId,
    String filePath, {
    String? fileHash,
    String? perceptualHash,
  }) async {
    if (!_initialized) await init();

    final updates = <String, dynamic>{};
    if (fileHash != null) updates[_colFileHash] = fileHash;
    if (perceptualHash != null) updates[_colPerceptualHash] = perceptualHash;

    if (updates.isEmpty) return;

    await _db!.update(
      _tablePhotos,
      updates,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 批量更新哈希值
  Future<void> updateHashBatch(List<PhotoEntity> photos) async {
    if (!_initialized) await init();
    if (photos.isEmpty) return;

    final batch = _db!.batch();
    for (final photo in photos) {
      if (photo.fileHash != null || photo.perceptualHash != null) {
        final updates = <String, dynamic>{};
        if (photo.fileHash != null) updates[_colFileHash] = photo.fileHash;
        if (photo.perceptualHash != null) updates[_colPerceptualHash] = photo.perceptualHash;

        batch.update(
          _tablePhotos,
          updates,
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [photo.sourceId, photo.filePath],
        );
      }
    }
    await batch.commit(noResult: true);
  }

  /// 获取没有哈希值的照片（用于增量计算）
  Future<List<PhotoEntity>> getPhotosWithoutHash({int limit = 100}) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tablePhotos,
      where: '$_colFileHash IS NULL OR $_colPerceptualHash IS NULL',
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取重复的照片组（基于文件哈希）
  /// 返回 Map<哈希值, 照片列表>
  Future<Map<String, List<PhotoEntity>>> getDuplicatesByFileHash() async {
    if (!_initialized) await init();

    // 先找出有重复的哈希值
    final duplicateHashes = await _db!.rawQuery('''
      SELECT $_colFileHash, COUNT(*) as cnt
      FROM $_tablePhotos
      WHERE $_colFileHash IS NOT NULL AND $_colFileHash != ''
      GROUP BY $_colFileHash
      HAVING cnt > 1
      ORDER BY cnt DESC
    ''');

    if (duplicateHashes.isEmpty) return {};

    final result = <String, List<PhotoEntity>>{};
    for (final row in duplicateHashes) {
      final hash = row[_colFileHash]! as String;
      final photos = await _db!.query(
        _tablePhotos,
        where: '$_colFileHash = ?',
        whereArgs: [hash],
        orderBy: '$_colModifiedTime DESC',
      );
      result[hash] = photos.map(_fromRow).toList();
    }

    return result;
  }

  /// 获取重复的照片组（基于感知哈希）
  /// 返回 Map<哈希值, 照片列表>
  Future<Map<String, List<PhotoEntity>>> getDuplicatesByPerceptualHash() async {
    if (!_initialized) await init();

    // 先找出有重复的哈希值
    final duplicateHashes = await _db!.rawQuery('''
      SELECT $_colPerceptualHash, COUNT(*) as cnt
      FROM $_tablePhotos
      WHERE $_colPerceptualHash IS NOT NULL AND $_colPerceptualHash != ''
      GROUP BY $_colPerceptualHash
      HAVING cnt > 1
      ORDER BY cnt DESC
    ''');

    if (duplicateHashes.isEmpty) return {};

    final result = <String, List<PhotoEntity>>{};
    for (final row in duplicateHashes) {
      final hash = row[_colPerceptualHash]! as String;
      final photos = await _db!.query(
        _tablePhotos,
        where: '$_colPerceptualHash = ?',
        whereArgs: [hash],
        orderBy: '$_colModifiedTime DESC',
      );
      result[hash] = photos.map(_fromRow).toList();
    }

    return result;
  }

  /// 获取重复照片统计
  Future<({int fileHashDuplicates, int perceptualHashDuplicates, int totalDuplicatePhotos})>
      getDuplicateStats() async {
    if (!_initialized) await init();

    final fileHashCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM (
        SELECT $_colFileHash FROM $_tablePhotos
        WHERE $_colFileHash IS NOT NULL AND $_colFileHash != ''
        GROUP BY $_colFileHash HAVING COUNT(*) > 1
      )
    ''')) ?? 0;

    final perceptualHashCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM (
        SELECT $_colPerceptualHash FROM $_tablePhotos
        WHERE $_colPerceptualHash IS NOT NULL AND $_colPerceptualHash != ''
        GROUP BY $_colPerceptualHash HAVING COUNT(*) > 1
      )
    ''')) ?? 0;

    final totalDuplicatePhotos = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tablePhotos
      WHERE $_colFileHash IN (
        SELECT $_colFileHash FROM $_tablePhotos
        WHERE $_colFileHash IS NOT NULL AND $_colFileHash != ''
        GROUP BY $_colFileHash HAVING COUNT(*) > 1
      )
    ''')) ?? 0;

    return (
      fileHashDuplicates: fileHashCount,
      perceptualHashDuplicates: perceptualHashCount,
      totalDuplicatePhotos: totalDuplicatePhotos,
    );
  }
}
