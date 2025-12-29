package com.kkape.mynas.transcoding

import android.media.*
import android.os.Build
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MediaCodec 硬件转码器
 *
 * 使用 Android MediaCodec API 进行硬件加速视频转码
 */
class MediaCodecTranscoder {
    companion object {
        private const val TAG = "MediaCodecTranscoder"
        private const val TIMEOUT_US = 10000L // 10ms
        private const val MIME_TYPE_H264 = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val MIME_TYPE_AAC = MediaFormat.MIMETYPE_AUDIO_AAC
        private const val I_FRAME_INTERVAL = 1 // 关键帧间隔（秒）
    }

    private var extractor: MediaExtractor? = null
    private var muxer: MediaMuxer? = null
    private var videoDecoder: MediaCodec? = null
    private var videoEncoder: MediaCodec? = null
    private var audioDecoder: MediaCodec? = null
    private var audioEncoder: MediaCodec? = null

    private var inputSurface: Surface? = null
    private var outputSurface: OutputSurface? = null

    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerVideoTrackIndex = -1
    private var muxerAudioTrackIndex = -1

    private var muxerStarted = false
    private val isCancelled = AtomicBoolean(false)

    private var progressCallback: ((Double, String?) -> Unit)? = null
    private var totalDurationUs: Long = 0

    /**
     * 转码参数
     */
    data class TranscodeParams(
        val inputPath: String,
        val outputPath: String,
        val targetWidth: Int?,
        val targetHeight: Int?,
        val targetBitrate: Int?,        // 视频码率 bps
        val audioBitrate: Int = 128000, // 音频码率 bps
        val startPositionMs: Long = 0,  // 起始位置 ms
    )

    /**
     * 转码结果
     */
    sealed class TranscodeResult {
        data class Success(val outputPath: String) : TranscodeResult()
        data class Error(val message: String) : TranscodeResult()
        object Cancelled : TranscodeResult()
    }

    /**
     * 设置进度回调
     */
    fun setProgressCallback(callback: (progress: Double, speed: String?) -> Unit) {
        progressCallback = callback
    }

    /**
     * 取消转码
     */
    fun cancel() {
        isCancelled.set(true)
    }

    /**
     * 执行转码
     */
    fun transcode(params: TranscodeParams): TranscodeResult {
        isCancelled.set(false)

        return try {
            doTranscode(params)
        } catch (e: Exception) {
            Log.e(TAG, "Transcode failed", e)
            TranscodeResult.Error(e.message ?: "Unknown error")
        } finally {
            release()
        }
    }

    private fun doTranscode(params: TranscodeParams): TranscodeResult {
        Log.i(TAG, "Starting transcode: ${params.inputPath} -> ${params.outputPath}")

        // 1. 初始化 MediaExtractor
        extractor = MediaExtractor().apply {
            setDataSource(params.inputPath)
        }

        // 2. 查找视频和音频轨道
        findTracks()

        if (videoTrackIndex < 0) {
            return TranscodeResult.Error("No video track found")
        }

        // 3. 获取原始视频格式
        val inputVideoFormat = extractor!!.getTrackFormat(videoTrackIndex)
        val inputWidth = inputVideoFormat.getInteger(MediaFormat.KEY_WIDTH)
        val inputHeight = inputVideoFormat.getInteger(MediaFormat.KEY_HEIGHT)
        totalDurationUs = inputVideoFormat.getLongOrDefault(MediaFormat.KEY_DURATION, 0)

        Log.i(TAG, "Input video: ${inputWidth}x${inputHeight}, duration=${totalDurationUs/1000}ms")

        // 4. 计算输出分辨率（保持宽高比）
        val (outputWidth, outputHeight) = calculateOutputSize(
            inputWidth, inputHeight,
            params.targetWidth, params.targetHeight
        )

        // 5. 计算码率
        val videoBitrate = params.targetBitrate
            ?: calculateBitrate(outputWidth, outputHeight)

        Log.i(TAG, "Output video: ${outputWidth}x${outputHeight}, bitrate=${videoBitrate/1000}kbps")

        // 6. 创建输出格式
        val outputVideoFormat = createOutputVideoFormat(outputWidth, outputHeight, videoBitrate)

        // 7. 创建 MediaMuxer
        muxer = MediaMuxer(params.outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        // 8. 设置起始位置
        if (params.startPositionMs > 0) {
            extractor!!.seekTo(params.startPositionMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        }

        // 9. 检查是否需要转码（分辨率不同才需要）
        val needsVideoTranscode = (outputWidth != inputWidth || outputHeight != inputHeight)

        if (needsVideoTranscode) {
            // 使用 Surface 进行转码
            setupSurfaceTranscode(inputVideoFormat, outputVideoFormat, outputWidth, outputHeight)
            return transcodeWithSurface(params)
        } else {
            // 直接复制（remux）
            return remuxVideo(params)
        }
    }

    private fun findTracks() {
        val extractor = this.extractor ?: return

        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue

            when {
                mime.startsWith("video/") && videoTrackIndex < 0 -> {
                    videoTrackIndex = i
                    Log.d(TAG, "Found video track: $i, mime=$mime")
                }
                mime.startsWith("audio/") && audioTrackIndex < 0 -> {
                    audioTrackIndex = i
                    Log.d(TAG, "Found audio track: $i, mime=$mime")
                }
            }
        }
    }

    private fun calculateOutputSize(
        inputWidth: Int, inputHeight: Int,
        targetWidth: Int?, targetHeight: Int?
    ): Pair<Int, Int> {
        if (targetWidth == null || targetHeight == null) {
            return Pair(inputWidth, inputHeight)
        }

        // 保持宽高比
        val inputAspect = inputWidth.toFloat() / inputHeight
        val targetAspect = targetWidth.toFloat() / targetHeight

        val (scaledWidth, scaledHeight) = if (inputAspect > targetAspect) {
            // 按宽度缩放
            Pair(targetWidth, (targetWidth / inputAspect).toInt())
        } else {
            // 按高度缩放
            Pair((targetHeight * inputAspect).toInt(), targetHeight)
        }

        // 确保是偶数（编码器要求）
        return Pair(
            scaledWidth and 0x7FFFFFFE.toInt(),
            scaledHeight and 0x7FFFFFFE.toInt()
        )
    }

    private fun calculateBitrate(width: Int, height: Int): Int {
        // 根据分辨率估算码率
        val pixels = width * height
        return when {
            pixels >= 1920 * 1080 -> 8_000_000  // 1080p: 8Mbps
            pixels >= 1280 * 720 -> 5_000_000   // 720p: 5Mbps
            pixels >= 854 * 480 -> 2_500_000    // 480p: 2.5Mbps
            else -> 1_500_000                    // 其他: 1.5Mbps
        }
    }

    private fun createOutputVideoFormat(width: Int, height: Int, bitrate: Int): MediaFormat {
        return MediaFormat.createVideoFormat(MIME_TYPE_H264, width, height).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_INTERVAL)
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)

            // 设置 profile 和 level（兼容性更好）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AVCProfileHigh)
                setInteger(MediaFormat.KEY_LEVEL,
                    MediaCodecInfo.CodecProfileLevel.AVCLevel41)
            }
        }
    }

    private fun setupSurfaceTranscode(
        inputFormat: MediaFormat,
        outputFormat: MediaFormat,
        outputWidth: Int,
        outputHeight: Int
    ) {
        // 创建编码器
        videoEncoder = MediaCodec.createEncoderByType(MIME_TYPE_H264).apply {
            configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = createInputSurface()
            start()
        }

        // 创建 OutputSurface 用于渲染和缩放
        outputSurface = OutputSurface(outputWidth, outputHeight)

        // 创建解码器
        val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        videoDecoder = MediaCodec.createDecoderByType(mime).apply {
            configure(inputFormat, outputSurface!!.surface, null, 0)
            start()
        }

        // 选择视频轨道
        extractor!!.selectTrack(videoTrackIndex)
    }

    private fun transcodeWithSurface(params: TranscodeParams): TranscodeResult {
        val extractor = this.extractor ?: return TranscodeResult.Error("Extractor not initialized")
        val decoder = this.videoDecoder ?: return TranscodeResult.Error("Decoder not initialized")
        val encoder = this.videoEncoder ?: return TranscodeResult.Error("Encoder not initialized")
        val outputSurface = this.outputSurface ?: return TranscodeResult.Error("OutputSurface not initialized")
        val inputSurface = this.inputSurface ?: return TranscodeResult.Error("InputSurface not initialized")

        val decoderInputBuffers = decoder.inputBuffers
        val bufferInfo = MediaCodec.BufferInfo()

        var inputDone = false
        var outputDone = false
        var decoderOutputAvailable = true
        var encoderOutputAvailable = true

        val startTime = System.currentTimeMillis()
        var lastProgressTime = 0L

        while (!outputDone && !isCancelled.get()) {
            // 1. 向解码器输入数据
            if (!inputDone) {
                val inputBufferIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = decoderInputBuffers[inputBufferIndex]
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)

                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                        Log.d(TAG, "Input EOS sent to decoder")
                    } else {
                        decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize,
                            extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            // 2. 从解码器获取输出，渲染到 Surface
            if (decoderOutputAvailable) {
                val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)

                when {
                    outputBufferIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // 暂无输出
                    }
                    outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        Log.d(TAG, "Decoder output format changed")
                    }
                    outputBufferIndex >= 0 -> {
                        val doRender = bufferInfo.size > 0

                        if (doRender) {
                            // 渲染到 OutputSurface
                            decoder.releaseOutputBuffer(outputBufferIndex, true)
                            outputSurface.awaitNewImage()
                            outputSurface.drawImage()

                            // 设置编码器时间戳
                            inputSurface.let { surface ->
                                // 使用 EGL 将帧从 OutputSurface 渲染到 InputSurface
                                outputSurface.renderToSurface(surface, bufferInfo.presentationTimeUs)
                            }

                            // 更新进度
                            if (totalDurationUs > 0 && bufferInfo.presentationTimeUs - lastProgressTime > 500_000) {
                                lastProgressTime = bufferInfo.presentationTimeUs
                                val progress = bufferInfo.presentationTimeUs.toDouble() / totalDurationUs
                                val elapsed = System.currentTimeMillis() - startTime
                                val speed = if (elapsed > 0) {
                                    String.format("%.1fx",
                                        (bufferInfo.presentationTimeUs / 1000.0) / elapsed)
                                } else null
                                progressCallback?.invoke(progress.coerceIn(0.0, 1.0), speed)
                            }
                        } else {
                            decoder.releaseOutputBuffer(outputBufferIndex, false)
                        }

                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            decoderOutputAvailable = false
                            encoder.signalEndOfInputStream()
                            Log.d(TAG, "Decoder EOS received, signaling encoder")
                        }
                    }
                }
            }

            // 3. 从编码器获取输出，写入 Muxer
            if (encoderOutputAvailable) {
                val outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)

                when {
                    outputBufferIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        // 暂无输出
                    }
                    outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (muxerStarted) {
                            Log.w(TAG, "Encoder format changed after muxer started")
                        } else {
                            val newFormat = encoder.outputFormat
                            Log.d(TAG, "Encoder output format: $newFormat")
                            muxerVideoTrackIndex = muxer!!.addTrack(newFormat)
                            muxer!!.start()
                            muxerStarted = true
                        }
                    }
                    outputBufferIndex >= 0 -> {
                        val outputBuffer = encoder.getOutputBuffer(outputBufferIndex)
                            ?: throw RuntimeException("Encoder output buffer null")

                        if (bufferInfo.size > 0 && muxerStarted) {
                            outputBuffer.position(bufferInfo.offset)
                            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            muxer!!.writeSampleData(muxerVideoTrackIndex, outputBuffer, bufferInfo)
                        }

                        encoder.releaseOutputBuffer(outputBufferIndex, false)

                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                            Log.d(TAG, "Encoder EOS received")
                        }
                    }
                }
            }
        }

        return if (isCancelled.get()) {
            TranscodeResult.Cancelled
        } else {
            progressCallback?.invoke(1.0, null)
            Log.i(TAG, "Transcode completed: ${params.outputPath}")
            TranscodeResult.Success(params.outputPath)
        }
    }

    private fun remuxVideo(params: TranscodeParams): TranscodeResult {
        Log.i(TAG, "Remuxing video (no transcode needed)")

        val extractor = this.extractor ?: return TranscodeResult.Error("Extractor not initialized")
        val muxer = this.muxer ?: return TranscodeResult.Error("Muxer not initialized")

        // 添加轨道
        if (videoTrackIndex >= 0) {
            val format = extractor.getTrackFormat(videoTrackIndex)
            muxerVideoTrackIndex = muxer.addTrack(format)
            extractor.selectTrack(videoTrackIndex)
        }

        if (audioTrackIndex >= 0) {
            val format = extractor.getTrackFormat(audioTrackIndex)
            muxerAudioTrackIndex = muxer.addTrack(format)
            extractor.selectTrack(audioTrackIndex)
        }

        muxer.start()
        muxerStarted = true

        val buffer = ByteBuffer.allocate(1024 * 1024) // 1MB buffer
        val bufferInfo = MediaCodec.BufferInfo()
        var lastProgressTime = 0L

        while (!isCancelled.get()) {
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break

            val trackIndex = extractor.sampleTrackIndex
            val muxerTrackIndex = when (trackIndex) {
                videoTrackIndex -> muxerVideoTrackIndex
                audioTrackIndex -> muxerAudioTrackIndex
                else -> -1
            }

            if (muxerTrackIndex >= 0) {
                bufferInfo.offset = 0
                bufferInfo.size = sampleSize
                bufferInfo.presentationTimeUs = extractor.sampleTime
                bufferInfo.flags = extractor.sampleFlags

                muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)

                // 更新进度
                if (totalDurationUs > 0 && extractor.sampleTime - lastProgressTime > 500_000) {
                    lastProgressTime = extractor.sampleTime
                    val progress = extractor.sampleTime.toDouble() / totalDurationUs
                    progressCallback?.invoke(progress.coerceIn(0.0, 1.0), null)
                }
            }

            extractor.advance()
        }

        return if (isCancelled.get()) {
            TranscodeResult.Cancelled
        } else {
            progressCallback?.invoke(1.0, null)
            TranscodeResult.Success(params.outputPath)
        }
    }

    private fun release() {
        try {
            videoDecoder?.stop()
            videoDecoder?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing decoder", e)
        }
        videoDecoder = null

        try {
            videoEncoder?.stop()
            videoEncoder?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing encoder", e)
        }
        videoEncoder = null

        try {
            outputSurface?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing output surface", e)
        }
        outputSurface = null
        inputSurface = null

        try {
            if (muxerStarted) {
                muxer?.stop()
            }
            muxer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing muxer", e)
        }
        muxer = null
        muxerStarted = false

        try {
            extractor?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing extractor", e)
        }
        extractor = null

        videoTrackIndex = -1
        audioTrackIndex = -1
        muxerVideoTrackIndex = -1
        muxerAudioTrackIndex = -1
    }

    private fun MediaFormat.getLongOrDefault(key: String, default: Long): Long {
        return try {
            getLong(key)
        } catch (e: Exception) {
            default
        }
    }
}
