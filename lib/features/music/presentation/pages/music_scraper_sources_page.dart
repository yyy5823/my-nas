import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/music_scraper_factory.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';

/// 音乐刮削源管理页面
///
/// 简化设计：
/// - 直接展示所有刮削源类型
/// - 可拖拽排序
/// - 可展开配置（API Key、Cookie）
/// - 内置源无需配置，只需调整顺序
class MusicScraperSourcesPage extends ConsumerStatefulWidget {
  const MusicScraperSourcesPage({super.key});

  @override
  ConsumerState<MusicScraperSourcesPage> createState() => _MusicScraperSourcesPageState();
}

class _MusicScraperSourcesPageState extends ConsumerState<MusicScraperSourcesPage> {
  // 每个刮削源类型的配置状态
  final Map<MusicScraperType, _MusicScraperConfig> _configs = {};

  // 展开状态
  final Set<MusicScraperType> _expandedTypes = {};

  @override
  void initState() {
    super.initState();
    // 初始化所有类型的配置
    for (final type in MusicScraperType.values) {
      _configs[type] = _MusicScraperConfig();
    }
    // 加载完成后同步配置
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncConfigs());
  }

  @override
  void dispose() {
    // 释放所有 TextEditingController
    for (final config in _configs.values) {
      config.dispose();
    }
    super.dispose();
  }

  /// 同步已保存的配置到 TextEditingController
  void _syncConfigs() {
    final state = ref.read(musicScraperSourcesProvider);
    for (final source in state.sources) {
      final config = _configs[source.type];
      if (config != null) {
        config.apiKeyController.text = source.apiKey ?? '';
        config.cookieController.text = source.cookie ?? '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicScraperSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐刮削源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
            tooltip: '帮助',
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(MusicScraperSourcesState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('加载失败: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(musicScraperSourcesProvider.notifier).load(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return _buildScraperList(state);
  }

  Widget _buildScraperList(MusicScraperSourcesState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 构建排序后的类型列表
    final sortedTypes = _getSortedTypes(state.sources);

    return Column(
      children: [
        // 说明文字
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '拖拽调整优先级，点击展开配置',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 刮削源列表
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: sortedTypes.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) => _onReorder(oldIndex, newIndex, sortedTypes, state),
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (context, index) {
              final type = sortedTypes[index];
              final source = state.sources.where((s) => s.type == type).firstOrNull;
              final isExpanded = _expandedTypes.contains(type);
              final config = _configs[type]!;

              return _MusicScraperTypeCard(
                key: ValueKey(type),
                index: index,
                type: type,
                source: source,
                priorityNumber: index + 1,
                isExpanded: isExpanded,
                config: config,
                onToggle: (enabled) => _toggleSource(type, source, enabled),
                onExpandToggle: () => _toggleExpand(type),
                onSave: () => _saveConfig(type, source, config),
                onTest: source != null ? () => _testConnection(source) : null,
              );
            },
          ),
        ),
      ],
    );
  }

  /// 获取排序后的类型列表
  List<MusicScraperType> _getSortedTypes(List<MusicScraperSourceEntity> sources) {
    // 已配置的类型按优先级排序
    final configuredTypes = sources.map((s) => s.type).toList();

    // 未配置的类型
    final unconfiguredTypes = MusicScraperType.values.where((t) => !configuredTypes.contains(t)).toList();

    // 合并：已配置的在前，未配置的在后
    return [...configuredTypes, ...unconfiguredTypes];
  }

  /// 处理重排序
  void _onReorder(int oldIndex, int newIndex, List<MusicScraperType> sortedTypes, MusicScraperSourcesState state) {
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }

    // 计算在已配置源中的位置
    final configuredCount = state.sources.length;

    // 如果是在已配置的源之间移动
    if (oldIndex < configuredCount && targetIndex < configuredCount) {
      ref.read(musicScraperSourcesProvider.notifier).reorder(oldIndex, targetIndex);
    }
    // 如果是将未配置的源移动到已配置区域，需要先创建源
    else if (oldIndex >= configuredCount && targetIndex < configuredCount) {
      final type = sortedTypes[oldIndex];
      // 先添加源
      _addSource(type, priority: targetIndex);
    }
    // 其他情况（将已配置的移到未配置区域等）暂不处理
  }

  /// 切换展开状态
  void _toggleExpand(MusicScraperType type) {
    setState(() {
      if (_expandedTypes.contains(type)) {
        _expandedTypes.remove(type);
      } else {
        _expandedTypes.add(type);
      }
    });
  }

  /// 切换启用状态
  Future<void> _toggleSource(MusicScraperType type, MusicScraperSourceEntity? source, bool enabled) async {
    if (source != null) {
      await ref.read(musicScraperSourcesProvider.notifier).toggleSource(source.id, isEnabled: enabled);
    } else if (enabled) {
      // 如果源不存在但要启用，先创建
      await _addSource(type);
    }
  }

  /// 添加刮削源
  Future<void> _addSource(MusicScraperType type, {int? priority}) async {
    final config = _configs[type]!;
    final source = MusicScraperSourceEntity(
      name: '',
      type: type,
      isEnabled: true,
      priority: priority ?? 999,
      apiKey: config.apiKeyController.text.isEmpty ? null : config.apiKeyController.text,
      cookie: config.cookieController.text.isEmpty ? null : config.cookieController.text,
    );
    await ref.read(musicScraperSourcesProvider.notifier).addSource(source);
  }

  /// 保存配置
  Future<void> _saveConfig(MusicScraperType type, MusicScraperSourceEntity? source, _MusicScraperConfig config) async {
    if (source != null) {
      // 更新现有源
      final updatedSource = source.copyWith(
        apiKey: config.apiKeyController.text.isEmpty ? null : config.apiKeyController.text,
        cookie: config.cookieController.text.isEmpty ? null : config.cookieController.text,
      );
      await ref.read(musicScraperSourcesProvider.notifier).updateSource(updatedSource);
    } else {
      // 创建新源
      await _addSource(type);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存 ${type.displayName} 配置'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 测试连接
  Future<void> _testConnection(MusicScraperSourceEntity source) async {
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
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();
      final scraper = await manager.getScraper(source.id);
      final success = scraper != null && await scraper.testConnection();

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '连接成功' : '连接失败'),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 显示帮助对话框
  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刮削源说明'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('推荐配置：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. MusicBrainz - 元数据（内置，无需配置）'),
              Text('2. AcoustID - 声纹识别（需要 API Key）'),
              Text('3. 网易云音乐 - 歌词和封面（可选 Cookie）'),
              SizedBox(height: 16),
              Text('功能说明：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• 元数据：歌曲名、艺术家、专辑等'),
              Text('• 封面：专辑封面图片'),
              Text('• 歌词：歌词文本（LRC 格式）'),
              Text('• 声纹：通过音频指纹识别歌曲'),
              SizedBox(height: 16),
              Text('API Key 获取：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• AcoustID: acoustid.org/api-key'),
              Text('• Last.fm: last.fm/api/account/create'),
              Text('• Genius: genius.com/api-clients'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 配置状态类
class _MusicScraperConfig {
  final apiKeyController = TextEditingController();
  final cookieController = TextEditingController();

  void dispose() {
    apiKeyController.dispose();
    cookieController.dispose();
  }
}

/// 刮削源类型卡片
class _MusicScraperTypeCard extends StatelessWidget {
  const _MusicScraperTypeCard({
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
  });

  final int index;
  final MusicScraperType type;
  final MusicScraperSourceEntity? source;
  final int priorityNumber;
  final bool isExpanded;
  final _MusicScraperConfig config;
  final void Function(bool) onToggle;
  final VoidCallback onExpandToggle;
  final VoidCallback onSave;
  final VoidCallback? onTest;

  bool get _isEnabled => source?.isEnabled ?? false;
  bool get _needsConfig => type.requiresApiKey || type.supportsCookie;
  bool get _isImplemented => MusicScraperFactory.isImplemented(type);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 主行
          InkWell(
            onTap: _needsConfig ? onExpandToggle : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 拖动手柄
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 优先级序号
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isEnabled && _isImplemented
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$priorityNumber',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _isEnabled && _isImplemented
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 图标
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (_isEnabled && _isImplemented ? type.themeColor : colorScheme.outline)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      type.icon,
                      size: 24,
                      color: _isEnabled && _isImplemented ? type.themeColor : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 名称和描述
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              type.displayName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: _isEnabled && _isImplemented
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (!_isImplemented) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '即将支持',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        _buildCapabilityChips(context),
                      ],
                    ),
                  ),

                  // 展开/收起图标（如果需要配置）
                  if (_needsConfig)
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.outline,
                    ),

                  // 启用开关
                  Switch(
                    value: _isEnabled,
                    onChanged: _isImplemented ? onToggle : null,
                  ),
                ],
              ),
            ),
          ),

          // 展开的配置区域
          if (isExpanded && _needsConfig)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Key 输入框
                  if (type.requiresApiKey) ...[
                    TextField(
                      controller: config.apiKeyController,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: '请输入 API Key',
                        helperText: _getApiKeyHelper(),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: config.apiKeyController.clear,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Cookie 输入框
                  if (type.supportsCookie) ...[
                    TextField(
                      controller: config.cookieController,
                      decoration: InputDecoration(
                        labelText: 'Cookie（可选）',
                        hintText: '登录后可获取更多内容',
                        helperText: '从浏览器开发者工具复制 Cookie',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: config.cookieController.clear,
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onTest != null)
                        OutlinedButton.icon(
                          onPressed: onTest,
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text('测试'),
                        ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: onSave,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建能力标签
  Widget _buildCapabilityChips(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chips = <Widget>[];

    if (type.supportsMetadata) {
      chips.add(_buildChip(context, '元数据', colorScheme.primaryContainer));
    }
    if (type.supportsCover) {
      chips.add(_buildChip(context, '封面', colorScheme.secondaryContainer));
    }
    if (type.supportsLyrics) {
      chips.add(_buildChip(context, '歌词', colorScheme.tertiaryContainer));
    }
    if (type.supportsFingerprint) {
      chips.add(_buildChip(context, '声纹', colorScheme.errorContainer));
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _buildChip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
              ),
        ),
      );

  /// 获取 API Key 帮助文本
  String? _getApiKeyHelper() => switch (type) {
        MusicScraperType.acoustId => '访问 acoustid.org 获取',
        MusicScraperType.lastFm => '访问 last.fm/api 获取',
        MusicScraperType.genius => '访问 genius.com/api-clients 获取',
        _ => null,
      };
}
