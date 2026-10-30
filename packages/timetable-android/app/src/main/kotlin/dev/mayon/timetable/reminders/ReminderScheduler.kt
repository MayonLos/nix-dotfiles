package dev.mayon.timetable.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.core.occurrences
import java.time.Instant

/** One rolling exact alarm avoids platform per-UID alarm limits. Rebuild after each delivery/edit. */
class ReminderScheduler(private val context: Context) {
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private fun pending(): PendingIntent = PendingIntent.getBroadcast(context, 1,
        Intent(context, ReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun reschedule(now: Instant = Instant.now()): Boolean {
        alarms.cancel(pending())
        val store = TimetableStore(context)
        if (!store.remindersEnabled) return true
        val table = store.active() ?: return true
        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) return false
        val next = occurrences(table).map { it.start.toInstant().minusSeconds(store.leadMinutes * 60L) }
            .firstOrNull { it.isAfter(now) } ?: return true
        return try {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.toEpochMilli(), pending())
            true
        } catch (_: SecurityException) { false }
    }
}
