package com.kkape.mynas.transcoding

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * MediaCodec 转码 Flutter 插件
 *
 * 提供 MethodChannel 接口供 Dart 调用
 */
class MediaCodecTranscodingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "MediaCodecTranscoding"
        private const val METHOD_CHANNEL = "com.kkape.mynas/mediacodec_transcoding"
        private const val EVENT_CHANNEL = "com.kkape.mynas/mediacodec_transcoding_progress"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var currentTranscoder: MediaCodecTranscoder? = null
    private var currentTaskId: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(this@MediaCodecTranscodingPlugin)
        }

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }

        Log.i(TAG, "MediaCodecTranscodingPlugin attached")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null

        currentTranscoder?.cancel()
        executor.shutdown()

        Log.i(TAG, "MediaCodecTranscodingPlugin detached")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                // MediaCodec 在 Android 上始终可用
                result.success(true)
            }

            "startTranscode" -> {
                val inputPath = call.argument<String>("inputPath")
                val outputPath = call.argument<String>("outputPath")
                val targetWidth = call.argument<Int>("targetWidth")
                val targetHeight = call.argument<Int>("targetHeight")
                val targetBitrate = call.argument<Int>("targetBitrate")
                val audioBitrate = call.argument<Int>("audioBitrate") ?: 128000
                val startPositionMs = call.argument<Long>("startPositionMs") ?: 0L
                val taskId = call.argument<String>("taskId")

                if (inputPath == null || outputPath == null || taskId == null) {
                    result.error("INVALID_ARGUMENT", "Missing required arguments", null)
                    return
                }

                startTranscode(
                    taskId = taskId,
                    inputPath = inputPath,
                    outputPath = outputPath,
                    targetWidth = targetWidth,
                    targetHeight = targetHeight,
                    targetBitrate = targetBitrate,
                    audioBitrate = audioBitrate,
                    startPositionMs = startPositionMs,
                    result = result
                )
            }

            "cancelTranscode" -> {
                val taskId = call.argument<String>("taskId")
                if (taskId == currentTaskId) {
                    currentTranscoder?.cancel()
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "getSupportedEncoders" -> {
                result.success(getSupportedEncoders())
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startTranscode(
        taskId: String,
        inputPath: String,
        outputPath: String,
        targetWidth: Int?,
        targetHeight: Int?,
        targetBitrate: Int?,
        audioBitrate: Int,
        startPositionMs: Long,
        result: MethodChannel.Result
    ) {
        // 检查是否有正在进行的任务
        if (currentTranscoder != null) {
            result.error("BUSY", "Another transcoding task is in progress", null)
            return
        }

        // 确保输出目录存在
        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()

        Log.i(TAG, "Starting transcode task $taskId: $inputPath -> $outputPath")

        executor.execute {
            val transcoder = MediaCodecTranscoder()
            currentTranscoder = transcoder
            currentTaskId = taskId

            // 设置进度回调
            transcoder.setProgressCallback { progress, speed ->
                mainHandler.post {
                    eventSink?.success(mapOf(
                        "taskId" to taskId,
                        "type" to "progress",
                        "progress" to progress,
                        "speed" to speed
                    ))
                }
            }

            // 执行转码
            val transcodeResult = transcoder.transcode(
                MediaCodecTranscoder.TranscodeParams(
                    inputPath = inputPath,
                    outputPath = outputPath,
                    targetWidth = targetWidth,
                    targetHeight = targetHeight,
                    targetBitrate = targetBitrate,
                    audioBitrate = audioBitrate,
                    startPositionMs = startPositionMs
                )
            )

            currentTranscoder = null
            currentTaskId = null

            // 返回结果
            mainHandler.post {
                when (transcodeResult) {
                    is MediaCodecTranscoder.TranscodeResult.Success -> {
                        eventSink?.success(mapOf(
                            "taskId" to taskId,
                            "type" to "complete",
                            "outputPath" to transcodeResult.outputPath
                        ))
                        result.success(mapOf(
                            "success" to true,
                            "outputPath" to transcodeResult.outputPath
                        ))
                    }
                    is MediaCodecTranscoder.TranscodeResult.Error -> {
                        eventSink?.success(mapOf(
                            "taskId" to taskId,
                            "type" to "error",
                            "message" to transcodeResult.message
                        ))
                        result.success(mapOf(
                            "success" to false,
                            "error" to transcodeResult.message
                        ))
                    }
                    is MediaCodecTranscoder.TranscodeResult.Cancelled -> {
                        eventSink?.success(mapOf(
                            "taskId" to taskId,
                            "type" to "cancelled"
                        ))
                        result.success(mapOf(
                            "success" to false,
                            "error" to "Cancelled"
                        ))
                    }
                }
            }
        }
    }

    private fun getSupportedEncoders(): List<String> {
        val encoders = mutableListOf<String>()

        try {
            val codecList = android.media.MediaCodecList(android.media.MediaCodecList.ALL_CODECS)
            for (codecInfo in codecList.codecInfos) {
                if (codecInfo.isEncoder) {
                    for (type in codecInfo.supportedTypes) {
                        if (type.contains("video/avc") || type.contains("video/hevc")) {
                            encoders.add("${codecInfo.name} ($type)")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting supported encoders", e)
        }

        return encoders
    }
}
