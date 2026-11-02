package com.solobyte.revise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget « Révisions du jour » : nombre à revoir, liste, série, bouton +. */
class TodayWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val data = WidgetData.read(widgetData)
    for (id in appWidgetIds) {
      appWidgetManager.updateAppWidget(id, render(context, data, appWidgetManager.getAppWidgetOptions(id)))
    }
  }

  // Redimensionné : on ajuste le nombre de lignes.
  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: Bundle,
  ) {
    val data = WidgetData.read(HomeWidgetPlugin.getData(context))
    appWidgetManager.updateAppWidget(appWidgetId, render(context, data, newOptions))
  }

  private fun render(context: Context, data: WidgetData, options: Bundle): RemoteViews {
    val v = RemoteViews(context.packageName, R.layout.widget_today)
    val day = data.day
    val done = data.doneToday
    val allDone = day.count == 0 && done > 0

    v.setTextViewText(R.id.date, data.dateLabel)
    v.setInt(
        R.id.widget_root,
        "setBackgroundResource",
        if (allDone) R.drawable.widget_bg_done else R.drawable.widget_bg_blue,
    )
    when {
      day.count > 0 -> {
        v.setTextViewText(R.id.count, "${day.count}")
        v.setTextViewText(R.id.count_label, if (day.count > 1) "sujets à revoir" else "sujet à revoir")
      }
      allDone -> {
        v.setTextViewText(R.id.count, "✓")
        v.setTextViewText(R.id.count_label, "Journée bouclée !")
      }
      else -> {
        v.setTextViewText(R.id.count, "0")
        v.setTextViewText(R.id.count_label, "rien à revoir")
      }
    }
    val streak = data.streak
    v.setTextViewText(
        R.id.streak,
        if (streak > 0) "🔥 ${WidgetData.plural(streak, "jour")} de suite"
        else if (done > 0) "✓ ${WidgetData.plural(done, "révision")} aujourd'hui"
        else "Commence une série",
    )

    // Hauteur en portrait (MAX_HEIGHT) : en-tête ≈ 120 dp, puis ≈ 32 dp par ligne.
    val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        .takeIf { it > 0 } ?: options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
    val maxRows = ((height - 120) / 32).coerceIn(0, ROWS.size)
    val shown = minOf(day.items.size, maxRows)
    for ((i, row) in ROWS.withIndex()) {
      if (i < shown) {
        val item = day.items[i]
        v.setViewVisibility(row.row, View.VISIBLE)
        v.setTextViewText(row.title, item.title)
        v.setInt(row.dot, "setColorFilter", item.color)
        v.setOnClickPendingIntent(row.row, WidgetData.open(context, "retiens://topic?id=${item.id}"))
      } else {
        v.setViewVisibility(row.row, View.GONE)
      }
    }
    val rest = day.count - shown
    if (shown > 0 && rest > 0) {
      v.setViewVisibility(R.id.more, View.VISIBLE)
      v.setTextViewText(R.id.more, "+ ${WidgetData.plural(rest, "autre")}")
    } else {
      v.setViewVisibility(R.id.more, View.GONE)
    }
    val next = data.nextLabel
    if (day.count == 0 && maxRows > 0) {
      v.setViewVisibility(R.id.empty, View.VISIBLE)
      v.setTextViewText(
          R.id.empty,
          if (next != null) "Prochain rappel $next" else "Ajoute ce que tu étudies avec +",
      )
    } else {
      v.setViewVisibility(R.id.empty, View.GONE)
    }

    v.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "retiens://today"))
    v.setOnClickPendingIntent(R.id.add, WidgetData.open(context, "retiens://add"))
    return v
  }

  private data class Row(val row: Int, val dot: Int, val title: Int)

  companion object {
    private val ROWS =
        listOf(
            Row(R.id.row0, R.id.dot0, R.id.title0),
            Row(R.id.row1, R.id.dot1, R.id.title1),
            Row(R.id.row2, R.id.dot2, R.id.title2),
            Row(R.id.row3, R.id.dot3, R.id.title3),
        )
  }
}
