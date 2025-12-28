package com.kkape.mynas

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.kkape.mynas.widgets.WidgetDataChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 Chromaprint 指纹插件
        flutterEngine.plugins.add(ChromaprintPlugin())

        // 注册小组件数据通道
        WidgetDataChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
