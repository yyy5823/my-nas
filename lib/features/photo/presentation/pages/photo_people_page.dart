import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/photo/data/services/face_database_service.dart';
import 'package:my_nas/features/photo/data/services/face_recognition_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 人物分组页面
class PhotoPeoplePage extends ConsumerStatefulWidget {
  const PhotoPeoplePage({super.key});

  @override
  ConsumerState<PhotoPeoplePage> createState() => _PhotoPeoplePageState();
}

class _PhotoPeoplePageState extends ConsumerState<PhotoPeoplePage> {
  final FaceDatabaseService _faceDb = FaceDatabaseService();
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _isLoading = true;
  bool _isScanning = false;
  bool _isClustering = false;
  String? _errorMessage;

  List<PersonEntity> _persons = [];
  Map<int, FaceEntity?> _representativeFaces = {};
  ({int totalFaces, int totalPersons, int unassignedFaces})? _stats;

  FaceProcessProgress? _scanProgress;
  StreamSubscription<FaceProcessProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _faceDb.init();
      final persons = await _faceDb.getAllPersons();
      final stats = await _faceDb.getStats();

      // 加载代表头像
      final faces = <int, FaceEntity?>{};
      for (final person in persons) {
        if (person.representativeFaceId != null) {
          final personFaces = await _faceDb.getFacesByPersonId(person.id);
          if (personFaces.isNotEmpty) {
            faces[person.id] = personFaces.firstWhere(
              (f) => f.id == person.representativeFaceId,
              orElse: () => personFaces.first,
            );
          }
        }
      }

      setState(() {
        _persons = persons;
        _representativeFaces = faces;
        _stats = stats;
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startScan() async {
    final connections = ref.read(activeConnectionsProvider);
    final connectedSources = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .toList();

    if (connectedSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先连接到 NAS')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanProgress = null;
    });

    _progressSubscription = _faceService.progressStream.listen((progress) {
      setState(() => _scanProgress = progress);

      if (progress.status == FaceProcessStatus.completed ||
          progress.status == FaceProcessStatus.cancelled ||
          progress.status == FaceProcessStatus.error) {
        setState(() => _isScanning = false);
        _startClustering();
      }
    });

    final fileSystem = connectedSources.first.adapter.fileSystem;
    await _faceService.processAllPhotos(fileSystem);
  }

  Future<void> _startClustering() async {
    setState(() => _isClustering = true);

    try {
      await _faceService.clusterFaces();
      await _loadData();
    } finally {
      setState(() => _isClustering = false);
    }
  }

  void _cancelScan() {
    _faceService.cancel();
  }

  Future<void> _renamePerson(PersonEntity person) async {
    final controller = TextEditingController(text: person.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('命名人物'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入名字',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _faceDb.updatePersonName(person.id, newName);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: const Text('人物'),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (!_isScanning && !_isClustering)
            IconButton(
              onPressed: _startScan,
              icon: const Icon(Icons.face_retouching_natural),
              tooltip: '扫描人脸',
            ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[300])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 扫描进度
        if (_isScanning || _scanProgress != null)
          SliverToBoxAdapter(child: _buildScanProgress(isDark)),

        // 聚类进度
        if (_isClustering)
          SliverToBoxAdapter(child: _buildClusteringProgress(isDark)),

        // 统计信息
        SliverToBoxAdapter(child: _buildStatsCard(isDark)),

        // 人物网格
        if (_persons.isEmpty)
          SliverFillRemaining(child: _buildEmptyState(isDark))
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildPersonCard(
                  _persons[index],
                  isDark,
                ),
                childCount: _persons.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScanProgress(bool isDark) {
    final progress = _scanProgress;

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    progress?.status == FaceProcessStatus.completed
                        ? Icons.check_circle
                        : progress?.status == FaceProcessStatus.error
                            ? Icons.error
                            : Icons.cancel,
                    color: progress?.status == FaceProcessStatus.completed
                        ? Colors.green
                        : progress?.status == FaceProcessStatus.error
                            ? Colors.red
                            : Colors.orange,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isScanning
                        ? '正在扫描人脸...'
                        : progress?.status == FaceProcessStatus.completed
                            ? '扫描完成'
                            : progress?.status == FaceProcessStatus.cancelled
                                ? '已取消'
                                : '扫描出错',
                    style: context.textTheme.titleMedium,
                  ),
                ),
                if (_isScanning)
                  TextButton(
                    onPressed: _cancelScan,
                    child: const Text('取消'),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress.progress),
              const SizedBox(height: 8),
              Text(
                '已处理 ${progress.processed}/${progress.total} 张照片，发现 ${progress.facesFound} 张人脸',
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClusteringProgress(bool isDark) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              '正在分析人物...',
              style: context.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );

  Widget _buildStatsCard(bool isDark) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildStatItem('人物', '${stats.totalPersons}', Icons.person, isDark),
            const SizedBox(width: 24),
            _buildStatItem('人脸', '${stats.totalFaces}', Icons.face, isDark),
            const SizedBox(width: 24),
            _buildStatItem(
              '待分组',
              '${stats.unassignedFaces}',
              Icons.help_outline,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _buildEmptyState(bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.face_retouching_natural,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '还没有发现人物',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角按钮扫描照片中的人脸',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('开始扫描'),
            ),
          ],
        ),
      );

  Widget _buildPersonCard(PersonEntity person, bool isDark) {
    final face = _representativeFaces[person.id];
    final connections = ref.watch(activeConnectionsProvider);

    return GestureDetector(
      onTap: () => _showPersonPhotos(person),
      onLongPress: () => _showPersonOptions(person),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 头像
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: face != null
                    ? _buildFaceImage(face, connections, isDark)
                    : Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 48,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                          ),
                        ),
                      ),
              ),
            ),
            // 名字和数量
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    person.displayName,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${person.photoCount} 张照片',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceImage(
    FaceEntity face,
    Map<String, SourceConnection> connections,
    bool isDark,
  ) {
    final connection = connections[face.photoSourceId];
    final fileSystem = connection?.adapter.fileSystem;

    return StreamImage(
      path: face.photoPath,
      fileSystem: fileSystem,
      placeholder: Container(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        child: const Icon(Icons.person),
      ),
      errorWidget: Container(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        child: const Icon(Icons.person),
      ),
      cacheKey: '${face.photoPath}_face_${face.id}',
    );
  }

  Future<void> _showPersonPhotos(PersonEntity person) async {
    // TODO: 导航到人物照片列表页面
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('查看 ${person.displayName} 的 ${person.photoCount} 张照片')),
    );
  }

  void _showPersonOptions(PersonEntity person) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _renamePerson(person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.merge),
              title: const Text('合并到其他人物'),
              onTap: () {
                Navigator.pop(context);
                _mergePerson(person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除人物', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deletePerson(person);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mergePerson(PersonEntity person) async {
    final otherPersons = _persons.where((p) => p.id != person.id).toList();
    if (otherPersons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有其他人物可以合并')),
      );
      return;
    }

    final targetPerson = await showDialog<PersonEntity>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择要合并到的人物'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherPersons.length,
            itemBuilder: (context, index) {
              final p = otherPersons[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(p.displayName),
                subtitle: Text('${p.photoCount} 张照片'),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (targetPerson != null) {
      await _faceDb.mergePersons(targetPerson.id, person.id);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将 ${person.displayName} 合并到 ${targetPerson.displayName}'),
          ),
        );
      }
    }
  }

  Future<void> _deletePerson(PersonEntity person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${person.displayName} 吗？\n'
            '这只会删除人物分组，不会删除照片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await _faceDb.deletePerson(person.id);
      await _loadData();
    }
  }
}
