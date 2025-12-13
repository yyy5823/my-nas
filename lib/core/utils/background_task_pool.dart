import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:my_nas/core/utils/logger.dart';

/// 后台任务池
///
/// 用于限制后台任务的并发数量，防止同时执行过多任务导致：
/// - CPU 占用过高（手机发热）
/// - 内存占用过高
/// - 网络请求过多被限流
///
/// 使用示例：
/// ```dart
/// final pool = BackgroundTaskPool.media; // 媒体处理任务池
/// await pool.add(() => downloadPoster(url));
/// ```
class BackgroundTaskPool {

  BackgroundTaskPool({
    required this.name,
    required this.maxConcurrency,
  });
  /// 媒体处理任务池（海报下载、缩略图生成等）
  ///
  /// 移动端限制 2 个并发，桌面端限制 4 个并发
  static final media = BackgroundTaskPool(
    name: 'media',
    maxConcurrency: _isMobile ? 2 : 4,
  );

  /// 网络请求任务池（API 调用等）
  ///
  /// 移动端限制 3 个并发，桌面端限制 6 个并发
  static final network = BackgroundTaskPool(
    name: 'network',
    maxConcurrency: _isMobile ? 3 : 6,
  );

  /// 刮削任务池
  ///
  /// 移动端限制 2 个并发，桌面端限制 4 个并发
  static final scrape = BackgroundTaskPool(
    name: 'scrape',
    maxConcurrency: _isMobile ? 2 : 4,
  );

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  final String name;
  final int maxConcurrency;

  final _queue = Queue<_QueuedTask<dynamic>>();
  int _running = 0;
  bool _disposed = false;

  /// 当前正在运行的任务数
  int get runningCount => _running;

  /// 队列中等待的任务数
  int get queuedCount => _queue.length;

  /// 是否已满（达到最大并发）
  bool get isFull => _running >= maxConcurrency;

  /// 添加任务到池中
  ///
  /// 如果当前运行的任务数小于 maxConcurrency，立即执行
  /// 否则加入队列等待
  ///
  /// 返回任务完成的 Future
  Future<T> add<T>(Future<T> Function() task, {String? taskName}) async {
    if (_disposed) {
      throw StateError('BackgroundTaskPool "$name" has been disposed');
    }

    final completer = Completer<T>();
    final queuedTask = _QueuedTask<T>(
      task: task,
      completer: completer,
      name: taskName,
    );

    if (_running < maxConcurrency) {
      // ignore: unawaited_futures - 故意不等待，由 completer 处理结果
      _executeTask(queuedTask);
    } else {
      _queue.add(queuedTask);
      // logger.d(
      //   'BackgroundTaskPool[$name]: 任务入队 '
      //   '(running: $_running, queued: ${_queue.length})',
      // );
    }

    return completer.future;
  }

  /// 添加任务但不等待结果（fire and forget）
  ///
  /// 任务仍然受并发限制，但调用者不需要等待完成
  void addFireAndForget(Future<void> Function() task, {String? taskName}) {
    add(task, taskName: taskName).catchError((Object e) {
      // 错误已在 _executeTask 中处理，这里只是防止 unhandled exception
    });
  }

  Future<void> _executeTask<T>(_QueuedTask<T> queuedTask) async {
    _running++;

    try {
      final result = await queuedTask.task();
      queuedTask.completer.complete(result);
    } catch (e, st) {
      queuedTask.completer.completeError(e, st);
      logger.w(
        'BackgroundTaskPool[$name]: 任务失败 ${queuedTask.name ?? ""}',
        e,
      );
    } finally {
      _running--;
      _processQueue();
    }
  }

  void _processQueue() {
    if (_disposed) return;

    while (_running < maxConcurrency && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _executeTask(task);
    }
  }

  /// 等待所有当前任务完成
  ///
  /// 注意：这不会阻止新任务的添加
  Future<void> drain() async {
    while (_running > 0 || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 清空队列中等待的任务
  ///
  /// 正在运行的任务不受影响
  void clearQueue() {
    for (final task in _queue) {
      task.completer.completeError(
        StateError('Task cancelled: queue cleared'),
      );
    }
    _queue.clear();
    logger.i('BackgroundTaskPool[$name]: 队列已清空');
  }

  /// 释放资源
  void dispose() {
    _disposed = true;
    clearQueue();
  }

  /// 获取状态信息（用于调试）
  Map<String, dynamic> get status => {
        'name': name,
        'maxConcurrency': maxConcurrency,
        'running': _running,
        'queued': _queue.length,
        'disposed': _disposed,
      };
}

class _QueuedTask<T> {
  _QueuedTask({
    required this.task,
    required this.completer,
    this.name,
  });

  final Future<T> Function() task;
  final Completer<T> completer;
  final String? name;
}
