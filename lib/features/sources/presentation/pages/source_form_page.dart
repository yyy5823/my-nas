import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/domain/entities/source_form_config.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/two_fa_sheet.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';
import 'package:my_nas/service_adapters/transmission/api/transmission_api.dart';

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
    this.popTwice = false,
  });

  /// 源类型
  final SourceType sourceType;

  /// 编辑模式时的现有源
  final SourceEntity? existingSource;

  /// 初始值（用于从发现的设备预填）
  final Map<String, String>? initialValues;

  /// 保存后是否需要返回两次（从类型选择页进入时为 true）
  final bool popTwice;

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
  late final Map<String, GlobalKey> _sectionKeys;

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
    _sectionKeys = {};

    _initializeFormValues();
  }

  void _initializeFormValues() {
    // 初始化默认值
    for (final section in _formConfig.sections) {
      if (section.defaultExpanded) {
        _expandedSections.add(section.title);
      }

      for (final field in section.fields) {
        dynamic initialValue;

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

        // 为文本类型字段创建控制器（仅支持 String 类型）
        if (field.type != SourceFormFieldType.toggle &&
            field.type != SourceFormFieldType.select &&
            field.type != SourceFormFieldType.keyValueList) {
          final textValue = initialValue is String ? initialValue : '';
          _controllers[field.key] = TextEditingController(text: textValue);
        }
      }
    }
  }

  dynamic _getValueFromSource(SourceEntity source, String key) {
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
        // 从 extraConfig 中获取，保持原始类型（List、Map 等）
        final value = source.extraConfig?[key];
        // 对于复杂类型（List、Map），直接返回
        if (value is List || value is Map) {
          return value;
        }
        return value?.toString();
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
        child: Theme(
          // 确保 ExpansionTile 内容在收起时正确裁剪
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ClipRect(
            key: _sectionKeys.putIfAbsent(section.title, GlobalKey.new),
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
              childrenPadding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedSections.add(section.title);
                    // 展开后滚动到该区块，确保内容可见
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final key = _sectionKeys[section.title];
                      if (key?.currentContext != null) {
                        Scrollable.ensureVisible(
                          key!.currentContext!,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                        );
                      }
                    });
                  } else {
                    _expandedSections.remove(section.title);
                  }
                });
              },
              children: [
                // 使用 Column 包装所有子项，确保正确的布局和裁剪
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < visibleFields.length; i++) ...[
                        _buildFormField(visibleFields[i], theme),
                        if (i < visibleFields.length - 1) const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
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

      // 服务类源使用专门的测试方法
      if (source.isServiceSource) {
        await _testServiceSourceConnection(source);
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

  /// 服务类源专用的连接测试
  Future<void> _testServiceSourceConnection(SourceEntity source) async {
    try {
      final connected = await _validateServiceSourceConnection(source);

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

  /// 验证服务类源连接
  Future<bool> _validateServiceSourceConnection(SourceEntity source) async {
    switch (source.type) {
      case SourceType.nastool:
        final apiToken = _formValues['apiToken'] as String? ?? '';
        final api = NasToolApi(
          baseUrl: source.baseUrl,
          apiToken: apiToken,
        );
        try {
          return await api.validateConnection();
        } finally {
          api.dispose();
        }
      case SourceType.qbittorrent:
        final password = _formValues['password'] as String? ?? '';
        final apiKey = _formValues['apiKey'] as String?;
        final api = QBittorrentApi(
          baseUrl: source.baseUrl,
          username: source.username.isNotEmpty ? source.username : null,
          password: password.isNotEmpty ? password : null,
          apiKey: (apiKey?.isNotEmpty ?? false) ? apiKey : null,
        );
        try {
          return await api.login();
        } finally {
          api.dispose();
        }
      case SourceType.transmission:
        final trPassword = _formValues['password'] as String? ?? '';
        final rpcPath = _formValues['rpcPath'] as String? ?? '/transmission/rpc';
        final trApi = TransmissionApi(
          baseUrl: source.baseUrl,
          rpcPath: rpcPath,
          username: source.username.isNotEmpty ? source.username : null,
          password: trPassword.isNotEmpty ? trPassword : null,
        );
        try {
          return await trApi.connect();
        } finally {
          trApi.dispose();
        }
      case SourceType.aria2:
        final rpcSecret = _formValues['rpcSecret'] as String?;
        final aria2Api = Aria2Api(
          baseUrl: source.baseUrl,
          rpcSecret: (rpcSecret?.isNotEmpty ?? false) ? rpcSecret : null,
        );
        try {
          return await aria2Api.connect();
        } finally {
          aria2Api.dispose();
        }
      // TODO: 添加其他服务类源的验证逻辑
      case SourceType.trakt:
      case SourceType.moviepilot:
      case SourceType.jellyfin:
      case SourceType.emby:
      case SourceType.plex:
        // 暂时返回 false，待各服务 API 实现后添加验证逻辑
        // ignore: only_throw_errors
        throw '${source.type.displayName} 连接验证尚未实现';
      default:
        return false;
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
        // 编辑模式 - 直接保存
        await sourcesNotifier.updateSource(source);

        // 如果输入了新密码，更新凭证
        if (password.isNotEmpty) {
          await sourceManager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }

        if (!mounted) return;
        _showSuccessAndPop(source, '源已更新');
      } else {
        // 创建模式 - 先验证连接再保存源
        await _submitNewSource(source, password);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('保存失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// 提交新源（创建模式）
  ///
  /// 流程：先验证连接 → 如果需要2FA则弹框验证 → 成功后再保存源
  Future<void> _submitNewSource(SourceEntity source, String password) async {
    final sourceManager = ref.read(sourceManagerProvider);

    // 服务类源使用专门的处理逻辑
    if (source.isServiceSource) {
      await _submitServiceSource(source);
      return;
    }

    // 移动端源：不需要密码验证，直接保存并连接
    if (source.type.isMobileSource) {
      await _submitMobileSource(source);
      return;
    }

    // 先尝试连接验证（不保存凭证）
    final connection = await sourceManager.connect(
      source,
      password: password,
      saveCredential: false,
    );

    if (!mounted) return;

    switch (connection.status) {
      case SourceStatus.connected:
        // 连接成功，保存源和凭证
        await _saveSourceAndCredential(source, password);
        if (mounted) {
          // 再次连接以更新状态（这次保存凭证）
          await ref
              .read(activeConnectionsProvider.notifier)
              .connect(source, password: password);
          _showSuccessAndPop(source, '已连接到 ${source.displayName}');
        }

      case SourceStatus.requires2FA:
        // 需要二次验证 - 弹出验证弹框
        await _handle2FAVerification(source, password);

      case SourceStatus.error:
        // 连接失败
        // 断开临时连接
        await sourceManager.disconnect(source.id);
        _showErrorSnackBar('连接失败: ${connection.errorMessage ?? "未知错误"}');

      default:
        // 其他状态
        await sourceManager.disconnect(source.id);
        _showErrorSnackBar('连接状态异常');
    }
  }

  /// 提交服务类源
  Future<void> _submitServiceSource(SourceEntity source) async {
    final sourcesNotifier = ref.read(sourcesProvider.notifier);

    try {
      // 验证连接
      final connected = await _validateServiceSourceConnection(source);

      if (!mounted) return;

      if (connected) {
        // 连接成功，保存源
        await sourcesNotifier.addSource(source);
        if (mounted) {
          _showSuccessAndPop(source, '已添加 ${source.displayName}');
        }
      } else {
        _showErrorSnackBar('连接失败，请检查认证信息');
      }
    } on String catch (message) {
      // 不支持的源类型
      if (!mounted) return;
      _showErrorSnackBar(message);
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('连接失败: $e');
    }
  }

  /// 提交移动端源
  ///
  /// 移动端源不需要密码验证，直接保存并尝试连接
  Future<void> _submitMobileSource(SourceEntity source) async {
    final sourcesNotifier = ref.read(sourcesProvider.notifier);
    final sourceManager = ref.read(sourceManagerProvider);

    try {
      // 尝试连接（会自动请求权限）
      final connection = await sourceManager.connect(
        source,
        password: '',
        saveCredential: false,
      );

      if (!mounted) return;

      if (connection.status == SourceStatus.connected) {
        // 连接成功，保存源
        await sourcesNotifier.addSource(source);
        // 刷新连接状态
        ref.read(activeConnectionsProvider.notifier).refresh();
        if (mounted) {
          _showSuccessAndPop(source, '已添加 ${source.displayName}');
        }
      } else {
        // 连接失败（可能是权限被拒绝）
        await sourceManager.disconnect(source.id);
        _showErrorSnackBar(connection.errorMessage ?? '连接失败，请检查权限设置');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('添加失败: $e');
    }
  }

  /// 处理2FA验证流程
  Future<void> _handle2FAVerification(
    SourceEntity source,
    String password,
  ) async {
    final sourceManager = ref.read(sourceManagerProvider);
    final sourcesNotifier = ref.read(sourcesProvider.notifier);

    // 弹出带在线验证的2FA弹框
    final result = await showTwoFASheetWithVerify(
      context,
      sourceName: source.displayName,
      initialRememberDevice: source.rememberDevice,
      onVerify: (otpCode, rememberDevice) async {
        // 在线验证OTP
        final verifyResult = await sourceManager.verify2FA(
          source.id,
          otpCode,
          rememberDevice: rememberDevice,
          password: password,
        );
        return verifyResult.status == SourceStatus.connected;
      },
    );

    if (!mounted) return;

    if (result == null) {
      // 用户直接关闭弹框（不保存）
      await sourceManager.disconnect(source.id);
      return;
    }

    switch (result.resultType) {
      case TwoFAResultType.verified:
        // 验证成功，保存源和凭证
        await _saveSourceAndCredential(source, password, result.rememberDevice);
        // 刷新连接状态（verify2FA 已经更新了底层状态为 connected）
        ref.read(activeConnectionsProvider.notifier).refresh();
        if (mounted) {
          _showSuccessAndPop(source, '已连接到 ${source.displayName}');
        }

      case TwoFAResultType.skipped:
        // 用户选择跳过验证，先保存源
        await sourcesNotifier.addSource(source);
        if (password.isNotEmpty) {
          await sourceManager.saveCredential(
            source.id,
            SourceCredential(password: password),
          );
        }
        // 更新连接状态（状态为 requires2FA）
        ref.read(activeConnectionsProvider.notifier).refresh();
        if (mounted) {
          _showWarningSnackBar('源已添加，需要完成二次验证后才能使用');
          Navigator.pop(context, source);
          if (widget.popTwice && mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }

      case TwoFAResultType.cancelled:
        // 用户取消（理论上不会到这里，因为取消时 result 为 null）
        await sourceManager.disconnect(source.id);
    }
  }

  /// 保存源和凭证
  Future<void> _saveSourceAndCredential(
    SourceEntity source,
    String password, [
    bool? rememberDevice,
  ]) async {
    final sourceManager = ref.read(sourceManagerProvider);
    final sourcesNotifier = ref.read(sourcesProvider.notifier);

    // 如果指定了 rememberDevice，更新源配置
    final sourceToSave = rememberDevice != null
        ? source.copyWith(rememberDevice: rememberDevice)
        : source;

    await sourcesNotifier.addSource(sourceToSave);

    if (password.isNotEmpty) {
      // 获取已保存的凭证（可能包含 deviceId）
      final existingCredential = await sourceManager.getCredential(source.id);
      await sourceManager.saveCredential(
        source.id,
        SourceCredential(
          password: password,
          deviceId: existingCredential?.deviceId,
        ),
      );
    }
  }

  /// 显示成功提示并返回
  void _showSuccessAndPop(SourceEntity source, String message) {
    _showSuccessSnackBar(message);
    Navigator.pop(context, source);
    if (widget.popTwice && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
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
