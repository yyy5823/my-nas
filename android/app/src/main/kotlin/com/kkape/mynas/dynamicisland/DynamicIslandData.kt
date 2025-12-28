package com.kkape.mynas.dynamicisland

import android.graphics.Bitmap

/**
 * 灵动岛媒体数据
 * 统一的数据结构，用于所有灵动岛实现
 */
data class DynamicIslandData(
    val title: String?,
    val artist: String?,
    val album: String?,
    val coverBitmap: Bitmap?,
    val isPlaying: Boolean,
    val progress: Double,
    val currentTimeMs: Long,
    val totalTimeMs: Long,
    val themeColor: Int?
) {
    val hasContent: Boolean
        get() = !title.isNullOrEmpty()

    val progressPercent: Int
        get() = if (totalTimeMs > 0) ((currentTimeMs.toDouble() / totalTimeMs) * 100).toInt() else 0

    val currentTimeFormatted: String
        get() = formatDuration(currentTimeMs)

    val totalTimeFormatted: String
        get() = formatDuration(totalTimeMs)

    companion object {
        val EMPTY = DynamicIslandData(
            title = null,
            artist = null,
            album = null,
            coverBitmap = null,
            isPlaying = false,
            progress = 0.0,
            currentTimeMs = 0,
            totalTimeMs = 0,
            themeColor = null
        )

        private fun formatDuration(ms: Long): String {
            val totalSeconds = ms / 1000
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60

            return if (hours > 0) {
                String.format("%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format("%d:%02d", minutes, seconds)
            }
        }
    }
}

/**
 * 灵动岛控制回调
 */
interface DynamicIslandCallback {
    fun onPlayPause()
    fun onNext()
    fun onPrevious()
    fun onSeek(position: Long)
    fun onDismiss()
    fun onExpand()
}

/**
 * 灵动岛类型
 */
enum class DynamicIslandType {
    /** 华为 Live View Kit */
    HUAWEI_LIVE_VIEW,
    /** 通用悬浮窗 */
    FLOATING_WINDOW,
    /** 不支持 */
    NOT_SUPPORTED
}

/**
 * 灵动岛状态
 */
enum class DynamicIslandState {
    /** 隐藏 */
    HIDDEN,
    /** 收起（胶囊形态） */
    COLLAPSED,
    /** 展开 */
    EXPANDED
}
