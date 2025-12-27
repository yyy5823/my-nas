import 'dart:async';

import 'package:flutter/foundation.dart';

/// 生成唯一 ID 的计数器
int _toastIdCounter = 0;

/// 生成唯一 ID
String _generateUniqueId() {
  _toastIdCounter++;
  return 'toast_${DateTime.now().millisecondsSinceEpoch}_$_toastIdCounter';
}

/// Toast 消息类型
enum ToastType {
  /// 成功消息 - 显示在底部（移动端）或右下角（桌面端）
  success,

  /// 信息消息 - 显示在底部（移动端）或右下角（桌面端）
  info,

  /// 警告消息 - 显示在顶部（移动端）或右下角（桌面端）
  warning,

  /// 错误消息 - 显示在顶部（移动端）或右下角（桌面端）
  error,
}

/// Toast 消息位置
enum ToastPosition {
  /// 顶部（移动端警告/错误）
  top,

  /// 底部（移动端成功/信息）
  bottom,

  /// 右下角堆叠（桌面端所有消息）
  bottomRight,
}

/// Toast 消息数据模型
class ToastMessage {
  ToastMessage({
    required this.message,
    required this.type,
    required this.duration,
    this.action,
    this.actionLabel,
    this.dismissible = true,
    String? id,
  }) : id = id ?? _generateUniqueId();

  /// 唯一标识符
  final String id;

  /// 消息内容
  final String message;

  /// 消息类型
  final ToastType type;

  /// 显示持续时间
  final Duration duration;

  /// 操作回调
  final VoidCallback? action;

  /// 操作按钮标签
  final String? actionLabel;

  /// 是否可手动关闭
  final bool dismissible;

  /// 创建时间（用于排序和超时计算）
  final DateTime createdAt = DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ToastMessage && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Toast 消息服务
///
/// 管理消息队列，根据消息类型和平台决定显示位置
class ToastService extends ChangeNotifier {
  /// 顶部消息列表（移动端警告/错误）
  final List<ToastMessage> _topMessages = [];

  /// 底部消息列表（移动端成功/信息）
  final List<ToastMessage> _bottomMessages = [];

  /// 右下角堆叠消息列表（桌面端）
  final List<ToastMessage> _stackMessages = [];

  /// 消息定时器映射
  final Map<String, Timer> _timers = {};

  /// 最大同时显示数量
  static const int maxTopMessages = 2;
  static const int maxBottomMessages = 2;
  static const int maxStackMessages = 5;

  /// 获取顶部消息列表
  List<ToastMessage> get topMessages => List.unmodifiable(_topMessages);

  /// 获取底部消息列表
  List<ToastMessage> get bottomMessages => List.unmodifiable(_bottomMessages);

  /// 获取右下角堆叠消息列表
  List<ToastMessage> get stackMessages => List.unmodifiable(_stackMessages);

  /// 根据消息类型获取默认持续时间
  Duration _getDefaultDuration(ToastType type) {
    switch (type) {
      case ToastType.success:
        return const Duration(seconds: 2);
      case ToastType.info:
        return const Duration(seconds: 3);
      case ToastType.warning:
        return const Duration(seconds: 4);
      case ToastType.error:
        return const Duration(seconds: 5);
    }
  }

  /// 根据消息类型和是否桌面端判断显示位置
  ToastPosition _getPosition(ToastType type, {required bool isDesktop}) {
    if (isDesktop) {
      return ToastPosition.bottomRight;
    }

    switch (type) {
      case ToastType.success:
      case ToastType.info:
        return ToastPosition.bottom;
      case ToastType.warning:
      case ToastType.error:
        return ToastPosition.top;
    }
  }

  /// 显示 Toast 消息
  ///
  /// [message] 消息内容
  /// [type] 消息类型，默认为 info
  /// [duration] 持续时间，不传则使用默认值
  /// [action] 操作回调
  /// [actionLabel] 操作按钮标签
  /// [dismissible] 是否可手动关闭，默认为 true
  /// [isDesktop] 是否桌面端，用于决定显示位置
  void show(
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
    bool dismissible = true,
    bool isDesktop = false,
  }) {
    final toast = ToastMessage(
      message: message,
      type: type,
      duration: duration ?? _getDefaultDuration(type),
      action: action,
      actionLabel: actionLabel,
      dismissible: dismissible,
    );

    final position = _getPosition(type, isDesktop: isDesktop);
    _addToQueue(toast, position);
  }

  /// 显示成功消息
  void success(
    String message, {
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
    bool isDesktop = false,
  }) {
    show(
      message,
      type: ToastType.success,
      duration: duration,
      action: action,
      actionLabel: actionLabel,
      isDesktop: isDesktop,
    );
  }

  /// 显示信息消息
  void info(
    String message, {
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
    bool isDesktop = false,
  }) {
    show(
      message,
      type: ToastType.info,
      duration: duration,
      action: action,
      actionLabel: actionLabel,
      isDesktop: isDesktop,
    );
  }

  /// 显示警告消息
  void warning(
    String message, {
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
    bool isDesktop = false,
  }) {
    show(
      message,
      type: ToastType.warning,
      duration: duration,
      action: action,
      actionLabel: actionLabel,
      isDesktop: isDesktop,
    );
  }

  /// 显示错误消息
  void error(
    String message, {
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
    bool isDesktop = false,
  }) {
    show(
      message,
      type: ToastType.error,
      duration: duration,
      action: action,
      actionLabel: actionLabel,
      isDesktop: isDesktop,
    );
  }

  /// 添加消息到对应队列
  void _addToQueue(ToastMessage toast, ToastPosition position) {
    switch (position) {
      case ToastPosition.top:
        _topMessages.add(toast);
        // 如果超过最大数量，移除最旧的
        while (_topMessages.length > maxTopMessages) {
          final removed = _topMessages.removeAt(0);
          _cancelTimer(removed.id);
        }
      case ToastPosition.bottom:
        _bottomMessages.add(toast);
        while (_bottomMessages.length > maxBottomMessages) {
          final removed = _bottomMessages.removeAt(0);
          _cancelTimer(removed.id);
        }
      case ToastPosition.bottomRight:
        _stackMessages.add(toast);
        while (_stackMessages.length > maxStackMessages) {
          final removed = _stackMessages.removeAt(0);
          _cancelTimer(removed.id);
        }
    }

    // 设置自动消失定时器
    _startTimer(toast, position);

    notifyListeners();
  }

  /// 启动消息定时器
  void _startTimer(ToastMessage toast, ToastPosition position) {
    _timers[toast.id] = Timer(toast.duration, () {
      _dismiss(toast.id, position);
    });
  }

  /// 取消消息定时器
  void _cancelTimer(String id) {
    _timers[id]?.cancel();
    _timers.remove(id);
  }

  /// 关闭指定消息
  void dismiss(String id) {
    // 尝试从所有队列中移除
    if (_topMessages.any((t) => t.id == id)) {
      _dismiss(id, ToastPosition.top);
    } else if (_bottomMessages.any((t) => t.id == id)) {
      _dismiss(id, ToastPosition.bottom);
    } else if (_stackMessages.any((t) => t.id == id)) {
      _dismiss(id, ToastPosition.bottomRight);
    }
  }

  /// 从指定位置移除消息
  void _dismiss(String id, ToastPosition position) {
    _cancelTimer(id);

    switch (position) {
      case ToastPosition.top:
        _topMessages.removeWhere((t) => t.id == id);
      case ToastPosition.bottom:
        _bottomMessages.removeWhere((t) => t.id == id);
      case ToastPosition.bottomRight:
        _stackMessages.removeWhere((t) => t.id == id);
    }

    notifyListeners();
  }

  /// 清除所有消息
  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _topMessages.clear();
    _bottomMessages.clear();
    _stackMessages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}
