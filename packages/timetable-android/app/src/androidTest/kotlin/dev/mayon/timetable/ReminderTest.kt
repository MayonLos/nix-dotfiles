package dev.mayon.timetable

import android.app.Notification
import android.app.NotificationManager
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.mayon.timetable.core.*
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.reminders.ReminderScheduler
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import java.time.*
import java.time.temporal.TemporalAdjusters
import java.time.format.DateTimeFormatter
import java.io.File

/** Host handshake keeps one instrumentation alive: a new runner force-stops the target package. */
@RunWith(AndroidJUnit4::class)
class ReminderTest {
    @Test fun realAlarmFiresExactlyOnceAfterHostClockAdvance() {
        assumeTrue("Use tools/verify-reminder.sh for the host clock handshake",
            InstrumentationRegistry.getArguments().getString("clockHandshake") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val zone = ZoneId.of("Asia/Shanghai")
        val start = ZonedDateTime.now(zone).plusMinutes(4).withSecond(0).withNano(0)
        val end = start.plusMinutes(45)
        val monday = start.toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val table = TimetableV1(semester = Semester("alarm-proof", "提醒实测", monday.toString(), 16, zone.id,
            listOf(PeriodTime(1, start.format(DateTimeFormatter.ofPattern("HH:mm")), end.format(DateTimeFormatter.ofPattern("HH:mm"))))),
            courses = listOf(Course("reminder-proof", "提醒验证课程", "合成教师", "测试教室", start.dayOfWeek.value, 1, 1, setOf(1))))
        context.getSharedPreferences("device", 0).edit().putStringSet("delivered", emptySet()).commit()
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
        TimetableStore(context).apply { save(table, true); activeId = table.semester.id; leadMinutes = 1; remindersEnabled = true }
        assertTrue(ReminderScheduler(context).reschedule())
        File(context.filesDir, "reminder-ready.txt").writeText((start.toEpochSecond() - 60).toString())
        val deadline = SystemClock.elapsedRealtime() + 90_000
        fun matching() = manager.activeNotifications.filter {
            it.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() == "提醒验证课程"
        }
        while (matching().isEmpty() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(200)
        assertEquals("Expected one real notification from the scheduled reminder", 1, matching().size)
        File(context.filesDir, "reminder-delivered.txt").writeText("count=1; observed=" + Instant.now())
        val captureDeadline = SystemClock.elapsedRealtime() + 30_000
        val captured = File(context.filesDir, "reminder-captured.txt")
        while (!captured.exists() && SystemClock.elapsedRealtime() < captureDeadline) Thread.sleep(200)
        assertTrue("Host must capture the visible notification before instrumentation exits", captured.exists())
    }
}
