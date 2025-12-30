package com.kkape.mynas.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.kkape.mynas.R

/**
 * 快捷操作小组件
 * 一键访问音乐、视频、图书等功能
 */
class QuickAccessWidget : AppWidgetProvider() {

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

        if (intent.action == WidgetDataChannel.ACTION_QUICK_ACCESS_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, QuickAccessWidget::class.java)
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
            val views = RemoteViews(context.packageName, R.layout.widget_quick_access)

            // 音乐按钮
            views.setOnClickPendingIntent(
                R.id.btn_music,
                createPendingIntent(context, "mynas://music")
            )

            // 视频按钮
            views.setOnClickPendingIntent(
                R.id.btn_video,
                createPendingIntent(context, "mynas://video")
            )

            // 图书按钮 - 对应路由 /reading
            views.setOnClickPendingIntent(
                R.id.btn_book,
                createPendingIntent(context, "mynas://reading")
            )

            // 相册按钮（如果有的话）
            views.setOnClickPendingIntent(
                R.id.btn_photo,
                createPendingIntent(context, "mynas://photo")
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createPendingIntent(context: Context, uriString: String): PendingIntent {
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
