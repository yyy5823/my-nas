/// 统一错误处理模块
///
/// 导出所有错误相关的类和工具。
///
/// ## 使用方式
///
/// ```dart
/// import 'package:my_nas/core/errors/errors.dart';
///
/// // 使用 AppError 处理错误
/// try {
///   await someOperation();
/// } catch (e, st) {
///   AppError.handle(e, st, action: 'myAction');
/// }
/// ```
library;

export 'app_error_handler.dart';
export 'exceptions.dart';
export 'failures.dart';
