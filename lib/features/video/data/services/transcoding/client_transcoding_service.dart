import 'dart:async' show StreamController, TimeoutException, unawaited;
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/transcoding/nas_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 客户端 FFmpeg 转码服务
///
/// 使用本地 FFmpeg 进行视频转码，适用于不支持服务端转码的源
/// 例如: SMB, FTP, WebDAV 等
///
/// 注意: 此服务需要设备支持 FFmpeg
/// - iOS/Android: 使用 ffmpeg_kit_flutter 依赖
/// - macOS: 使用打包在应用内的 FFmpeg
/// - Linux/Windows: 需要本地安装 FFmpeg
class ClientTranscodingService implements NasTranscodingService {
  ClientTranscodingService();

  /// 是否支持转码
  bool _isAvailable = false;

  /// 临时文件目录
  Directory? _tempDir;

  /// 桌面端 FFmpeg 可执行文件路径
  String? _ffmpegPath;

  /// 活跃的转码任务
  final Map<String, _TranscodingTask> _tasks = {};

  /// 转码进度控制器
  final Map<String, StreamController<TranscodingProgress>> _progressControllers = {};

  @override
  bool get isAvailable => _isAvailable;

  @override
  TranscodingCapability get capability =>
      _isAvailable ? TranscodingCapability.clientSide : TranscodingCapability.none;

  /// 初始化服务
  Future<void> init() async {
    try {
      // 获取临时目录
      _tempDir = await getTemporaryDirectory();

      // 检查 FFmpeg 是否可用
      _isAvailable = await _checkFfmpegAvailable();

      if (_isAvailable) {
        logger.i('ClientTranscoding: FFmpeg 可用，客户端转码已启用');
      } else {
        logger.w('ClientTranscoding: FFmpeg 不可用，客户端转码已禁用');
      }
    } catch (e, st) {
      AppError.ignore(e, st, '初始化客户端转码服务失败');
      _isAvailable = false;
    }
  }

  /// 检查 FFmpeg 是否可用
  Future<bool> _checkFfmpegAvailable() async {
    // 在不同平台上检查 FFmpeg
    if (Platform.isIOS || Platform.isAndroid) {
      // 移动端使用 ffmpeg_kit_flutter
      try {
        // 执行简单命令验证 FFmpeg 可用
        final session = await FFmpegKit.execute('-version');
        final returnCode = await session.getReturnCode();
        return ReturnCode.isSuccess(returnCode);
      } catch (e, st) {
        AppError.ignore(e, st, '检查移动端 FFmpeg 可用性失败');
        return false;
      }
    } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      // 桌面端检查 FFmpeg
      _ffmpegPath = await _findDesktopFfmpeg();
      if (_ffmpegPath != null) {
        logger.i('ClientTranscoding: 找到 FFmpeg: $_ffmpegPath');
        return true;
      }
      return false;
    }
    return false;
  }

  /// 查找桌面端 FFmpeg 可执行文件
  Future<String?> _findDesktopFfmpeg() async {
    // macOS: 优先使用打包在应用内的 FFmpeg
    if (Platform.isMacOS) {
      final bundledPath = await _getBundledFfmpegPath();
      logger.d('ClientTranscoding: 检查打包的 FFmpeg 路径: $bundledPath');
      if (bundledPath != null && await File(bundledPath).exists()) {
        logger.d('ClientTranscoding: 打包的 FFmpeg 文件存在');
        // 验证可执行（添加超时防止卡住）
        try {
          final result = await Process.run(bundledPath, ['-version'])
              .timeout(const Duration(seconds: 5));
          logger.d('ClientTranscoding: FFmpeg 执行测试退出码: ${result.exitCode}');
          if (result.exitCode == 0) {
            return bundledPath;
          } else {
            logger.w('ClientTranscoding: FFmpeg 执行失败: ${result.stderr}');
          }
        } on TimeoutException {
          logger.w('ClientTranscoding: FFmpeg 执行超时');
          // 继续尝试系统 FFmpeg
        } catch (e) {
          logger.w('ClientTranscoding: FFmpeg 执行异常: $e');
          // 继续尝试系统 FFmpeg
        }
      } else {
        logger.w('ClientTranscoding: 打包的 FFmpeg 文件不存在');
      }
    }

    // 尝试系统 PATH 中的 FFmpeg
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        return 'ffmpeg';
      }
    } catch (_) {
      // FFmpeg 不在 PATH 中
    }

    return null;
  }

  /// 获取打包在 macOS 应用内的 FFmpeg 路径
  Future<String?> _getBundledFfmpegPath() async {
    if (!Platform.isMacOS) return null;

    try {
      // 获取应用可执行文件路径
      final executable = Platform.resolvedExecutable;
      // 应用结构: MyApp.app/Contents/MacOS/my_nas
      // FFmpeg 位置: MyApp.app/Contents/MacOS/ffmpeg
      final macosDir = File(executable).parent.path;
      final ffmpegPath = '$macosDir/ffmpeg';
      return ffmpegPath;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (!_isAvailable) {
      logger.w('ClientTranscoding: 转码不可用');
      return null;
    }

    // 如果是原画，不需要转码
    if (quality.isOriginal) {
      return null;
    }

    try {
      // 创建转码任务
      final taskId = const Uuid().v4();
      final outputPath = '${_tempDir!.path}/transcoded_$taskId.mp4';

      // 开始后台转码
      final task = _TranscodingTask(
        taskId: taskId,
        inputPath: videoPath,
        outputPath: outputPath,
        quality: quality,
        startPosition: startPosition,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      _tasks[taskId] = task;

      // 同步执行转码并等待完成
      await _startTranscoding(task);

      // 检查转码结果
      if (task.isCompleted && task.error == null) {
        // 验证输出文件存在
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          return 'file://$outputPath';
        } else {
          logger.e('ClientTranscoding: 输出文件不存在 $outputPath');
          return null;
        }
      } else {
        logger.e('ClientTranscoding: 转码失败 ${task.error}');
        return null;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'clientGetTranscodedStreamUrl');
      return null;
    }
  }

  @override
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  }) async {
    if (!_isAvailable) {
      return [VideoQuality.original];
    }

    // 客户端转码支持所有低于原始分辨率的清晰度
    if (originalWidth != null && originalHeight != null) {
      return VideoQuality.getAvailableQualities(
        videoWidth: originalWidth,
        videoHeight: originalHeight,
      );
    }

    // 默认返回常见清晰度
    return [
      VideoQuality.original,
      VideoQuality.quality1080p,
      VideoQuality.quality720p,
      VideoQuality.quality480p,
    ];
  }

  @override
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  }) async {
    if (!_isAvailable) return null;

    try {
      final streamUrl = await getTranscodedStreamUrl(
        videoPath: videoPath,
        quality: quality,
      );

      if (streamUrl == null) return null;

      final sessionId = const Uuid().v4();

      // 创建进度控制器
      _progressControllers[sessionId] = StreamController<TranscodingProgress>.broadcast();

      logger.i('ClientTranscoding: 会话已创建 $sessionId');

      return TranscodingSession(
        sessionId: sessionId,
        streamUrl: streamUrl,
        quality: quality,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'clientStartSession');
      return null;
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    // 关闭进度控制器
    await _progressControllers[sessionId]?.close();
    _progressControllers.remove(sessionId);

    logger.i('ClientTranscoding: 会话已停止 $sessionId');
  }

  @override
  Future<TranscodingProgress?> getProgress(String sessionId) async {
    // 查找对应的任务
    for (final task in _tasks.values) {
      if (task.isRunning) {
        return TranscodingProgress(
          status: TranscodingStatus.transcoding,
          progress: task.progress,
          speed: task.speed,
          eta: task.eta,
        );
      }
    }

    return const TranscodingProgress(status: TranscodingStatus.idle);
  }

  /// 获取转码进度流
  Stream<TranscodingProgress>? getProgressStream(String sessionId) =>
      _progressControllers[sessionId]?.stream;

  @override
  Future<void> dispose() async {
    // 停止所有任务
    for (final task in _tasks.values) {
      task.cancel();
    }
    _tasks.clear();

    // 关闭所有控制器
    for (final controller in _progressControllers.values) {
      await controller.close();
    }
    _progressControllers.clear();

    // 清理临时文件
    await _cleanupTempFiles();
  }

  /// 启动转码任务
  ///
  /// [waitForComplete] 如果为 true，等待转码完成；否则等待输出文件有数据就返回
  Future<void> _startTranscoding(_TranscodingTask task, {bool waitForComplete = false}) async {
    task.isRunning = true;

    try {
      // 如果输入是 HTTP URL，先验证可访问性
      if (task.inputPath.startsWith('http://') || task.inputPath.startsWith('https://')) {
        final isAccessible = await _checkUrlAccessible(task.inputPath);
        if (!isAccessible) {
          task.isRunning = false;
          task.error = '无法访问输入 URL';
          return;
        }
      }

      // 构建 FFmpeg 命令参数
      final args = _buildFfmpegArgs(task);
      final command = args.join(' ');

      logger.i('ClientTranscoding: 开始转码 ${task.inputPath}');
      logger.d('ClientTranscoding: FFmpeg 命令 => $command');

      if (Platform.isIOS || Platform.isAndroid) {
        // 移动端使用 FFmpegKit
        await _runMobileTranscoding(task, command);
      } else {
        // 桌面端使用 Process
        await _runDesktopTranscoding(task, args, waitForComplete: waitForComplete);
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'clientStartTranscoding');
    }
  }

  /// 检查 URL 是否可访问
  Future<bool> _checkUrlAccessible(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.headUrl(Uri.parse(url));
      final response = await request.close();

      final statusCode = response.statusCode;
      final contentLength = response.contentLength;

      logger.d('ClientTranscoding: URL 检查 - 状态码=$statusCode, 内容长度=$contentLength');

      client.close();

      if (statusCode >= 200 && statusCode < 400) {
        return true;
      } else {
        logger.e('ClientTranscoding: URL 不可访问，状态码=$statusCode');
        return false;
      }
    } catch (e) {
      logger.e('ClientTranscoding: URL 检查失败: $e');
      return false;
    }
  }

  /// 移动端转码（使用 FFmpegKit）
  Future<void> _runMobileTranscoding(_TranscodingTask task, String command) async {
    try {
      // 设置进度回调
      FFmpegKitConfig.enableStatisticsCallback((Statistics statistics) {
        final timeInMs = statistics.getTime().toDouble();
        if (timeInMs > 0) {
          task.currentTime = Duration(milliseconds: timeInMs.round());
          // 如果知道总时长，计算进度
          if (task.totalDuration != null && task.totalDuration! > Duration.zero) {
            task.progress = timeInMs / task.totalDuration!.inMilliseconds;
          }
        }
        task.speed = '${(statistics.getSpeed()).toStringAsFixed(1)}x';
      });

      // 执行转码
      final session = await FFmpegKit.execute(command);
      task.ffmpegSession = session;

      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        task.isRunning = false;
        task.isCompleted = true;
        logger.i('ClientTranscoding: 转码完成 ${task.outputPath}');
      } else if (ReturnCode.isCancel(returnCode)) {
        task.isRunning = false;
        task.error = '转码已取消';
        logger.i('ClientTranscoding: 转码已取消');
      } else {
        task.isRunning = false;
        final logs = await session.getAllLogsAsString();
        task.error = '转码失败: $logs';
        logger.e('ClientTranscoding: 转码失败 $returnCode');
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'mobileTranscoding');
    }
  }

  /// 桌面端转码（使用 Process）
  ///
  /// [waitForComplete] 如果为 true，等待转码完成；否则等待输出文件有数据就返回
  Future<void> _runDesktopTranscoding(
    _TranscodingTask task,
    List<String> args, {
    bool waitForComplete = false,
  }) async {
    if (_ffmpegPath == null) {
      task.isRunning = false;
      task.error = 'FFmpeg 不可用';
      return;
    }

    try {
      // 执行 FFmpeg（使用已检测到的路径）
      final process = await Process.start(_ffmpegPath!, args);
      task.process = process;

      // 收集 stderr 输出用于错误诊断
      final stderrBuffer = StringBuffer();
      var hasStartedOutput = false;

      // 解析进度输出
      process.stderr.transform(const SystemEncoding().decoder).listen((line) {
        stderrBuffer.write(line);
        _parseProgress(task, line);

        // 检查是否开始输出视频数据
        if (line.contains('frame=') && !hasStartedOutput) {
          hasStartedOutput = true;
          logger.d('ClientTranscoding: 开始输出视频帧');
        }
      });

      if (waitForComplete) {
        // 等待完整转码完成
        final exitCode = await process.exitCode;
        _handleExitCode(task, exitCode, stderrBuffer);
      } else {
        // 流式转码：等待输出文件有足够数据就返回
        final outputFile = File(task.outputPath);
        const minFileSize = 512 * 1024; // 至少 512KB
        const maxWaitTime = Duration(seconds: 30);
        const checkInterval = Duration(milliseconds: 500);

        final startTime = DateTime.now();
        var fileReady = false;

        while (DateTime.now().difference(startTime) < maxWaitTime) {
          await Future<void>.delayed(checkInterval);

          // 检查进程是否已退出（表示转码失败）
          final exitCode = await process.exitCode.timeout(
            Duration.zero,
            onTimeout: () => -1, // 仍在运行
          );

          if (exitCode != -1) {
            // 进程已退出
            _handleExitCode(task, exitCode, stderrBuffer);
            return;
          }

          // 检查输出文件大小
          if (await outputFile.exists()) {
            final size = await outputFile.length();
            if (size >= minFileSize) {
              logger.i('ClientTranscoding: 流式输出就绪，文件大小: ${size ~/ 1024}KB');
              fileReady = true;
              break;
            }
          }
        }

        if (fileReady) {
          // 文件已有足够数据，可以开始播放
          // 注意：转码仍在后台继续
          task.isCompleted = true; // 标记为"可播放"状态
          logger.i('ClientTranscoding: 流式转码已就绪 ${task.outputPath}');

          // 后台监控转码进程
          unawaited(process.exitCode.then((exitCode) {
            if (exitCode == 0) {
              logger.i('ClientTranscoding: 后台转码完成 ${task.outputPath}');
            } else {
              logger.w('ClientTranscoding: 后台转码异常退出 $exitCode');
            }
            task.isRunning = false;
          }));
        } else {
          // 等待超时，检查当前状态
          task.isRunning = false;
          task.error = '等待转码输出超时';
          logger.e('ClientTranscoding: 等待转码输出超时');
          logger.e('ClientTranscoding: FFmpeg 输出:\n${stderrBuffer.toString().length > 1000 ? stderrBuffer.toString().substring(stderrBuffer.toString().length - 1000) : stderrBuffer.toString()}');
          process.kill();
        }
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'desktopTranscoding');
    }
  }

  /// 处理 FFmpeg 退出码
  void _handleExitCode(_TranscodingTask task, int exitCode, StringBuffer stderrBuffer) {
    if (exitCode == 0) {
      task.isRunning = false;
      task.isCompleted = true;
      logger.i('ClientTranscoding: 转码完成 ${task.outputPath}');
    } else {
      task.isRunning = false;
      // 获取最后 500 字符的错误输出
      final stderrOutput = stderrBuffer.toString();
      final errorSnippet = stderrOutput.length > 500
          ? stderrOutput.substring(stderrOutput.length - 500)
          : stderrOutput;
      task.error = '转码失败，退出码: $exitCode';
      logger.e('ClientTranscoding: 转码失败 $exitCode');
      logger.e('ClientTranscoding: FFmpeg 错误输出:\n$errorSnippet');
    }
  }

  /// 构建 FFmpeg 参数
  List<String> _buildFfmpegArgs(_TranscodingTask task) {
    final args = <String>[
      '-y', // 覆盖输出文件
      '-i', task.inputPath, // 输入文件
    ];

    // 起始位置
    if (task.startPosition != null && task.startPosition! > Duration.zero) {
      args.addAll(['-ss', '${task.startPosition!.inSeconds}']);
    }

    // 视频编码参数
    args.addAll(['-c:v', 'libx264']); // H.264 编码
    args.addAll(['-preset', 'fast']); // 编码速度

    // 分辨率缩放
    if (!task.quality.isOriginal && task.quality.maxWidth != null && task.quality.maxHeight != null) {
      args.addAll([
        '-vf',
        'scale=${task.quality.maxWidth}:${task.quality.maxHeight}:force_original_aspect_ratio=decrease',
      ]);
    }

    // 码率
    if (task.quality.estimatedBitrate != null) {
      args.addAll(['-b:v', '${task.quality.estimatedBitrate}']);
    }

    // 音频编码
    args.addAll(['-c:a', 'aac']); // AAC 编码
    args.addAll(['-b:a', '128k']); // 128kbps 音频

    // 选择音轨
    if (task.audioStreamIndex != null) {
      args.addAll(['-map', '0:v:0', '-map', '0:a:${task.audioStreamIndex}']);
    }

    // 字幕烧录
    if (task.subtitleStreamIndex != null && task.subtitleStreamIndex! >= 0) {
      // 需要处理字幕烧录，这里简化处理
      args.addAll(['-sn']); // 暂时不处理字幕
    } else {
      args.addAll(['-sn']); // 不包含字幕
    }

    // 输出格式 - 使用 fragmented MP4 支持流式播放（边转边播）
    args.addAll(['-f', 'mp4']);
    args.addAll(['-movflags', 'frag_keyframe+empty_moov+default_base_moof']);

    // 输出文件
    args.add(task.outputPath);

    return args;
  }

  /// 解析 FFmpeg 进度输出
  void _parseProgress(_TranscodingTask task, String line) {
    // 解析时间戳: time=00:01:23.45
    final timeMatch = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(line);
    if (timeMatch != null) {
      final hours = int.parse(timeMatch.group(1)!);
      final minutes = int.parse(timeMatch.group(2)!);
      final seconds = double.parse(timeMatch.group(3)!);

      final currentSeconds = hours * 3600 + minutes * 60 + seconds;
      // 这里需要知道总时长才能计算进度
      // 暂时只更新当前时间
      task.currentTime = Duration(milliseconds: (currentSeconds * 1000).round());
    }

    // 解析速度: speed=1.5x
    final speedMatch = RegExp(r'speed=\s*(\d+\.?\d*)x').firstMatch(line);
    if (speedMatch != null) {
      task.speed = '${speedMatch.group(1)}x';
    }
  }

  /// 清理临时文件
  Future<void> _cleanupTempFiles() async {
    if (_tempDir == null) return;

    try {
      final files = _tempDir!.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('transcoded_')) {
          await file.delete();
        }
      }
    } catch (e, st) {
      AppError.ignore(e, st, '清理临时文件失败');
    }
  }

  /// 取消指定的转码任务
  Future<void> cancelTask(String taskId) async {
    final task = _tasks.remove(taskId);
    if (task != null) {
      task.cancel();

      // 删除输出文件
      final outputFile = File(task.outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
    }
  }
}

/// 转码任务内部类
class _TranscodingTask {
  _TranscodingTask({
    required this.taskId,
    required this.inputPath,
    required this.outputPath,
    required this.quality,
    this.startPosition,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final String taskId;
  final String inputPath;
  final String outputPath;
  final VideoQuality quality;
  final Duration? startPosition;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  /// 桌面端 Process
  Process? process;

  /// 移动端 FFmpegSession
  FFmpegSession? ffmpegSession;

  bool isRunning = false;
  bool isCompleted = false;
  String? error;

  double progress = 0.0;
  String? speed;
  Duration? eta;
  Duration? currentTime;
  Duration? totalDuration;

  void cancel() {
    isRunning = false;

    // 取消桌面端 Process
    process?.kill();
    process = null;

    // 取消移动端 FFmpegSession
    if (ffmpegSession != null) {
      FFmpegKit.cancel(ffmpegSession!.getSessionId());
      ffmpegSession = null;
    }
  }
}
