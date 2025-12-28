package com.kkape.mynas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.kkape.mynas.widgets.WidgetDataChannel
import com.kkape.mynas.dynamicisland.DynamicIslandChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 Chromaprint 指纹插件
        flutterEngine.plugins.add(ChromaprintPlugin())

        // 注册小组件数据通道
        WidgetDataChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)

        // 注册灵动岛通道
        flutterEngine.plugins.add(DynamicIslandChannel())

        // 注册显示能力检测插件 (HDR)
        flutterEngine.plugins.add(DisplayCapabilityPlugin())

        // 注册音频能力检测插件 (直通)
        flutterEngine.plugins.add(AudioCapabilityPlugin())
    }
}
