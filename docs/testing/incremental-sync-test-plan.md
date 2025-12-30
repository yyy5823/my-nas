# 增量同步功能测试方案

## 概述

本文档描述视频库增量同步功能的测试方案。增量同步用于在应用启动时快速检测媒体库变化，避免全量扫描带来的性能开销。

### 相关文件

- `lib/features/video/data/services/video_scanner_service.dart` - 增量同步主逻辑
- `lib/features/video/data/services/video_database_service.dart` - 数据库操作
- `lib/nas_adapters/smb/smb_file_system.dart` - SMB 文件系统适配器

### 核心方法

- `VideoScannerService.incrementalSync()` - 增量同步入口
- `_incrementalSyncDirectory()` - 分层目录检测
- `_scanDirectoryForChanges()` - 文件级变化检测

---

## 测试环境准备

### 1. 测试用 NAS 目录结构

```
/测试媒体库/
├── 电影/
│   ├── 动作片/
│   │   ├── Movie1.mkv
│   │   ├── Movie1.nfo
│   │   └── Movie2.mp4
│   ├── 喜剧片/
│   │   └── Comedy1.avi
│   └── 科幻片/
│       ├── SciFi1.mkv
│       └── SciFi2.mp4
├── 电视剧/
│   ├── 剧集A/
│   │   ├── Season 1/
│   │   │   ├── S01E01.mkv
│   │   │   └── S01E02.mkv
│   │   └── Season 2/
│   │       └── S02E01.mkv
│   └── 剧集B/
│       └── E01.mp4
└── 空目录/
```

### 2. 前置条件

1. 已配置并连接 SMB/WebDAV 源
2. 已完成至少一次全量扫描
3. 数据库中有完整的 `scan_progress` 和 `video_metadata` 记录

---

## 测试用例

### TC-001: 无变化场景测试

**目的**: 验证无变化时快速跳过

**前置条件**:
- 完成全量扫描后未修改任何文件

**测试步骤**:
1. 记录当前时间 T1
2. 调用 `incrementalSync()`
3. 记录完成时间 T2

**预期结果**:
- [ ] T2 - T1 < 5 秒（快速完成）
- [ ] 返回结果 `hasChanges == false`
- [ ] `unchangedDirectories >= 1`
- [ ] 无网络请求（除根目录检查）
- [ ] 日志显示 "根目录未变化，跳过"

**验证方法**:
```dart
final result = await scannerService.incrementalSync(
  paths: paths,
  connections: connections,
);
assert(result != null);
assert(!result.hasChanges);
print('耗时: ${stopwatch.elapsedMilliseconds}ms');
```

---

### TC-002: 新增文件测试

**目的**: 验证检测新增视频文件

**前置条件**:
- 完成全量扫描

**测试步骤**:
1. 在 `电影/动作片/` 目录添加新文件 `NewMovie.mkv`
2. 等待 2 秒（确保文件系统时间戳更新）
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] `addedFiles == 1`
- [ ] `changedDirectories >= 1`
- [ ] `hasChanges == true`
- [ ] 新文件被写入 `video_metadata` 表
- [ ] 触发后续刮削流程

**SQL 验证**:
```sql
SELECT * FROM video_metadata
WHERE file_path LIKE '%NewMovie.mkv';
```

---

### TC-003: 删除文件测试

**目的**: 验证检测已删除视频文件

**前置条件**:
- 目录中有 `Movie2.mp4` 文件
- 数据库中有该文件记录

**测试步骤**:
1. 删除 `电影/动作片/Movie2.mp4`
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] `deletedFiles == 1`
- [ ] `hasChanges == true`
- [ ] 文件从 `video_metadata` 表删除

**SQL 验证**:
```sql
-- 应返回空
SELECT * FROM video_metadata
WHERE file_path LIKE '%Movie2.mp4';
```

---

### TC-004: 文件修改测试

**目的**: 验证检测已修改的视频文件

**前置条件**:
- 目录中有 `Movie1.mkv` 文件

**测试步骤**:
1. 修改 `Movie1.mkv` 文件（追加数据或替换）
2. 确保文件大小或修改时间变化
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] `changedFiles == 1`
- [ ] `hasChanges == true`
- [ ] 数据库中文件大小/时间已更新

---

### TC-005: 新增目录测试

**目的**: 验证检测新增目录及其内容

**测试步骤**:
1. 创建新目录 `电影/恐怖片/`
2. 在新目录添加 `Horror1.mkv`
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] `newDirectories >= 1`
- [ ] `addedFiles >= 1`
- [ ] 新目录记录写入 `scan_progress` 表
- [ ] 新文件记录写入 `video_metadata` 表

---

### TC-006: 删除目录测试

**目的**: 验证检测已删除目录及清理数据

**前置条件**:
- 存在 `电影/喜剧片/` 目录且有扫描记录

**测试步骤**:
1. 删除整个 `电影/喜剧片/` 目录
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] `deletedDirectories >= 1`
- [ ] `deletedFiles >= 1`（目录内的文件）
- [ ] 相关记录从 `scan_progress` 表删除
- [ ] 相关文件从 `video_metadata` 表删除

---

### TC-007: 深层目录变化测试

**目的**: 验证只扫描有变化的分支

**测试步骤**:
1. 在深层目录 `电视剧/剧集A/Season 2/` 添加 `S02E02.mkv`
2. 不修改其他目录
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] `addedFiles == 1`
- [ ] `changedDirectories` 只包含变化路径上的目录
- [ ] `电影/` 分支完全跳过（无网络请求）

**日志验证**:
- 应看到 "电影" 目录被跳过的日志
- 应看到 "剧集A" 分支被扫描的日志

---

### TC-008: 中断测试

**目的**: 验证用户中断时正确处理

**测试步骤**:
1. 准备大量目录变化（100+ 个目录）
2. 调用 `incrementalSync()`
3. 在执行中调用 `stopScraping()`
4. 检查返回结果

**预期结果**:
- [ ] 方法正常返回，不抛出异常
- [ ] 返回部分完成的统计结果
- [ ] `_isScanning` 被重置为 `false`
- [ ] 日志显示 "增量同步被中断"

**代码示例**:
```dart
final future = scannerService.incrementalSync(...);

// 2秒后中断
Future.delayed(Duration(seconds: 2), () {
  scannerService.stopScraping();
});

final result = await future;
print('中断后结果: $result');
```

---

### TC-009: 超时测试

**目的**: 验证超时保护机制

**测试步骤**:
1. 设置短超时时间（如 10 秒）
2. 准备需要长时间扫描的场景（大量目录）
3. 调用 `incrementalSync(timeout: Duration(seconds: 10))`

**预期结果**:
- [ ] 10 秒后方法返回
- [ ] 返回部分完成的结果
- [ ] 日志显示 "增量同步超时"
- [ ] 不会无限执行

---

### TC-010: 目录数量上限测试

**目的**: 验证 maxDirsToCheck 限制

**测试步骤**:
1. 准备超过 1000 个目录的变化
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] 最多检查 1000 个目录后返回
- [ ] 不会继续无限扫描
- [ ] 返回已检查部分的结果

---

### TC-011: 并发调用测试

**目的**: 验证防止重复扫描

**测试步骤**:
1. 同时调用两次 `incrementalSync()`
2. 检查返回结果

**预期结果**:
- [ ] 第二次调用立即返回 `null`
- [ ] 日志显示 "扫描正在进行中，跳过增量同步"
- [ ] 只有一次实际执行

**代码示例**:
```dart
final future1 = scannerService.incrementalSync(...);
final future2 = scannerService.incrementalSync(...);

final results = await Future.wait([future1, future2]);
assert(results[0] != null || results[1] != null);
assert(results[0] == null || results[1] == null);
```

---

### TC-012: 连接断开测试

**目的**: 验证源未连接时的处理

**测试步骤**:
1. 断开 NAS 连接
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] 不抛出异常
- [ ] 日志显示 "源 xxx 未连接，跳过增量同步"
- [ ] 返回空结果或跳过该源

---

### TC-013: 网络异常测试

**目的**: 验证网络错误时的容错

**测试步骤**:
1. 在扫描过程中模拟网络中断
2. 观察错误处理

**预期结果**:
- [ ] 捕获异常，不崩溃
- [ ] 通过 `AppError.handle()` 上报错误
- [ ] 返回部分结果或 `null`

---

### TC-014: 空目录测试

**目的**: 验证空目录的处理

**测试步骤**:
1. 创建空目录 `电影/新分类/`
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] 空目录被正确记录
- [ ] `videoCount == 0`
- [ ] 不影响其他扫描

---

### TC-015: 隐藏文件/目录测试

**目的**: 验证隐藏文件被正确跳过

**测试步骤**:
1. 创建隐藏目录 `.隐藏目录/` 或以 `.` 开头的目录
2. 在其中放置视频文件
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] 隐藏目录被跳过
- [ ] 隐藏文件不被扫描
- [ ] 无相关记录写入数据库

---

### TC-016: 特殊字符路径测试

**目的**: 验证特殊字符路径处理

**测试步骤**:
1. 创建包含特殊字符的目录: `电影/[2024] 新片 (高清)/`
2. 添加视频文件
3. 调用 `incrementalSync()`

**预期结果**:
- [ ] 正确处理特殊字符
- [ ] 文件路径正确保存到数据库
- [ ] 无 SQL 注入或路径解析错误

---

### TC-017: 大文件测试

**目的**: 验证大文件不影响扫描性能

**测试步骤**:
1. 添加大文件（10GB+）
2. 调用 `incrementalSync()`
3. 测量扫描时间

**预期结果**:
- [ ] 扫描时间与文件大小无关
- [ ] 只读取元数据，不读取文件内容
- [ ] 内存使用稳定

---

### TC-018: 数据库迁移测试

**目的**: 验证从旧版本升级时的兼容性

**前置条件**:
- 使用 v17 数据库（无 `dir_modified_time` 列）

**测试步骤**:
1. 升级到 v18 数据库
2. 调用 `incrementalSync()`

**预期结果**:
- [ ] 数据库迁移成功
- [ ] `dir_modified_time` 列被添加
- [ ] 首次增量同步正常工作（会扫描所有目录，因为无历史修改时间）

---

## 性能基准测试

### PB-001: 无变化场景性能

| 目录数量 | 预期耗时 | 网络请求数 |
|---------|---------|----------|
| 10      | < 1s    | 1        |
| 100     | < 2s    | 1        |
| 1000    | < 5s    | 1        |

### PB-002: 单目录变化性能

| 场景 | 预期耗时 | 说明 |
|-----|---------|-----|
| 根目录新增1文件 | < 3s | 只扫描根目录 |
| 深层目录新增1文件 | < 5s | 需要遍历路径 |
| 10个目录各新增1文件 | < 10s | 批量处理 |

### PB-003: 内存使用

- 峰值内存增长 < 50MB
- 无内存泄漏（长时间运行后内存稳定）

---

## 自动化测试建议

### 单元测试

```dart
// test/features/video/data/services/video_scanner_service_test.dart

void main() {
  group('IncrementalSync', () {
    late VideoScannerService scannerService;
    late MockVideoDatabaseService mockDbService;
    late MockNasFileSystem mockFileSystem;

    setUp(() {
      mockDbService = MockVideoDatabaseService();
      mockFileSystem = MockNasFileSystem();
      scannerService = VideoScannerService(mockDbService);
    });

    test('should skip unchanged root directory', () async {
      // Arrange
      when(mockDbService.getScanProgressItem(any, any)).thenAnswer(
        (_) async => ScanProgressItem(
          dirModifiedTime: DateTime(2024, 1, 1),
          // ...
        ),
      );
      when(mockFileSystem.getFileInfo(any)).thenAnswer(
        (_) async => FileItem(
          modifiedTime: DateTime(2024, 1, 1), // 相同时间
          // ...
        ),
      );

      // Act
      final result = await scannerService.incrementalSync(...);

      // Assert
      expect(result?.hasChanges, false);
      expect(result?.unchangedDirectories, 1);
    });

    test('should detect new files', () async {
      // ...
    });

    test('should handle interruption gracefully', () async {
      // ...
    });
  });
}
```

### 集成测试

```dart
// integration_test/incremental_sync_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full incremental sync flow', (tester) async {
    // 1. 连接真实 NAS
    // 2. 执行全量扫描
    // 3. 添加测试文件
    // 4. 执行增量同步
    // 5. 验证结果
    // 6. 清理测试文件
  });
}
```

---

## 手动测试检查清单

### 功能测试
- [ ] TC-001: 无变化场景
- [ ] TC-002: 新增文件
- [ ] TC-003: 删除文件
- [ ] TC-004: 文件修改
- [ ] TC-005: 新增目录
- [ ] TC-006: 删除目录
- [ ] TC-007: 深层目录变化

### 边界测试
- [ ] TC-008: 中断测试
- [ ] TC-009: 超时测试
- [ ] TC-010: 目录数量上限
- [ ] TC-011: 并发调用

### 异常测试
- [ ] TC-012: 连接断开
- [ ] TC-013: 网络异常

### 兼容性测试
- [ ] TC-014: 空目录
- [ ] TC-015: 隐藏文件/目录
- [ ] TC-016: 特殊字符路径
- [ ] TC-017: 大文件
- [ ] TC-018: 数据库迁移

### 性能测试
- [ ] PB-001: 无变化场景性能
- [ ] PB-002: 单目录变化性能
- [ ] PB-003: 内存使用

---

## 问题记录模板

| 编号 | 测试用例 | 问题描述 | 严重程度 | 状态 |
|-----|---------|---------|---------|-----|
| BUG-001 | TC-xxx | | P0/P1/P2 | 待修复 |

---

## 版本历史

| 版本 | 日期 | 作者 | 说明 |
|-----|-----|-----|-----|
| 1.0 | 2024-12-30 | Claude | 初始版本 |
