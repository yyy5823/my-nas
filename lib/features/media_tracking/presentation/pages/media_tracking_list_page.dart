import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// 媒体追踪列表页面
class MediaTrackingListPage extends StatelessWidget {
  const MediaTrackingListPage({super.key});

  @override
  Widget build(BuildContext context) => const ServiceSourcesPage(
        title: '媒体追踪',
        category: SourceCategory.mediaTracking,
        emptyIcon: Icons.track_changes_rounded,
        emptyTitle: '尚未添加追踪工具',
        emptySubtitle: '添加 Trakt 等追踪工具\n来同步您的观看记录和媒体状态',
      );
}
