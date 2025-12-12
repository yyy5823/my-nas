import 'package:flutter/material.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/trakt_connection_page.dart';

/// 媒体追踪列表页面
///
/// 由于当前只有 Trakt 一个媒体追踪服务，直接显示 Trakt 连接页面
class MediaTrackingListPage extends StatelessWidget {
  const MediaTrackingListPage({super.key});

  @override
  Widget build(BuildContext context) => const TraktConnectionPage();
}
