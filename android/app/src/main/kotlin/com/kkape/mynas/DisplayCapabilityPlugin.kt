package com.kkape.mynas

import android.content.Context
import android.os.Build
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 显示能力检测插件
 *
 * 检测 Android 设备的 HDR 显示能力
 */
class DisplayCapabilityPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    companion object {
        private const val CHANNEL_NAME = "com.kkape.mynas/display_capability"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getHdrCapability" -> {
                result.success(getHdrCapability())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 获取 HDR 能力
     */
    private fun getHdrCapability(): Map<String, Any?> {
        var isSupported = false
        val supportedTypes = mutableListOf<String>()
        var maxLuminance = 0.0
        var colorGamut: String? = null

        // Android 7.0+ 支持 HDR 检测
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val display = windowManager.defaultDisplay

            val hdrCapabilities = display.hdrCapabilities

            if (hdrCapabilities != null) {
                val hdrTypes = hdrCapabilities.supportedHdrTypes

                isSupported = hdrTypes.isNotEmpty()

                for (type in hdrTypes) {
                    when (type) {
                        Display.HdrCapabilities.HDR_TYPE_HDR10 -> {
                            supportedTypes.add("hdr10")
                        }
                        Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> {
                            supportedTypes.add("hdr10+")
                        }
                        Display.HdrCapabilities.HDR_TYPE_HLG -> {
                            supportedTypes.add("hlg")
                        }
                        Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> {
                            supportedTypes.add("dolbyVision")
                        }
                    }
                }

                // 获取最大亮度
                val peak = hdrCapabilities.desiredMaxLuminance
                if (peak > 0) {
                    maxLuminance = peak.toDouble()
                }
            }

            // 检测色域
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val isWideGamut = display.isWideColorGamut
                colorGamut = if (isWideGamut) "P3" else "sRGB"
            }
        }

        return mapOf(
            "isSupported" to isSupported,
            "supportedTypes" to supportedTypes,
            "maxLuminance" to maxLuminance,
            "colorGamut" to colorGamut
        )
    }
}
