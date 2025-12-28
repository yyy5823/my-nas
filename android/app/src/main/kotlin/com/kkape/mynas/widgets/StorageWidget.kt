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
 * 存储状态小组件
 * 显示 NAS 存储使用情况
 */
class StorageWidget : AppWidgetProvider() {

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

        if (intent.action == WidgetDataChannel.ACTION_STORAGE_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, StorageWidget::class.java)
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
            val storageData = dataManager.getStorageData()

            val views = RemoteViews(context.packageName, R.layout.widget_storage)

            if (!storageData.isConnected || !storageData.hasValidData) {
                // 显示未连接状态
                views.setViewVisibility(R.id.layout_connected, View.GONE)
                views.setViewVisibility(R.id.layout_not_connected, View.VISIBLE)
            } else {
                // 显示存储信息
                views.setViewVisibility(R.id.layout_connected, View.VISIBLE)
                views.setViewVisibility(R.id.layout_not_connected, View.GONE)

                // NAS 名称
                views.setTextViewText(
                    R.id.text_nas_name,
                    storageData.nasName.ifEmpty { "NAS" }
                )

                // 使用百分比
                views.setTextViewText(
                    R.id.text_usage_percent,
                    "${storageData.usagePercentInt}%"
                )

                // 存储详情
                val usedStr = storageData.usedBytes.formatBytes()
                val totalStr = storageData.totalBytes.formatBytes()
                views.setTextViewText(
                    R.id.text_storage_info,
                    "$usedStr / $totalStr"
                )

                // 进度条
                views.setProgressBar(
                    R.id.progress_storage,
                    100,
                    storageData.usagePercentInt,
                    false
                )
            }

            // 点击打开应用
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("mynas://storage")).apply {
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
