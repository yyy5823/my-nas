package com.kkape.mynas

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 音频能力检测插件
 *
 * 检测 Android 设备的音频直通能力
 */
class AudioCapabilityPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    companion object {
        private const val CHANNEL_NAME = "com.kkape.mynas/audio_capability"
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
            "getPassthroughCapability" -> {
                result.success(getPassthroughCapability())
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 获取音频直通能力
     */
    private fun getPassthroughCapability(): Map<String, Any?> {
        var isSupported = false
        val supportedCodecs = mutableListOf<String>()
        var outputDevice = "unknown"
        var maxChannels = 2
        var deviceName: String? = null

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

            for (device in devices) {
                when (device.type) {
                    AudioDeviceInfo.TYPE_HDMI,
                    AudioDeviceInfo.TYPE_HDMI_ARC,
                    AudioDeviceInfo.TYPE_HDMI_EARC -> {
                        isSupported = true
                        outputDevice = "hdmi"
                        deviceName = device.productName?.toString()

                        // HDMI 支持大多数直通格式
                        supportedCodecs.addAll(listOf("ac3", "eac3", "dts", "dts-hd", "truehd"))

                        // 获取最大声道数
                        val channelCounts = device.channelCounts
                        if (channelCounts.isNotEmpty()) {
                            maxChannels = channelCounts.maxOrNull() ?: 8
                        } else {
                            maxChannels = 8
                        }

                        // 检查编码支持
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            // Android 12+ 可以检查具体编码支持
                            checkEncodingSupport(device, supportedCodecs)
                        }

                        break
                    }

                    AudioDeviceInfo.TYPE_USB_DEVICE,
                    AudioDeviceInfo.TYPE_USB_ACCESSORY -> {
                        // USB 音频设备可能支持直通
                        isSupported = true
                        outputDevice = "usb"
                        deviceName = device.productName?.toString()
                        supportedCodecs.addAll(listOf("ac3", "dts"))

                        val channelCounts = device.channelCounts
                        if (channelCounts.isNotEmpty()) {
                            maxChannels = channelCounts.maxOrNull() ?: 2
                        }

                        // 如果没有找到 HDMI，才使用 USB
                    }

                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                        if (outputDevice == "unknown") {
                            outputDevice = "bluetooth"
                            deviceName = device.productName?.toString()
                        }
                    }

                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> {
                        if (outputDevice == "unknown") {
                            outputDevice = "speaker"
                            deviceName = "内置扬声器"
                        }
                    }

                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                        if (outputDevice == "unknown") {
                            outputDevice = "headphones"
                            deviceName = device.productName?.toString()
                        }
                    }
                }
            }
        }

        return mapOf(
            "isSupported" to isSupported,
            "supportedCodecs" to supportedCodecs.distinct(),
            "outputDevice" to outputDevice,
            "maxChannels" to maxChannels,
            "deviceName" to deviceName
        )
    }

    /**
     * 检查具体编码支持 (Android 12+)
     */
    private fun checkEncodingSupport(device: AudioDeviceInfo, codecs: MutableList<String>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val encodings = device.encodings

            // 检查具体编码
            for (encoding in encodings) {
                when (encoding) {
                    android.media.AudioFormat.ENCODING_AC3 -> {
                        if (!codecs.contains("ac3")) codecs.add("ac3")
                    }
                    android.media.AudioFormat.ENCODING_E_AC3 -> {
                        if (!codecs.contains("eac3")) codecs.add("eac3")
                    }
                    android.media.AudioFormat.ENCODING_DTS -> {
                        if (!codecs.contains("dts")) codecs.add("dts")
                    }
                    android.media.AudioFormat.ENCODING_DTS_HD -> {
                        if (!codecs.contains("dts-hd")) codecs.add("dts-hd")
                    }
                    android.media.AudioFormat.ENCODING_DOLBY_TRUEHD -> {
                        if (!codecs.contains("truehd")) codecs.add("truehd")
                    }
                    // Android 12+ 支持更多编码检测
                }
            }
        }
    }
}
