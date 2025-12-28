package com.kkape.mynas.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.kkape.mynas.R

/**
 * 媒体播放小组件
 * 显示正在播放的音乐
 */
class MediaWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == WidgetDataChannel.ACTION_MEDIA_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, MediaWidget::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val dataManager = WidgetDataManager(context)
            val mediaData = dataManager.getMediaData()
            val coverImage = dataManager.getCoverImage()

            val views = RemoteViews(context.packageName, R.layout.widget_media)

            if (!mediaData.hasContent) {
                // 无播放内容
                views.setViewVisibility(R.id.layout_playing, View.GONE)
                views.setViewVisibility(R.id.layout_not_playing, View.VISIBLE)
            } else {
                // 显示播放信息
                views.setViewVisibility(R.id.layout_playing, View.VISIBLE)
                views.setViewVisibility(R.id.layout_not_playing, View.GONE)

                // 封面图片
                if (coverImage != null) {
                    views.setImageViewBitmap(R.id.image_cover, coverImage)
                } else {
                    views.setImageViewResource(R.id.image_cover, R.drawable.ic_music_note)
                }

                // 歌曲标题
                views.setTextViewText(
                    R.id.text_title,
                    mediaData.title ?: "未知歌曲"
                )

                // 艺术家
                views.setTextViewText(
                    R.id.text_artist,
                    mediaData.artist ?: "未知艺术家"
                )

                // 播放/暂停按钮图标
                views.setImageViewResource(
                    R.id.btn_play_pause,
                    if (mediaData.isPlaying) R.drawable.ic_pause else R.drawable.ic_play
                )

                // 进度条
                val progressPercent = (mediaData.progress * 100).toInt()
                views.setProgressBar(
                    R.id.progress_media,
                    100,
                    progressPercent,
                    false
                )

                // 时间显示
                views.setTextViewText(
                    R.id.text_current_time,
                    mediaData.currentTime.formatDuration()
                )
                views.setTextViewText(
                    R.id.text_total_time,
                    mediaData.totalTime.formatDuration()
                )

                // 控制按钮
                views.setOnClickPendingIntent(
                    R.id.btn_previous,
                    createControlIntent(context, "mynas://music/previous")
                )
                views.setOnClickPendingIntent(
                    R.id.btn_play_pause,
                    createControlIntent(context, "mynas://music/toggle")
                )
                views.setOnClickPendingIntent(
                    R.id.btn_next,
                    createControlIntent(context, "mynas://music/next")
                )
            }

            // 点击打开播放器
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("mynas://music/player")).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createControlIntent(context: Context, uriString: String): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uriString)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            return PendingIntent.getActivity(
                context,
                uriString.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
