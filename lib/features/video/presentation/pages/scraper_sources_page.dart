import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';

/// 刮削源管理页面 - 简化版
/// 所有刮削源类型直接显示，可展开配置，支持拖拽排序
class ScraperSourcesPage extends ConsumerStatefulWidget {
  const ScraperSourcesPage({super.key});

  @override
  ConsumerState<ScraperSourcesPage> createState() => _ScraperSourcesPageState();
}

class _ScraperSourcesPageState extends ConsumerState<ScraperSourcesPage> {
  // 展开状态管理
  final Set<ScraperType> _expandedTypes = {};

  // 各类型的配置控制器
  final Map<ScraperType, _ScraperConfig> _configs = {};

  @override
  void initState() {
    super.initState();
    // 初始化所有类型的配置控制器
    for (final type in ScraperType.values) {
      _configs[type] = _ScraperConfig();
    }
  }

  @override
  void dispose() {
    for (final config in _configs.values) {
      config.dispose();
    }
    super.dispose();
  }

  /// 从现有数据加载配置到控制器
  void _loadConfigFromSource(ScraperSourceEntity source) {
    final config = _configs[source.type];
    if (config == null) return;

    config.apiKeyController.text = source.apiKey ?? '';
    config.apiUrlController.text = source.apiUrl ?? '';
    config.cookieController.text = source.cookie ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: const Text('视频刮削源'),
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkSurface : null,
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
                onPressed: () => ref.read(scraperSourcesProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (sources) => _buildContent(sources, isDark),
      ),
    );
  }

  Widget _buildContent(List<ScraperSourceEntity> sources, bool isDark) {
    // 创建一个包含所有类型的列表，已配置的优先
    final configuredTypes = sources.map((s) => s.type).toSet();
    final allTypes = [
      ...ScraperType.values.where(configuredTypes.contains),
      ...ScraperType.values.where((t) => !configuredTypes.contains(t)),
    ];

    // 按已配置的源的优先级排序
    final sortedTypes = <ScraperType>[];
    for (final source in sources) {
      if (!sortedTypes.contains(source.type)) {
        sortedTypes.add(source.type);
      }
    }
    for (final type in allTypes) {
      if (!sortedTypes.contains(type)) {
        sortedTypes.add(type);
      }
    }

    return Column(
      children: [
        // 顶部说明
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '拖拽调整优先级，优先级高的刮削源将优先使用',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 刮削源列表
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedTypes.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) => _handleReorder(
              sources,
              sortedTypes,
              oldIndex,
              newIndex,
            ),
            proxyDecorator: (child, index, animation) => Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: child,
            ),
            itemBuilder: (context, index) {
              final type = sortedTypes[index];
              final source = sources.where((s) => s.type == type).firstOrNull;
              final isExpanded = _expandedTypes.contains(type);

              // 如果有已配置的源，加载配置
              if (source != null && !_expandedTypes.contains(type)) {
                _loadConfigFromSource(source);
              }

              return _ScraperTypeCard(
                key: ValueKey(type),
                index: index,
                type: type,
                source: source,
                priorityNumber: index + 1,
                isExpanded: isExpanded,
                config: _configs[type]!,
                onToggle: (enabled) => _handleToggle(type, source, enabled),
                onExpandToggle: () => _toggleExpanded(type),
                onSave: () => _saveConfig(type, source),
                onTest: source != null ? () => _testConnection(source) : null,
                isDark: Theme.of(context).brightness == Brightness.dark,
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleReorder(
    List<ScraperSourceEntity> sources,
    List<ScraperType> sortedTypes,
    int oldIndex,
    int newIndex,
  ) {
    var adjustedNewIndex = newIndex;
    if (oldIndex < adjustedNewIndex) {
      adjustedNewIndex -= 1;
    }

    // 获取要移动的类型
    final type = sortedTypes[oldIndex];

    // 找到对应的源
    final sourceIndex = sources.indexWhere((s) => s.type == type);
    if (sourceIndex == -1) return;

    // 计算新的目标位置（在已配置的源中）
    final targetType = sortedTypes[adjustedNewIndex];
    final targetSourceIndex = sources.indexWhere((s) => s.type == targetType);
    if (targetSourceIndex == -1) return;

    ref.read(scraperSourcesProvider.notifier).reorderSources(sourceIndex, targetSourceIndex);
  }

  void _toggleExpanded(ScraperType type) {
    setState(() {
      if (_expandedTypes.contains(type)) {
        _expandedTypes.remove(type);
      } else {
        _expandedTypes.add(type);
      }
    });
  }

  Future<void> _handleToggle(ScraperType type, ScraperSourceEntity? source, bool enabled) async {
    if (source != null) {
      // 已有配置，直接切换启用状态
      await ref.read(scraperSourcesProvider.notifier).toggleSource(source.id, enabled: enabled);
    } else if (enabled) {
      // 没有配置，需要检查是否需要必填项
      if (_needsConfiguration(type)) {
        // 需要配置，展开卡片
        setState(() {
          _expandedTypes.add(type);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('请先填写 ${type.displayName} 的配置信息'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // 不需要配置，直接创建并启用
        await _createAndEnableSource(type);
      }
    }
  }

  bool _needsConfiguration(ScraperType type) =>
      type.requiresApiKey || type.requiresApiUrl || type.requiresCookie;

  Future<void> _createAndEnableSource(ScraperType type) async {
    final newSource = ScraperSourceEntity(
      name: '',
      type: type,
      isEnabled: true,
    );
    await ref.read(scraperSourcesProvider.notifier).addSource(newSource);
  }

  Future<void> _saveConfig(ScraperType type, ScraperSourceEntity? existingSource) async {
    final config = _configs[type]!;

    // 验证必填项
    if (type.requiresApiKey && config.apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写 API Key'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (type.requiresApiUrl && config.apiUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写 API 地址'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (type.requiresCookie && config.cookieController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写 Cookie'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (existingSource != null) {
      // 更新现有配置
      final updated = existingSource.copyWith(
        apiKey: config.apiKeyController.text.trim().isEmpty
            ? null
            : config.apiKeyController.text.trim(),
        apiUrl: config.apiUrlController.text.trim().isEmpty
            ? null
            : config.apiUrlController.text.trim(),
        cookie: config.cookieController.text.trim().isEmpty
            ? null
            : config.cookieController.text.trim(),
      );
      await ref.read(scraperSourcesProvider.notifier).updateSource(updated);
    } else {
      // 创建新配置
      final newSource = ScraperSourceEntity(
        name: '',
        type: type,
        isEnabled: true,
        apiKey: config.apiKeyController.text.trim().isEmpty
            ? null
            : config.apiKeyController.text.trim(),
        apiUrl: config.apiUrlController.text.trim().isEmpty
            ? null
            : config.apiUrlController.text.trim(),
        cookie: config.cookieController.text.trim().isEmpty
            ? null
            : config.cookieController.text.trim(),
      );
      await ref.read(scraperSourcesProvider.notifier).addSource(newSource);
    }

    // 收起卡片
    setState(() {
      _expandedTypes.remove(type);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${type.displayName} 配置已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testConnection(ScraperSourceEntity source) async {
    // 显示加载对话框
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在测试连接...'),
          ],
        ),
      ),
    );

    try {
      final success =
          await ref.read(scraperSourcesProvider.notifier).testConnection(source);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '连接成功' : '连接失败'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 刮削源配置控制器
class _ScraperConfig {
  final apiKeyController = TextEditingController();
  final apiUrlController = TextEditingController();
  final cookieController = TextEditingController();

  void dispose() {
    apiKeyController.dispose();
    apiUrlController.dispose();
    cookieController.dispose();
  }
}

/// 刮削源类型卡片
class _ScraperTypeCard extends StatefulWidget {
  const _ScraperTypeCard({
    super.key,
    required this.index,
    required this.type,
    required this.source,
    required this.priorityNumber,
    required this.isExpanded,
    required this.config,
    required this.onToggle,
    required this.onExpandToggle,
    required this.onSave,
    required this.onTest,
    required this.isDark,
  });

  final int index;
  final ScraperType type;
  final ScraperSourceEntity? source;
  final int priorityNumber;
  final bool isExpanded;
  final _ScraperConfig config;
  final void Function(bool) onToggle;
  final VoidCallback onExpandToggle;
  final VoidCallback onSave;
  final VoidCallback? onTest;
  final bool isDark;

  @override
  State<_ScraperTypeCard> createState() => _ScraperTypeCardState();
}

class _ScraperTypeCardState extends State<_ScraperTypeCard> {
  bool _obscureApiKey = true;
  bool _obscureCookie = true;

  bool get _isEnabled => widget.source?.isEnabled ?? false;
  bool get _isConfigured => widget.source?.isConfigured ?? false;
  bool get _needsConfig =>
      widget.type.requiresApiKey ||
      widget.type.requiresApiUrl ||
      widget.type.requiresCookie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: widget.isDark ? AppColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: widget.isExpanded ? 4 : 1,
        shadowColor: widget.type.themeColor.withValues(alpha: 0.3),
        child: Column(
          children: [
            // 主卡片内容
            InkWell(
              onTap: _needsConfig ? widget.onExpandToggle : null,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 拖动手柄
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Icon(
                        Icons.drag_handle,
                        color: widget.isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 图标（带主题色背景）
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isEnabled
                            ? widget.type.themeColor.withValues(alpha: 0.15)
                            : (widget.isDark ? Colors.grey[800] : Colors.grey[200]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.type.icon,
                        size: 26,
                        color: _isEnabled
                            ? widget.type.themeColor
                            : (widget.isDark ? Colors.grey[600] : Colors.grey[400]),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // 名称和描述
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.type.displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _isEnabled
                                      ? null
                                      : (widget.isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[600]),
                                ),
                              ),
                              if (_isConfigured) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '已配置',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getDescription(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 展开/收起指示器（如果需要配置）
                    if (_needsConfig) ...[
                      Icon(
                        widget.isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: widget.isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                      const SizedBox(width: 8),
                    ],

                    // 启用开关
                    Switch(
                      value: _isEnabled,
                      onChanged: widget.onToggle,
                      activeTrackColor: widget.type.themeColor.withValues(alpha: 0.5),
                      activeThumbColor: widget.type.themeColor,
                    ),
                  ],
                ),
              ),
            ),

            // 展开的配置区域
            if (widget.isExpanded) _buildExpandedContent(theme),
          ],
        ),
      ),
    );
  }

  String _getDescription() {
    if (!_needsConfig) {
      return '内置服务，无需配置';
    }
    if (widget.type.requiresApiKey) {
      return '需要 API Key';
    }
    if (widget.type.requiresApiUrl) {
      return '需要 API 地址';
    }
    if (widget.type.requiresCookie) {
      return '需要登录 Cookie';
    }
    return widget.type.description;
  }

  Widget _buildExpandedContent(ThemeData theme) => Container(
        decoration: BoxDecoration(
          color: widget.isDark
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.grey[50],
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key 输入
            if (widget.type.requiresApiKey || widget.type == ScraperType.doubanApi) ...[
              _buildConfigField(
                label: 'API Key',
                hint: widget.type == ScraperType.tmdb
                    ? '从 themoviedb.org 获取'
                    : '可选',
                controller: widget.config.apiKeyController,
                isRequired: widget.type.requiresApiKey,
                isObscure: _obscureApiKey,
                onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
              ),
              const SizedBox(height: 16),
            ],

            // API URL 输入
            if (widget.type.requiresApiUrl) ...[
              _buildConfigField(
                label: 'API 地址',
                hint: '第三方豆瓣 API 服务地址',
                controller: widget.config.apiUrlController,
                isRequired: true,
                isUrl: true,
              ),
              const SizedBox(height: 16),
            ],

            // Cookie 输入
            if (widget.type.requiresCookie) ...[
              _buildConfigField(
                label: 'Cookie',
                hint: '从浏览器复制登录后的 Cookie',
                controller: widget.config.cookieController,
                isRequired: true,
                isObscure: _obscureCookie,
                onToggleObscure: () => setState(() => _obscureCookie = !_obscureCookie),
                isMultiline: true,
              ),
              const SizedBox(height: 16),
            ],

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onTest != null)
                  TextButton.icon(
                    onPressed: widget.onTest,
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('测试'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: widget.onSave,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.type.themeColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildConfigField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool isRequired = false,
    bool isObscure = false,
    bool isUrl = false,
    bool isMultiline = false,
    VoidCallback? onToggleObscure,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              if (isRequired) ...[
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: isObscure,
            maxLines: isMultiline ? 3 : 1,
            keyboardType: isUrl ? TextInputType.url : TextInputType.text,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 13,
                color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              filled: true,
              fillColor: widget.isDark ? Colors.grey[900] : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: widget.isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: widget.type.themeColor,
                  width: 2,
                ),
              ),
              suffixIcon: onToggleObscure != null
                  ? IconButton(
                      icon: Icon(
                        isObscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      onPressed: onToggleObscure,
                    )
                  : null,
            ),
          ),
        ],
      );
}
