/// 文件系统抽象接口
abstract class NasFileSystem {
  /// 列出目录内容
  Future<List<FileItem>> listDirectory(String path);

  /// 获取文件信息
  Future<FileItem> getFileInfo(String path);

  /// 获取文件下载流
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range});

  /// 获取文件直接访问 URL
  Future<String> getFileUrl(String path, {Duration? expiry});

  /// 创建目录
  Future<void> createDirectory(String path);

  /// 删除文件或目录
  Future<void> delete(String path);

  /// 重命名文件或目录
  Future<void> rename(String oldPath, String newPath);

  /// 复制文件或目录
  Future<void> copy(String sourcePath, String destPath);

  /// 移动文件或目录
  Future<void> move(String sourcePath, String destPath);

  /// 上传文件
  /// [localPath] 本地文件路径
  /// [remotePath] 远程目标目录路径
  /// [fileName] 文件名（可选，默认使用本地文件名）
  /// [onProgress] 上传进度回调 (已上传字节数, 总字节数)
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  });

  /// 搜索文件
  Future<List<FileItem>> search(String query, {String? path});

  /// 获取缩略图 URL
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size});
}

/// 文件项
class FileItem {
  const FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modifiedTime,
    this.createdTime,
    this.mimeType,
    this.extension,
    this.thumbnailUrl,
    this.isHidden = false,
    this.isReadOnly = false,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? createdTime;
  final String? mimeType;
  final String? extension;
  final String? thumbnailUrl;
  final bool isHidden;
  final bool isReadOnly;

  bool get isFile => !isDirectory;

  FileType get type {
    if (isDirectory) return FileType.folder;
    return FileType.fromExtension(extension ?? '');
  }

  String get displaySize {
    if (isDirectory) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var unitIndex = 0;
    var displaySize = size.toDouble();
    while (displaySize >= 1024 && unitIndex < units.length - 1) {
      displaySize /= 1024;
      unitIndex++;
    }
    return '${displaySize.toStringAsFixed(displaySize < 10 ? 1 : 0)} ${units[unitIndex]}';
  }
}

/// 文件类型
enum FileType {
  folder,
  image,
  video,
  audio,
  document,
  archive,
  code,
  text,
  pdf,
  epub,
  comic,
  other;

  static FileType fromExtension(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    return switch (e) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' =>
        FileType.image,
      'mp4' ||
      'mkv' ||
      'avi' ||
      'mov' ||
      'wmv' ||
      'flv' ||
      'webm' ||
      'rmvb' ||
      'ts' ||
      'm2ts' =>
        FileType.video,
      'mp3' ||
      'flac' ||
      'wav' ||
      'aac' ||
      'm4a' ||
      'ogg' ||
      'wma' ||
      'ape' ||
      'aiff' ||
      'dsd' =>
        FileType.audio,
      'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' => FileType.document,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' => FileType.archive,
      'cbz' || 'cbr' => FileType.comic,
      'dart' ||
      'js' ||
      'ts' ||
      'py' ||
      'java' ||
      'kt' ||
      'swift' ||
      'go' ||
      'rs' ||
      'c' ||
      'cpp' ||
      'h' ||
      'css' ||
      'html' ||
      'xml' ||
      'json' ||
      'yaml' ||
      'yml' =>
        FileType.code,
      'txt' || 'md' || 'log' => FileType.text,
      'pdf' => FileType.pdf,
      'epub' || 'mobi' || 'azw3' || 'fb2' => FileType.epub,
      _ => FileType.other,
    };
  }
}

/// 文件范围 (用于断点续传)
class FileRange {
  const FileRange({required this.start, this.end});

  final int start;
  final int? end;
}

/// 缩略图尺寸
enum ThumbnailSize {
  small(120),
  medium(240),
  large(480),
  xlarge(720);

  const ThumbnailSize(this.pixels);
  final int pixels;
}
