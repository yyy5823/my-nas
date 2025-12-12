import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// PT 站点列表页面
///
/// 用于管理 PT 站点连接（馒头等）
class PTSitesListPage extends StatelessWidget {
  const PTSitesListPage({super.key});

  @override
  Widget build(BuildContext context) => const ServiceSourcesPage(
    title: '站点',
    category: SourceCategory.ptSites,
    emptyIcon: Icons.rss_feed_rounded,
    emptyTitle: '尚未添加站点',
    emptySubtitle: '添加 PT 站点来订阅和下载资源\n目前支持馒头 M-Team',
  );
}
