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
  /// [onProgress] 复制进度回调 (当前文件索引, 总文件数, 当前文件名)
  ///
  /// 返回: 成功导入的文件路径列表（相对于 Documents 目录的虚拟路径）
  Future<List<ImportedFile>> importFiles({
    required FileImportType type,
    bool allowMultiple = true,
    void Function(int current, int total, String fileName)? onProgress,
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

        onProgress?.call(i + 1, totalFiles, fileName);

        if (sourcePath == null) {
          logger.w('FileImportService: 文件路径为空 - $fileName');
          continue;
        }

        try {
          // 检查文件是否已存在于目标目录
          final targetPath = p.join(targetDir.path, fileName);
          final targetFile = File(targetPath);

          if (await targetFile.exists()) {
            // 文件已存在，生成新文件名
            final newFileName = _generateUniqueFileName(targetDir.path, fileName);
            final newTargetPath = p.join(targetDir.path, newFileName);
            await File(sourcePath).copy(newTargetPath);

            importedFiles.add(ImportedFile(
              name: newFileName,
              virtualPath: '/documents/$subdir/$newFileName',
              realPath: newTargetPath,
              size: file.size,
            ));
            logger.d('FileImportService: 导入文件（重命名）- $newFileName');
          } else {
            // 复制文件
            await File(sourcePath).copy(targetPath);

            importedFiles.add(ImportedFile(
              name: fileName,
              virtualPath: '/documents/$subdir/$fileName',
              realPath: targetPath,
              size: file.size,
            ));
            logger.d('FileImportService: 导入文件 - $fileName');
          }
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
