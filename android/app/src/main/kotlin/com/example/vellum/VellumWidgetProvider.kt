package com.example.vellum

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Compact "继续阅读" widget. It intentionally launches the same safe app
 * entry point as the launcher; the Flutter shell can then restore the last
 * reading state without duplicating book data in a widget process.
 */
class VellumWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context,
            4101,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_continue_reading)
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_continue_title))
            views.setTextViewText(R.id.widget_subtitle, context.getString(R.string.widget_continue_subtitle))
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            views.setOnClickPendingIntent(R.id.widget_open, pending)
            manager.updateAppWidget(id, views)
        }
    }
}
