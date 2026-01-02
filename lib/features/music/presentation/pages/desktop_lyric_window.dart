import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';

import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';
import 'package:my_nas/features/music/presentation/widgets/desktop_lyric_content.dart';

/// 桌面歌词窗口入口
/// 作为子窗口的 main 函数调用
Future<void> desktopLyricMain(List<String> args) async {
  // 解析窗口 ID 和参数
  final windowId = int.parse(args[0]);
  final arguments = args.length > 1 ? jsonDecode(args[1]) as Map<String, dynamic> : <String, dynamic>{};

  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  // 初始化透明效果（仅 Windows）
  if (Platform.isWindows) {
    await Window.initialize();
  }

  // 解析设置
  final settingsJson = arguments['settings'] as Map<String, dynamic>?;
  final settings = settingsJson != null
      ? DesktopLyricSettings.fromJson(settingsJson)
      : const DesktopLyricSettings();

  // 配置窗口属性
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(settings.windowWidth, settings.windowHeight),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: settings.alwaysOnTop,
    ),
    () async {
      // 设置透明效果
      if (Platform.isWindows) {
        await Window.setEffect(
          effect: WindowEffect.transparent,
          color: Colors.transparent,
        );
      }
      await windowManager.show();
    },
  );

  runApp(DesktopLyricApp(
    windowId: windowId,
    initialSettings: settings,
  ));
}

/// 桌面歌词应用
class DesktopLyricApp extends StatelessWidget {
  const DesktopLyricApp({
    super.key,
    required this.windowId,
    required this.initialSettings,
  });

  final int windowId;
  final DesktopLyricSettings initialSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: DesktopLyricWindow(
        windowId: windowId,
        initialSettings: initialSettings,
      ),
    );
  }
}

/// 桌面歌词窗口
class DesktopLyricWindow extends StatefulWidget {
  const DesktopLyricWindow({
    super.key,
    required this.windowId,
    required this.initialSettings,
  });

  final int windowId;
  final DesktopLyricSettings initialSettings;

  @override
  State<DesktopLyricWindow> createState() => _DesktopLyricWindowState();
}

class _DesktopLyricWindowState extends State<DesktopLyricWindow>
    with WindowListener {
  late DesktopLyricSettings _settings;
  String? _currentLyric;
  String? _currentTranslation;
  String? _nextLyric;
  String? _nextTranslation;
  bool _isPlaying = false;
  bool _isHovering = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    windowManager.addListener(this);
    _setupMethodHandler();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _setupMethodHandler() {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'updateData') {
        final data = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        _handleUpdateData(data);
      }
      return null;
    });
  }

  void _handleUpdateData(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'updateLyric':
        final currentLine = data['currentLine'] as Map<String, dynamic>?;
        final nextLine = data['nextLine'] as Map<String, dynamic>?;
        setState(() {
          _currentLyric = currentLine?['text'] as String?;
          _currentTranslation = currentLine?['translation'] as String?;
          _nextLyric = nextLine?['text'] as String?;
          _nextTranslation = nextLine?['translation'] as String?;
          _isPlaying = data['isPlaying'] as bool? ?? false;
        });
        break;

      case 'updatePlayingState':
        setState(() {
          _isPlaying = data['isPlaying'] as bool? ?? false;
        });
        break;

      case 'updateSettings':
        final settingsJson = data['settings'] as Map<String, dynamic>?;
        if (settingsJson != null) {
          setState(() {
            _settings = DesktopLyricSettings.fromJson(settingsJson);
          });
          _applySettings();
        }
        break;
    }
  }

  Future<void> _applySettings() async {
    await windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
    await windowManager.setOpacity(_settings.opacity);
  }

  Future<void> _closeWindow() async {
    await windowManager.close();
  }

  Future<void> _savePosition() async {
    final position = await windowManager.getPosition();
    // 通知主窗口保存位置
    await DesktopMultiWindow.invokeMethod(
      0, // 主窗口 ID
      'saveDesktopLyricPosition',
      jsonEncode({
        'x': position.dx,
        'y': position.dy,
      }),
    );
  }

  @override
  void onWindowMove() {
    if (!_isDragging) {
      _isDragging = true;
    }
  }

  @override
  void onWindowMoved() {
    _isDragging = false;
    _savePosition();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onPanStart: _settings.lockPosition ? null : (_) => windowManager.startDragging(),
          child: DesktopLyricContent(
            currentLyric: _currentLyric,
            currentTranslation: _currentTranslation,
            nextLyric: _nextLyric,
            nextTranslation: _nextTranslation,
            isPlaying: _isPlaying,
            isHovering: _isHovering,
            settings: _settings,
            onClose: _closeWindow,
            onLockToggle: () {
              setState(() {
                _settings = _settings.copyWith(lockPosition: !_settings.lockPosition);
              });
            },
          ),
        ),
      ),
    );
  }
}
