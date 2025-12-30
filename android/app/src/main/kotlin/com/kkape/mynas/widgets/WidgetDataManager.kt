package com.kkape.mynas.widgets

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Widget 数据管理器
 * 负责读写共享存储中的 Widget 数据
 */
class WidgetDataManager(private val context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences(
        PREFS_NAME, Context.MODE_PRIVATE
    )

    companion object {
        const val PREFS_NAME = "widget_data"

        // Storage Widget keys
        const val KEY_STORAGE_DATA = "storage_data"
        const val KEY_NAS_CONNECTED = "nas_connected"
        const val KEY_NAS_NAME = "nas_name"

        // Download Widget keys
        const val KEY_DOWNLOAD_DATA = "download_data"

        // Quick Access Widget keys
        const val KEY_QUICK_ACCESS_DATA = "quick_access_data"

        // Media Widget keys
        const val KEY_MEDIA_DATA = "media_data"
        const val KEY_COVER_IMAGE_PATH = "cover_image_path"
    }

    // ==================== Storage Data ====================

    data class StorageData(
        val totalBytes: Long,
        val usedBytes: Long,
        val nasName: String,
        val adapterType: String,
        val lastUpdated: Long,
        val isConnected: Boolean
    ) {
        val usagePercent: Double
            get() = if (totalBytes > 0) usedBytes.toDouble() / totalBytes else 0.0

        val usagePercentInt: Int
            get() = (usagePercent * 100).toInt()

        val isLowSpace: Boolean
            get() = usagePercent > 0.9

        val hasValidData: Boolean
            get() = totalBytes > 0

        companion object {
            val EMPTY = StorageData(0, 0, "", "unknown", 0, false)

            val PLACEHOLDER = StorageData(
                1_000_000_000_000L,
                650_000_000_000L,
                "My NAS",
                "synology",
                System.currentTimeMillis(),
                true
            )

            fun fromJson(json: JSONObject): StorageData {
                return StorageData(
                    totalBytes = json.optLong("totalBytes", 0),
                    usedBytes = json.optLong("usedBytes", 0),
                    nasName = json.optString("nasName", ""),
                    adapterType = json.optString("adapterType", "unknown"),
                    lastUpdated = json.optLong("lastUpdated", 0),
                    isConnected = json.optBoolean("isConnected", false)
                )
            }
        }
    }

    fun getStorageData(): StorageData {
        val jsonStr = prefs.getString(KEY_STORAGE_DATA, null) ?: return StorageData.EMPTY
        return try {
            StorageData.fromJson(JSONObject(jsonStr))
        } catch (e: Exception) {
            StorageData.EMPTY
        }
    }

    fun saveStorageData(data: Map<String, Any?>) {
        val json = JSONObject(data)
        prefs.edit()
            .putString(KEY_STORAGE_DATA, json.toString())
            .putBoolean(KEY_NAS_CONNECTED, data["isConnected"] as? Boolean ?: false)
            .putString(KEY_NAS_NAME, data["nasName"] as? String)
            .apply()
    }

    // ==================== Download Data ====================

    data class DownloadTaskSummary(
        val id: String,
        val fileName: String,
        val progress: Double,
        val status: String
    ) {
        companion object {
            fun fromJson(json: JSONObject): DownloadTaskSummary {
                return DownloadTaskSummary(
                    id = json.optString("id", ""),
                    fileName = json.optString("fileName", ""),
                    progress = json.optDouble("progress", 0.0),
                    status = json.optString("status", "pending")
                )
            }
        }
    }

    data class DownloadData(
        val activeTasks: List<DownloadTaskSummary>,
        val completedCount: Int,
        val totalCount: Int,
        val lastUpdated: Long
    ) {
        val activeCount: Int
            get() = activeTasks.size

        val hasActiveDownloads: Boolean
            get() = activeTasks.isNotEmpty()

        val overallProgress: Double
            get() = if (activeTasks.isEmpty()) 0.0
            else activeTasks.sumOf { it.progress } / activeTasks.size

        val currentFileName: String?
            get() = activeTasks.firstOrNull()?.fileName

        companion object {
            val EMPTY = DownloadData(emptyList(), 0, 0, 0)

            val PLACEHOLDER = DownloadData(
                listOf(DownloadTaskSummary("1", "movie.mkv", 0.45, "downloading")),
                3,
                5,
                System.currentTimeMillis()
            )

            fun fromJson(json: JSONObject): DownloadData {
                val tasksArray = json.optJSONArray("activeTasks") ?: JSONArray()
                val tasks = (0 until tasksArray.length()).map {
                    DownloadTaskSummary.fromJson(tasksArray.getJSONObject(it))
                }
                return DownloadData(
                    activeTasks = tasks,
                    completedCount = json.optInt("completedCount", 0),
                    totalCount = json.optInt("totalCount", 0),
                    lastUpdated = json.optLong("lastUpdated", 0)
                )
            }
        }
    }

    fun getDownloadData(): DownloadData {
        val jsonStr = prefs.getString(KEY_DOWNLOAD_DATA, null) ?: return DownloadData.EMPTY
        return try {
            DownloadData.fromJson(JSONObject(jsonStr))
        } catch (e: Exception) {
            DownloadData.EMPTY
        }
    }

    fun saveDownloadData(data: Map<String, Any?>) {
        val json = JSONObject(data)
        prefs.edit()
            .putString(KEY_DOWNLOAD_DATA, json.toString())
            .apply()
    }

    // ==================== Quick Access Data ====================

    data class QuickAccessData(
        val items: List<String>,
        val nasName: String?,
        val isConnected: Boolean
    ) {
        companion object {
            // 默认快捷操作项 - 使用与路由一致的名称
            val DEFAULT = QuickAccessData(listOf("music", "video", "reading"), null, false)

            fun fromJson(json: JSONObject): QuickAccessData {
                val itemsArray = json.optJSONArray("items") ?: JSONArray()
                val items = (0 until itemsArray.length()).map { itemsArray.getString(it) }
                return QuickAccessData(
                    items = items.ifEmpty { listOf("music", "video", "reading") },
                    nasName = json.optString("nasName", null),
                    isConnected = json.optBoolean("isConnected", false)
                )
            }
        }
    }

    fun getQuickAccessData(): QuickAccessData {
        val jsonStr = prefs.getString(KEY_QUICK_ACCESS_DATA, null)
            ?: return QuickAccessData.DEFAULT
        return try {
            QuickAccessData.fromJson(JSONObject(jsonStr))
        } catch (e: Exception) {
            QuickAccessData.DEFAULT
        }
    }

    fun saveQuickAccessData(data: Map<String, Any?>) {
        val json = JSONObject(data)
        prefs.edit()
            .putString(KEY_QUICK_ACCESS_DATA, json.toString())
            .apply()
    }

    // ==================== Media Data ====================

    data class MediaData(
        val title: String?,
        val artist: String?,
        val album: String?,
        val coverImagePath: String?,
        val isPlaying: Boolean,
        val progress: Double,
        val currentTime: Int,
        val totalTime: Int,
        val themeColor: Int?
    ) {
        val hasContent: Boolean
            get() = !title.isNullOrEmpty()

        companion object {
            val EMPTY = MediaData(null, null, null, null, false, 0.0, 0, 0, null)

            val PLACEHOLDER = MediaData(
                "Song Title",
                "Artist Name",
                "Album Name",
                null,
                true,
                0.45,
                120,
                300,
                null
            )

            fun fromJson(json: JSONObject): MediaData {
                return MediaData(
                    title = json.optString("title", null),
                    artist = json.optString("artist", null),
                    album = json.optString("album", null),
                    coverImagePath = json.optString("coverImagePath", null),
                    isPlaying = json.optBoolean("isPlaying", false),
                    progress = json.optDouble("progress", 0.0),
                    currentTime = json.optInt("currentTime", 0),
                    totalTime = json.optInt("totalTime", 0),
                    themeColor = if (json.has("themeColor")) json.optInt("themeColor") else null
                )
            }
        }
    }

    fun getMediaData(): MediaData {
        val jsonStr = prefs.getString(KEY_MEDIA_DATA, null) ?: return MediaData.EMPTY
        return try {
            MediaData.fromJson(JSONObject(jsonStr))
        } catch (e: Exception) {
            MediaData.EMPTY
        }
    }

    fun saveMediaData(data: Map<String, Any?>) {
        // Remove cover image data before saving to JSON
        val jsonData = data.toMutableMap()
        jsonData.remove("coverImageData")

        val json = JSONObject(jsonData)
        prefs.edit()
            .putString(KEY_MEDIA_DATA, json.toString())
            .apply()
    }

    fun saveCoverImage(imageData: ByteArray) {
        val file = File(context.cacheDir, "widget_cover.jpg")
        file.writeBytes(imageData)
        prefs.edit()
            .putString(KEY_COVER_IMAGE_PATH, file.absolutePath)
            .apply()
    }

    fun getCoverImage(): Bitmap? {
        val path = prefs.getString(KEY_COVER_IMAGE_PATH, null) ?: return null
        val file = File(path)
        if (!file.exists()) return null
        return try {
            BitmapFactory.decodeFile(path)
        } catch (e: Exception) {
            null
        }
    }

    // ==================== Utility ====================

    fun isNasConnected(): Boolean {
        return prefs.getBoolean(KEY_NAS_CONNECTED, false)
    }

    fun getNasName(): String? {
        return prefs.getString(KEY_NAS_NAME, null)
    }
}

/**
 * 格式化字节数为人类可读的字符串
 */
fun Long.formatBytes(): String {
    val bytes = this.toDouble()
    val kb = bytes / 1024
    val mb = kb / 1024
    val gb = mb / 1024
    val tb = gb / 1024

    return when {
        tb >= 1 -> String.format("%.1f TB", tb)
        gb >= 1 -> String.format("%.1f GB", gb)
        mb >= 1 -> String.format("%.1f MB", mb)
        kb >= 1 -> String.format("%.1f KB", kb)
        else -> "$this B"
    }
}

/**
 * 格式化秒数为时间字符串
 */
fun Int.formatDuration(): String {
    val hours = this / 3600
    val minutes = (this % 3600) / 60
    val seconds = this % 60

    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format("%d:%02d", minutes, seconds)
    }
}
