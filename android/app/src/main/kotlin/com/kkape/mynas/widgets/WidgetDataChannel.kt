package com.kkape.mynas.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter Method Channel for Widget Data
 * 处理 Flutter 端的小组件数据更新请求
 */
class WidgetDataChannel : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var dataManager: WidgetDataManager

    companion object {
        const val CHANNEL_NAME = "com.kkape.mynas/android_widgets"

        // Broadcast actions for widget updates
        const val ACTION_STORAGE_UPDATE = "com.kkape.mynas.STORAGE_UPDATE"
        const val ACTION_DOWNLOAD_UPDATE = "com.kkape.mynas.DOWNLOAD_UPDATE"
        const val ACTION_QUICK_ACCESS_UPDATE = "com.kkape.mynas.QUICK_ACCESS_UPDATE"
        const val ACTION_MEDIA_UPDATE = "com.kkape.mynas.MEDIA_UPDATE"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        dataManager = WidgetDataManager(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateStorageWidget" -> handleUpdateStorageWidget(call, result)
            "updateDownloadWidget" -> handleUpdateDownloadWidget(call, result)
            "updateQuickAccessWidget" -> handleUpdateQuickAccessWidget(call, result)
            "updateMediaWidget" -> handleUpdateMediaWidget(call, result)
            "refreshAllWidgets" -> handleRefreshAllWidgets(result)
            else -> result.notImplemented()
        }
    }

    private fun handleUpdateStorageWidget(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: run {
                result.error("INVALID_ARGS", "Invalid arguments", null)
                return
            }

            dataManager.saveStorageData(data)

            // Update widgets
            updateWidgetsByClass(StorageWidget::class.java)

            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleUpdateDownloadWidget(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: run {
                result.error("INVALID_ARGS", "Invalid arguments", null)
                return
            }

            dataManager.saveDownloadData(data)

            // Update widgets
            updateWidgetsByClass(DownloadWidget::class.java)

            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleUpdateQuickAccessWidget(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: run {
                result.error("INVALID_ARGS", "Invalid arguments", null)
                return
            }

            dataManager.saveQuickAccessData(data)

            // Update widgets
            updateWidgetsByClass(QuickAccessWidget::class.java)

            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleUpdateMediaWidget(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val data = call.arguments as? Map<String, Any?> ?: run {
                result.error("INVALID_ARGS", "Invalid arguments", null)
                return
            }

            // Handle cover image data
            @Suppress("UNCHECKED_CAST")
            val coverData = data["coverImageData"] as? ByteArray
            if (coverData != null) {
                dataManager.saveCoverImage(coverData)
            }

            dataManager.saveMediaData(data)

            // Update widgets
            updateWidgetsByClass(MediaWidget::class.java)

            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleRefreshAllWidgets(result: MethodChannel.Result) {
        try {
            updateWidgetsByClass(StorageWidget::class.java)
            updateWidgetsByClass(DownloadWidget::class.java)
            updateWidgetsByClass(QuickAccessWidget::class.java)
            updateWidgetsByClass(MediaWidget::class.java)
            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun <T> updateWidgetsByClass(widgetClass: Class<T>) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetIds = appWidgetManager.getAppWidgetIds(
            ComponentName(context, widgetClass)
        )

        if (widgetIds.isNotEmpty()) {
            val intent = Intent(context, widgetClass).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            }
            context.sendBroadcast(intent)
        }
    }
}
