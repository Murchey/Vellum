package com.example.vellum

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/** Dynamic, metadata-only VELLUM bookshelf widget. */
class VellumWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        val snapshot = readSnapshot(context)
        val pending = openAppPendingIntent(context)
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_continue_reading)
            renderSnapshot(context, views, snapshot)
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            manager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, VellumWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) onUpdate(context, manager, ids)
            return
        }
        super.onReceive(context, intent)
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            4101,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun renderSnapshot(
        context: Context,
        views: RemoteViews,
        snapshot: ShelfSnapshot,
    ) {
        val current = snapshot.books.firstOrNull { it.id == snapshot.currentBookId }
        views.setTextViewText(
            R.id.widget_current_title,
            current?.title?.ifBlank { context.getString(R.string.widget_empty_title) }
                ?: context.getString(R.string.widget_empty_title),
        )
        views.setTextViewText(
            R.id.widget_progress_label,
            if (current == null) {
                context.getString(R.string.widget_empty_subtitle)
            } else {
                context.getString(
                    R.string.widget_progress_format,
                    (current.progress * 100).toInt().coerceIn(0, 100),
                )
            },
        )
        views.setProgressBar(
            R.id.widget_progress,
            100,
            ((current?.progress ?: 0.0) * 100).toInt().coerceIn(0, 100),
            false,
        )
        views.setViewVisibility(
            R.id.widget_progress,
            if (current == null) View.GONE else View.VISIBLE,
        )
        views.setViewVisibility(
            R.id.widget_empty,
            if (snapshot.books.isEmpty()) View.VISIBLE else View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_shelf_row,
            if (snapshot.books.isEmpty()) View.GONE else View.VISIBLE,
        )

        val spineIds = intArrayOf(
            R.id.widget_spine_1,
            R.id.widget_spine_2,
            R.id.widget_spine_3,
            R.id.widget_spine_4,
            R.id.widget_spine_5,
        )
        val spineBackgrounds = intArrayOf(
            R.drawable.widget_spine_current,
            R.drawable.widget_spine_sage,
            R.drawable.widget_spine_ochre,
            R.drawable.widget_spine_ink,
            R.drawable.widget_spine_rose,
        )
        spineIds.forEachIndexed { index, id ->
            val book = snapshot.books.getOrNull(index)
            if (book == null) {
                views.setViewVisibility(id, View.GONE)
            } else {
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, book.title)
                views.setInt(id, "setBackgroundResource", spineBackgrounds[index])
                views.setContentDescription(id, book.title)
            }
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.example.vellum.action.REFRESH_WIDGET"
        const val SNAPSHOT_FILE = "vellum_widget_shelf.json"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, VellumWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                context.sendBroadcast(
                    Intent(context, VellumWidgetProvider::class.java)
                        .setAction(ACTION_REFRESH),
                )
            }
        }

        private fun readSnapshot(context: Context): ShelfSnapshot {
            return try {
                val root = JSONObject(
                    context.filesDir.resolve(SNAPSHOT_FILE).readText(Charsets.UTF_8),
                )
                if (root.optInt("version", 0) != 1) return ShelfSnapshot.empty()
                val currentId = root.optString("currentBookId", "")
                val array = root.optJSONArray("books") ?: return ShelfSnapshot.empty()
                val books = mutableListOf<ShelfBook>()
                val seen = mutableSetOf<String>()
                for (index in 0 until minOf(array.length(), 5)) {
                    val item = array.optJSONObject(index) ?: continue
                    val id = item.optString("id", "").trim()
                    val title = item.optString("title", "").trim()
                    if (id.isEmpty() || title.isEmpty() || !seen.add(id)) continue
                    books += ShelfBook(
                        id = id,
                        title = title,
                        progress = item.optDouble("progress", 0.0).coerceIn(0.0, 1.0),
                    )
                }
                val resolvedCurrent = if (books.any { it.id == currentId }) {
                    currentId
                } else {
                    books.firstOrNull()?.id.orEmpty()
                }
                ShelfSnapshot(resolvedCurrent, books)
            } catch (_: Exception) {
                ShelfSnapshot.empty()
            }
        }
    }
}

private data class ShelfBook(
    val id: String,
    val title: String,
    val progress: Double,
)

private data class ShelfSnapshot(
    val currentBookId: String,
    val books: List<ShelfBook>,
) {
    companion object {
        fun empty() = ShelfSnapshot("", emptyList())
    }
}
