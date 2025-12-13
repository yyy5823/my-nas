import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 发现的设备信息
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.type,
    this.serviceType,
    this.txtRecords,
  });

  final String name;
  final String host;
  final int port;
  final SourceType type;
  final String? serviceType;
  final Map<String, String>? txtRecords;

  @override
  String toString() => 'DiscoveredDevice($name, $host:$port, $type)';
}

/// 网络发现状态
class NetworkDiscoveryState {
  const NetworkDiscoveryState({
    this.devices = const [],
    this.isDiscovering = false,
    this.lastDiscoveryTime,
  });

  final List<DiscoveredDevice> devices;
  final bool isDiscovering;
  final DateTime? lastDiscoveryTime;

  NetworkDiscoveryState copyWith({
    List<DiscoveredDevice>? devices,
    bool? isDiscovering,
    DateTime? lastDiscoveryTime,
  }) =>
      NetworkDiscoveryState(
        devices: devices ?? this.devices,
        isDiscovering: isDiscovering ?? this.isDiscovering,
        lastDiscoveryTime: lastDiscoveryTime ?? this.lastDiscoveryTime,
      );
}

/// 网络发现服务 Provider
final networkDiscoveryProvider =
    StateNotifierProvider<NetworkDiscoveryNotifier, NetworkDiscoveryState>(
  (ref) => NetworkDiscoveryNotifier(),
);

class NetworkDiscoveryNotifier extends StateNotifier<NetworkDiscoveryState> {
  NetworkDiscoveryNotifier() : super(const NetworkDiscoveryState());

  /// mDNS 服务类型映射
  static const _serviceTypes = {
    '_smb._tcp': SourceType.smb,
    '_webdav._tcp': SourceType.webdav,
    '_webdavs._tcp': SourceType.webdav,
    '_ftp._tcp': SourceType.ftp,
    '_sftp-ssh._tcp': SourceType.sftp,
    '_nfs._tcp': SourceType.nfs,
    '_http._tcp': null, // 通用 HTTP，需要进一步判断
    '_https._tcp': null,
    // NAS 设备专用服务
    '_diskstation._tcp': SourceType.synology,
    '_synology._tcp': SourceType.synology,
    '_qnap._tcp': SourceType.qnap,
  };

  MDnsClient? _mdnsClient;
  Timer? _discoveryTimer;

  /// 开始发现
  Future<void> startDiscovery() async {
    if (state.isDiscovering) return;

    state = state.copyWith(isDiscovering: true, devices: []);
    logger.i('NetworkDiscovery: 开始发现局域网设备');

    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      final devices = <DiscoveredDevice>[];

      // 遍历所有服务类型进行发现
      for (final entry in _serviceTypes.entries) {
        final serviceType = entry.key;
        final sourceType = entry.value;

        try {
          await for (final ptr in _mdnsClient!.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          ).timeout(const Duration(seconds: 3))) {
            // 获取服务详情
            await for (final srv in _mdnsClient!.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            ).timeout(const Duration(seconds: 2))) {
              // 获取 IP 地址
              await for (final ip in _mdnsClient!.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              ).timeout(const Duration(seconds: 2))) {
                final name = _extractServiceName(ptr.domainName, serviceType);
                final host = ip.address.address;
                final port = srv.port;

                // 确定源类型
                final type = sourceType ?? _guessSourceType(name, port);
                if (type != null) {
                  final device = DiscoveredDevice(
                    name: name,
                    host: host,
                    port: port,
                    type: type,
                    serviceType: serviceType,
                  );

                  // 避免重复
                  if (!devices.any((d) => d.host == host && d.port == port)) {
                    devices.add(device);
                    logger.d('NetworkDiscovery: 发现设备 $device');
                  }
                }
              }
            }
          }
        } on TimeoutException {
          // 超时继续下一个服务类型
        } on Exception catch (e) {
          logger.w('NetworkDiscovery: 发现 $serviceType 失败', e);
        }
      }

      state = state.copyWith(
        devices: devices,
        isDiscovering: false,
        lastDiscoveryTime: DateTime.now(),
      );
      logger.i('NetworkDiscovery: 发现完成，共 ${devices.length} 个设备');
    } on Exception catch (e, st) {
      logger.e('NetworkDiscovery: 发现失败', e, st);
      state = state.copyWith(isDiscovering: false);
    } finally {
      _mdnsClient?.stop();
      _mdnsClient = null;
    }
  }

  /// 停止发现
  void stopDiscovery() {
    _discoveryTimer?.cancel();
    _mdnsClient?.stop();
    _mdnsClient = null;
    state = state.copyWith(isDiscovering: false);
  }

  /// 从域名中提取服务名称
  String _extractServiceName(String domainName, String serviceType) {
    // 域名格式: <name>.<serviceType>.local
    final suffix = '$serviceType.local';
    if (domainName.endsWith(suffix)) {
      return domainName.substring(0, domainName.length - suffix.length - 1);
    }
    return domainName;
  }

  /// 根据名称和端口猜测源类型
  SourceType? _guessSourceType(String name, int port) {
    final nameLower = name.toLowerCase();

    // 根据名称关键词判断
    if (nameLower.contains('synology') || nameLower.contains('diskstation')) {
      return SourceType.synology;
    }
    if (nameLower.contains('qnap')) {
      return SourceType.qnap;
    }

    // 根据端口判断
    return switch (port) {
      5001 || 5000 => SourceType.synology,
      8080 => SourceType.qnap,
      445 => SourceType.smb,
      443 || 80 => SourceType.webdav,
      21 => SourceType.ftp,
      22 => SourceType.sftp,
      2049 => SourceType.nfs,
      _ => null,
    };
  }

  @override
  void dispose() {
    stopDiscovery();
    super.dispose();
  }
}
