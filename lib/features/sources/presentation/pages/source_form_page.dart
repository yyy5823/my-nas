import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/domain/entities/source_form_config.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 表单模式
enum SourceFormMode {
  create,
  edit,
}

/// 源表单页面
///
/// 根据源类型动态生成表单，支持创建和编辑模式
class SourceFormPage extends ConsumerStatefulWidget {
  const SourceFormPage({
    required this.sourceType, super.key,
    this.existingSource,
    this.initialValues,
  });

  /// 源类型
  final SourceType sourceType;

  /// 编辑模式时的现有源
  final SourceEntity? existingSource;

  /// 初始值（用于从发现的设备预填）
  final Map<String, String>? initialValues;

  SourceFormMode get mode =>
      existingSource != null ? SourceFormMode.edit : SourceFormMode.create;

  @override
  ConsumerState<SourceFormPage> createState() => _SourceFormPageState();
}

class _SourceFormPageState extends ConsumerState<SourceFormPage> {
  late final SourceFormConfig _formConfig;
  late final GlobalKey<FormState> _formKey;
  late final Map<String, dynamic> _formValues;
  late final Map<String, TextEditingController> _controllers;
  late final Set<String> _expandedSections;

  bool _isSubmitting = false;
  bool _isTesting = false;
  bool _obscurePasswords = true;

  @override
  void initState() {
    super.initState();
    _formConfig = SourceFormConfig.forType(widget.sourceType);
    _formKey = GlobalKey<FormState>();
    _formValues = {};
    _controllers = {};
    _expandedSections = {};

    _initializeFormValues();
  }

  void _initializeFormValues() {
    // 初始化默认值
    for (final section in _formConfig.sections) {
      if (section.defaultExpanded) {
        _expandedSections.add(section.title);
      }

      for (final field in section.fields) {
        String? initialValue;

        if (widget.existingSource != null) {
          // 编辑模式：从现有源获取值
          initialValue = _getValueFromSource(widget.existingSource!, field.key);
        } else if (widget.initialValues != null && widget.initialValues!.containsKey(field.key)) {
          // 从发现的设备预填
          initialValue = widget.initialValues![field.key];
        }

        // 如果没有现有值，使用默认值
        initialValue ??= field.defaultValue ?? '';

        _formValues[field.key] = initialValue;

        // 为文本类型字段创建控制器
        if (field.type != SourceFormFieldType.toggle &&
            field.type != SourceFormFieldType.select) {
          _controllers[field.key] = TextEditingController(text: initialValue);
        }
      }
    }
  }

  String? _getValueFromSource(SourceEntity source, String key) {
    switch (key) {
      case 'name':
        return source.name;
      case 'host':
        return source.host;
      case 'port':
        return source.port.toString();
      case 'username':
        return source.username;
      case 'useSsl':
        return source.useSsl.toString();
      case 'autoConnect':
        return source.autoConnect.toString();
      case 'rememberDevice':
        return source.rememberDevice.toString();
      case 'apiKey':
        return source.apiKey;
      default:
        // 从 extraConfig 中获取
        return source.extraConfig?[key]?.toString();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sourceType.displayName),
        centerTitle: true,
        actions: [
          if (_formConfig.testConnectionSupported)
            TextButton(
              onPressed: _isTesting || _isSubmitting ? null : _testConnection,
              child: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('测试'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 表单字段（扁平化，不使用分组卡片）
              for (final section in _formConfig.sections)
                _buildFormSection(section, theme),

              const SizedBox(height: 24),

              // 提交按钮
              _buildSubmitButton(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection(SourceFormSection section, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    // 过滤可见的字段
    final visibleFields = section.fields.where((field) {
      if (field.visibilityCondition == null) return true;
      return field.visibilityCondition!(_formValues);
    }).toList();

    if (visibleFields.isEmpty) {
      return const SizedBox.shrink();
    }

    // 如果是可折叠的高级设置区块
    if (section.collapsible) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ExpansionTile(
          title: Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: section.description != null
              ? Text(
                  section.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          initiallyExpanded: section.defaultExpanded,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedSections.add(section.title);
              } else {
                _expandedSections.remove(section.title);
              }
            });
          },
          children: [
            for (int i = 0; i < visibleFields.length; i++) ...[
              _buildFormField(visibleFields[i], theme),
              if (i < visibleFields.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      );
    }

    // 普通区块 - 只显示分组标题（如果有多个区块）
    final showTitle = _formConfig.sections.length > 1 && !section.collapsible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              section.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        for (int i = 0; i < visibleFields.length; i++) ...[
          _buildFormField(visibleFields[i], theme),
          if (i < visibleFields.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildFormField(SourceFormField field, ThemeData theme) {
    switch (field.type) {
      case SourceFormFieldType.toggle:
        return _buildToggleField(field, theme);
      case SourceFormFieldType.select:
        return _buildSelectField(field, theme);
      case SourceFormFieldType.password:
        return _buildPasswordField(field, theme);
      case SourceFormFieldType.number:
        return _buildNumberField(field, theme);
      case SourceFormFieldType.keyValueList:
        return _buildKeyValueListField(field, theme);
      default:
        return _buildTextField(field, theme);
    }
  }

  Widget _buildTextField(SourceFormField field, ThemeData theme) => TextFormField(
      controller: _controllers[field.key],
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        helperText: field.helpText,
        helperMaxLines: 2,
        prefixIcon: _getFieldIcon(field.key),
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return '请输入${field.label}';
        }
        return field.validator?.call(value);
      },
      onChanged: (value) {
        setState(() {
          _formValues[field.key] = value;
        });
      },
    );

  Widget _buildPasswordField(SourceFormField field, ThemeData theme) => TextFormField(
      controller: _controllers[field.key],
      obscureText: _obscurePasswords,
      decoration: InputDecoration(
        labelText: widget.mode == SourceFormMode.edit
            ? '${field.label}（留空保持不变）'
            : field.label,
        hintText: field.placeholder,
        helperText: field.helpText,
        helperMaxLines: 2,
        prefixIcon: _getFieldIcon(field.key),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePasswords
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () {
            setState(() {
              _obscurePasswords = !_obscurePasswords;
            });
          },
        ),
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          // 编辑模式下密码可以为空（保持不变）
          if (widget.mode == SourceFormMode.edit) {
            return null;
          }
          return '请输入${field.label}';
        }
        return field.validator?.call(value);
      },
      onChanged: (value) {
        setState(() {
          _formValues[field.key] = value;
        });
      },
    );

  Widget _buildNumberField(SourceFormField field, ThemeData theme) => TextFormField(
      controller: _controllers[field.key],
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        helperText: field.helpText,
        helperMaxLines: 2,
        prefixIcon: _getFieldIcon(field.key),
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) {
          return '请输入${field.label}';
        }
        if (value != null && value.isNotEmpty) {
          final number = int.tryParse(value);
          if (number == null) {
            return '请输入有效的数字';
          }
        }
        return field.validator?.call(value);
      },
      onChanged: (value) {
        setState(() {
          _formValues[field.key] = value;
        });
      },
    );

  Widget _buildToggleField(SourceFormField field, ThemeData theme) {
    final value = _formValues[field.key] == 'true';

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(field.label),
      subtitle: field.helpText != null ? Text(field.helpText!) : null,
      value: value,
      onChanged: (newValue) {
        setState(() {
          _formValues[field.key] = newValue.toString();
        });
      },
    );
  }

  Widget _buildSelectField(SourceFormField field, ThemeData theme) {
    final currentValue =
        (_formValues[field.key] as String?) ?? field.options?.first ?? '';

    return DropdownButtonFormField<String>(
      initialValue: currentValue.isNotEmpty ? currentValue : null,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.helpText,
        helperMaxLines: 2,
        prefixIcon: _getFieldIcon(field.key),
      ),
      items: field.options
          ?.map((option) => DropdownMenuItem(
                value: option,
                child: Text(option),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _formValues[field.key] = value;
          });
        }
      },
    );
  }

  /// 构建键值对列表字段（用于自定义请求头等）
  Widget _buildKeyValueListField(SourceFormField field, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    // 获取当前的键值对列表
    var items = <Map<String, String>>[];
    final existingValue = _formValues[field.key];
    if (existingValue is List) {
      items = existingValue.cast<Map<String, String>>().toList();
    } else if (existingValue is String && existingValue.isNotEmpty) {
      // 尝试解析 JSON 格式（字符串值暂不支持，保持空列表）
      items = [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Expanded(
              child: Text(
                field.label,
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  items.add({'key': '', 'value': ''});
                  _formValues[field.key] = items;
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        if (field.helpText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              field.helpText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // 键值对列表
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Text(
                '点击「添加」按钮添加请求头',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Key 输入框
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: item['key'],
                      decoration: InputDecoration(
                        labelText: 'Key',
                        hintText: 'x-api-key',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          items[index]['key'] = value;
                          _formValues[field.key] = items;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Value 输入框
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      initialValue: item['value'],
                      decoration: InputDecoration(
                        labelText: 'Value',
                        hintText: '值',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          items[index]['value'] = value;
                          _formValues[field.key] = items;
                        });
                      },
                    ),
                  ),
                  // 删除按钮
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: colorScheme.error,
                    ),
                    onPressed: () {
                      setState(() {
                        items.removeAt(index);
                        _formValues[field.key] = items;
                      });
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// 根据字段 key 获取对应的图标
  Icon? _getFieldIcon(String key) {
    final iconData = switch (key) {
      'name' => Icons.label_outline,
      'host' => Icons.dns_outlined,
      'port' => Icons.numbers,
      'username' => Icons.person_outline,
      'password' => Icons.lock_outline,
      'apiKey' || 'apiToken' => Icons.key,
      'clientId' => Icons.apps,
      'clientSecret' => Icons.vpn_key,
      _ => null,
    };
    return iconData != null ? Icon(iconData) : null;
  }

  Widget _buildSubmitButton(ThemeData theme) => SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isSubmitting || _isTesting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.mode == SourceFormMode.edit ? '保存' : '添加并连接',
              ),
      ),
    );

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
    });

    try {
      final source = _buildSourceEntity();

      // PT 站点使用专用的测试方法
      if (source.type == SourceType.ptSite) {
        await _testPTSiteConnection(source);
        return;
      }

      final password = _formValues['password'] as String? ?? '';

      final sourceManager = ref.read(sourceManagerProvider);

      // 使用 connect 方法测试连接，但不保存凭证
      final connection = await sourceManager.connect(
        source,
        password: password,
        saveCredential: false,
      );

      if (!mounted) return;

      switch (connection.status) {
        case SourceStatus.connected:
          _showSuccessSnackBar('连接测试成功');
          // 断开测试连接
          await sourceManager.disconnect(source.id);
        case SourceStatus.requires2FA:
          _showWarningSnackBar('需要二次验证，请保存后完成验证');
        case SourceStatus.error:
          _showErrorSnackBar('连接失败: ${connection.errorMessage ?? "未知错误"}');
        default:
          _showErrorSnackBar('连接状态异常');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('测试失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// PT 站点专用的连接测试
  Future<void> _testPTSiteConnection(SourceEntity source) async {
    try {
      // 使用 PTSiteApiFactory 创建 API 实例并测试连接
      final api = PTSiteApiFactory.create(source);
      final connected = await api.testConnection();
      api.dispose();

      if (!mounted) return;

      if (connected) {
        _showSuccessSnackBar('连接测试成功');
      } else {
        _showErrorSnackBar('连接失败，请检查认证信息');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('测试失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final source = _buildSourceEntity();
      final password = _formValues['password'] as String? ?? '';
      final sourcesNotifier = ref.read(sourcesProvider.notifier);

      final sourceManager = ref.read(sourceManagerProvider);

      if (widget.mode == SourceFormMode.edit) {
        // 编辑模式
        await sourcesNotifier.updateSource(source);

        // 如果输入了新密码，更新凭证
        if (password.isNotEmpty) {
          await sourceManager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }
      } else {
        // 创建模式
        await sourcesNotifier.addSource(source);

        // 保存凭证
        if (password.isNotEmpty) {
          await sourceManager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }

        // 尝试连接（通过 provider 以更新 UI 状态）
        if (source.autoConnect) {
          await ref
              .read(activeConnectionsProvider.notifier)
              .connect(source, password: password);
        }
      }

      if (!mounted) return;

      // 返回上一页
      Navigator.pop(context, source);

      // 如果是从类型选择页进入的，再返回一次
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } on Exception catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('保存失败: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  SourceEntity _buildSourceEntity() {
    final name = _formValues['name'] as String? ?? '';
    final host = _formValues['host'] as String? ?? '';
    final portStr = _formValues['port'] as String? ?? '';
    final port = int.tryParse(portStr) ?? widget.sourceType.defaultPort;
    final username = _formValues['username'] as String? ?? '';
    final useSsl = _formValues['useSsl'] == 'true';
    final autoConnect = _formValues['autoConnect'] == 'true';
    final rememberDevice = _formValues['rememberDevice'] == 'true';
    final apiKey = _formValues['apiKey'] as String?;

    // 收集额外配置
    final extraConfig = <String, dynamic>{};
    final standardKeys = {
      'name',
      'host',
      'port',
      'username',
      'password',
      'useSsl',
      'autoConnect',
      'rememberDevice',
      'apiKey',
    };

    for (final entry in _formValues.entries) {
      if (!standardKeys.contains(entry.key) && entry.value != null) {
        extraConfig[entry.key] = entry.value;
      }
    }

    return SourceEntity(
      id: widget.existingSource?.id,
      name: name,
      type: widget.sourceType,
      host: host,
      port: port,
      username: username,
      useSsl: useSsl,
      autoConnect: autoConnect,
      rememberDevice: rememberDevice,
      apiKey: apiKey?.isNotEmpty ?? false ? apiKey : null,
      extraConfig: extraConfig.isNotEmpty ? extraConfig : null,
      lastConnected: widget.existingSource?.lastConnected,
      quickConnectId: widget.existingSource?.quickConnectId,
      accessToken: widget.existingSource?.accessToken,
      refreshToken: widget.existingSource?.refreshToken,
      tokenExpiresAt: widget.existingSource?.tokenExpiresAt,
    );
  }
}
