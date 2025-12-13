import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Epub Viewer Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final epubController = EpubController();

  var textSelectionCfi = '';

  bool isLoading = true;

  double progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildChapterDrawer(),
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search not implemented')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
          child: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.transparent,
          ),
          Expanded(
            child: Stack(
              children: [
                EpubViewer(
                  initialCfi: 'epubcfi(/6/20!/4/2[introduction]/2[c1_h]/1:0)',
                  epubSource: EpubSource.fromUrl(
                      'https://github.com/IDPF/epub3-samples/releases/download/20230704/accessible_epub_3.epub'),
                  epubController: epubController,
                  displaySettings: EpubDisplaySettings(
                      flow: EpubFlow.paginated,
                      useSnapAnimationAndroid: false,
                      snap: true,
                      theme: EpubTheme.light(),
                      allowScriptedContent: true),
                  selectionContextMenu: ContextMenu(
                    menuItems: [
                      ContextMenuItem(
                        title: "Highlight",
                        id: 1,
                        action: () async {
                          epubController.addHighlight(cfi: textSelectionCfi);
                        },
                      ),
                    ],
                    settings: ContextMenuSettings(
                        hideDefaultSystemContextMenuItems: true),
                  ),
                  onChaptersLoaded: (chapters) {
                    setState(() {
                      isLoading = false;
                    });
                  },
                  onEpubLoaded: () async {
                    if (kDebugMode) {
                      debugPrint('Epub loaded');
                    }
                  },
                  onRelocated: (value) {
                    if (kDebugMode) {
                      debugPrint("Reloacted to $value");
                    }
                    setState(() {
                      progress = value.progress;
                    });
                  },
                  onAnnotationClicked: (cfi, data) {
                    if (kDebugMode) {
                      debugPrint("Annotation clicked $cfi");
                    }
                  },
                  onTextSelected: (epubTextSelection) {
                    textSelectionCfi = epubTextSelection.selectionCfi;
                    if (kDebugMode) {
                      debugPrint(textSelectionCfi);
                    }
                  },
                  onLocationLoaded: () {
                    if (kDebugMode) {
                      debugPrint('on location loaded');
                    }
                  },
                  onSelection:
                      (selectedText, cfiRange, selectionRect, viewRect) {
                    if (kDebugMode) {
                      debugPrint("On selection changes");
                    }
                  },
                  onDeselection: () {
                    if (kDebugMode) {
                      debugPrint("on delection");
                    }
                  },
                  onSelectionChanging: () {
                    if (kDebugMode) {
                      debugPrint("on slection chnages");
                    }
                  },
                  onTouchDown: (x, y) {
                    if (kDebugMode) {
                      debugPrint("Touch down at $x , $y");
                    }
                  },
                  onTouchUp: (x, y) {
                    if (kDebugMode) {
                      debugPrint("Touch up at $x , $y");
                    }
                  },
                  selectAnnotationRange: true,
                ),
                Visibility(
                  visible: isLoading,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _buildChapterDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Text('Chapters', style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          ListTile(
            title: const Text('Table of Contents'),
            onTap: () async {
              final chapters = await epubController.parseChapters();
              if (!mounted) return;
              Navigator.pop(context);
              if (chapters.isNotEmpty) {
                epubController.display(cfi: chapters.first.href);
              }
            },
          ),
        ],
      ),
    );
  }
}
