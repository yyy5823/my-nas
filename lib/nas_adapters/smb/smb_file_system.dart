import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_connection_pool.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';
import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

/// SMB 文件系统实现
///
/// 使用 smb_connect 库实现文件操作
/// 支持连接池，长操作（视频流）使用独立连接
class SmbFileSystem implements NasFileSystem {
  SmbFileSystem({
    required this.client,
    this.connectionPool,
  });

  /// 主连接（用于快速操作）
  final SmbConnect client;

  /// 连接池（用于并发操作）
  final SmbConnectionPool? connectionPool;

  /// 缓存的共享列表
  List<SmbFile>? _cachedShares;

  /// 检查是否是连接断开错误
  bool _isConnectionError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('network name is no longer available') ||
        msg.contains('connection closed') ||
        msg.contains('socket closed') ||
        msg.contains('streamsink is closed') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe');
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    // logger.d('SmbFileSystem: listDirectory => $path'); // 减少日志输出

    // 根目录显示共享列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    // 尝试使用主连接
    try {
      return await _listDirectoryWithClient(client, path);
    // 使用通用 catch 捕获所有类型的异常（包括 SMB 库抛出的 String 异常）
    } catch (e) {
      // 如果是连接错误且有连接池，尝试用新连接重试
      if (_isConnectionError(e) && connectionPool != null) {
        logger.w('SmbFileSystem: 主连接断开，使用连接池重试');
        return connectionPool!.withConnection(
          (poolClient) => _listDirectoryWithClient(poolClient, path),
          type: SmbConnectionType.general,
        );
      }
      rethrow;
    }
  }

  /// 使用指定连接列出目录
  Future<List<FileItem>> _listDirectoryWithClient(
    SmbConnect smbClient,
    String path,
  ) async {
    try {
      final folder = await smbClient.file(path);
      final files = await smbClient.listFiles(folder);
      return files.map(_toFileItem).toList();
    } catch (e, st) {
      AppError.handle(e, st, 'SmbFileSystem.listDirectory');
      rethrow;
    }
  }

  /// 并行列出多个目录
  ///
  /// 利用连接池同时列出多个目录，大幅提升扫描速度
  /// 如果没有连接池，则回退到串行执行
  ///
  /// [paths] 要列出的目录路径列表
  /// [concurrency] 最大并发数（默认根据连接池配置自动调整）
  ///
  /// 返回 Map<路径, 文件列表>，失败的目录会被跳过并记录日志
  Future<Map<String, List<FileItem>>> listDirectoriesParallel(
    List<String> paths, {
    int? concurrency,
  }) async {
    if (paths.isEmpty) return {};

    final results = <String, List<FileItem>>{};

    // 如果没有连接池，回退到串行执行
    if (connectionPool == null) {
      // logger.d('SmbFileSystem: 无连接池，使用串行目录列表'); // 减少日志输出
      for (final path in paths) {
        try {
          results[path] = await listDirectory(path);
        // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          logger.w('SmbFileSystem: 列出目录失败: $path - $e');
        }
      }
      return results;
    }

    // 使用连接池并行执行
    final pool = connectionPool!;
    final maxConcurrency = concurrency ?? pool.maxConnections;
    final actualConcurrency = maxConcurrency < paths.length ? maxConcurrency : paths.length;

    // logger.d('SmbFileSystem: 并行列出 ${paths.length} 个目录，并发数: $actualConcurrency'); // 减少日志输出

    // 分批处理，每批使用连接池并行执行
    for (var i = 0; i < paths.length; i += actualConcurrency) {
      final batch = paths.skip(i).take(actualConcurrency).toList();

      final futures = batch.map((path) async {
        try {
          final files = await pool.withConnection(
            (client) => _listDirectoryWithClient(client, path),
            type: SmbConnectionType.general,
          );
          return MapEntry(path, files);
        // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          logger.w('SmbFileSystem: 并行列出目录失败: $path - $e');
          return MapEntry(path, <FileItem>[]);
        }
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        if (entry.value.isNotEmpty || !results.containsKey(entry.key)) {
          results[entry.key] = entry.value;
        }
      }
    }

    // logger.d('SmbFileSystem: 并行列出完成，成功 ${results.length}/${paths.length} 个目录'); // 减少日志输出
    return results;
  }

  /// 并行获取多个目录的修改时间（用于增量同步）
  ///
  /// [paths] 要获取信息的目录路径列表
  ///
  /// 返回 Map<路径, 修改时间>，失败的目录返回 null
  Future<Map<String, DateTime?>> getDirectoriesModifiedTime(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return {};

    final results = <String, DateTime?>{};

    // 如果没有连接池，回退到串行执行
    if (connectionPool == null) {
      for (final path in paths) {
        try {
          final info = await getFileInfo(path);
          results[path] = info.modifiedTime;
        // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          results[path] = null;
        }
      }
      return results;
    }

    // 使用连接池并行执行
    final pool = connectionPool!;
    final maxConcurrency = pool.maxConnections < paths.length
        ? pool.maxConnections
        : paths.length;

    // 分批处理
    for (var i = 0; i < paths.length; i += maxConcurrency) {
      final batch = paths.skip(i).take(maxConcurrency).toList();
      final futures = batch.map((path) async {
        try {
          final conn = await pool.acquire(SmbConnectionType.general);
          try {
            final info = await conn.stat(path);
            return MapEntry(path, info.modified);
          } finally {
            pool.release(conn);
          }
        // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          return MapEntry<String, DateTime?>(path, null);
        }
      });

      final batchResults = await Future.wait(futures);
      for (final entry in batchResults) {
        results[entry.key] = entry.value;
      }
    }

    return results;
  }

  /// 递归发现所有子目录（用于扫描阶段1）
  ///
  /// 从根目录开始，并行遍历发现所有子目录
  /// 返回所有目录路径（包括根目录）
  ///
  /// [rootPath] 根目录路径
  /// [onProgress] 进度回调，参数为当前发现的目录数
  Future<List<String>> discoverAllDirectories(
    String rootPath, {
    void Function(int count)? onProgress,
  }) async {
    final allDirectories = <String>[rootPath];
    final pendingDirectories = <String>[rootPath];

    while (pendingDirectories.isNotEmpty) {
      // 取出一批待处理的目录
      final batch = pendingDirectories.take(10).toList();
      pendingDirectories.removeRange(0, batch.length);

      // 并行列出这批目录
      final results = await listDirectoriesParallel(batch);

      // 收集发现的子目录
      for (final entry in results.entries) {
        final subDirs = entry.value
            .where((f) => f.isDirectory && !f.isHidden)
            .map((f) => f.path)
            .toList();
        allDirectories.addAll(subDirs);
        pendingDirectories.addAll(subDirs);
      }

      onProgress?.call(allDirectories.length);
    }

    logger.i('SmbFileSystem: 发现 ${allDirectories.length} 个目录');
    return allDirectories;
  }

  /// 列出共享文件夹
  Future<List<FileItem>> listShares() async {
    // logger.d('SmbFileSystem: 获取共享列表'); // 减少日志输出

    // 使用缓存
    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      return _cachedShares!.map(_toFileItem).toList();
    }

    final shares = await client.listShares();
    _cachedShares = shares;

    logger.i('SmbFileSystem: 获取到 ${shares.length} 个共享');

    return shares.map(_toFileItem).toList();
  }

  /// 清除共享缓存
  void clearSharesCache() {
    _cachedShares = null;
  }

  FileItem _toFileItem(SmbFile file) {
    final name = file.name;
    final isDir = file.isDirectory(); // isDirectory 是方法

    return FileItem(
      name: name,
      path: file.path,
      isDirectory: isDir,
      size: file.size,
      // lastModified 和 createTime 是 int (Unix 时间戳毫秒)
      modifiedTime: file.lastModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.lastModified)
          : null,
      createdTime: file.createTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(file.createTime)
          : null,
      extension: isDir ? null : _getExtension(name),
      isHidden: name.startsWith('.') || file.isHidden(),
    );
  }

  String? _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 尝试使用主连接
    try {
      final file = await client.file(path);
      return _toFileItem(file);
    } catch (e) {
      // 如果是连接错误且有连接池，尝试用新连接重试
      if (_isConnectionError(e) && connectionPool != null) {
        logger.w('SmbFileSystem: getFileInfo 主连接断开，使用连接池重试');
        return connectionPool!.withConnection(
          (poolClient) async {
            final file = await poolClient.file(path);
            return _toFileItem(file);
          },
          type: SmbConnectionType.general,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 连接策略：
    // - 有 range 参数 = 视频播放（需要长时间占用）-> 使用专用连接
    // - 无 range 参数 = 普通文件下载 -> 使用连接池（支持并发）或主连接
    SmbConnect streamClient;
    void Function()? releaseCallback;

    final needsDedicatedConnection = range != null;

    // 标记是否需要关闭连接（专用连接需要关闭，连接池连接只需释放）
    var shouldCloseOnCleanup = false;

    if (connectionPool != null && needsDedicatedConnection) {
      // 视频播放：使用专用连接，避免阻塞其他操作
      final dedicated = await connectionPool!.createDedicatedConnection();
      streamClient = dedicated.client;
      releaseCallback = dedicated.releaseCallback;
      shouldCloseOnCleanup = true;
    } else if (connectionPool != null) {
      // 普通文件下载：使用连接池分配连接（支持并发读取多个文件）
      streamClient = await connectionPool!.acquire(type: SmbConnectionType.background);
      releaseCallback = () => connectionPool!.release(streamClient);
      shouldCloseOnCleanup = false; // 连接池连接只释放，不关闭
    } else {
      // 无连接池：使用主连接（不支持并发）
      streamClient = client;
    }

    /// 清理连接资源（确保只执行一次）
    var cleanupCalled = false;
    Future<void> cleanup() async {
      if (cleanupCalled) return; // 防止重复调用
      cleanupCalled = true;

      if (releaseCallback != null) {
        if (shouldCloseOnCleanup) {
          // 专用连接：先关闭再释放槽位
          try {
            await streamClient.close();
            // ignore: avoid_catches_without_on_clauses
          } catch (_) {}
        }
        releaseCallback();
      }
    }

    try {
      final file = await streamClient.file(path);
      final fileSize = file.size;

      if (range != null) {
        // 使用 RandomAccessFile 实现范围读取
        final raf = await streamClient.open(file);

        try {
          await raf.setPosition(range.start);
          final length = range.end != null ? range.end! - range.start : fileSize - range.start;

          // 分块读取 - 使用平台特定的块大小以平衡性能和内存
          final controller = StreamController<List<int>>();
          final chunkSize = SmbPoolConfig.streamChunkSize;
          var remaining = length;

          // 使用暂停/恢复机制控制内存使用
          var isPaused = false;

          controller.onPause = () => isPaused = true;
          // ignore: cascade_invocations
          controller.onResume = () => isPaused = false;
          // ignore: cascade_invocations
          controller.onCancel = () async {
            // 客户端取消，清理资源
            // 使用 try-catch 防止连接已断开时的错误
            try {
              await raf.close();
            // ignore: avoid_catches_without_on_clauses
            } catch (_) {
              // 忽略关闭时的错误，连接可能已经断开
            }
            await cleanup();
          };

          AppError.fireAndForget(
            () async {
              var chunksRead = 0;
              try {
                while (remaining > 0 && !controller.isClosed) {
                  // 如果流被暂停，等待恢复（带超时以防止死锁）
                  var waitCount = 0;
                  while (isPaused && !controller.isClosed && waitCount < 1000) {
                    await Future<void>.delayed(const Duration(milliseconds: 10));
                    waitCount++;
                  }

                  if (controller.isClosed) break;

                  final toRead = remaining > chunkSize ? chunkSize : remaining;
                  final chunk = await raf.read(toRead);

                  if (chunk.isEmpty) break;

                  controller.add(chunk);
                  remaining -= chunk.length;
                  chunksRead++;

                  // 每读取 2 块后让出执行权，减少内存压力
                  if (chunksRead.isEven) {
                    await Future<void>.delayed(Duration.zero);
                  }
                }
                await controller.close();
              // ignore: avoid_catches_without_on_clauses
              } catch (e, st) {
                // 上报流读取错误
                AppError.handle(e, st, 'SmbFileSystem.streamRead', {
                  'path': path,
                  'rangeStart': range.start,
                  'rangeEnd': range.end,
                  'remaining': remaining,
                  'chunksRead': chunksRead,
                });
                if (!controller.isClosed) {
                  controller.addError(e);
                }
                await controller.close();
              } finally {
                try {
                  await raf.close();
                // ignore: avoid_catches_without_on_clauses
                } catch (_) {
                  // 忽略关闭时的错误，连接可能已经断开
                }
                await cleanup();
              }
            }(),
            action: 'SmbFileSystem.getFileStream',
          );

          return controller.stream;
        // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          try {
            await raf.close();
          // ignore: avoid_catches_without_on_clauses
          } catch (_) {
            // 忽略关闭时的错误
          }
          rethrow;
        }
      } else {
        // 完整文件流 - 包装以便在完成时关闭连接
        final rawStream = await streamClient.openRead(file);

        if (releaseCallback != null) {
          // 包装流，在完成时关闭专用连接
          final controller = StreamController<List<int>>();
          rawStream.listen(
            controller.add,
            onError: controller.addError,
            onDone: () async {
              await controller.close();
              await cleanup();
            },
            cancelOnError: true,
          );
          return controller.stream;
        }

        return rawStream;
      }
    } on Exception {
      await cleanup();
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      throw UnimplementedError('SMB 不支持通过 URL 获取数据流');

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      // SMB 不支持直接 URL 访问，需要通过流来访问
      // 返回一个特殊的 smb:// URL 格式，应用层需要处理
      'smb://smb-local$path';

  @override
  Future<void> createDirectory(String path) async {
    await client.createFolder(path);
  }

  @override
  Future<void> delete(String path) async {
    final file = await client.file(path);
    await client.delete(file);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final file = await client.file(oldPath);
    await client.rename(file, newPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    // SMB 原生不支持服务端复制，需要下载后上传
    throw UnimplementedError('SMB 暂不支持服务端复制，请使用下载后上传');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await rename(sourcePath, destPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('本地文件不存在', localPath);
    }

    final name = fileName ?? p.basename(localPath);
    final targetPath = remotePath.endsWith('/') ? '$remotePath$name' : '$remotePath/$name';

    // 创建远程文件
    await client.createFile(targetPath);
    final remoteFile = await client.file(targetPath);

    // 获取写入流
    final writer = await client.openWrite(remoteFile);

    try {
      final total = await file.length();
      var sent = 0;

      await for (final chunk in file.openRead()) {
        writer.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, total);
      }

      await writer.flush();
      await writer.close();
    } on Exception {
      await writer.close();
      rethrow;
    }
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    // 先尝试删除已存在的文件（如果存在）
    // 使用通用 catch 捕获所有类型的异常（包括 String 异常）
    try {
      final existingFile = await client.file(remotePath);
      await client.delete(existingFile);
    // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // 文件不存在或删除失败，忽略错误继续写入
    }

    // 创建远程文件
    await client.createFile(remotePath);
    final remoteFile = await client.file(remotePath);

    // 获取写入流
    final writer = await client.openWrite(remoteFile);

    try {
      writer.add(data);
      await writer.flush();
      await writer.close();
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      await writer.close();
      rethrow;
    }
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // SMB 不支持服务端搜索，需要客户端遍历实现
    throw UnimplementedError('SMB 暂不支持搜索功能');
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async => null;

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async => null;
}
