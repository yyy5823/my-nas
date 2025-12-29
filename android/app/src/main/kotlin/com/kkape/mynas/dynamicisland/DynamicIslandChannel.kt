package com.kkape.mynas.dynamicisland

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter Method Channel for Dynamic Island
 * 处理 Flutter 端的灵动岛控制请求
 */
class DynamicIslandChannel : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var manager: DynamicIslandManager? = null

    companion object {
        private const val TAG = "DynamicIslandChannel"
        const val CHANNEL_NAME = "com.kkape.mynas/dynamic_island"

        // 从 Flutter 发送到 Android 的方法
        const val METHOD_INITIALIZE = "initialize"
        const val METHOD_SHOW = "show"
        const val METHOD_HIDE = "hide"
        const val METHOD_EXPAND = "expand"
        const val METHOD_COLLAPSE = "collapse"
        const val METHOD_UPDATE_DATA = "updateData"
        const val METHOD_IS_SUPPORTED = "isSupported"
        const val METHOD_HAS_PERMISSION = "hasPermission"
        const val METHOD_REQUEST_PERMISSION = "requestPermission"
        const val METHOD_GET_TYPE = "getType"
        const val METHOD_RELEASE = "release"

        // 从 Android 发送到 Flutter 的事件
        const val EVENT_ON_PLAY_PAUSE = "onPlayPause"
        const val EVENT_ON_NEXT = "onNext"
        const val EVENT_ON_PREVIOUS = "onPrevious"
        const val EVENT_ON_SEEK = "onSeek"
        const val EVENT_ON_DISMISS = "onDismiss"
        const val EVENT_ON_EXPAND = "onExpand"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        Log.d(TAG, "DynamicIslandChannel attached to engine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        manager?.release()
        manager = null
        Log.d(TAG, "DynamicIslandChannel detached from engine")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Method called: ${call.method}")

        when (call.method) {
            METHOD_INITIALIZE -> handleInitialize(result)
            METHOD_SHOW -> handleShow(result)
            METHOD_HIDE -> handleHide(result)
            METHOD_EXPAND -> handleExpand(result)
            METHOD_COLLAPSE -> handleCollapse(result)
            METHOD_UPDATE_DATA -> handleUpdateData(call, result)
            METHOD_IS_SUPPORTED -> handleIsSupported(result)
            METHOD_HAS_PERMISSION -> handleHasPermission(result)
            METHOD_REQUEST_PERMISSION -> handleRequestPermission(result)
            METHOD_GET_TYPE -> handleGetType(result)
            METHOD_RELEASE -> handleRelease(result)
            else -> result.notImplemented()
        }
    }

    private fun getOrCreateManager(): DynamicIslandManager {
        if (manager == null) {
            manager = DynamicIslandFactory.getInstance(context)
            setupCallback()
        }
        return manager!!
    }

    private fun setupCallback() {
        manager?.callback = object : DynamicIslandCallback {
            override fun onPlayPause() {
                Log.d(TAG, "Callback: onPlayPause")
                channel.invokeMethod(EVENT_ON_PLAY_PAUSE, null)
            }

            override fun onNext() {
                Log.d(TAG, "Callback: onNext")
                channel.invokeMethod(EVENT_ON_NEXT, null)
            }

            override fun onPrevious() {
                Log.d(TAG, "Callback: onPrevious")
                channel.invokeMethod(EVENT_ON_PREVIOUS, null)
            }

            override fun onSeek(position: Long) {
                Log.d(TAG, "Callback: onSeek - $position")
                channel.invokeMethod(EVENT_ON_SEEK, mapOf("position" to position))
            }

            override fun onDismiss() {
                Log.d(TAG, "Callback: onDismiss")
                channel.invokeMethod(EVENT_ON_DISMISS, null)
            }

            override fun onExpand() {
                Log.d(TAG, "Callback: onExpand")
                channel.invokeMethod(EVENT_ON_EXPAND, null)
            }
        }
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        try {
            val mgr = getOrCreateManager()
            mgr.initialize()
            result.success(mapOf(
                "type" to mgr.type.name,
                "isSupported" to mgr.isSupported(),
                "hasPermission" to mgr.hasPermission()
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize", e)
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun handleShow(result: MethodChannel.Result) {
        try {
            getOrCreateManager().show()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show", e)
            result.error("SHOW_ERROR", e.message, null)
        }
    }

    private fun handleHide(result: MethodChannel.Result) {
        try {
            getOrCreateManager().hide()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to hide", e)
            result.error("HIDE_ERROR", e.message, null)
        }
    }

    private fun handleExpand(result: MethodChannel.Result) {
        try {
            getOrCreateManager().expand()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to expand", e)
            result.error("EXPAND_ERROR", e.message, null)
        }
    }

    private fun handleCollapse(result: MethodChannel.Result) {
        try {
            getOrCreateManager().collapse()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to collapse", e)
            result.error("COLLAPSE_ERROR", e.message, null)
        }
    }

    private fun handleUpdateData(call: MethodCall, result: MethodChannel.Result) {
        try {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<String, Any?> ?: run {
                result.error("INVALID_ARGS", "Invalid arguments", null)
                return
            }

            // 解析封面图片
            val coverBitmap = (args["coverImageData"] as? ByteArray)?.let { bytes ->
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }

            val data = DynamicIslandData(
                title = args["title"] as? String,
                artist = args["artist"] as? String,
                album = args["album"] as? String,
                coverBitmap = coverBitmap,
                isPlaying = args["isPlaying"] as? Boolean ?: false,
                progress = (args["progress"] as? Double) ?: 0.0,
                currentTimeMs = ((args["currentTimeMs"] as? Number)?.toLong()) ?: 0L,
                totalTimeMs = ((args["totalTimeMs"] as? Number)?.toLong()) ?: 0L,
                themeColor = (args["themeColor"] as? Number)?.toInt()
            )

            getOrCreateManager().updateData(data)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update data", e)
            result.error("UPDATE_ERROR", e.message, null)
        }
    }

    private fun handleIsSupported(result: MethodChannel.Result) {
        try {
            result.success(getOrCreateManager().isSupported())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check support", e)
            result.error("CHECK_ERROR", e.message, null)
        }
    }

    private fun handleHasPermission(result: MethodChannel.Result) {
        try {
            result.success(getOrCreateManager().hasPermission())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check permission", e)
            result.error("CHECK_ERROR", e.message, null)
        }
    }

    private fun handleRequestPermission(result: MethodChannel.Result) {
        try {
            result.success(getOrCreateManager().requestPermission())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to request permission", e)
            result.error("PERMISSION_ERROR", e.message, null)
        }
    }

    private fun handleGetType(result: MethodChannel.Result) {
        try {
            result.success(getOrCreateManager().type.name)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get type", e)
            result.error("TYPE_ERROR", e.message, null)
        }
    }

    private fun handleRelease(result: MethodChannel.Result) {
        try {
            manager?.release()
            manager = null
            DynamicIslandFactory.release()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release", e)
            result.error("RELEASE_ERROR", e.message, null)
        }
    }
}
