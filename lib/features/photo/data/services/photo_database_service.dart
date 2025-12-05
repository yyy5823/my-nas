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
  });

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? thumbnailUrl;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? lastUpdated;

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
  }) =>
      PhotoEntity(
        sourceId: sourceId ?? this.sourceId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        size: size ?? this.size,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastUpdated: lastUpdated ?? this.lastUpdated,
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

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'photo_library.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
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
  Future<int> getCount() async {
    if (!_initialized) await init();
    return Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tablePhotos')) ??
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
  Future<void> deleteBySource(String sourceId) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tablePhotos,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
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
      );
}
