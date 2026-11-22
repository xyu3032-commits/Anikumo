package com.anikumo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Batch 284 (#32): the "今日放送" home-screen widget.
 * Dart (HomeWidgetPublisher.publishCalendar) merges the
 * anime broadcast calendar and the film zone's TVmaze
 * schedule into up to four display lines; this provider
 * only renders them. Tapping opens the app.
 */
class CalendarWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("cw_title", null) ?: "今日放送"
        val lines = widgetData.getString("cw_lines", null) ?: ""
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            1,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.calendar_widget)
            views.setTextViewText(R.id.cw_title, title)
            views.setTextViewText(R.id.cw_lines, lines)
            views.setOnClickPendingIntent(R.id.cw_root, pendingIntent)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
