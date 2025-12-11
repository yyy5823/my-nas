import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// 下载器列表页面
class DownloaderListPage extends StatelessWidget {
  const DownloaderListPage({super.key});

  @override
  Widget build(BuildContext context) => const ServiceSourcesPage(
        title: '下载器',
        category: SourceCategory.downloadTools,
        emptyIcon: Icons.download_rounded,
        emptyTitle: '尚未添加下载器',
        emptySubtitle: '添加 qBittorrent、Transmission 或 Aria2\n来管理您的下载任务',
      );
}
