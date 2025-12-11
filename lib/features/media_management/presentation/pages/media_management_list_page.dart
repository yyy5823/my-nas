import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// 媒体管理列表页面
class MediaManagementListPage extends StatelessWidget {
  const MediaManagementListPage({super.key});

  @override
  Widget build(BuildContext context) => const ServiceSourcesPage(
        title: '媒体管理',
        category: SourceCategory.mediaManagement,
        emptyIcon: Icons.construction_rounded,
        emptyTitle: '尚未添加管理工具',
        emptySubtitle: '添加 NASTool、MoviePilot 等工具\n来自动化管理您的媒体库',
      );
}
