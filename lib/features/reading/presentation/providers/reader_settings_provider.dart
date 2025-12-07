import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

/// 图书阅读设置 Provider
final bookReaderSettingsProvider =
    StateNotifierProvider<BookReaderSettingsNotifier, BookReaderSettings>(
  (ref) => BookReaderSettingsNotifier(),
);

/// 漫画阅读设置 Provider
final comicReaderSettingsProvider =
    StateNotifierProvider<ComicReaderSettingsNotifier, ComicReaderSettings>(
  (ref) => ComicReaderSettingsNotifier(),
);

/// 图书阅读设置 Notifier
class BookReaderSettingsNotifier extends StateNotifier<BookReaderSettings> {
  BookReaderSettingsNotifier() : super(const BookReaderSettings()) {
    _load();
  }

  final _service = ReaderSettingsService();

  Future<void> _load() async {
    await _service.init();
    state = _service.getBookSettings();
  }

  Future<void> _save() async {
    await _service.saveBookSettings(state);
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(12.0, 36.0));
    _save();
  }

  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height.clamp(1.0, 3.0));
    _save();
  }

  void setParagraphSpacing(double spacing) {
    state = state.copyWith(paragraphSpacing: spacing.clamp(0.0, 3.0));
    _save();
  }

  void setHorizontalPadding(double padding) {
    state = state.copyWith(horizontalPadding: padding.clamp(8.0, 64.0));
    _save();
  }

  void setVerticalPadding(double padding) {
    state = state.copyWith(verticalPadding: padding.clamp(8.0, 64.0));
    _save();
  }

  void setTheme(BookReaderTheme theme) {
    state = state.copyWith(theme: theme);
    _save();
  }

  void setPageTurnMode(BookPageTurnMode mode) {
    state = state.copyWith(pageTurnMode: mode);
    _save();
  }

  void setKeepScreenOn({required bool value}) {
    state = state.copyWith(keepScreenOn: value);
    _save();
  }

  void setTapToTurn({required bool value}) {
    state = state.copyWith(tapToTurn: value);
    _save();
  }

  void setVolumeKeyTurn({required bool value}) {
    state = state.copyWith(volumeKeyTurn: value);
    _save();
  }

  void setShowProgress({required bool value}) {
    state = state.copyWith(showProgress: value);
    _save();
  }

  void setFontFamily(String? fontFamily) {
    state = state.copyWith(fontFamily: fontFamily);
    _save();
  }
}

/// 漫画阅读设置 Notifier
class ComicReaderSettingsNotifier extends StateNotifier<ComicReaderSettings> {
  ComicReaderSettingsNotifier() : super(const ComicReaderSettings()) {
    _load();
  }

  final _service = ReaderSettingsService();

  Future<void> _load() async {
    await _service.init();
    state = _service.getComicSettings();
  }

  Future<void> _save() async {
    await _service.saveComicSettings(state);
  }

  void setReadingMode(ComicReadingMode mode) {
    state = state.copyWith(readingMode: mode);
    _save();
  }

  void setReadingDirection(ComicReadingDirection direction) {
    state = state.copyWith(readingDirection: direction);
    _save();
  }

  void setScaleMode(ComicScaleMode mode) {
    state = state.copyWith(scaleMode: mode);
    _save();
  }

  void setBackgroundColor(ComicBackgroundColor color) {
    state = state.copyWith(backgroundColor: color);
    _save();
  }

  void setWebtoonPageGap(double gap) {
    state = state.copyWith(webtoonPageGap: gap.clamp(0.0, 32.0));
    _save();
  }

  void setKeepScreenOn({required bool value}) {
    state = state.copyWith(keepScreenOn: value);
    _save();
  }

  void setTapToTurn({required bool value}) {
    state = state.copyWith(tapToTurn: value);
    _save();
  }

  void setVolumeKeyTurn({required bool value}) {
    state = state.copyWith(volumeKeyTurn: value);
    _save();
  }

  void setShowPageNumber({required bool value}) {
    state = state.copyWith(showPageNumber: value);
    _save();
  }

  void setPreloadPages(int count) {
    state = state.copyWith(preloadPages: count.clamp(0, 5));
    _save();
  }

  void setDoubleTapToZoom({required bool value}) {
    state = state.copyWith(doubleTapToZoom: value);
    _save();
  }
}
