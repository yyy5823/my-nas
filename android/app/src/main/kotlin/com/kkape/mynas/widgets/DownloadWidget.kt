package com.kkape.mynas.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.kkape.mynas.R

/**
 * 下载进度小组件
 * 显示当前下载任务
 */
class DownloadWidget : AppWidgetProvider() {

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

        if (intent.action == WidgetDataChannel.ACTION_DOWNLOAD_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, DownloadWidget::class.java)
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
            val downloadData = dataManager.getDownloadData()

            val views = RemoteViews(context.packageName, R.layout.widget_download)

            if (!downloadData.hasActiveDownloads) {
                // 无下载任务
                views.setViewVisibility(R.id.layout_downloading, View.GONE)
                views.setViewVisibility(R.id.layout_no_downloads, View.VISIBLE)

                // 显示已完成数量
                if (downloadData.completedCount > 0) {
                    views.setTextViewText(
                        R.id.text_completed_count,
                        "已完成 ${downloadData.completedCount} 个"
                    )
                    views.setViewVisibility(R.id.text_completed_count, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.text_completed_count, View.GONE)
                }
            } else {
                // 显示下载进度
                views.setViewVisibility(R.id.layout_downloading, View.VISIBLE)
                views.setViewVisibility(R.id.layout_no_downloads, View.GONE)

                // 活跃任务数
                views.setTextViewText(
                    R.id.text_active_count,
                    "${downloadData.activeCount}"
                )

                // 总体进度
                val progressPercent = (downloadData.overallProgress * 100).toInt()
                views.setTextViewText(
                    R.id.text_progress_percent,
                    "${progressPercent}%"
                )

                // 进度条
                views.setProgressBar(
                    R.id.progress_download,
                    100,
                    progressPercent,
                    false
                )

                // 当前文件名
                val fileName = downloadData.currentFileName
                if (fileName != null) {
                    views.setTextViewText(R.id.text_current_file, fileName)
                    views.setViewVisibility(R.id.text_current_file, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.text_current_file, View.GONE)
                }
            }

            // 点击打开下载管理 - 导航到"我的"页面
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("mynas://mine")).apply {
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
    }
}
