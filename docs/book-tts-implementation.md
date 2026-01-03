# 图书朗读功能 (TTS) 实现方案

## 1. 概述

本文档详细说明如何在图书模块中实现朗读功能，支持不同音色、性别选择，以及朗读内容的实时高亮标注。

---

## 2. 功能需求

### 2.1 核心功能

- **文本朗读**: 将章节/段落内容转为语音播放
- **音色选择**: 支持多种音色 (男声/女声/童声等)
- **语速调节**: 0.5x - 2.0x 速度调整
- **音调调节**: 高/中/低音调
- **朗读高亮**: 实时标注当前朗读位置
- **后台播放**: 支持后台/锁屏继续朗读

### 2.2 用户交互

```
┌─────────────────────────────────────┐
│  朗读控制栏                          │
├─────────────────────────────────────┤
│  ◀◀   ▶/❚❚   ▶▶   🔊   🎤   ⚙️    │
│  上段  播放   下段  音量  音色  设置  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  音色选择面板                        │
├─────────────────────────────────────┤
│  👨 标准男声    👩 标准女声          │
│  👨‍🦱 磁性男声    👩‍🦰 温柔女声          │
│  🧒 可爱童声    🤖 机器人声          │
│  📖 朗诵风格    🎭 戏剧风格          │
└─────────────────────────────────────┘
```

---

## 3. 技术实现方案

### 3.1 TTS 引擎选择

#### 方案对比

| 方案 | 优点 | 缺点 | 推荐场景 |
|-----|-----|-----|---------|
| **flutter_tts** | 跨平台、离线、免费 | 音色有限、依赖系统 | 基础朗读 |
| **在线 TTS API** | 音色丰富、效果好 | 需联网、有成本 | 高质量朗读 |
| **混合方案** | 兼顾质量与离线 | 实现复杂 | 推荐 ✅ |

#### 推荐: 混合方案

```dart
class TTSService {
  // 优先使用在线 TTS (如有配置)
  // 降级到本地 TTS 引擎
  
  Future<void> speak(String text) async {
    if (useOnlineTTS && hasNetwork) {
      await _speakOnline(text);
    } else {
      await _speakLocal(text);
    }
  }
}
```

### 3.2 flutter_tts 集成

```yaml
dependencies:
  flutter_tts: ^4.0.2
```

```dart
import 'package:flutter_tts/flutter_tts.dart';

class LocalTTSService {
  final FlutterTts _tts = FlutterTts();
  
  Future<void> init() async {
    // 设置语言
    await _tts.setLanguage('zh-CN');
    
    // 获取可用音色
    final voices = await _tts.getVoices;
    
    // 设置回调
    _tts.setStartHandler(() => print('开始朗读'));
    _tts.setCompletionHandler(() => print('朗读完成'));
    _tts.setProgressHandler((text, start, end, word) {
      // 关键: 用于高亮当前朗读位置
      _onProgress(start, end, word);
    });
  }
  
  Future<void> setVoice(Map<String, String> voice) async {
    await _tts.setVoice(voice);
  }
  
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }
  
  Future<void> pause() async {
    await _tts.pause();
  }
  
  Future<void> stop() async {
    await _tts.stop();
  }
}
```

### 3.3 在线 TTS API 集成 (可选)

支持的在线 TTS 服务:

| 服务商 | 特点 | 计费 |
|-------|-----|-----|
| **Azure TTS** | 神经网络语音、效果极佳 | 按字符计费 |
| **Google Cloud TTS** | 多语言、WaveNet 音色 | 按字符计费 |
| **阿里云 TTS** | 中文效果好 | 按调用次数 |
| **讯飞 TTS** | 中文最佳、情感语音 | 按调用次数 |

```dart
class OnlineTTSService {
  // 以 Azure 为例
  Future<Uint8List> synthesize(String text, String voiceName) async {
    final response = await dio.post(
      'https://eastus.tts.speech.microsoft.com/cognitiveservices/v1',
      options: Options(headers: {
        'Ocp-Apim-Subscription-Key': apiKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-16khz-32kbitrate-mono-mp3',
      }),
      data: '''
        <speak version="1.0" xml:lang="zh-CN">
          <voice name="$voiceName">$text</voice>
        </speak>
      ''',
    );
    return response.data;
  }
}
```

---

## 4. 朗读高亮实现

### 4.1 核心原理

```
文本: "这是第一段内容。这是第二句话。"
         ├───────────┤
           当前朗读位置 (高亮显示)
```

### 4.2 实现方案

#### 方案 A: 基于 TTS 进度回调 (推荐)

```dart
class ReadingHighlightController extends ChangeNotifier {
  int _currentStart = 0;
  int _currentEnd = 0;
  String _currentWord = '';
  
  void onTTSProgress(String text, int start, int end, String word) {
    _currentStart = start;
    _currentEnd = end;
    _currentWord = word;
    notifyListeners();
  }
  
  TextSpan buildHighlightedText(String fullText) {
    if (_currentEnd <= 0) {
      return TextSpan(text: fullText);
    }
    
    return TextSpan(
      children: [
        // 已读部分
        TextSpan(
          text: fullText.substring(0, _currentStart),
          style: const TextStyle(color: Colors.grey),
        ),
        // 当前朗读部分 (高亮)
        TextSpan(
          text: fullText.substring(_currentStart, _currentEnd),
          style: TextStyle(
            color: Colors.white,
            backgroundColor: Colors.blue.withValues(alpha: 0.5),
            fontWeight: FontWeight.bold,
          ),
        ),
        // 未读部分
        TextSpan(
          text: fullText.substring(_currentEnd),
          style: const TextStyle(color: Colors.black),
        ),
      ],
    );
  }
}
```

#### 方案 B: 基于时间估算

```dart
class TimeBasedHighlight {
  // 根据语速和文本长度估算进度
  // 适用于不支持进度回调的 TTS 引擎
  
  double estimateProgress(String text, double speechRate, Duration elapsed) {
    // 平均每分钟朗读字数 (中文约 200-300 字)
    const wordsPerMinute = 250.0;
    final adjustedWPM = wordsPerMinute * speechRate;
    final totalDuration = text.length / adjustedWPM * 60;
    return elapsed.inSeconds / totalDuration;
  }
}
```

### 4.3 段落级高亮

```dart
class ParagraphHighlighter extends StatefulWidget {
  final List<String> paragraphs;
  final int currentParagraphIndex;
  final int currentCharIndex;
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: paragraphs.length,
      itemBuilder: (context, index) {
        final isCurrentParagraph = index == currentParagraphIndex;
        
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            // 当前段落背景高亮
            color: isCurrentParagraph 
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: isCurrentParagraph
              ? _buildHighlightedParagraph(paragraphs[index])
              : Text(paragraphs[index]),
        );
      },
    );
  }
  
  Widget _buildHighlightedParagraph(String text) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text.substring(0, currentCharIndex),
            style: const TextStyle(color: Colors.grey),
          ),
          TextSpan(
            text: text.substring(currentCharIndex, min(currentCharIndex + 10, text.length)),
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: text.substring(min(currentCharIndex + 10, text.length)),
          ),
        ],
      ),
    );
  }
}
```

---

## 5. 音色管理

### 5.1 音色模型

```dart
enum VoiceGender { male, female, neutral }

class TTSVoice {
  final String id;
  final String name;
  final String displayName;
  final VoiceGender gender;
  final String language;
  final bool isOnline;
  final String? previewUrl;
  
  const TTSVoice({
    required this.id,
    required this.name,
    required this.displayName,
    required this.gender,
    required this.language,
    this.isOnline = false,
    this.previewUrl,
  });
}
```

### 5.2 预设音色列表

```dart
class VoicePresets {
  static const List<TTSVoice> chineseVoices = [
    // 本地音色 (flutter_tts)
    TTSVoice(
      id: 'zh-CN-local-male',
      name: 'zh-CN-default',
      displayName: '标准男声',
      gender: VoiceGender.male,
      language: 'zh-CN',
    ),
    TTSVoice(
      id: 'zh-CN-local-female',
      name: 'zh-CN-female',
      displayName: '标准女声',
      gender: VoiceGender.female,
      language: 'zh-CN',
    ),
    
    // 在线音色 (Azure 示例)
    TTSVoice(
      id: 'zh-CN-XiaoxiaoNeural',
      name: 'zh-CN-XiaoxiaoNeural',
      displayName: '晓晓 (甜美女声)',
      gender: VoiceGender.female,
      language: 'zh-CN',
      isOnline: true,
    ),
    TTSVoice(
      id: 'zh-CN-YunxiNeural',
      name: 'zh-CN-YunxiNeural',
      displayName: '云希 (阳光男声)',
      gender: VoiceGender.male,
      language: 'zh-CN',
      isOnline: true,
    ),
    TTSVoice(
      id: 'zh-CN-XiaoyiNeural',
      name: 'zh-CN-XiaoyiNeural',
      displayName: '晓伊 (温柔女声)',
      gender: VoiceGender.female,
      language: 'zh-CN',
      isOnline: true,
    ),
  ];
}
```

### 5.3 音色选择界面

```dart
class VoiceSelector extends StatelessWidget {
  final TTSVoice? selectedVoice;
  final ValueChanged<TTSVoice> onVoiceSelected;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 性别筛选
        Row(
          children: [
            FilterChip(label: Text('全部'), selected: true, onSelected: (_) {}),
            FilterChip(label: Text('男声'), onSelected: (_) {}),
            FilterChip(label: Text('女声'), onSelected: (_) {}),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 音色列表
        Expanded(
          child: ListView.builder(
            itemCount: VoicePresets.chineseVoices.length,
            itemBuilder: (context, index) {
              final voice = VoicePresets.chineseVoices[index];
              final isSelected = voice.id == selectedVoice?.id;
              
              return ListTile(
                leading: Icon(
                  voice.gender == VoiceGender.male 
                      ? Icons.person 
                      : Icons.person_outline,
                ),
                title: Text(voice.displayName),
                subtitle: voice.isOnline 
                    ? const Text('在线音色 (需联网)') 
                    : const Text('本地音色'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 试听按钮
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () => _previewVoice(voice),
                    ),
                    if (isSelected)
                      const Icon(Icons.check, color: Colors.green),
                  ],
                ),
                onTap: () => onVoiceSelected(voice),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

---

## 6. 跨平台差异处理

### 6.1 平台特定配置

| 平台 | 配置要求 |
|-----|---------|
| **Android** | 需要 TTS 引擎 (Google TTS) |
| **iOS** | 使用 AVSpeechSynthesizer |
| **macOS** | 使用 NSSpeechSynthesizer |
| **Windows** | 使用 SAPI 5 |
| **Web** | 使用 Web Speech API |

### 6.2 Android 配置

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE" />
  </intent>
</queries>
```

### 6.3 iOS 配置

```xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

---

## 7. 开发计划

### 第一阶段: 基础朗读 (1 周)
- [ ] 集成 flutter_tts
- [ ] 实现基本播放控制
- [ ] 添加语速/音量调节

### 第二阶段: 高亮功能 (1 周)
- [ ] 实现段落级高亮
- [ ] 实现字符级高亮
- [ ] 自动滚动跟随

### 第三阶段: 音色扩展 (1 周)
- [ ] 本地音色管理
- [ ] 在线 TTS 集成 (可选)
- [ ] 音色试听预览

### 第四阶段: 优化完善 (1 周)
- [ ] 后台播放
- [ ] 定时停止
- [ ] 阅读进度保存

---

## 8. 参考资源

- [flutter_tts](https://pub.dev/packages/flutter_tts) - Flutter TTS 库
- [Azure Speech Services](https://azure.microsoft.com/en-us/services/cognitive-services/text-to-speech/) - 高质量在线 TTS
- [Web Speech API](https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesis) - Web 平台 TTS
