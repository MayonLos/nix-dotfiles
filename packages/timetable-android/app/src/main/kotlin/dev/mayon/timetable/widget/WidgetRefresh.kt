package dev.mayon.timetable.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.mayon.timetable.core.occurrences
import dev.mayon.timetable.data.TimetableStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** Schedules the next local day or lesson boundary with a normal, inexact RTC alarm. */
class WidgetRefreshScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    private fun pendingIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, WidgetRefreshReceiver::class.java).setAction(ACTION_REFRESH),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun reschedule(now: Instant = Instant.now()): Boolean {
        val pending = pendingIntent()
        alarmManager.cancel(pending)
        return try {
            val table = TimetableStore(context).active()
            val zone = table?.let { ZoneId.of(it.semester.timeZone) } ?: ZoneId.systemDefault()
            val localNow = now.atZone(zone)
            val candidates = buildList {
                add(localNow.toLocalDate().plusDays(1).atStartOfDay(zone).toInstant())
                table?.let { schedule ->
                    occurrences(schedule).forEach { occurrence ->
                        add(occurrence.start.toInstant())
                        add(occurrence.end.toInstant())
                    }
                }
            }.filter { it.isAfter(now.plusSeconds(1)) }
            val next = candidates.minOrNull() ?: localNow.toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
            // Deliberately not setExact*: widget freshness must not request precise-alarm access.
            alarmManager.set(AlarmManager.RTC_WAKEUP, next.toEpochMilli(), pending)
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val ACTION_REFRESH = "dev.mayon.timetable.action.REFRESH_WIDGETS"
        private const val REQUEST_CODE = 7365
    }
}

/** Explicit-only receiver for inexact widget refresh alarms. */
class WidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try { refreshTimetableWidgets(context) }
            finally { result.finish() }
        }
    }
}
