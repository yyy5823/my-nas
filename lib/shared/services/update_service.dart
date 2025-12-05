import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/core/utils/logger.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 更新信息
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseDate,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
    this.isMandatory = false,
  });

  final String version;
  final String releaseNotes;
  final DateTime releaseDate;
  final String downloadUrl;
  final String fileName;
  final int fileSize;
  final bool isMandatory;

  String get fileSizeText {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 更新状态
enum UpdateStatus {
  idle,
  checking,
  available,
  notAvailable,
  downloading,
  readyToInstall,
  error,
}

/// 更新服务
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final instance = UpdateService._();

  // GitHub 仓库信息
  static const _owner = 'chenqi92';
  static const _repo = 'my-nas';
  static const _apiUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _updateInfo;
  String? _errorMessage;
  double _downloadProgress = 0;
  String? _downloadedFilePath;

  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  String? get errorMessage => _errorMessage;
  double get downloadProgress => _downloadProgress;
  String? get downloadedFilePath => _downloadedFilePath;
  bool get hasUpdate => _status == UpdateStatus.available || _status == UpdateStatus.readyToInstall;

  /// 检查更新
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_status == UpdateStatus.checking || _status == UpdateStatus.downloading) {
      return;
    }

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('GitHub API 返回错误: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String).replaceFirst('v', '');
      // 解析远程版本（支持格式：0.1.5 或 0.1.5-build.2）
      final (latestVersion, latestBuild) = _parseVersion(tagName);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      logger.i('UpdateService: 当前版本 $currentVersion+$currentBuild, 最新版本 $latestVersion+$latestBuild');

      if (_isNewerVersion(latestVersion, latestBuild, currentVersion, currentBuild)) {
        final asset = _findPlatformAsset(data['assets'] as List<dynamic>);
        if (asset != null) {
          // 显示版本：如果 build > 1 则显示 0.1.5 (build 2)
          final displayVersion = latestBuild > 1
              ? '$latestVersion (build $latestBuild)'
              : latestVersion;
          _updateInfo = UpdateInfo(
            version: displayVersion,
            releaseNotes: data['body'] as String? ?? '暂无更新说明',
            releaseDate: DateTime.parse(data['published_at'] as String),
            downloadUrl: asset['browser_download_url'] as String,
            fileName: asset['name'] as String,
            fileSize: asset['size'] as int,
          );
          _status = UpdateStatus.available;
          logger.i('UpdateService: 发现新版本 $displayVersion');
        } else {
          _status = UpdateStatus.notAvailable;
          _errorMessage = '未找到当前平台的安装包';
          logger.w('UpdateService: 未找到当前平台的安装包');
        }
      } else {
        _status = UpdateStatus.notAvailable;
        logger.i('UpdateService: 当前已是最新版本');
      }
    } on Exception catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      logger.e('UpdateService: 检查更新失败', e);
    }

    notifyListeners();
  }

  /// 下载更新
  Future<void> downloadUpdate() async {
    if (_updateInfo == null || _status == UpdateStatus.downloading) {
      return;
    }

    _status = UpdateStatus.downloading;
    _downloadProgress = 0;
    _errorMessage = null;
    notifyListeners();

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_updateInfo!.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('下载失败: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? _updateInfo!.fileSize;
      final dir = await _getDownloadDirectory();
      final file = File('${dir.path}/${_updateInfo!.fileName}');
      final sink = file.openWrite();

      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        _downloadProgress = received / contentLength;
        notifyListeners();
      }

      await sink.close();
      client.close();

      _downloadedFilePath = file.path;
      _status = UpdateStatus.readyToInstall;
      logger.i('UpdateService: 下载完成 ${file.path}');
    } on Exception catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = '下载失败: $e';
      logger.e('UpdateService: 下载失败', e);
    }

    notifyListeners();
  }

  /// 安装更新
  Future<bool> installUpdate() async {
    if (_downloadedFilePath == null) return false;

    try {
      if (Platform.isWindows) {
        return await _installWindows();
      } else if (Platform.isMacOS) {
        return await _installMacOS();
      } else if (Platform.isLinux) {
        return await _installLinux();
      } else if (Platform.isAndroid) {
        return await _installAndroid();
      }
      return false;
    } on Exception catch (e) {
      _errorMessage = '安装失败: $e';
      logger.e('UpdateService: 安装失败', e);
      notifyListeners();
      return false;
    }
  }

  /// Windows 安装
  Future<bool> _installWindows() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.exe')) {
      // 运行安装程序
      await Process.start(file, [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (file.endsWith('.msix') || file.endsWith('.msixbundle')) {
      // MSIX 安装
      await Process.run('powershell', [
        '-Command',
        'Add-AppxPackage',
        '-Path',
        file,
      ]);
      return true;
    } else if (file.endsWith('.zip')) {
      // 便携版 - 打开文件夹让用户手动替换
      await Process.run('explorer', ['/select,', file]);
      return true;
    }
    return false;
  }

  /// macOS 安装
  Future<bool> _installMacOS() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.dmg')) {
      // 挂载 DMG 并打开
      await Process.run('open', [file]);
      return true;
    } else if (file.endsWith('.zip')) {
      // 打开 Finder
      await Process.run('open', ['-R', file]);
      return true;
    }
    return false;
  }

  /// Linux 安装
  Future<bool> _installLinux() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.deb')) {
      // Debian/Ubuntu
      final result = await Process.run('pkexec', ['dpkg', '-i', file]);
      return result.exitCode == 0;
    } else if (file.endsWith('.AppImage')) {
      // 设置执行权限并运行
      await Process.run('chmod', ['+x', file]);
      await Process.start(file, [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (file.endsWith('.tar.gz')) {
      // 打开文件管理器
      await Process.run('xdg-open', [File(file).parent.path]);
      return true;
    }
    return false;
  }

  /// Android 安装
  Future<bool> _installAndroid() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.apk')) {
      // 使用 open_filex 打开 APK 文件进行安装
      final result = await OpenFilex.open(file);
      logger.i('UpdateService: Android 安装结果 ${result.type} - ${result.message}');
      return result.type == ResultType.done;
    }
    return false;
  }

  /// 解析版本号（支持格式：0.1.5 或 0.1.5-build.2）
  (String version, int build) _parseVersion(String tagVersion) {
    // 检查是否包含 -build. 后缀
    if (tagVersion.contains('-build.')) {
      final parts = tagVersion.split('-build.');
      final version = parts[0];
      final build = int.tryParse(parts[1]) ?? 1;
      return (version, build);
    }
    // 没有 build 后缀，默认 build 为 1
    return (tagVersion, 1);
  }

  /// 比较版本号（包含 build number）
  bool _isNewerVersion(
    String latestVersion,
    int latestBuild,
    String currentVersion,
    int currentBuild,
  ) {
    final latestParts = latestVersion.split('.').map(int.parse).toList();
    final currentParts = currentVersion.split('.').map(int.parse).toList();

    // 首先比较主版本号
    for (var i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    // 如果主版本号长度不同
    if (latestParts.length != currentParts.length) {
      return latestParts.length > currentParts.length;
    }

    // 主版本号相同，比较 build number
    return latestBuild > currentBuild;
  }

  /// 查找当前平台的安装包
  Map<String, dynamic>? _findPlatformAsset(List<dynamic> assets) {
    final platformPatterns = _getPlatformPatterns();

    for (final asset in assets) {
      final name = (asset['name'] as String).toLowerCase();
      for (final pattern in platformPatterns) {
        if (name.contains(pattern)) {
          return asset as Map<String, dynamic>;
        }
      }
    }
    return null;
  }

  /// 获取当前平台的文件名模式
  List<String> _getPlatformPatterns() {
    if (Platform.isWindows) {
      return ['windows', 'win64', 'win32', '.exe', '.msix'];
    } else if (Platform.isMacOS) {
      // 区分 Intel 和 Apple Silicon
      return ['macos', 'darwin', '.dmg'];
    } else if (Platform.isLinux) {
      return ['linux', '.appimage', '.deb', '.tar.gz'];
    } else if (Platform.isAndroid) {
      return ['android', '.apk'];
    } else if (Platform.isIOS) {
      // iOS 不支持侧载
      return [];
    }
    return [];
  }

  /// 获取下载目录
  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android 使用外部存储
      final dir = await getExternalStorageDirectory();
      return dir ?? await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    } else {
      // 桌面平台使用下载文件夹
      final dir = await getDownloadsDirectory();
      return dir ?? await getApplicationDocumentsDirectory();
    }
  }

  /// 重置状态
  void reset() {
    _status = UpdateStatus.idle;
    _updateInfo = null;
    _errorMessage = null;
    _downloadProgress = 0;
    _downloadedFilePath = null;
    notifyListeners();
  }

  /// 清理下载的文件
  Future<void> cleanUp() async {
    if (_downloadedFilePath != null) {
      try {
        final file = File(_downloadedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } on Exception catch (e) {
        logger.w('UpdateService: 清理下载文件失败', e);
      }
      _downloadedFilePath = null;
    }
  }
}
