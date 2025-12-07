import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/book_cover_service.dart';

/// 图书封面服务 Provider
final bookCoverServiceProvider = Provider<BookCoverService>((ref) {
  final service = BookCoverService()..init();
  return service;
});
