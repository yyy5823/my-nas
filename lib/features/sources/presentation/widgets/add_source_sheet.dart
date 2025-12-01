import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

class AddSourceSheet extends ConsumerStatefulWidget {
  const AddSourceSheet({
    this.source,
    super.key,
  });

  final SourceEntity? source;

  @override
  ConsumerState<AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends ConsumerState<AddSourceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  late SourceType _sourceType;
  late bool _useSsl;
  late bool _autoConnect;
  late bool _rememberDevice;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  bool get _isEditing => widget.source != null;

  @override
  void initState() {
    super.initState();
    final source = widget.source;

    _nameController = TextEditingController(text: source?.name ?? '');
    _hostController = TextEditingController(text: source?.host ?? '');
    _portController = TextEditingController(
      text: source?.port.toString() ?? '5001',
    );
    _usernameController = TextEditingController(text: source?.username ?? '');
    _passwordController = TextEditingController();

    _sourceType = source?.type ?? SourceType.synology;
    _useSsl = source?.useSsl ?? true;
    _autoConnect = source?.autoConnect ?? true;
    _rememberDevice = source?.rememberDevice ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 拖动条
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    _isEditing ? '编辑源' : '添加源',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 表单
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 源类型选择
                      Text(
                        '源类型',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _buildSourceTypeSelector(),
                      const SizedBox(height: 24),

                      // 名称
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '名称（可选）',
                          hintText: '给这个源起个名字',
                          prefixIcon: Icon(Icons.label_outline),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 主机地址
                      TextFormField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: '主机地址',
                          hintText: '192.168.1.100 或 nas.example.com',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入主机地址';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 端口和 SSL
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _portController,
                              decoration: const InputDecoration(
                                labelText: '端口',
                                prefixIcon: Icon(Icons.numbers),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '请输入端口';
                                }
                                final port = int.tryParse(value);
                                if (port == null || port < 1 || port > 65535) {
                                  return '无效端口';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            children: [
                              const Text('SSL'),
                              Switch(
                                value: _useSsl,
                                onChanged: (v) => setState(() => _useSsl = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 用户名
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入用户名';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 密码
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: _isEditing ? '密码（留空保持不变）' : '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (value) {
                          if (!_isEditing && (value == null || value.isEmpty)) {
                            return '请输入密码';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // 选项
                      SwitchListTile(
                        title: const Text('自动连接'),
                        subtitle: const Text('启动时自动连接此源'),
                        value: _autoConnect,
                        onChanged: (v) => setState(() => _autoConnect = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        title: const Text('记住设备'),
                        subtitle: const Text('跳过二次验证（如果支持）'),
                        value: _rememberDevice,
                        onChanged: (v) => setState(() => _rememberDevice = v),
                        contentPadding: EdgeInsets.zero,
                      ),

                      // 错误信息
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // 提交按钮
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isEditing ? '保存' : '添加并连接'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SourceType.values.map((type) {
        final isSelected = _sourceType == type;
        final isSupported = type.isSupported;

        return FilterChip(
          label: Text(type.displayName),
          selected: isSelected,
          onSelected: isSupported
              ? (selected) {
                  if (selected && _sourceType != type) {
                    setState(() {
                      _sourceType = type;
                      // 重置表单内容
                      _nameController.clear();
                      _hostController.clear();
                      _usernameController.clear();
                      _passwordController.clear();
                      _portController.text = type.defaultPort.toString();
                      _useSsl = type.defaultPort == 5001 || type.defaultPort == 443;
                      _errorMessage = null;
                    });
                  }
                }
              : null,
          avatar: Icon(
            switch (type) {
              SourceType.synology => Icons.storage,
              SourceType.ugreen => Icons.storage,
              SourceType.fnos => Icons.storage,
              SourceType.qnap => Icons.storage,
              SourceType.webdav => Icons.cloud,
              SourceType.smb => Icons.folder_shared,
              SourceType.local => Icons.phone_android,
            },
            size: 18,
          ),
        );
      }).toList(),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final source = SourceEntity(
        id: widget.source?.id,
        name: _nameController.text.trim(),
        type: _sourceType,
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        useSsl: _useSsl,
        autoConnect: _autoConnect,
        rememberDevice: _rememberDevice,
      );

      final password = _passwordController.text;

      if (_isEditing) {
        // 更新源
        await ref.read(sourcesProvider.notifier).updateSource(source);

        // 如果输入了新密码，保存凭证
        if (password.isNotEmpty) {
          final manager = ref.read(sourceManagerProvider);
          await manager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源已更新')),
          );
        }
      } else {
        // 先尝试连接，只有连接成功才保存源
        final connection = await ref
            .read(activeConnectionsProvider.notifier)
            .connectNew(source, password: password);

        if (connection.status == SourceStatus.connected) {
          // 连接成功，保存源和凭证
          await ref.read(sourcesProvider.notifier).addSource(source);
          final manager = ref.read(sourceManagerProvider);
          await manager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已连接到 ${source.displayName}')),
            );
          }
        } else if (connection.status == SourceStatus.requires2FA) {
          // 需要二次验证
          if (mounted) {
            final result = await _show2FADialog();
            if (result != null && result.otpCode.isNotEmpty) {
              final verified = await ref
                  .read(activeConnectionsProvider.notifier)
                  .verify2FA(
                    source.id,
                    result.otpCode,
                    rememberDevice: result.rememberDevice,
                  );

              if (verified.status == SourceStatus.connected) {
                // 2FA验证成功，保存源和凭证
                await ref.read(sourcesProvider.notifier).addSource(source);
                final manager = ref.read(sourceManagerProvider);
                await manager.saveCredential(
                  source.id,
                  SourceCredential(password: password),
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已连接到 ${source.displayName}')),
                  );
                }
              } else {
                // 2FA失败，断开临时连接
                await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
                setState(() {
                  _errorMessage = verified.errorMessage ?? '二次验证失败';
                });
              }
            } else {
              // 用户取消2FA，断开临时连接
              await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
            }
          }
        } else {
          // 连接失败，断开临时连接
          await ref.read(activeConnectionsProvider.notifier).disconnect(source.id);
          setState(() {
            _errorMessage = connection.errorMessage ?? '连接失败';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<_TwoFAResult?> _show2FADialog() async {
    final controller = TextEditingController();
    bool rememberDevice = _rememberDevice;

    return showDialog<_TwoFAResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('二次验证'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入验证器应用中的验证码'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  hintText: '6 位数字',
                  prefixIcon: Icon(Icons.security),
                ),
                autofocus: true,
                maxLength: 6,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: rememberDevice,
                onChanged: (value) {
                  setDialogState(() {
                    rememberDevice = value ?? false;
                  });
                },
                title: const Text('记住此设备'),
                subtitle: const Text(
                  '下次登录时跳过二次验证',
                  style: TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _TwoFAResult(
                  otpCode: controller.text,
                  rememberDevice: rememberDevice,
                ),
              ),
              child: const Text('验证'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2FA 验证结果
class _TwoFAResult {
  const _TwoFAResult({
    required this.otpCode,
    required this.rememberDevice,
  });

  final String otpCode;
  final bool rememberDevice;
}
