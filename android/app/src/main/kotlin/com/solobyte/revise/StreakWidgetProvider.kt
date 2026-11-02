package com.solobyte.revise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget « Série » : flamme, jours de suite et progression du jour. */
class StreakWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val data = WidgetData.read(widgetData)
    for (id in appWidgetIds) {
      appWidgetManager.updateAppWidget(id, render(context, data))
    }
  }

  private fun render(context: Context, data: WidgetData): RemoteViews {
    val v = RemoteViews(context.packageName, R.layout.widget_streak)
    val streak = data.streak
    val done = data.doneToday
    val total = done + data.day.count

    // Flamme orange tant que la série est vivante, grise sinon.
    v.setInt(
        R.id.widget_root,
        "setBackgroundResource",
        if (streak > 0) R.drawable.widget_bg_flame else R.drawable.widget_bg_flame_off,
    )
    v.setTextViewText(R.id.streak_count, "$streak")
    v.setTextViewText(R.id.streak_label, if (streak > 1) "jours de suite" else "jour de suite")
    v.setTextViewText(
        R.id.streak_today,
        when {
          total == 0 -> "rien aujourd'hui"
          done == total -> "tout est revu ✓"
          else -> "$done/$total aujourd'hui"
        },
    )
    v.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "retiens://today"))
    return v
  }
}
