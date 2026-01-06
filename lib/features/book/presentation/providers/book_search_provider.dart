import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/sources/book_content_service.dart';
import 'package:my_nas/features/book/data/services/sources/book_search_service.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_search_provider.g.dart';

/// 书籍搜索服务 Provider
@riverpod
BookSearchService bookSearchService(Ref ref) {
  return BookSearchService.instance;
}

/// 书籍内容服务 Provider
@riverpod
BookContentService bookContentService(Ref ref) {
  return BookContentService.instance;
}

/// 搜索状态
class BookSearchState {
  const BookSearchState({
    this.keyword = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.isComplete = false,
  });

  final String keyword;
  final List<OnlineBook> results;
  final bool isLoading;
  final String? error;
  final bool isComplete;

  BookSearchState copyWith({
    String? keyword,
    List<OnlineBook>? results,
    bool? isLoading,
    String? error,
    bool? isComplete,
  }) =>
      BookSearchState(
        keyword: keyword ?? this.keyword,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isComplete: isComplete ?? this.isComplete,
      );
}

/// 书籍搜索状态管理 Provider
@riverpod
class BookSearch extends _$BookSearch {
  StreamSubscription<OnlineBook>? _subscription;

  @override
  BookSearchState build() {
    ref.onDispose(() {
      _subscription?.cancel();
    });
    return const BookSearchState();
  }

  /// 开始搜索
  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;

    // 取消之前的搜索
    await _subscription?.cancel();

    // 重置状态
    state = BookSearchState(
      keyword: keyword,
      isLoading: true,
    );

    final searchService = ref.read(bookSearchServiceProvider);
    final results = <OnlineBook>[];
    final seen = <String>{};

    try {
      _subscription = searchService.search(keyword).listen(
        (book) {
          // 去重
          final key = book.uniqueKey;
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(book);
            // 更新状态
            state = state.copyWith(results: List.from(results));
          }
        },
        onError: (Object e) {
          state = state.copyWith(
            isLoading: false,
            error: e.toString(),
          );
        },
        onDone: () {
          state = state.copyWith(
            isLoading: false,
            isComplete: true,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 取消搜索
  void cancel() {
    _subscription?.cancel();
    state = state.copyWith(isLoading: false);
  }

  /// 清空结果
  void clear() {
    _subscription?.cancel();
    state = const BookSearchState();
  }
}

/// 书籍详情 Provider
@riverpod
Future<BookInfo?> bookInfo(Ref ref, OnlineBook book) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getBookInfo(book);
}

/// 章节目录 Provider
@riverpod
Future<List<OnlineChapter>> chapterList(
  Ref ref,
  BookSource source,
  String bookUrl, {
  String? tocUrl,
}) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getChapterList(source, bookUrl, tocUrl: tocUrl);
}

/// 章节内容 Provider
@riverpod
Future<String?> chapterContent(
  Ref ref,
  BookSource source,
  OnlineChapter chapter,
) async {
  final contentService = ref.watch(bookContentServiceProvider);
  return contentService.getChapterContent(source, chapter);
}
