import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';

/// 照片收藏项
class PhotoFavoriteItem {
  const PhotoFavoriteItem({
    required this.photoPath,
    required this.photoName,
    required this.sourceId,
    this.thumbnailUrl,
    this.size,
    this.width,
    this.height,
    this.modifiedAt,
    required this.addedAt,
  });

  final String photoPath;
  final String photoName;
  final String sourceId;
  final String? thumbnailUrl;
  final int? size;
  final int? width;
  final int? height;
  final DateTime? modifiedAt;
  final DateTime addedAt;

  /// 生成唯一标识符（结合源ID和路径）
  String get uniqueKey => '$sourceId:$photoPath';

  Map<String, dynamic> toMap() => {
        'photoPath': photoPath,
        'photoName': photoName,
        'sourceId': sourceId,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'width': width,
        'height': height,
        'modifiedAt': modifiedAt?.millisecondsSinceEpoch,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory PhotoFavoriteItem.fromMap(Map<dynamic, dynamic> map) =>
      PhotoFavoriteItem(
        photoPath: map['photoPath'] as String,
        photoName: map['photoName'] as String,
        sourceId: map['sourceId'] as String? ?? '',
        thumbnailUrl: map['thumbnailUrl'] as String?,
        size: map['size'] as int?,
        width: map['width'] as int?,
        height: map['height'] as int?,
        modifiedAt: map['modifiedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int)
            : null,
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );

  factory PhotoFavoriteItem.fromPhotoItem(PhotoItem item) => PhotoFavoriteItem(
        photoPath: item.path,
        photoName: item.name,
        sourceId: item.sourceId,
        thumbnailUrl: item.thumbnailUrl,
        size: item.size,
        width: item.width,
        height: item.height,
        modifiedAt: item.modifiedAt,
        addedAt: DateTime.now(),
      );

  PhotoItem toPhotoItem({String url = ''}) => PhotoItem(
        name: photoName,
        path: photoPath,
        url: url,
        sourceId: sourceId,
        thumbnailUrl: thumbnailUrl,
        size: size ?? 0,
        width: width,
        height: height,
        modifiedAt: modifiedAt,
      );
}

/// 照片收藏服务
class PhotoFavoritesService {
  PhotoFavoritesService._();
  static final instance = PhotoFavoritesService._();

  static const _favoritesBoxName = 'photo_favorites';

  Box<Map<dynamic, dynamic>>? _favoritesBox;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      _favoritesBox =
          await Hive.openBox<Map<dynamic, dynamic>>(_favoritesBoxName);
      _initialized = true;
      logger.i('PhotoFavoritesService: 初始化完成');
    } on Exception catch (e) {
      logger.e('PhotoFavoritesService: 初始化失败', e);
    }
  }

  /// 添加到收藏
  Future<void> addToFavorites(PhotoItem item) async {
    await init();
    if (_favoritesBox == null) return;

    final favorite = PhotoFavoriteItem.fromPhotoItem(item);
    await _favoritesBox!.put(favorite.uniqueKey, favorite.toMap());
    logger.i('PhotoFavoritesService: 添加收藏 ${item.name}');
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(String photoPath, String sourceId) async {
    await init();
    if (_favoritesBox == null) return;

    final key = '$sourceId:$photoPath';
    await _favoritesBox!.delete(key);
    logger.i('PhotoFavoritesService: 移除收藏 $photoPath');
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String photoPath, String sourceId) async {
    await init();
    if (_favoritesBox == null) return false;

    final key = '$sourceId:$photoPath';
    return _favoritesBox!.containsKey(key);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(PhotoItem item) async {
    final isFav = await isFavorite(item.path, item.sourceId);
    if (isFav) {
      await removeFromFavorites(item.path, item.sourceId);
      return false;
    } else {
      await addToFavorites(item);
      return true;
    }
  }

  /// 获取所有收藏
  Future<List<PhotoFavoriteItem>> getAllFavorites() async {
    await init();
    if (_favoritesBox == null) return [];

    final favorites = <PhotoFavoriteItem>[];
    for (final key in _favoritesBox!.keys) {
      final data = _favoritesBox!.get(key);
      if (data != null) {
        try {
          favorites.add(PhotoFavoriteItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按添加时间倒序排列
    favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return favorites;
  }

  /// 获取指定源的收藏
  Future<List<PhotoFavoriteItem>> getFavoritesBySource(String sourceId) async {
    final all = await getAllFavorites();
    return all.where((item) => item.sourceId == sourceId).toList();
  }

  /// 清空所有收藏
  Future<void> clearAllFavorites() async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.clear();
    logger.i('PhotoFavoritesService: 清空所有收藏');
  }

  /// 获取收藏数量
  Future<int> getFavoritesCount() async {
    await init();
    return _favoritesBox?.length ?? 0;
  }
}
