import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';

class ConnectionPage extends ConsumerStatefulWidget {
  const ConnectionPage({super.key});

  @override
  ConsumerState<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends ConsumerState<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '5000');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscurePassword = true;
  bool _useSsl = true;
  NasAdapterType _selectedType = NasAdapterType.synology;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(connectionStateProvider.notifier).connect(
          type: _selectedType,
          host: _hostController.text.trim(),
          port: int.parse(_portController.text.trim()),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          useSsl: _useSsl,
          verifySSL: false, // 允许自签名证书
        );
  }

  Future<void> _handleVerify2FA() async {
    if (_otpController.text.isEmpty) return;
    await ref
        .read(connectionStateProvider.notifier)
        .verify2FA(_otpController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);

    // 监听连接状态变化
    ref.listen<NasConnectionState>(connectionStateProvider, (previous, next) {
      if (next is ConnectionConnected) {
        context.go(Routes.files);
      } else if (next is ConnectionError) {
        context.showErrorSnackBar(next.message);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: AppSpacing.screenPadding,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: AppSpacing.xxxxl),
                    if (connectionState is ConnectionRequires2FAState)
                      _build2FAForm(connectionState)
                    else
                      _buildLoginForm(connectionState),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Column(
        children: [
          Icon(
            Icons.storage,
            size: 80,
            color: context.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'MyNAS',
            style: context.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: context.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '连接您的 NAS 设备',
            style: context.textTheme.bodyLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  Widget _buildLoginForm(NasConnectionState state) {
    final isLoading = state is ConnectionLoading;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // NAS Type Selector
          _buildNasTypeSelector(),
          const SizedBox(height: AppSpacing.xxl),

          // Host
          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: '主机地址',
              hintText: '192.168.1.100 或 nas.example.com',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入主机地址';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Port
          TextFormField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: '端口',
              hintText: '5000',
              prefixIcon: Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入端口';
              }
              final port = int.tryParse(value);
              if (port == null || port < 1 || port > 65535) {
                return '请输入有效端口 (1-65535)';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Username
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            enabled: !isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入用户名';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Password
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            enabled: !isLoading,
            onFieldSubmitted: (_) => _handleConnect(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // SSL Switch
          SwitchListTile(
            title: const Text('使用 HTTPS'),
            subtitle: Text(
              _useSsl ? '安全连接' : '不安全连接',
              style: context.textTheme.bodySmall,
            ),
            value: _useSsl,
            onChanged: isLoading ? null : (v) => setState(() => _useSsl = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Connect Button
          FilledButton(
            onPressed: isLoading ? null : _handleConnect,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text((state as ConnectionLoading).message ?? '连接中...'),
                      ],
                    )
                  : const Text('连接'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build2FAForm(ConnectionRequires2FAState state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.security,
            size: 48,
            color: context.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '二次验证',
            style: context.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '请输入验证器应用中的验证码',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          TextFormField(
            controller: _otpController,
            decoration: const InputDecoration(
              labelText: '验证码',
              hintText: '6 位数字',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            onFieldSubmitted: (_) => _handleVerify2FA(),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: _handleVerify2FA,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('验证'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: () {
              ref.read(connectionStateProvider.notifier).disconnect();
              _otpController.clear();
            },
            child: const Text('返回'),
          ),
        ],
      );

  Widget _buildNasTypeSelector() => SegmentedButton<NasAdapterType>(
        segments: const [
          ButtonSegment(
            value: NasAdapterType.synology,
            label: Text('群晖'),
            icon: Icon(Icons.storage),
          ),
          ButtonSegment(
            value: NasAdapterType.ugreen,
            label: Text('绿联'),
            icon: Icon(Icons.storage),
          ),
          ButtonSegment(
            value: NasAdapterType.webdav,
            label: Text('WebDAV'),
            icon: Icon(Icons.cloud_outlined),
          ),
        ],
        selected: {_selectedType},
        onSelectionChanged: (selected) {
          setState(() {
            _selectedType = selected.first;
            // 根据类型设置默认端口
            _portController.text = switch (_selectedType) {
              NasAdapterType.synology => '5000',
              NasAdapterType.webdav => '5005',
              _ => '5000',
            };
          });
        },
      );
}
