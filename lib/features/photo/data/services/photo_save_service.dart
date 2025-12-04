import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' hide FileType;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 照片保存服务
/// 负责下载照片到本地/相册，以及分享功能
///
/// 支持多种数据源：
/// - HTTP/HTTPS URL（NAS API、群晖、QNAP等）
/// - 文件流（SMB、WebDAV等）
/// - 本地文件（file:// URL）
class PhotoSaveService {
  PhotoSaveService._();
  static final instance = PhotoSaveService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));

  /// 判断是否为桌面平台
  bool get isDesktop => PlatformCapabilities.isDesktop;

  /// 判断是否为移动平台
  bool get isMobile => PlatformCapabilities.isMobile;

  /// 是否支持保存到相册
  bool get canSaveToGallery => PlatformCapabilities.canSaveToGallery;

  /// 是否支持系统分享
  bool get canShare => PlatformCapabilities.canShare;

  /// 是否支持完整的系统分享
  bool get canShareNatively => PlatformCapabilities.canShareNatively;

  /// 下载照片（通过 HTTP URL）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  /// - [cancelToken] 用于取消下载
  Future<SaveResult> downloadPhoto({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始下载照片: $fileName');

      // 1. 下载文件到临时目录
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'photo_download_$fileName');
      tempFile = File(tempPath);

      final response = await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      if (response.statusCode != 200) {
        return SaveResult.failure('下载失败: HTTP ${response.statusCode}');
      }

      if (!await tempFile.exists()) {
        return SaveResult.failure('下载的文件不存在');
      }

      // 2. 根据平台保存文件
      if (isDesktop) {
        return _saveToDesktop(tempFile, fileName);
      } else {
        return _saveToGallery(tempFile, fileName);
      }
    } on DioException catch (e) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      if (e.type == DioExceptionType.cancel) {
        logger.i('PhotoSaveService: 下载已取消');
        return SaveResult.cancelled();
      }

      logger.e('PhotoSaveService: 下载失败', e);
      return SaveResult.failure('下载失败: ${_getDioErrorMessage(e)}');
    } on Exception catch (e) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      logger.e('PhotoSaveService: 保存失败', e);
      return SaveResult.failure('保存失败: $e');
    }
  }

  /// 从文件系统流下载照片（用于 SMB、WebDAV 等非 HTTP 源）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  Future<SaveResult> downloadPhotoFromStream({
    required NasFileSystem fileSystem,
    required String path,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始从流下载照片: $fileName');

      // 1. 获取文件信息（用于计算进度）
      int? totalSize;
      try {
        final fileInfo = await fileSystem.getFileInfo(path);
        totalSize = fileInfo.size;
      } on Exception catch (_) {
        // 获取文件信息失败，继续下载但不显示进度
      }

      // 2. 获取文件流并写入临时文件
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'photo_download_$fileName');
      tempFile = File(tempPath);

      final stream = await fileSystem.getFileStream(path);
      final sink = tempFile.openWrite();
      var receivedBytes = 0;

      await for (final chunk in stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalSize != null && totalSize > 0) {
          onProgress?.call(receivedBytes / totalSize);
        }
      }

      await sink.close();

      if (!await tempFile.exists()) {
        return SaveResult.failure('下载的文件不存在');
      }

      // 3. 根据平台保存文件
      if (isDesktop) {
        return _saveToDesktop(tempFile, fileName);
      } else {
        return _saveToGallery(tempFile, fileName);
      }
    } on Exception catch (e) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      logger.e('PhotoSaveService: 从流下载失败', e);
      return SaveResult.failure('保存失败: $e');
    }
  }

  /// 从本地文件保存照片（用于本地文件系统）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  Future<SaveResult> saveLocalPhoto({
    required String localPath,
    required String fileName,
  }) async {
    try {
      logger.i('PhotoSaveService: 开始保存本地照片: $fileName');

      final sourceFile = File(localPath);
      if (!await sourceFile.exists()) {
        return SaveResult.failure('源文件不存在');
      }

      // 根据平台保存文件
      if (isDesktop) {
        return _saveToDesktop(sourceFile, fileName, deleteAfter: false);
      } else {
        return _saveToGallery(sourceFile, fileName, deleteAfter: false);
      }
    } on Exception catch (e) {
      logger.e('PhotoSaveService: 保存本地照片失败', e);
      return SaveResult.failure('保存失败: $e');
    }
  }

  /// 智能下载照片（根据 URL 类型自动选择下载方式）
  ///
  /// 支持的 URL 类型：
  /// - http:// 或 https:// - 使用 HTTP 下载
  /// - file:// - 直接保存本地文件
  /// - smb:// 或 webdav:// - 使用文件流下载
  Future<SaveResult> smartDownloadPhoto({
    required String url,
    required String path,
    required String fileName,
    NasFileSystem? fileSystem,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    logger.i('PhotoSaveService: 智能下载 url=$url, path=$path');

    // HTTP/HTTPS URL - 使用 Dio 下载
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return downloadPhoto(
        url: url,
        fileName: fileName,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // file:// URL - 直接保存本地文件
    if (url.startsWith('file://')) {
      final localPath = Uri.parse(url).toFilePath();
      return saveLocalPhoto(localPath: localPath, fileName: fileName);
    }

    // SMB/WebDAV 等特殊协议 - 使用文件流
    if (fileSystem != null) {
      return downloadPhotoFromStream(
        fileSystem: fileSystem,
        path: path,
        fileName: fileName,
        onProgress: onProgress,
      );
    }

    return SaveResult.failure('不支持的 URL 类型或缺少文件系统');
  }

  /// 桌面端：弹出文件对话框让用户选择保存位置
  Future<SaveResult> _saveToDesktop(
    File sourceFile,
    String fileName, {
    bool deleteAfter = true,
  }) async {
    try {
      // 弹出保存文件对话框
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存照片',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: _getAllowedExtensions(fileName),
      );

      if (result == null) {
        // 用户取消
        if (deleteAfter) await _cleanupTempFile(sourceFile);
        return SaveResult.cancelled();
      }

      // 复制文件到选定位置
      await sourceFile.copy(result);
      if (deleteAfter) await _cleanupTempFile(sourceFile);

      logger.i('PhotoSaveService: 照片已保存到: $result');
      return SaveResult.success(result);
    } on Exception catch (e) {
      logger.e('PhotoSaveService: 桌面端保存失败', e);
      if (deleteAfter) await _cleanupTempFile(sourceFile);
      return SaveResult.failure('保存失败: $e');
    }
  }

  /// 移动端：保存到相册
  Future<SaveResult> _saveToGallery(
    File sourceFile,
    String fileName, {
    bool deleteAfter = true,
  }) async {
    try {
      // 使用 gal 库保存到相册
      await Gal.putImage(sourceFile.path, album: 'MyNAS');

      // 删除临时文件
      if (deleteAfter) await _cleanupTempFile(sourceFile);

      logger.i('PhotoSaveService: 照片已保存到相册');
      return SaveResult.success(null, isGallery: true);
    } on GalException catch (e) {
      logger.e('PhotoSaveService: 保存到相册失败', e);
      if (deleteAfter) await _cleanupTempFile(sourceFile);

      // 处理权限问题
      if (e.type == GalExceptionType.accessDenied) {
        return SaveResult.failure('没有相册访问权限，请在设置中授权');
      }
      return SaveResult.failure('保存到相册失败: ${e.type.name}');
    } on Exception catch (e) {
      logger.e('PhotoSaveService: 保存到相册失败', e);
      if (deleteAfter) await _cleanupTempFile(sourceFile);
      return SaveResult.failure('保存到相册失败: $e');
    }
  }

  /// 分享照片
  /// 使用系统分享功能，支持 AirDrop、短信、邮件、社交应用等
  /// - [cancelToken] 用于取消下载
  Future<ShareResult> sharePhoto({
    required String url,
    required String fileName,
    String? text,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!canShare) {
      return ShareResult.failure('当前平台不支持分享功能');
    }

    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始分享照片: $fileName');

      // 1. 下载文件到临时目录
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'share_$fileName');
      tempFile = File(tempPath);

      final response = await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      if (response.statusCode != 200) {
        return ShareResult.failure('下载失败: HTTP ${response.statusCode}');
      }

      if (!await tempFile.exists()) {
        return ShareResult.failure('文件不存在');
      }

      // 2. 使用系统分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 分享完成后删除临时文件
      // 延迟一点删除，确保分享系统已经读取完文件
      _scheduleCleanup(tempFile);

      logger.i('PhotoSaveService: 分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable =>
          ShareResult.failure('分享功能不可用'),
      };
    } on DioException catch (e) {
      _scheduleCleanup(tempFile);

      if (e.type == DioExceptionType.cancel) {
        logger.i('PhotoSaveService: 分享下载已取消');
        return ShareResult.cancelled();
      }

      logger.e('PhotoSaveService: 分享失败 - 下载错误', e);
      return ShareResult.failure('下载失败: ${_getDioErrorMessage(e)}');
    } on Exception catch (e) {
      _scheduleCleanup(tempFile);

      logger.e('PhotoSaveService: 分享失败', e);
      return ShareResult.failure('分享失败: $e');
    }
  }

  /// 直接从内存分享照片（用于已加载的照片）
  Future<ShareResult> sharePhotoFromBytes({
    required Uint8List bytes,
    required String fileName,
    String? text,
  }) async {
    if (!canShare) {
      return ShareResult.failure('当前平台不支持分享功能');
    }

    File? tempFile;

    try {
      // 保存到临时文件
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'share_$fileName');
      tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      // 分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 延迟删除临时文件
      _scheduleCleanup(tempFile);

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable =>
          ShareResult.failure('分享功能不可用'),
      };
    } on Exception catch (e) {
      _scheduleCleanup(tempFile);

      logger.e('PhotoSaveService: 分享失败', e);
      return ShareResult.failure('分享失败: $e');
    }
  }

  /// 从本地文件分享照片
  Future<ShareResult> shareLocalPhoto({
    required String localPath,
    required String fileName,
    String? text,
  }) async {
    if (!canShare) {
      return ShareResult.failure('当前平台不支持分享功能');
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return ShareResult.failure('文件不存在');
      }

      // 直接分享本地文件，无需复制
      final xFile = XFile(localPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      logger.i('PhotoSaveService: 本地文件分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable =>
          ShareResult.failure('分享功能不可用'),
      };
    } on Exception catch (e) {
      logger.e('PhotoSaveService: 分享本地文件失败', e);
      return ShareResult.failure('分享失败: $e');
    }
  }

  /// 从文件系统流分享照片（用于 SMB、WebDAV 等非 HTTP 源）
  Future<ShareResult> sharePhotoFromStream({
    required NasFileSystem fileSystem,
    required String path,
    required String fileName,
    String? text,
    void Function(double progress)? onProgress,
  }) async {
    if (!canShare) {
      return ShareResult.failure('当前平台不支持分享功能');
    }

    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始从流准备分享: $fileName');

      // 1. 获取文件信息（用于计算进度）
      int? totalSize;
      try {
        final fileInfo = await fileSystem.getFileInfo(path);
        totalSize = fileInfo.size;
      } on Exception catch (_) {
        // 获取文件信息失败，继续但不显示进度
      }

      // 2. 获取文件流并写入临时文件
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'share_$fileName');
      tempFile = File(tempPath);

      final stream = await fileSystem.getFileStream(path);
      final sink = tempFile.openWrite();
      var receivedBytes = 0;

      await for (final chunk in stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalSize != null && totalSize > 0) {
          onProgress?.call(receivedBytes / totalSize);
        }
      }

      await sink.close();

      if (!await tempFile.exists()) {
        return ShareResult.failure('准备分享文件失败');
      }

      // 3. 分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 延迟删除临时文件
      _scheduleCleanup(tempFile);

      logger.i('PhotoSaveService: 流式分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable =>
          ShareResult.failure('分享功能不可用'),
      };
    } on Exception catch (e) {
      _scheduleCleanup(tempFile);

      logger.e('PhotoSaveService: 从流分享失败', e);
      return ShareResult.failure('分享失败: $e');
    }
  }

  /// 智能分享照片（根据 URL 类型自动选择分享方式）
  ///
  /// 支持的 URL 类型：
  /// - http:// 或 https:// - 下载后分享
  /// - file:// - 直接分享本地文件
  /// - smb:// 或其他 - 使用文件流下载后分享
  Future<ShareResult> smartSharePhoto({
    required String url,
    required String path,
    required String fileName,
    NasFileSystem? fileSystem,
    String? text,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    logger.i('PhotoSaveService: 智能分享 url=$url, path=$path');

    // HTTP/HTTPS URL - 使用 Dio 下载后分享
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return sharePhoto(
        url: url,
        fileName: fileName,
        text: text,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // file:// URL - 直接分享本地文件
    if (url.startsWith('file://')) {
      final localPath = Uri.parse(url).toFilePath();
      return shareLocalPhoto(
        localPath: localPath,
        fileName: fileName,
        text: text,
      );
    }

    // SMB/WebDAV 等特殊协议 - 使用文件流
    if (fileSystem != null) {
      return sharePhotoFromStream(
        fileSystem: fileSystem,
        path: path,
        fileName: fileName,
        text: text,
        onProgress: onProgress,
      );
    }

    return ShareResult.failure('不支持的 URL 类型或缺少文件系统');
  }

  /// 请求相册权限（iOS/Android）
  Future<bool> requestGalleryPermission() async {
    if (!canSaveToGallery) return false;

    final hasAccess = await Gal.hasAccess(toAlbum: true);
    if (hasAccess) return true;

    return Gal.requestAccess(toAlbum: true);
  }

  /// 获取允许的文件扩展名
  List<String>? _getAllowedExtensions(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext.isEmpty) return null;

    // 移除前导点
    final extWithoutDot = ext.substring(1);
    return [extWithoutDot];
  }

  /// 清理临时文件
  Future<void> _cleanupTempFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 延迟清理临时文件
  void _scheduleCleanup(File? file) {
    if (file == null) return;
    Future.delayed(const Duration(seconds: 5), () async {
      await _cleanupTempFile(file);
    });
  }

  /// 获取 Dio 错误消息
  String _getDioErrorMessage(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout => '连接超时',
      DioExceptionType.sendTimeout => '发送超时',
      DioExceptionType.receiveTimeout => '接收超时',
      DioExceptionType.badResponse => 'HTTP ${e.response?.statusCode}',
      DioExceptionType.cancel => '已取消',
      DioExceptionType.connectionError => '网络连接失败',
      DioExceptionType.unknown => e.message ?? '未知错误',
      _ => e.message ?? '网络错误',
    };
  }
}

/// 保存结果
class SaveResult {
  const SaveResult._({
    required this.status,
    this.path,
    this.error,
    this.isGallery = false,
  });

  factory SaveResult.success(String? path, {bool isGallery = false}) =>
      SaveResult._(status: SaveStatus.success, path: path, isGallery: isGallery);

  factory SaveResult.failure(String error) =>
      SaveResult._(status: SaveStatus.failure, error: error);

  factory SaveResult.cancelled() =>
      const SaveResult._(status: SaveStatus.cancelled);

  final SaveStatus status;
  final String? path;
  final String? error;
  final bool isGallery;

  bool get isSuccess => status == SaveStatus.success;
  bool get isCancelled => status == SaveStatus.cancelled;
  bool get isFailure => status == SaveStatus.failure;

  String get message {
    return switch (status) {
      SaveStatus.success when isGallery => '已保存到相册',
      SaveStatus.success => '已保存到: $path',
      SaveStatus.cancelled => '已取消',
      SaveStatus.failure => error ?? '保存失败',
    };
  }
}

enum SaveStatus { success, failure, cancelled }

/// 分享结果
class ShareResult {
  const ShareResult._({
    required this.status,
    this.error,
  });

  factory ShareResult.success() =>
      const ShareResult._(status: ShareStatus.success);

  factory ShareResult.failure(String error) =>
      ShareResult._(status: ShareStatus.failure, error: error);

  factory ShareResult.cancelled() =>
      const ShareResult._(status: ShareStatus.cancelled);

  final ShareStatus status;
  final String? error;

  bool get isSuccess => status == ShareStatus.success;
  bool get isCancelled => status == ShareStatus.cancelled;
  bool get isFailure => status == ShareStatus.failure;
}

enum ShareStatus { success, failure, cancelled }
