import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/add_source_sheet.dart';

class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSourceSheet(context),
            tooltip: '添加源',
          ),
        ],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $e'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(sourcesProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (sources) {
          if (sources.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              final connection = connections[source.id];
              return _SourceCard(
                source: source,
                connection: connection,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '尚未添加任何源',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '添加 NAS、WebDAV 或 SMB 源\n以开始浏览您的媒体文件',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddSourceSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('添加源'),
            ),
          ],
        ),
      ),
    );

  void _showAddSourceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const AddSourceSheet(),
    );
  }
}

class _SourceCard extends ConsumerStatefulWidget {
  const _SourceCard({
    required this.source,
    this.connection,
  });

  final SourceEntity source;
  final SourceConnection? connection;

  @override
  ConsumerState<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends ConsumerState<_SourceCard> {
  bool _isConnecting = false;
  String? _errorMessage;

  SourceStatus get _status =>
      widget.connection?.status ?? SourceStatus.disconnected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (_status == SourceStatus.connected) {
            // 已连接时，直接打开文件浏览器
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FileBrowserPage(
                  sourceId: widget.source.id,
                  sourceName: widget.source.displayName,
                ),
              ),
            );
          } else {
            // 未连接时，显示操作选项
            _showSourceOptions(context);
          }
        },
        onLongPress: () => _showSourceOptions(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getSourceIcon(),
                  color: _getStatusColor(),
                ),
              ),
              const SizedBox(width: 16),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.source.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.source.type.displayName} • ${widget.source.host}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // 状态/操作
              if (_isConnecting)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildStatusChip(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final (label, color) = switch (_status) {
      SourceStatus.connected => ('已连接', Colors.green),
      SourceStatus.connecting => ('连接中', Colors.orange),
      SourceStatus.requires2FA => ('需要验证', Colors.amber),
      SourceStatus.error => ('错误', Colors.red),
      SourceStatus.disconnected => ('未连接', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _getSourceIcon() => switch (widget.source.type) {
      SourceType.synology => Icons.storage,
      SourceType.ugreen => Icons.storage,
      SourceType.fnos => Icons.storage,
      SourceType.qnap => Icons.storage,
      SourceType.webdav => Icons.cloud,
      SourceType.smb => Icons.folder_shared,
      SourceType.local => Icons.phone_android,
    };

  Color _getStatusColor() => switch (_status) {
      SourceStatus.connected => Colors.green,
      SourceStatus.connecting => Colors.orange,
      SourceStatus.requires2FA => Colors.amber,
      SourceStatus.error => Colors.red,
      SourceStatus.disconnected => Colors.grey,
    };

  void _showSourceOptions(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[600]
                  : Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
              _status == SourceStatus.connected
                  ? Icons.link_off
                  : Icons.link,
            ),
            title: Text(
              _status == SourceStatus.connected ? '断开连接' : '连接',
            ),
            onTap: () {
              Navigator.pop(context);
              if (_status == SourceStatus.connected) {
                _disconnect();
              } else {
                _connect();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(context);
              _editSource();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('删除', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deleteSource();
            },
          ),
          // 底部安全区域
          SizedBox(height: bottomPadding > 0 ? bottomPadding : 16),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // 本地存储不需要密码，直接连接
      if (widget.source.type == SourceType.local) {
        await ref.read(activeConnectionsProvider.notifier).connect(
              widget.source,
              password: '',
              saveCredential: false,
            );
      } else {
        // 获取保存的凭证
        final manager = ref.read(sourceManagerProvider);
        final credential = await manager.getCredential(widget.source.id);

        if (credential == null) {
          // 如果没有保存的凭证，显示密码输入对话框
          if (mounted) {
            final password = await _showPasswordDialog();
            if (password == null || password.isEmpty) {
              setState(() => _isConnecting = false);
              return;
            }
            await ref.read(activeConnectionsProvider.notifier).connect(
                  widget.source,
                  password: password,
                );
          }
        } else {
          // 总是保存凭证，以便更新 deviceId
          await ref.read(activeConnectionsProvider.notifier).connect(
                widget.source,
                password: credential.password,
              );
        }
      }

      final connection =
          ref.read(activeConnectionsProvider)[widget.source.id];

      // 处理需要 2FA 验证的情况
      if (connection?.status == SourceStatus.requires2FA) {
        if (mounted) {
          final result = await _show2FADialog();
          if (result != null && result.otpCode.isNotEmpty) {
            await ref.read(activeConnectionsProvider.notifier).verify2FA(
                  widget.source.id,
                  result.otpCode,
                  rememberDevice: result.rememberDevice,
                );
          }
        }
      } else if (connection?.status == SourceStatus.error) {
        setState(() {
          _errorMessage = connection?.errorMessage;
        });
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<_TwoFAResult?> _show2FADialog() async {
    final controller = TextEditingController();
    var rememberDevice = widget.source.rememberDevice;

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

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '${widget.source.username} 的密码',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    await ref
        .read(activeConnectionsProvider.notifier)
        .disconnect(widget.source.id);
  }

  void _editSource() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddSourceSheet(source: widget.source),
    );
  }

  Future<void> _deleteSource() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除源'),
        content: Text('确定要删除 "${widget.source.displayName}" 吗？\n相关的媒体库配置也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await ref.read(sourcesProvider.notifier).removeSource(widget.source.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除 "${widget.source.displayName}"')),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
