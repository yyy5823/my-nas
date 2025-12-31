# 桌面端与移动端差异化适配方案

> 本文档用于跟踪和规划桌面端与移动端的 UI/UX 差异化处理，采用渐进式改进策略。

## 目录

- [当前实现分析](#当前实现分析)
- [需要改进的问题](#需要改进的问题)
- [改进任务清单](#改进任务清单)
- [实现规范](#实现规范)
- [进度跟踪](#进度跟踪)

---

## 当前实现分析

### 已有的平台适配基础设施

| 组件 | 文件位置 | 功能 |
|------|---------|------|
| `PlatformCapabilities` | `lib/core/utils/platform_capabilities.dart` | 平台检测（isDesktop/isMobile/isWeb） |
| `context_extensions` | `lib/core/extensions/context_extensions.dart` | 响应式断点（isCompact/isMedium/isExpanded/isLarge） |
| `ContextMenuRegion` | `lib/shared/widgets/context_menu_region.dart` | 自动切换右键菜单/长按菜单 |
| `KeyboardShortcuts` | `lib/core/widgets/keyboard_shortcuts.dart` | 键盘快捷键处理 |
| `AppBottomSheet` | `lib/shared/widgets/app_bottom_sheet.dart` | 底部弹框 |
| `MainScaffold` | `lib/shared/widgets/main_scaffold.dart` | 导航栏适配（NavigationRail vs BottomNav） |

### 当前做得好的地方

- [x] 平台检测系统完整
- [x] 导航栏根据平台切换（侧边栏 vs 底部栏）
- [x] 右键菜单/长按菜单自动切换
- [x] 键盘快捷键系统已实现
- [x] 玻璃效果三层适配（原生 API > Flutter）
- [x] 动态网格列数计算

---

## 需要改进的问题

### 1. 交互方式差异 🔴 高优先级

| 问题 | 移动端行为 | 桌面端应有行为 | 当前状态 |
|------|-----------|---------------|---------|
| 长按操作 | 长按显示菜单 | 右键显示菜单 | ⚠️ 部分实现 |
| 悬停效果 | 不适用 | 显示预览/工具栏 | ⚠️ 仅部分组件有 |
| 双击操作 | 放大 | 打开/编辑 | ❌ 未统一 |
| 拖放操作 | 不适用 | 拖放排序/移动文件 | ❌ 未实现 |
| 滚动方式 | 触摸滚动 | 鼠标滚轮 + 滚动条 | ⚠️ 滚动条未优化 |

### 2. 布局密度差异 🔴 高优先级

| 问题 | 移动端 | 桌面端应有 | 当前状态 |
|------|--------|-----------|---------|
| 音乐列表 | 2 列卡片 | 4-6 列或表格视图 | ✅ 使用 GridHelper |
| 视频列表 | 2-3 列 | 4-6 列 | ✅ 使用 GridHelper |
| 相册网格 | 3 列 | 6-8 列 | ⚠️ 桌面端已 6 列 |
| 文件列表 | 卡片视图 | 表格/详情视图 | ❌ 缺少表格视图 |
| 按钮大小 | 48dp 触摸目标 | 32dp 即可 | ✅ AdaptiveButton |
| 间距 | 较大 | 可以更紧凑 | ✅ AppSpacing 扩展 |

### 3. 弹框和对话框 🟡 中优先级

| 问题 | 移动端 | 桌面端应有 | 当前状态 |
|------|--------|-----------|---------|
| 底部弹框 | 从底部滑出 | 居中对话框/侧边面板 | ❌ 统一使用底部弹框 |
| 菜单位置 | 底部操作表 | 鼠标位置弹出 | ⚠️ 右键菜单已实现 |
| 选择器 | 底部滚轮选择 | 下拉菜单 | ❌ 未区分 |
| 确认对话框 | 全宽按钮 | 紧凑按钮组 | ❌ 未区分 |

### 4. 信息密度差异 🟡 中优先级

| 问题 | 移动端 | 桌面端应有 | 当前状态 |
|------|--------|-----------|---------|
| 列表项高度 | 72dp | 48dp | ❌ 未区分 |
| 卡片信息 | 精简显示 | 可显示更多元数据 | ❌ 信息量相同 |
| 工具栏 | 精简图标 | 图标+文字标签 | ❌ 未区分 |
| 表头 | 无 | 可排序表头 | ❌ 缺少表格视图 |

### 5. 导航和布局 🟢 低优先级

| 问题 | 移动端 | 桌面端应有 | 当前状态 |
|------|--------|-----------|---------|
| 分屏视图 | 单页面 | 主从视图（列表+详情） | ❌ 未实现 |
| 面包屑 | 返回按钮 | 面包屑导航 | ❌ 未实现 |
| 标签页 | 底部/顶部 | 顶部标签栏 | ⚠️ 部分实现 |
| 侧边栏 | 抽屉 | 固定侧边栏 | ✅ 已实现 |

### 6. 滚动条和光标 🟢 低优先级

| 问题 | 移动端 | 桌面端应有 | 当前状态 |
|------|--------|-----------|---------|
| 滚动条 | 隐藏 | 显示并可拖动 | ❌ 未定制 |
| 鼠标光标 | 不适用 | 根据操作变化 | ❌ 未实现 |
| 选择高亮 | 触摸反馈 | 悬停高亮 | ⚠️ 部分实现 |

---

## 改进任务清单

### Phase 1: 核心交互统一 (高优先级)

- [ ] **P1-1: 统一上下文菜单触发方式**
  - 确保所有可交互元素都使用 `ContextMenuRegion`
  - 移动端：长按
  - 桌面端：右键
  - 涉及文件：所有列表项组件

- [ ] **P1-2: 弹框适配**
  - 创建 `AdaptiveSheet` 组件
  - 移动端：底部弹框 `showModalBottomSheet`
  - 桌面端：居中对话框 `showDialog` 或侧边面板
  - 涉及文件：`lib/shared/widgets/` 新增组件

- [ ] **P1-3: 悬停效果统一**
  - 创建 `HoverableWidget` 包装组件
  - 统一悬停时的视觉反馈（缩放、阴影、工具栏显示）
  - 涉及文件：所有卡片组件

- [ ] **P1-4: 滚动条优化**
  - 在 `AppTheme` 中配置 `ScrollbarTheme`
  - 桌面端：始终显示、可拖动
  - 移动端：自动隐藏
  - 涉及文件：`lib/app/theme/app_theme.dart`

### Phase 2: 布局密度调整 (高优先级)

- [ ] **P2-1: 音乐列表桌面端优化**
  - 移动端：2 列卡片
  - 桌面端：4-6 列卡片或表格视图
  - 涉及文件：`lib/features/music/presentation/pages/music_list_page.dart`

- [ ] **P2-2: 视频列表桌面端优化**
  - 统一使用 `context.isDesktop` 判断
  - 调整列数和卡片大小
  - 涉及文件：`lib/features/video/presentation/pages/video_list_page.dart`

- [ ] **P2-3: 统一网格列数计算**
  - 创建 `GridHelper` 工具类
  - 统一列数计算逻辑
  - 涉及文件：新增 `lib/core/utils/grid_helper.dart`

- [ ] **P2-4: 触摸目标大小适配**
  - 移动端：最小 48dp
  - 桌面端：最小 32dp
  - 涉及文件：按钮和可交互组件

- [ ] **P2-5: 间距和填充适配**
  - 扩展 `AppSpacing` 类
  - 添加 `listItemPadding`、`cardPadding` 等平台差异化值
  - 涉及文件：`lib/app/theme/app_spacing.dart`

### Phase 3: 表格视图和信息密度 (中优先级)

- [ ] **P3-1: 文件列表表格视图**
  - 桌面端添加表格视图切换
  - 支持列排序
  - 涉及文件：`lib/features/file/presentation/`

- [ ] **P3-2: 音乐表格视图**
  - 类似 Spotify/iTunes 的表格布局
  - 显示更多元数据（时长、艺术家、专辑等）
  - 涉及文件：`lib/features/music/presentation/`

- [ ] **P3-3: 列表项高度适配**
  - 移动端：72dp
  - 桌面端：48dp
  - 涉及文件：所有列表项组件

- [ ] **P3-4: 工具栏适配**
  - 移动端：仅图标
  - 桌面端：图标 + 文字标签
  - 涉及文件：各页面工具栏

### Phase 4: 高级桌面特性 (低优先级)

- [ ] **P4-1: 拖放支持**
  - 文件拖放排序
  - 文件拖放移动
  - 涉及文件：文件列表相关组件

- [ ] **P4-2: 主从视图（分屏）**
  - 大屏幕显示列表+详情
  - 涉及文件：需要重构页面结构

- [ ] **P4-3: 面包屑导航**
  - 文件浏览器添加面包屑
  - 涉及文件：文件管理相关页面

- [ ] **P4-4: 鼠标光标定制**
  - 链接：手型
  - 可拖动：拖动光标
  - 加载中：等待光标
  - 涉及文件：全局配置

- [ ] **P4-5: 键盘快捷键帮助面板**
  - 按 `?` 显示快捷键列表
  - 涉及文件：`lib/core/widgets/keyboard_shortcuts.dart`

---

## 实现规范

### 平台判断规范

```dart
// ✅ 推荐：使用 PlatformCapabilities
import 'package:my_nas/core/utils/platform_capabilities.dart';

if (PlatformCapabilities.isDesktop) {
  // 桌面端逻辑
}

// ✅ 推荐：使用 context 扩展进行响应式判断
if (context.isDesktop) {
  // 桌面端布局
}

// ❌ 避免：直接使用 Platform
if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
  // 不推荐
}
```

### 网格列数规范

```dart
// ✅ 推荐：使用统一的 GridHelper（待实现）
final crossAxisCount = GridHelper.getColumnCount(
  context,
  minItemWidth: 160,
  maxColumns: 8,
);

// ⚠️ 当前临时方案
final crossAxisCount = context.isDesktop ? 6 : 3;
```

### 弹框规范

```dart
// ✅ 推荐：使用 AdaptiveSheet（待实现）
await showAdaptiveSheet(
  context: context,
  builder: (context) => MyContent(),
);

// ⚠️ 当前方案
if (PlatformCapabilities.isDesktop) {
  await showDialog(...);
} else {
  await showAppBottomSheet(...);
}
```

### 悬停效果规范

```dart
// ✅ 推荐：使用 HoverableWidget（待实现）
HoverableWidget(
  onHover: (isHovering) => setState(() => _isHovering = isHovering),
  child: MyCard(),
)

// 当前方案
MouseRegion(
  onEnter: (_) => _controller.forward(),
  onExit: (_) => _controller.reverse(),
  child: AnimatedBuilder(...),
)
```

---

## 进度跟踪

### Phase 1 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P1-1 统一上下文菜单 | ✅ 已完成 | - | 已有 ContextMenuRegion |
| P1-2 弹框适配 | ✅ 已完成 | 2025-12-31 | AdaptiveSheet |
| P1-3 悬停效果统一 | ✅ 已完成 | 2025-12-31 | HoverableWidget |
| P1-4 滚动条优化 | ✅ 已完成 | 2025-12-31 | ScrollbarTheme |

### Phase 2 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P2-1 音乐列表优化 | ✅ 已完成 | 2025-12-31 | 艺术家/专辑/流派/年代网格使用 GridHelper |
| P2-2 视频列表优化 | ✅ 已完成 | 2025-12-31 | 海报墙/视频缩略图使用 GridHelper |
| P2-3 统一网格计算 | ✅ 已完成 | 2025-12-31 | GridHelper |
| P2-4 触摸目标适配 | ✅ 已完成 | 2025-12-31 | AdaptiveButton |
| P2-5 间距适配 | ✅ 已完成 | 2025-12-31 | AppSpacing 扩展 |

### Phase 3 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P3-1 通用表格视图 | ✅ 已完成 | 2025-12-31 | AdaptiveTableView |
| P3-2 音乐表格视图 | ✅ 已完成 | 2025-12-31 | 桌面端表格视图模式 |
| P3-3 列表项组件 | ✅ 已完成 | 2025-12-31 | AdaptiveListTile |
| P3-4 工具栏适配 | ✅ 已完成 | 2025-12-31 | AdaptiveToolbar |

### Phase 4 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P4-1 拖放支持 | ✅ 已完成 | 2025-12-31 | DraggableList/Grid |
| P4-2 主从视图 | ✅ 已完成 | 2025-12-31 | MasterDetailLayout |
| P4-3 面包屑导航 | ✅ 已完成 | 2025-12-31 | BreadcrumbNavigation |
| P4-4 鼠标光标 | ✅ 已完成 | 2025-12-31 | HoverableWidget |
| P4-5 快捷键帮助 | ✅ 已完成 | 2025-12-31 | KeyboardShortcutsOverlay |

---

## 相关文件索引

### 核心适配文件

- `lib/core/utils/platform_capabilities.dart` - 平台检测
- `lib/core/extensions/context_extensions.dart` - 响应式扩展
- `lib/core/widgets/keyboard_shortcuts.dart` - 键盘快捷键
- `lib/shared/widgets/main_scaffold.dart` - 主导航栏
- `lib/shared/widgets/context_menu_region.dart` - 上下文菜单
- `lib/shared/widgets/app_bottom_sheet.dart` - 底部弹框
- `lib/app/theme/app_spacing.dart` - 间距配置
- `lib/app/theme/app_theme.dart` - 主题配置

### 新增组件文件

- `lib/core/utils/grid_helper.dart` - 网格列数计算工具 ✅
- `lib/shared/widgets/adaptive_sheet.dart` - 自适应弹框 ✅
- `lib/shared/widgets/hoverable_widget.dart` - 悬停效果组件 ✅
- `lib/shared/widgets/adaptive_button.dart` - 自适应按钮 ✅
- `lib/shared/widgets/adaptive_list_tile.dart` - 自适应列表项 ✅
- `lib/shared/widgets/adaptive_table_view.dart` - 表格视图 ✅
- `lib/shared/widgets/adaptive_toolbar.dart` - 自适应工具栏 ✅
- `lib/shared/widgets/draggable_list.dart` - 拖放列表/网格 ✅
- `lib/shared/widgets/master_detail_layout.dart` - 主从视图布局 ✅
- `lib/shared/widgets/breadcrumb_navigation.dart` - 面包屑导航 ✅
- `lib/shared/widgets/adaptive_widgets.dart` - 统一导出文件 ✅

---

## 更新日志

| 日期 | 更新内容 |
|------|---------|
| 2025-12-31 | 初始文档创建，完成现状分析和任务规划 |
| 2025-12-31 | 完成 Phase 1-4 基础设施组件开发 |
| 2025-12-31 | 应用 GridHelper 到音乐列表页（艺术家/专辑/流派/年代）|
| 2025-12-31 | 应用 GridHelper 到视频列表页（海报墙/视频缩略图）|
| 2025-12-31 | P3-2: 音乐列表页添加桌面端表格视图模式 |
| 2025-12-31 | P4-2: 实现 MasterDetailLayout 主从视图组件 |
| 2025-12-31 | P4-3: 实现 BreadcrumbNavigation 面包屑导航组件 |

## 组件使用指南

### 快速开始

```dart
// 导入所有自适应组件
import 'package:my_nas/shared/widgets/adaptive_widgets.dart';
```

### AdaptiveSheet（自适应弹框）

```dart
// 自动选择：移动端底部弹框，桌面端居中对话框
await showAdaptiveSheet(
  context: context,
  title: '设置',
  builder: (context, scrollController) => SettingsContent(),
);

// 确认对话框
final confirmed = await showAdaptiveConfirmDialog(
  context: context,
  title: '删除文件',
  message: '确定要删除这个文件吗？',
  isDestructive: true,
);

// 选项菜单
final option = await showAdaptiveOptions<String>(
  context: context,
  title: '排序方式',
  options: [
    AdaptiveOptionItem(icon: Icons.sort_by_alpha, title: '名称', value: 'name'),
    AdaptiveOptionItem(icon: Icons.access_time, title: '时间', value: 'time'),
  ],
);
```

### HoverableWidget（悬停效果）

```dart
// 完整悬停效果
HoverableWidget(
  effect: HoverEffect.combined,
  cursor: HoverCursor.pointer,
  onTap: () => openItem(),
  child: ItemCard(),
)

// 简化版悬停卡片
HoverCard(
  onTap: () => openItem(),
  onSecondaryTap: () => showMenu(),
  showOverlayOnHover: true,
  overlayBuilder: (context) => PlayButton(),
  child: ItemContent(),
)
```

### GridHelper（网格布局）

```dart
// 获取预设网格配置
final config = GridHelper.getMusicGridConfig(context);
// 或
final config = GridHelper.getGridConfig(context, type: GridLayoutType.video);

// 使用配置
GridView.builder(
  padding: config.padding,
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: config.crossAxisCount,
    mainAxisSpacing: config.mainAxisSpacing,
    crossAxisSpacing: config.crossAxisSpacing,
    childAspectRatio: config.childAspectRatio,
  ),
  itemBuilder: ...,
)
```

### AdaptiveTableView（表格视图）

```dart
AdaptiveTableView<MusicFile>(
  items: musicFiles,
  columns: [
    TableColumn(
      id: 'name',
      title: '名称',
      flex: 3,
      sortable: true,
      cellBuilder: (context, item, index) => Text(item.name),
    ),
    TableColumn(
      id: 'artist',
      title: '艺术家',
      flex: 2,
      cellBuilder: (context, item, index) => Text(item.artist ?? ''),
    ),
    TableColumn(
      id: 'duration',
      title: '时长',
      width: 80,
      cellBuilder: (context, item, index) => Text(item.durationFormatted),
    ),
  ],
  onTap: (item, index) => playMusic(item),
  onSort: (sortState) => sortBy(sortState),
)
```

### AdaptiveToolbar（工具栏）

```dart
AdaptiveToolbar(
  items: [
    ToolbarItem.iconText(
      icon: Icons.add,
      label: '新建',
      onPressed: () => createNew(),
    ),
    ToolbarItem.divider(),
    ToolbarItem.icon(
      icon: Icons.delete,
      tooltip: '删除',
      onPressed: () => delete(),
      isDestructive: true,
    ),
    ToolbarItem.spacer(),
    ToolbarItem.custom(child: SearchField()),
  ],
)
```

### DraggableList（拖放列表）

```dart
DraggableList<Track>(
  items: playlist,
  itemBuilder: (context, item, index, isDragging) => TrackTile(
    track: item,
    isDragging: isDragging,
  ),
  onReorder: (oldIndex, newIndex) {
    setState(() {
      final item = playlist.removeAt(oldIndex);
      playlist.insert(newIndex, item);
    });
  },
)
```

### KeyboardShortcutsOverlay（快捷键帮助）

```dart
// 包装页面，按 ? 显示快捷键帮助
KeyboardShortcutsOverlay(
  title: '视频播放器快捷键',
  groups: CommonShortcutGroups.videoPlayer,
  child: VideoPlayerPage(),
)
```

### MasterDetailLayout（主从视图）

```dart
// 桌面端分屏：左侧列表 + 右侧详情
// 移动端：单页面导航
MasterDetailScaffold<EmailItem>(
  items: emails,
  masterTitle: '收件箱',
  detailTitle: (item) => item.subject,
  masterBuilder: (context, item, isSelected) => ListTile(
    title: Text(item.subject),
    subtitle: Text(item.sender),
    selected: isSelected,
  ),
  detailBuilder: (context, item) => EmailDetailView(email: item),
  config: MasterDetailConfig(
    masterMinWidth: 300,
    masterMaxWidth: 400,
    breakpoint: 900,
  ),
)

// 可调整分隔线的主从视图
ResizableMasterDetail(
  masterChild: FileList(),
  detailChild: FilePreview(),
  initialMasterWidth: 320,
  minMasterWidth: 200,
  maxMasterWidth: 500,
)
```

### BreadcrumbNavigation（面包屑导航）

```dart
// 从路径自动生成面包屑
final breadcrumbs = buildBreadcrumbsFromPath('/documents/work/projects');

BreadcrumbNavigation(
  items: breadcrumbs,
  onItemTap: (item) => navigateTo(item.path),
  config: BreadcrumbConfig(
    showHomeIcon: true,
    maxVisibleItems: 5,  // 超出则折叠中间项
  ),
)

// 带返回按钮和操作按钮的面包屑栏
BreadcrumbBar(
  items: breadcrumbs,
  onItemTap: (item) => navigateTo(item.path),
  onBack: () => goUp(),
  actions: [
    IconButton(icon: Icon(Icons.refresh), onPressed: refresh),
    IconButton(icon: Icon(Icons.add), onPressed: createNew),
  ],
)

// 移动端紧凑型面包屑
CompactBreadcrumb(
  currentPath: '/documents/work',
  onBack: () => goUp(),
)
```
