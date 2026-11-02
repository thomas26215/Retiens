package com.solobyte.revise

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import org.json.JSONObject

/**
 * Données des widgets, préparées par l'app pour les 14 prochains jours
 * (lib/services/home_widgets.dart). Le widget choisit l'entrée du jour : il
 * reste juste au changement de date même si l'app n'a pas été ouverte.
 */
class WidgetData private constructor(private val json: JSONObject?) {

  data class Item(val id: String, val title: String, val color: Int)

  data class Day(val count: Int, val items: List<Item>)

  private val today = key(0)

  /** Sujets à revoir aujourd'hui (entrée du jour, ou la plus récente avant). */
  val day: Day by lazy {
    val days = json?.optJSONObject("days") ?: return@lazy Day(0, emptyList())
    val best = days.keys().asSequence().filter { it <= today }.maxOrNull()
    val o = best?.let { days.optJSONObject(it) } ?: return@lazy Day(0, emptyList())
    val arr = o.optJSONArray("items")
    val items = (0 until (arr?.length() ?: 0)).mapNotNull { i ->
      arr?.optJSONObject(i)?.let {
        Item(it.optString("id"), it.optString("t"), it.optLong("c", 0xFF8A8A8A).toInt())
      }
    }
    Day(o.optInt("n"), items)
  }

  /** Révisions faites aujourd'hui (0 si l'app n'a pas tourné aujourd'hui). */
  val doneToday: Int
    get() = if (json?.optString("doneDay") == today) json.optInt("done") else 0

  /** Série en cours : vivante si la dernière révision date d'hier ou d'aujourd'hui. */
  val streak: Int
    get() {
      val n = json?.optInt("streak") ?: 0
      val last = json?.optString("streakDay") ?: return 0
      return if (n > 0 && (last == today || last == key(-1))) n else 0
    }

  /** « demain », « dans 3 j »… pour le prochain jour qui aura des sujets. */
  val nextLabel: String?
    get() {
      val days = json?.optJSONObject("days") ?: return null
      for (offset in 1..13) {
        if ((days.optJSONObject(key(offset))?.optInt("n") ?: 0) > 0) {
          return if (offset == 1) "demain" else "dans $offset j"
        }
      }
      return null
    }

  /** « Vendredi 23 octobre ». */
  val dateLabel: String
    get() =
        SimpleDateFormat("EEEE d MMMM", Locale.FRENCH).format(Date()).replaceFirstChar {
          it.uppercase()
        }

  companion object {
    private const val KEY = "retiens_widget"

    fun read(prefs: SharedPreferences): WidgetData =
        WidgetData(prefs.getString(KEY, null)?.let { runCatching { JSONObject(it) }.getOrNull() })

    /** Date du jour décalée de [offset] jours, au format yyyy-MM-dd. */
    fun key(offset: Int): String {
      val c = Calendar.getInstance()
      c.add(Calendar.DAY_OF_YEAR, offset)
      return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(c.time)
    }

    /** Ouvre l'app sur [link] (retiens://today, retiens://add, retiens://topic?id=…). */
    fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    fun plural(n: Int, word: String) = if (n > 1) "$n ${word}s" else "$n $word"
  }
}
