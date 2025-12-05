import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/services/update_service.dart';

/// 更新服务 Provider
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// 更新状态 Provider
final updateStatusProvider = StreamProvider<UpdateStatus>((ref) async* {
  final service = ref.watch(updateServiceProvider);

  // 初始状态
  yield service.status;

  // 监听变化
  service.addListener(() {
    ref.state = AsyncData(service.status);
  });
});

/// 更新信息 Provider
final updateInfoProvider = Provider<UpdateInfo?>((ref) {
  final service = ref.watch(updateServiceProvider);
  return service.updateInfo;
});

/// 下载进度 Provider
final downloadProgressProvider = Provider<double>((ref) {
  final service = ref.watch(updateServiceProvider);
  return service.downloadProgress;
});

/// 是否有更新 Provider
final hasUpdateProvider = Provider<bool>((ref) {
  final service = ref.watch(updateServiceProvider);
  return service.hasUpdate;
});
