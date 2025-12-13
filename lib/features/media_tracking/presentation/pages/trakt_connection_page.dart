import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/services/deep_link_service.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/service_adapters/trakt/trakt_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Trakt 连接页面
///
/// 显示 Trakt 连接状态：
/// - 未连接：显示连接按钮 → 打开系统浏览器进行 OAuth
/// - 已连接：显示用户头像、名称、同步统计、注销按钮
class TraktConnectionPage extends ConsumerStatefulWidget {
  const TraktConnectionPage({super.key});

  @override
  ConsumerState<TraktConnectionPage> createState() => _TraktConnectionPageState();
}

class _TraktConnectionPageState extends ConsumerState<TraktConnectionPage> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _showAdvancedOptions = false;
  bool _showAuthCodeInput = false;
  bool _obscureSecret = true;
  bool _useCustomCredentials = false;

  StreamSubscription<AsyncValue<TraktOAuthCallback>>? _oauthCallbackSubscription;

  @override
  void initState() {
    super.initState();
    // 如果没有内置凭证，默认展开高级选项
    if (!TraktOAuthConfig.hasBuiltInCredentials) {
      _showAdvancedOptions = true;
      _useCustomCredentials = true;
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _codeController.dispose();
    _oauthCallbackSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final traktState = ref.watch(traktConnectionProvider);

    // 监听 OAuth 回调
    ref.listen<AsyncValue<TraktOAuthCallback>>(
      traktOAuthCallbackProvider,
      (previous, next) {
        next.whenData((callback) {
          // 收到回调，处理授权码
          ref.read(traktConnectionProvider.notifier).handleOAuthCallback(callback.code);
        });
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trakt'),
        centerTitle: true,
        actions: [
          if (traktState.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.read(traktConnectionProvider.notifier).refreshStats();
              },
            ),
        ],
      ),
      body: traktState.isConnected
          ? _buildConnectedView(context, traktState)
          : _buildDisconnectedView(context, traktState),
    );
  }

  /// 已连接状态视图
  Widget _buildConnectedView(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userSettings = state.userSettings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 用户信息卡片
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 头像
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: userSettings?.avatarUrl != null
                        ? NetworkImage(userSettings!.avatarUrl!)
                        : null,
                    child: userSettings?.avatarUrl == null
                        ? Icon(
                            Icons.person,
                            size: 40,
                            color: colorScheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // 用户名
                  Text(
                    userSettings?.username ?? '未知用户',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (userSettings?.name != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      userSettings!.name!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),

                  // 连接状态
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Text(
                          '已连接',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 同步统计
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '同步统计',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          context,
                          Icons.movie_outlined,
                          '电影',
                          '${state.stats?.moviesWatched ?? 0}',
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          Icons.tv_outlined,
                          '剧集',
                          '${state.stats?.episodesWatched ?? 0}',
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          Icons.subscriptions_outlined,
                          '节目',
                          '${state.stats?.showsWatched ?? 0}',
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          context,
                          Icons.bookmark_border,
                          '待看',
                          '${state.stats?.watchlistCount ?? 0}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 注销按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showLogoutConfirmation,
              icon: const Icon(Icons.logout),
              label: const Text('注销'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showLogoutConfirmation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销 Trakt'),
        content: const Text('确定要注销吗？这将清除所有保存的认证信息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(traktConnectionProvider.notifier).logout();
            },
            child: const Text('注销'),
          ),
        ],
      ),
    );
  }

  /// 未连接状态视图
  Widget _buildDisconnectedView(BuildContext context, TraktConnectionState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notifier = ref.read(traktConnectionProvider.notifier);
    final hasBuiltIn = TraktOAuthConfig.hasBuiltInCredentials;
    final supportsDeepLink = notifier.supportsDeepLinkCallback;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Trakt Logo 和说明
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.track_changes,
                        size: 40,
                        color: Color(0xFFED1C24),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '连接 Trakt',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '追踪您的观看记录、同步媒体状态',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 主要登录按钮（如果有内置凭证）
            if (hasBuiltIn && !_useCustomCredentials && !_showAuthCodeInput) ...[
              FilledButton.icon(
                onPressed: state.status == TraktConnectionStatus.connecting
                    ? null
                    : _startBuiltInOAuthFlow,
                icon: state.status == TraktConnectionStatus.connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('使用 Trakt 账号登录'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              if (!supportsDeepLink) ...[
                const SizedBox(height: 8),
                Text(
                  '登录后需要手动输入授权码',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 高级选项开关
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showAdvancedOptions = !_showAdvancedOptions;
                  });
                },
                icon: Icon(
                  _showAdvancedOptions
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                label: Text(_showAdvancedOptions ? '隐藏高级选项' : '使用自定义凭证'),
              ),
            ],

            // 高级选项（自定义凭证）
            if (_showAdvancedOptions || !hasBuiltIn) ...[
              if (hasBuiltIn) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('使用自定义 API 凭证'),
                  subtitle: const Text('如果您有自己的 Trakt 应用'),
                  value: _useCustomCredentials,
                  onChanged: (value) {
                    setState(() {
                      _useCustomCredentials = value;
                      _showAuthCodeInput = false;
                    });
                  },
                ),
              ],

              if (_useCustomCredentials || !hasBuiltIn) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _clientIdController,
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    helperText: '从 trakt.tv/oauth/applications 获取',
                    prefixIcon: const Icon(Icons.apps),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (_useCustomCredentials || !hasBuiltIn) {
                      if (value == null || value.isEmpty) {
                        return '请输入 Client ID';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _clientSecretController,
                  obscureText: _obscureSecret,
                  decoration: InputDecoration(
                    labelText: 'Client Secret',
                    prefixIcon: const Icon(Icons.vpn_key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureSecret ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureSecret = !_obscureSecret;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (_useCustomCredentials || !hasBuiltIn) {
                      if (value == null || value.isEmpty) {
                        return '请输入 Client Secret';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
              ],
            ],

            // 授权码输入（OOB 模式或非移动端）
            if (_showAuthCodeInput) ...[
              const Divider(),
              const SizedBox(height: 16),
              Text(
                '请在浏览器中完成登录，然后输入授权码',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: '授权码',
                  helperText: '从 Trakt 网页复制授权码',
                  prefixIcon: const Icon(Icons.code),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (_showAuthCodeInput && (value == null || value.isEmpty)) {
                    return '请输入授权码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _showAuthCodeInput = false;
                        });
                      },
                      child: const Text('返回'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: state.status == TraktConnectionStatus.connecting
                          ? null
                          : _submitAuthCode,
                      child: state.status == TraktConnectionStatus.connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('完成认证'),
                    ),
                  ),
                ],
              ),
            ],

            // 自定义凭证的登录按钮
            if ((_useCustomCredentials || !hasBuiltIn) && !_showAuthCodeInput) ...[
              FilledButton.icon(
                onPressed: state.status == TraktConnectionStatus.connecting
                    ? null
                    : _startCustomOAuthFlow,
                icon: state.status == TraktConnectionStatus.connecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_browser),
                label: const Text('在浏览器中登录'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],

            // 错误信息
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 使用内置凭证启动 OAuth 流程
  Future<void> _startBuiltInOAuthFlow() async {
    final notifier = ref.read(traktConnectionProvider.notifier);

    try {
      final url = await notifier.startOAuthFlow(useBuiltIn: true);
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // 如果不支持深度链接回调，显示授权码输入框
        if (!notifier.supportsDeepLinkCallback) {
          setState(() {
            _showAuthCodeInput = true;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器')),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动登录失败: $e')),
        );
      }
    }
  }

  /// 使用自定义凭证启动 OAuth 流程
  Future<void> _startCustomOAuthFlow() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(traktConnectionProvider.notifier);
    final clientId = _clientIdController.text.trim();
    final clientSecret = _clientSecretController.text.trim();

    try {
      final url = await notifier.startOAuthFlow(
        useBuiltIn: false,
        clientId: clientId,
        clientSecret: clientSecret,
      );
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // 如果不支持深度链接回调，显示授权码输入框
        if (!notifier.supportsDeepLinkCallback) {
          setState(() {
            _showAuthCodeInput = true;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开浏览器')),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动登录失败: $e')),
        );
      }
    }
  }

  /// 提交授权码（OOB 模式）
  Future<void> _submitAuthCode() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim();

    // 使用 handleOAuthCallback 处理，它会从存储中读取待处理的 OAuth 状态
    await ref.read(traktConnectionProvider.notifier).handleOAuthCallback(code);
  }
}
