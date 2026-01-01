import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_api.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_models.dart';
import 'package:url_launcher/url_launcher.dart';

/// Plex PIN 认证状态
enum PlexAuthStatus {
  /// 初始状态
  initial,

  /// 获取 PIN 中
  gettingPin,

  /// 等待用户授权
  waitingForAuth,

  /// 轮询中
  polling,

  /// 已授权
  authorized,

  /// 已过期
  expired,

  /// 错误
  error,
}

/// Plex PIN 认证结果
class PlexAuthResult {
  const PlexAuthResult({
    required this.success,
    this.authToken,
    this.errorMessage,
  });

  final bool success;
  final String? authToken;
  final String? errorMessage;
}

/// Plex PIN 认证 Widget
///
/// 用于 Plex 服务器的 PIN 码登录流程
/// 用户需要在 plex.tv 上输入 PIN 码或扫描二维码完成授权
class PlexAuthWidget extends StatefulWidget {
  const PlexAuthWidget({
    required this.onResult,
    super.key,
  });

  /// 认证结果回调
  final void Function(PlexAuthResult result) onResult;

  @override
  State<PlexAuthWidget> createState() => _PlexAuthWidgetState();
}

class _PlexAuthWidgetState extends State<PlexAuthWidget> {
  PlexAuthStatus _status = PlexAuthStatus.initial;
  PlexPinInfo? _pinInfo;
  String? _authUrl;
  String? _errorMessage;
  Timer? _pollingTimer;
  int _remainingSeconds = 300; // 5 分钟超时
  PlexApi? _api;

  @override
  void initState() {
    super.initState();
    _initiatePinAuth();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _api?.dispose();
    super.dispose();
  }

  /// 发起 PIN 认证
  Future<void> _initiatePinAuth() async {
    setState(() {
      _status = PlexAuthStatus.gettingPin;
    });

    try {
      _api = PlexApi(
        serverUrl: 'https://plex.tv', // 初始使用 plex.tv
        authToken: '',
        clientIdentifier: 'mynas-${DateTime.now().millisecondsSinceEpoch}',
        clientName: 'MyNas App',
      );

      final pin = await _api!.initiatePin();

      if (!mounted) return;

      setState(() {
        _status = PlexAuthStatus.waitingForAuth;
        _pinInfo = pin;
        _authUrl = pin.getAuthUrl(
          clientId: _api!.clientIdentifier ?? 'mynas-client',
          clientName: 'MyNas App',
        );
        _remainingSeconds = 300;
      });

      // 开始轮询
      _startPolling();
    } on Exception catch (e) {
      logger.e('PlexAuth: 获取 PIN 失败', e);
      if (mounted) {
        setState(() {
          _status = PlexAuthStatus.error;
          _errorMessage = '无法获取 PIN 码';
        });
      }
    }
  }

  /// 开始轮询检查授权状态
  void _startPolling() {
    setState(() {
      _status = PlexAuthStatus.polling;
    });

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_pinInfo == null) {
        timer.cancel();
        return;
      }

      // 更新剩余时间
      _remainingSeconds -= 2;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _status = PlexAuthStatus.expired;
            _errorMessage = 'PIN 码已过期';
          });
        }
        return;
      }

      try {
        final result = await _api!.checkPin(_pinInfo!.id);

        if (!mounted) return;

        if (result.isAuthorized) {
          timer.cancel();

          setState(() {
            _status = PlexAuthStatus.authorized;
          });

          widget.onResult(PlexAuthResult(
            success: true,
            authToken: result.authToken,
          ));
        } else {
          // 继续轮询，更新 UI
          if (mounted) {
            setState(() {});
          }
        }
      } on Exception catch (e) {
        logger.w('PlexAuth: 轮询失败', e);
        // 轮询失败不立即停止，继续尝试
      }
    });
  }

  /// 打开授权链接
  Future<void> _openAuthUrl() async {
    if (_authUrl == null) return;

    final uri = Uri.parse(_authUrl!);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器')),
          );
        }
      }
    } on Exception catch (e) {
      logger.e('PlexAuth: 打开链接失败', e);
    }
  }

  /// 复制 PIN 码到剪贴板
  Future<void> _copyPin() async {
    if (_pinInfo?.code == null) return;

    await Clipboard.setData(ClipboardData(text: _pinInfo!.code));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN 码已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 重新开始
  Future<void> _restart() async {
    _pollingTimer?.cancel();
    setState(() {
      _status = PlexAuthStatus.initial;
      _pinInfo = null;
      _authUrl = null;
      _errorMessage = null;
      _remainingSeconds = 300;
    });
    await _initiatePinAuth();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Plex 账号登录',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildContent(theme),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    switch (_status) {
      case PlexAuthStatus.initial:
      case PlexAuthStatus.gettingPin:
        return _buildLoadingState(theme, '正在获取 PIN 码...');

      case PlexAuthStatus.waitingForAuth:
      case PlexAuthStatus.polling:
        return _buildPinState(theme);

      case PlexAuthStatus.authorized:
        return _buildSuccessState(theme);

      case PlexAuthStatus.expired:
        return _buildErrorState(theme, _errorMessage ?? '已过期', canRetry: true);

      case PlexAuthStatus.error:
        return _buildErrorState(
            theme, _errorMessage ?? '发生错误', canRetry: true);
    }
  }

  Widget _buildLoadingState(ThemeData theme, String message) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          message,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildPinState(ThemeData theme) {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '请在 plex.tv/link 上输入以下 PIN 码：',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        // PIN 码显示
        InkWell(
          onTap: _copyPin,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5A00D).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFE5A00D).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pinInfo?.code ?? '',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: const Color(0xFFE5A00D),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.copy,
                  size: 20,
                  color: const Color(0xFFE5A00D),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 打开链接按钮
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openAuthUrl,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('打开 plex.tv/link'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE5A00D),
              side: const BorderSide(color: Color(0xFFE5A00D)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 状态和倒计时
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              '等待授权...',
              style: theme.textTheme.bodySmall,
            ),
            const Spacer(),
            Icon(
              Icons.timer,
              size: 16,
              color: _remainingSeconds < 60
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              timeString,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _remainingSeconds < 60 ? theme.colorScheme.error : null,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 说明
        Text(
          '或者在手机上打开 Plex App → 设置 → 链接设备，输入上述 PIN 码',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle,
          color: Colors.green,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '认证成功！',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(
      ThemeData theme, String message, {required bool canRetry}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
        if (canRetry) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ],
    );
  }
}
