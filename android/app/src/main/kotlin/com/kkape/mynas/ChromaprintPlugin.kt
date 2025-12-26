package com.kkape.mynas

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.min

/**
 * Chromaprint 指纹生成插件
 *
 * 使用 Android MediaCodec 解码音频，然后通过 JNI 调用 Chromaprint 生成指纹
 * 需要预编译的 libchromaprint.so 库
 */
class ChromaprintPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val CHANNEL_NAME = "com.mynas.fingerprint/chromaprint"
        private const val SAMPLE_RATE = 44100
        private const val CHANNELS = 2

        // 是否加载了原生库
        private var nativeLibraryLoaded = false

        init {
            try {
                System.loadLibrary("chromaprint_jni")
                nativeLibraryLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                // 原生库未编译，使用 fallback 方案
                nativeLibraryLoaded = false
            }
        }
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
            "isAvailable" -> {
                result.success(nativeLibraryLoaded)
            }
            "generateFingerprint" -> {
                val filePath = call.argument<String>("filePath")
                val maxDuration = call.argument<Int>("maxDuration") ?: 120

                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return
                }

                executor.execute {
                    try {
                        val fpResult = generateFingerprint(filePath, maxDuration)
                        mainHandler.post {
                            result.success(fpResult)
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("FINGERPRINT_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                }
            }
            "getVersion" -> {
                if (nativeLibraryLoaded) {
                    result.success(nativeGetVersion())
                } else {
                    result.success(null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 生成音频指纹
     */
    private fun generateFingerprint(filePath: String, maxDuration: Int): Map<String, Any> {
        val file = File(filePath)
        if (!file.exists()) {
            throw IllegalArgumentException("文件不存在: $filePath")
        }

        if (!nativeLibraryLoaded) {
            throw UnsupportedOperationException("Chromaprint 原生库未加载")
        }

        // 使用 MediaExtractor 和 MediaCodec 解码音频
        val extractor = MediaExtractor()
        extractor.setDataSource(filePath)

        // 查找音频轨道
        var audioTrackIndex = -1
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                break
            }
        }

        if (audioTrackIndex < 0) {
            extractor.release()
            throw IllegalArgumentException("文件不包含音频轨道")
        }

        extractor.selectTrack(audioTrackIndex)
        val format = extractor.getTrackFormat(audioTrackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: "audio/mpeg"
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val duration = format.getLong(MediaFormat.KEY_DURATION) / 1000000 // 微秒转秒

        // 创建解码器
        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(format, null, null, 0)
        decoder.start()

        // 初始化 Chromaprint
        val chromaprintCtx = nativeNew(SAMPLE_RATE, CHANNELS)
        if (chromaprintCtx == 0L) {
            decoder.release()
            extractor.release()
            throw RuntimeException("创建 Chromaprint 上下文失败")
        }

        try {
            nativeStart(chromaprintCtx)

            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var processedDuration = 0L
            val maxDurationUs = maxDuration * 1000000L

            while (!outputDone) {
                // 输入
                if (!inputDone) {
                    val inputBufferIndex = decoder.dequeueInputBuffer(10000)
                    if (inputBufferIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputBufferIndex)!!
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)

                        if (sampleSize < 0 || processedDuration >= maxDurationUs) {
                            decoder.queueInputBuffer(
                                inputBufferIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            val presentationTimeUs = extractor.sampleTime
                            decoder.queueInputBuffer(
                                inputBufferIndex, 0, sampleSize,
                                presentationTimeUs, 0
                            )
                            extractor.advance()
                        }
                    }
                }

                // 输出
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    } else {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)!!

                        // 转换为 16-bit PCM 并重采样
                        val pcmData = convertToPcm16(
                            outputBuffer, bufferInfo.size,
                            sampleRate, channelCount, SAMPLE_RATE, CHANNELS
                        )

                        // 喂给 Chromaprint
                        nativeFeed(chromaprintCtx, pcmData, pcmData.size / 2)

                        processedDuration = bufferInfo.presentationTimeUs
                    }
                    decoder.releaseOutputBuffer(outputBufferIndex, false)
                }
            }

            nativeFinish(chromaprintCtx)

            // 获取指纹
            val fingerprint = nativeGetFingerprint(chromaprintCtx)
                ?: throw RuntimeException("获取指纹失败")

            return mapOf(
                "fingerprint" to fingerprint,
                "duration" to min(duration.toInt(), maxDuration)
            )
        } finally {
            nativeFree(chromaprintCtx)
            decoder.stop()
            decoder.release()
            extractor.release()
        }
    }

    /**
     * 转换音频数据为目标格式的 16-bit PCM
     */
    private fun convertToPcm16(
        buffer: ByteBuffer,
        size: Int,
        srcSampleRate: Int,
        srcChannels: Int,
        dstSampleRate: Int,
        dstChannels: Int
    ): ShortArray {
        // 简化处理：假设输入已经是 16-bit PCM
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        val shortBuffer = buffer.asShortBuffer()
        val samples = size / 2
        val srcData = ShortArray(samples)
        shortBuffer.get(srcData)

        // 如果采样率和声道数相同，直接返回
        if (srcSampleRate == dstSampleRate && srcChannels == dstChannels) {
            return srcData
        }

        // 简单重采样（线性插值）和声道转换
        val srcFrames = samples / srcChannels
        val ratio = srcSampleRate.toDouble() / dstSampleRate
        val dstFrames = (srcFrames / ratio).toInt()
        val dstData = ShortArray(dstFrames * dstChannels)

        for (i in 0 until dstFrames) {
            val srcPos = (i * ratio).toInt()
            val srcIndex = min(srcPos * srcChannels, samples - srcChannels)

            for (c in 0 until dstChannels) {
                val srcC = if (c < srcChannels) c else 0
                dstData[i * dstChannels + c] = srcData[srcIndex + srcC]
            }
        }

        return dstData
    }

    // JNI 方法
    private external fun nativeNew(sampleRate: Int, channels: Int): Long
    private external fun nativeStart(ctx: Long): Boolean
    private external fun nativeFeed(ctx: Long, data: ShortArray, size: Int): Boolean
    private external fun nativeFinish(ctx: Long): Boolean
    private external fun nativeGetFingerprint(ctx: Long): String?
    private external fun nativeFree(ctx: Long)
    private external fun nativeGetVersion(): String
}
