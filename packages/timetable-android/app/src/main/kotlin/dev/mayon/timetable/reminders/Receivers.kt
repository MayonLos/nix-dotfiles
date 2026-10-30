package dev.mayon.timetable.reminders

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import dev.mayon.timetable.MainActivity
import dev.mayon.timetable.R
import dev.mayon.timetable.core.occurrences
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.widget.WidgetRefreshScheduler
import dev.mayon.timetable.widget.TodayWidget
import dev.mayon.timetable.widget.NextWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant

private fun runAsync(receiver: BroadcastReceiver, context: Context, work: suspend () -> Unit) {
    val pending = receiver.goAsync()
    CoroutineScope(Dispatchers.IO).launch {
        try { work() }
        catch (_: Exception) {
            // Never dump parsing exceptions: their messages can include private timetable text.
            context.getSharedPreferences("device", Context.MODE_PRIVATE).edit()
                .putString("lastBackgroundError", "local_operation_failed").apply()
        } finally { pending.finish() }
    }
}

/** Deliver only lessons whose reminder time is within the last five minutes. */
internal suspend fun deliverDueReminders(context: Context, now: Instant) {
    val store = TimetableStore(context)
    val manager = context.getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(NotificationChannel("lessons", "上课提醒", NotificationManager.IMPORTANCE_HIGH))
    val canNotify = Build.VERSION.SDK_INT < 33 ||
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    if (!store.remindersEnabled || !canNotify) return
    val table = store.active() ?: return
    occurrences(table).filter { occurrence ->
        val due = occurrence.start.toInstant().minusSeconds(store.leadMinutes * 60L)
        !due.isAfter(now) && due.isAfter(now.minusSeconds(5 * 60)) && occurrence.end.toInstant().isAfter(now)
    }.forEach { occurrence ->
        val deliveryKey = "${occurrence.start.toEpochSecond()}:${table.semester.id}:${occurrence.course.id}:${store.leadMinutes}"
        if (!store.claimReminder(deliveryKey)) return@forEach
        val click = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // The complete delivery key is a notification tag, so colliding String.hashCode values cannot replace lessons.
        manager.notify(deliveryKey, 0, Notification.Builder(context, "lessons")
            .setSmallIcon(R.drawable.ic_lesson).setContentTitle(occurrence.course.name)
            .setContentText("${occurrence.start.toLocalTime()} · ${occurrence.course.classroom.orEmpty()}")
            .setContentIntent(click).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build())
    }
}

private suspend fun refreshAfterScheduleChange(context: Context, now: Instant) {
    deliverDueReminders(context, now)
    ReminderScheduler(context).reschedule(now)
    TodayWidget().updateAll(context); NextWidget().updateAll(context)
    WidgetRefreshScheduler(context).reschedule(now)
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = runAsync(this, context) {
        val now = Instant.now()
        deliverDueReminders(context, now)
        ReminderScheduler(context).reschedule(now)
        TodayWidget().updateAll(context); NextWidget().updateAll(context)
        WidgetRefreshScheduler(context).reschedule(now)
    }
}

class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_MY_PACKAGE_REPLACED,
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) return
        runAsync(this, context) {
            // Claim the due window before re-scheduling; the ledger prevents duplicate delivery.
            refreshAfterScheduleChange(context, Instant.now())
        }
    }
}
