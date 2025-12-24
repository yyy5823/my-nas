import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/transfer/data/services/transfer_database_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';

/// 已上传标记服务
/// 记录哪些本机文件已上传到哪个目标源
class UploadedMarkService {
  factory UploadedMarkService() => _instance ??= UploadedMarkService._();
  UploadedMarkService._();

  static UploadedMarkService? _instance;

  final _dbService = TransferDatabaseService();
  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      await _dbService.init();
      _initialized = true;
      logger.i('UploadedMarkService: 初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'UploadedMarkService.init');
      rethrow;
    }
  }

  /// 检查文件是否已上传到指定目标
  Future<bool> isUploaded(String localPath, String targetSourceId) async {
    if (!_initialized) await init();

    try {
      return await _dbService.isUploaded(localPath, targetSourceId);
    } catch (e, st) {
      AppError.ignore(e, st, '检查已上传状态失败');
      return false;
    }
  }

  /// 批量检查文件是否已上传
  /// 返回已上传的本地路径集合
  Future<Set<String>> checkUploadedBatch(
    List<String> localPaths,
    String targetSourceId,
  ) async {
    if (!_initialized) await init();

    try {
      final uploadedPaths = await _dbService.getUploadedPaths(targetSourceId);
      final uploadedSet = uploadedPaths.toSet();
      return localPaths.where(uploadedSet.contains).toSet();
    } catch (e, st) {
      AppError.ignore(e, st, '批量检查已上传状态失败');
      return {};
    }
  }

  /// 标记文件已上传
  Future<void> markUploaded(
    String localPath,
    String targetSourceId,
    String targetPath,
  ) async {
    if (!_initialized) await init();

    try {
      await _dbService.markUploaded(localPath, targetSourceId, targetPath);
      logger.d('UploadedMarkService: 已标记上传 $localPath -> $targetPath');
    } catch (e, st) {
      AppError.handle(e, st, 'UploadedMarkService.markUploaded');
    }
  }

  /// 批量标记文件已上传
  Future<void> markUploadedBatch(
    List<({String localPath, String targetPath})> items,
    String targetSourceId,
  ) async {
    if (!_initialized) await init();

    for (final item in items) {
      try {
        await _dbService.markUploaded(
          item.localPath,
          targetSourceId,
          item.targetPath,
        );
      } catch (e, st) {
        AppError.ignore(e, st, '标记单个文件上传失败');
      }
    }
    logger.i('UploadedMarkService: 批量标记 ${items.length} 个文件已上传');
  }

  /// 取消标记
  Future<void> unmarkUploaded(String localPath, String targetSourceId) async {
    if (!_initialized) await init();

    try {
      await _dbService.unmarkUploaded(localPath, targetSourceId);
      logger.d('UploadedMarkService: 已取消标记 $localPath');
    } catch (e, st) {
      AppError.ignore(e, st, '取消上传标记失败');
    }
  }

  /// 获取已上传到指定目标的所有本地路径
  Future<List<String>> getUploadedPaths(String targetSourceId) async {
    if (!_initialized) await init();

    try {
      return await _dbService.getUploadedPaths(targetSourceId);
    } catch (e, st) {
      AppError.ignore(e, st, '获取已上传路径列表失败');
      return [];
    }
  }

  /// 获取所有上传标记
  Future<List<UploadedMark>> getAllMarks({String? targetSourceId}) async {
    if (!_initialized) await init();

    try {
      return await _dbService.getAllUploadedMarks(targetSourceId: targetSourceId);
    } catch (e, st) {
      AppError.ignore(e, st, '获取所有上传标记失败');
      return [];
    }
  }

  /// 获取指定目标的上传统计
  Future<int> getUploadedCount(String targetSourceId) async {
    if (!_initialized) await init();

    try {
      final paths = await _dbService.getUploadedPaths(targetSourceId);
      return paths.length;
    } catch (e, st) {
      AppError.ignore(e, st, '获取上传统计失败');
      return 0;
    }
  }

  /// 清除指定目标的所有上传标记
  Future<void> clearMarksForTarget(String targetSourceId) async {
    if (!_initialized) await init();

    try {
      final paths = await _dbService.getUploadedPaths(targetSourceId);
      for (final path in paths) {
        await _dbService.unmarkUploaded(path, targetSourceId);
      }
      logger.i('UploadedMarkService: 已清除目标 $targetSourceId 的所有标记');
    } catch (e, st) {
      AppError.handle(e, st, 'UploadedMarkService.clearMarksForTarget');
    }
  }
}
