import 'dart:async';

import 'package:flutter_epub_viewer/src/epub_metadata.dart';
import 'package:flutter_epub_viewer/src/models/epub_display_settings.dart';
import 'package:flutter_epub_viewer/src/models/epub_location.dart';
import 'package:flutter_epub_viewer/src/models/epub_search_result.dart';
import 'package:flutter_epub_viewer/src/models/epub_text_extract_res.dart';
import 'package:flutter_epub_viewer/src/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'models/epub_chapter.dart';
import 'models/epub_theme.dart';

class EpubController {
  InAppWebViewController? webViewController;

  ///List of chapters from epub
  List<EpubChapter> _chapters = [];

  void setWebViewController(InAppWebViewController controller) {
    webViewController = controller;
  }

  ///Move epub view to specific area using Cfi string, XPath/XPointer, or chapter href
  void display({
    ///Cfi String, XPath/XPointer string, or chapter href of the desired location
    ///If the string starts with '/', it will be treated as XPath/XPointer
    required String cfi,
  }) {
    checkEpubLoaded();
    // Escape quotes in the string
    final escapedCfi = cfi.replaceAll('"', '\\"');
    webViewController?.evaluateJavascript(source: 'toCfi("$escapedCfi")');
  }

  ///Moves to next page in epub view
  void next() {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'next()');
  }

  ///Moves to previous page in epub view
  void prev() {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'previous()');
  }

  ///Returns current location of epub viewer
  Future<EpubLocation> getCurrentLocation() async {
    checkEpubLoaded();
    final result = await webViewController?.evaluateJavascript(source: 'getCurrentLocation()');

    if (result == null) {
      throw Exception("Epub locations not loaded");
    }

    return EpubLocation.fromJson(result);
  }

  ///Returns list of [EpubChapter] from epub,
  /// should be called after onChaptersLoaded callback, otherwise returns empty list
  List<EpubChapter> getChapters() {
    checkEpubLoaded();
    return _chapters;
  }

  Future<List<EpubChapter>> parseChapters() async {
    if (_chapters.isNotEmpty) return _chapters;

    checkEpubLoaded();

    final result = await webViewController!.evaluateJavascript(source: 'getChapters()');

    _chapters = parseChapterList(result);
    return _chapters;
  }

  Future<EpubMetadata> getMetadata() async {
    checkEpubLoaded();
    final result = await webViewController!.evaluateJavascript(source: 'getBookInfo()');
    return EpubMetadata.fromJson(result);
  }

  Completer searchResultCompleter = Completer<List<EpubSearchResult>>();

  ///Search in epub using query string
  ///Returns a list of [EpubSearchResult]
  Future<List<EpubSearchResult>> search({
    ///Search query string
    required String query,
    // bool optimized = false,
  }) async {
    searchResultCompleter = Completer<List<EpubSearchResult>>();
    if (query.isEmpty) return [];
    checkEpubLoaded();
    await webViewController?.evaluateJavascript(source: 'searchInBook("$query")');
    return await searchResultCompleter.future;
  }

  ///Adds a highlight to epub viewer
  void addHighlight({
    ///Cfi string of the desired location
    required String cfi,

    ///Color of the highlight
    Color color = Colors.yellow,

    ///Opacity of the highlight
    double opacity = 0.3,
  }) {
    final colorHex = color.toHex();
    final opacityString = opacity.toString();
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'addHighlight("$cfi", "$colorHex", "$opacityString")');
  }

  ///Adds a underline annotation
  void addUnderline({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'addUnderLine("$cfi")');
  }

  ///Adds a mark annotation
  // addMark({required String cfi}) {
  //   checkEpubLoaded();
  //   webViewController?.evaluateJavascript(source: 'addMark("$cfi")');
  // }

  ///Removes a highlight from epub viewer
  void removeHighlight({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'removeHighlight("$cfi")');
  }

  ///Removes a underline from epub viewer
  void removeUnderline({required String cfi}) {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'removeUnderLine("$cfi")');
  }

  ///Removes a mark from epub viewer
  // removeMark({required String cfi}) {
  //   checkEpubLoaded();
  //   webViewController?.evaluateJavascript(source: 'removeMark("$cfi")');
  // }

  ///Clears any active text selection in the epub viewer
  void clearSelection() {
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'clearSelection()');
  }

  ///Set [EpubSpread] value
  Future<void> setSpread({required EpubSpread spread}) async {
    await webViewController?.evaluateJavascript(source: 'setSpread("$spread")');
  }

  ///Set [EpubFlow] value
  Future<void> setFlow({required EpubFlow flow}) async {
    await webViewController?.evaluateJavascript(source: 'setFlow("$flow")');
  }

  ///Set [EpubManager] value
  Future<void> setManager({required EpubManager manager}) async {
    await webViewController?.evaluateJavascript(source: 'setManager("$manager")');
  }

  ///Adjust font size in epub viewer
  Future<void> setFontSize({required double fontSize}) async {
    await webViewController?.evaluateJavascript(source: 'setFontSize("$fontSize")');
  }

  Future<void> updateTheme({required EpubTheme theme}) async {
    String? foregroundColor = theme.foregroundColor?.toHex();
    await webViewController?.evaluateJavascript(source: 'updateTheme("","$foregroundColor")');
  }

  Completer<EpubTextExtractRes>? _pageTextCompleter;
  Completer<Rect?> cfiRectCompleter = Completer<Rect?>();

  /// Safely complete the page text completer
  void completePageText(EpubTextExtractRes result) {
    if (_pageTextCompleter != null && !_pageTextCompleter!.isCompleted) {
      _pageTextCompleter!.complete(result);
    }
  }

  ///Extract text from a given cfi range,
  Future<EpubTextExtractRes> extractText({
    ///start cfi
    required String startCfi,

    ///end cfi
    required String endCfi,
  }) async {
    checkEpubLoaded();
    // Complete previous completer if it exists and isn't completed
    if (_pageTextCompleter != null && !_pageTextCompleter!.isCompleted) {
      try {
        _pageTextCompleter!.completeError('Cancelled by new request');
      } catch (e) {
        // Ignore if already completed
      }
    }
    _pageTextCompleter = Completer<EpubTextExtractRes>();
    await webViewController?.evaluateJavascript(source: 'getTextFromCfi("$startCfi","$endCfi")');
    return _pageTextCompleter!.future;
  }

  ///Get bounding rectangle for a given CFI range
  ///Returns WebView-relative coordinates in pixels, or null if rect cannot be determined
  Future<Rect?> getRectFromCfi(String cfiRange) async {
    checkEpubLoaded();
    cfiRectCompleter = Completer<Rect?>();
    // Escape quotes in the CFI string
    final escapedCfi = cfiRange.replaceAll('"', '\\"');
    await webViewController?.evaluateJavascript(source: 'getRectFromCfi("$escapedCfi")');
    return cfiRectCompleter.future;
  }

  ///Extracts text content from current page
  Future<EpubTextExtractRes> extractCurrentPageText() async {
    checkEpubLoaded();
    // Complete previous completer if it exists and isn't completed
    if (_pageTextCompleter != null && !_pageTextCompleter!.isCompleted) {
      try {
        _pageTextCompleter!.completeError('Cancelled by new request');
      } catch (e) {
        // Ignore if already completed
      }
    }
    _pageTextCompleter = Completer<EpubTextExtractRes>();
    await webViewController?.evaluateJavascript(source: 'getCurrentPageText()');
    return _pageTextCompleter!.future;
  }

  ///Given a percentage moves to the corresponding page
  ///Progress percentage should be between 0.0 and 1.0
  void toProgressPercentage(double progressPercent) {
    assert(progressPercent >= 0.0 && progressPercent <= 1.0, 'Progress percentage must be between 0.0 and 1.0');
    checkEpubLoaded();
    webViewController?.evaluateJavascript(source: 'toProgress($progressPercent)');
  }

  ///Moves to the first page of the epub
  void moveToFistPage() {
    toProgressPercentage(0.0);
  }

  ///Moves to the last page of the epub
  void moveToLastPage() {
    toProgressPercentage(1.0);
  }

  void checkEpubLoaded() {
    if (webViewController == null) {
      throw Exception("Epub viewer is not loaded, wait for onEpubLoaded callback");
    }
  }
}

class LocalServerController {
  final InAppLocalhostServer _localhostServer = InAppLocalhostServer(
    documentRoot: 'packages/flutter_epub_viewer/lib/assets/webpage',
  );

  Future<void> initServer() async {
    if (_localhostServer.isRunning()) return;
    await _localhostServer.start();
  }

  Future<void> disposeServer() async {
    if (!_localhostServer.isRunning()) return;
    await _localhostServer.close();
  }
}
