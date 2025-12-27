import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文件导入服务
///
/// 用于从 iOS/Android 的 Files App 导入文件到应用目录
class FileImportService {
  FileImportService._();

  static final FileImportService _instance = FileImportService._();
  static FileImportService get instance => _instance;

  /// 导入文件的目标子目录
  static const String _booksSubdir = 'Books';
  static const String _comicsSubdir = 'Comics';
  static const String _documentsSubdir = 'Documents';

  /// 根据媒体类型获取目标目录
  String _getSubdirForType(FileImportType type) => switch (type) {
    FileImportType.book => _booksSubdir,
    FileImportType.comic => _comicsSubdir,
    FileImportType.document => _documentsSubdir,
  };

  /// 获取文件类型的扩展名过滤器
  List<String>? _getAllowedExtensions(FileImportType type) => switch (type) {
    FileImportType.book => ['epub', 'pdf', 'mobi', 'azw3', 'txt', 'fb2'],
    FileImportType.comic => ['cbz', 'cbr', 'zip', 'rar', 'pdf'],
    FileImportType.document => null, // 允许所有类型
  };

  /// 从 Files App 选择并导入文件
  ///
  /// [type] 导入的文件类型，决定目标目录和文件过滤器
  /// [allowMultiple] 是否允许选择多个文件
  /// [onProgress] 复制进度回调 (当前文件索引, 总文件数, 当前文件名, 已复制字节, 文件总字节)
  ///
  /// 返回: 成功导入的文件路径列表（相对于 Documents 目录的虚拟路径）
  ///
  /// 注意：由于 iOS 安全限制，从 iCloud 或外部存储选择的文件必须复制到应用沙盒。
  /// 对于大文件（如电子书），复制可能需要一些时间。
  Future<List<ImportedFile>> importFiles({
    required FileImportType type,
    bool allowMultiple = true,
    void Function(int current, int total, String fileName, int copied, int fileSize)? onProgress,
  }) async {
    try {
      // 获取目标目录
      final docDir = await getApplicationDocumentsDirectory();
      final subdir = _getSubdirForType(type);
      final targetDir = Directory(p.join(docDir.path, subdir));

      // 确保目标目录存在
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
        logger.i('FileImportService: 创建目录 ${targetDir.path}');
      }

      // 打开文件选择器
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _getAllowedExtensions(type),
        allowMultiple: allowMultiple,
        withData: false, // 不读取数据，我们手动复制
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) {
        logger.d('FileImportService: 用户取消选择');
        return [];
      }

      final importedFiles = <ImportedFile>[];
      final totalFiles = result.files.length;

      for (var i = 0; i < totalFiles; i++) {
        final file = result.files[i];
        final fileName = file.name;
        final sourcePath = file.path;
        final fileSize = file.size;

        // 初始进度回调
        onProgress?.call(i + 1, totalFiles, fileName, 0, fileSize);

        if (sourcePath == null) {
          logger.w('FileImportService: 文件路径为空 - $fileName');
          continue;
        }

        try {
          // 检查源文件是否在应用目录内（不需要复制）
          final sourceFile = File(sourcePath);
          final isInAppDir = sourcePath.startsWith(docDir.path);

          if (isInAppDir) {
            // 文件已在应用目录内，直接添加引用
            importedFiles.add(ImportedFile(
              name: fileName,
              virtualPath: '/documents/$subdir/$fileName',
              realPath: sourcePath,
              size: fileSize,
            ));
            onProgress?.call(i + 1, totalFiles, fileName, fileSize, fileSize);
            logger.d('FileImportService: 文件已在应用目录 - $fileName');
            continue;
          }

          // 确定目标文件名
          var targetFileName = fileName;
          var targetPath = p.join(targetDir.path, fileName);
          final targetFile = File(targetPath);

          if (await targetFile.exists()) {
            // 文件已存在，生成新文件名
            targetFileName = _generateUniqueFileName(targetDir.path, fileName);
            targetPath = p.join(targetDir.path, targetFileName);
          }

          // 使用流式复制以提供进度反馈
          await _copyFileWithProgress(
            sourceFile,
            File(targetPath),
            (copied) => onProgress?.call(i + 1, totalFiles, fileName, copied, fileSize),
          );

          importedFiles.add(ImportedFile(
            name: targetFileName,
            virtualPath: '/documents/$subdir/$targetFileName',
            realPath: targetPath,
            size: fileSize,
          ));
          logger.d('FileImportService: 导入文件 - $targetFileName');
        } on Exception catch (e) {
          logger.e('FileImportService: 复制文件失败 - $fileName', e);
        }
      }

      logger.i('FileImportService: 成功导入 ${importedFiles.length}/$totalFiles 个文件');
      return importedFiles;
    } on Exception catch (e, st) {
      logger.e('FileImportService: 导入失败', e, st);
      rethrow;
    }
  }

  /// 使用流式复制文件并提供进度回调
  Future<void> _copyFileWithProgress(
    File source,
    File target,
    void Function(int copied)? onProgress,
  ) async {
    final input = source.openRead();
    final output = target.openWrite();

    var copied = 0;
    const chunkSize = 65536; // 64KB chunks for smooth progress updates
    var lastProgressTime = DateTime.now();

    await for (final chunk in input) {
      output.add(chunk);
      copied += chunk.length;

      // 每 100ms 或每 256KB 更新一次进度，避免过于频繁
      final now = DateTime.now();
      if (now.difference(lastProgressTime).inMilliseconds >= 100 ||
          copied % (chunkSize * 4) == 0) {
        onProgress?.call(copied);
        lastProgressTime = now;
      }
    }

    await output.flush();
    await output.close();

    // 最终进度
    onProgress?.call(copied);
  }

  /// 选择目录（用于浏览外部存储）
  ///
  /// 注意：在 iOS 上，选择的目录只能在当前会话中访问，
  /// 重启应用后需要重新选择。
  Future<String?> pickDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        logger.i('FileImportService: 选择目录 - $result');
      }
      return result;
    } on Exception catch (e, st) {
      logger.e('FileImportService: 选择目录失败', e, st);
      return null;
    }
  }

  /// 生成唯一文件名
  String _generateUniqueFileName(String directory, String fileName) {
    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var counter = 1;
    var newName = '${baseName}_$counter$extension';

    while (File(p.join(directory, newName)).existsSync()) {
      counter++;
      newName = '${baseName}_$counter$extension';
    }

    return newName;
  }

  /// 获取导入目录路径
  Future<String> getImportDirectory(FileImportType type) async {
    final docDir = await getApplicationDocumentsDirectory();
    final subdir = _getSubdirForType(type);
    final targetDir = Directory(p.join(docDir.path, subdir));

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    return targetDir.path;
  }

  /// 获取虚拟路径前缀
  String getVirtualPathPrefix(FileImportType type) {
    final subdir = _getSubdirForType(type);
    return '/documents/$subdir';
  }
}

/// 文件导入类型
enum FileImportType {
  book,
  comic,
  document,
}

/// 导入的文件信息
class ImportedFile {
  const ImportedFile({
    required this.name,
    required this.virtualPath,
    required this.realPath,
    required this.size,
  });

  final String name;
  final String virtualPath;
  final String realPath;
  final int size;
}
