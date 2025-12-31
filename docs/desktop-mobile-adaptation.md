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
| 音乐列表 | 2 列卡片 | 4-6 列或表格视图 | ❌ 过于稀疏 |
| 视频列表 | 2-3 列 | 4-6 列 | ⚠️ 部分适配 |
| 相册网格 | 3 列 | 6-8 列 | ⚠️ 桌面端已 6 列 |
| 文件列表 | 卡片视图 | 表格/详情视图 | ❌ 缺少表格视图 |
| 按钮大小 | 48dp 触摸目标 | 32dp 即可 | ❌ 未区分 |
| 间距 | 较大 | 可以更紧凑 | ⚠️ 部分适配 |

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
| P1-1 统一上下文菜单 | 🔵 待开始 | - | - |
| P1-2 弹框适配 | 🔵 待开始 | - | - |
| P1-3 悬停效果统一 | 🔵 待开始 | - | - |
| P1-4 滚动条优化 | 🔵 待开始 | - | - |

### Phase 2 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P2-1 音乐列表优化 | 🔵 待开始 | - | - |
| P2-2 视频列表优化 | 🔵 待开始 | - | - |
| P2-3 统一网格计算 | 🔵 待开始 | - | - |
| P2-4 触摸目标适配 | 🔵 待开始 | - | - |
| P2-5 间距适配 | 🔵 待开始 | - | - |

### Phase 3 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P3-1 文件表格视图 | 🔵 待开始 | - | - |
| P3-2 音乐表格视图 | 🔵 待开始 | - | - |
| P3-3 列表项高度 | 🔵 待开始 | - | - |
| P3-4 工具栏适配 | 🔵 待开始 | - | - |

### Phase 4 进度

| 任务 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| P4-1 拖放支持 | 🔵 待开始 | - | - |
| P4-2 主从视图 | 🔵 待开始 | - | - |
| P4-3 面包屑导航 | 🔵 待开始 | - | - |
| P4-4 鼠标光标 | 🔵 待开始 | - | - |
| P4-5 快捷键帮助 | 🔵 待开始 | - | - |

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

### 待创建文件

- `lib/core/utils/grid_helper.dart` - 网格列数计算
- `lib/shared/widgets/adaptive_sheet.dart` - 自适应弹框
- `lib/shared/widgets/hoverable_widget.dart` - 悬停效果包装
- `lib/shared/widgets/adaptive_list_tile.dart` - 自适应列表项
- `lib/shared/widgets/table_view.dart` - 通用表格视图

---

## 更新日志

| 日期 | 更新内容 |
|------|---------|
| 2025-12-31 | 初始文档创建，完成现状分析和任务规划 |
