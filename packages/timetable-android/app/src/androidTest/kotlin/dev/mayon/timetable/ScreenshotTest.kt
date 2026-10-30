package dev.mayon.timetable

import android.graphics.Bitmap
import android.view.KeyEvent
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.mayon.timetable.core.Course
import dev.mayon.timetable.core.PeriodTime
import dev.mayon.timetable.core.Semester
import dev.mayon.timetable.core.TimetableV1
import dev.mayon.timetable.data.TimetableStore
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule
    val activityRule = createAndroidComposeRule<MainActivity>()

    private val semesterId = "screenshot-fixture"
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val outputDirectory by lazy {
        File(requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)), "proof").apply { mkdirs() }
    }
    private val round by lazy {
        InstrumentationRegistry.getArguments().getString("round", "round1").replace(Regex("[^A-Za-z0-9_-]"), "_")
    }
    private var themeName = "dark"

    @Before
    fun installFixtureAndReload() {
        val context = instrumentation.targetContext
        context.getSharedPreferences("device", 0).edit()
            .putBoolean("onboardingDone", true)
            .putInt("theme", 1)
            .commit()
        val zone = ZoneId.of("Asia/Shanghai")
        val today = LocalDate.now(zone)
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val slots = listOf(
            PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "08:55", "09:40"),
            PeriodTime(3, "10:10", "10:55"), PeriodTime(4, "11:05", "11:50"),
            PeriodTime(5, "14:00", "14:45"), PeriodTime(6, "14:55", "15:40"),
        )
        val todayWeekday = today.dayOfWeek.value
        val fixture = TimetableV1(
            semester = Semester(semesterId, "截图验收学期", monday.toString(), 16, zone.id, slots),
            courses = listOf(
                Course("shot-data", "数据结构", "林老师", "A-101", todayWeekday, 1, 2, (1..16).toSet()),
                Course("shot-math", "离散数学", "周老师", "B-204", todayWeekday, 3, 4, (1..16).toSet()),
                Course("shot-english", "大学英语", "陈老师", "C-302", todayWeekday, 5, 6, (1..16).toSet()),
                Course("shot-physics", "大学物理", "赵老师", "理学楼", todayWeekday % 7 + 1, 1, 2, (1..16).toSet()),
                Course("shot-sport", "体育", null, "操场", (todayWeekday + 5) % 7 + 1, 5, 6, (1..16).toSet()),
            ),
        ).requireValid()
        TimetableStore(context).apply { save(fixture, replace = true); activeId = semesterId }
        activityRule.activityRule.scenario.recreate()
        activityRule.waitUntil(8_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("截图验收学期")).fetchSemanticsNodes().isNotEmpty() &&
                activityRule.onAllNodes(androidx.compose.ui.test.hasText("数据结构")).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun captureRealAppScreensInDarkAndLightThemes() {
        captureTheme("dark", 1)
        captureTheme("light", 0)
    }

    private fun captureTheme(name: String, theme: Int) {
        themeName = name
        instrumentation.targetContext.getSharedPreferences("device", 0).edit().putInt("theme", theme).commit()
        activityRule.activityRule.scenario.recreate()
        activityRule.waitForIdle()
        activityRule.onNodeWithText("今日").performClick()
        activityRule.waitUntil(8_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("数据结构")).fetchSemanticsNodes().isNotEmpty()
        }
        saveScreen("today")

        activityRule.onNodeWithText("一周").performClick()
        activityRule.waitForIdle()
        saveScreen("week")

        activityRule.onNodeWithText("导入导出").performClick()
        activityRule.waitForIdle()
        saveScreen("import-export")

        activityRule.onNodeWithText("学期").performClick()
        activityRule.waitForIdle()
        saveScreen("semesters")

        activityRule.onNodeWithTag("semester-edit").performScrollTo().performClick()
        activityRule.waitForIdle()
        saveScreen("semester-editor")
        activityRule.onNodeWithText("取消").performClick()

        activityRule.onNodeWithText("今日").performClick()
        activityRule.onNodeWithText("数据结构").performClick()
        activityRule.waitForIdle()
        saveScreen("course-editor")
        activityRule.onNodeWithText("取消").performClick()

        activityRule.onNodeWithTag("settings").performClick()
        activityRule.waitForIdle()
        saveScreen("settings")
        activityRule.onNodeWithText("完成").performClick()

        activityRule.onNodeWithText("导入导出").performClick()
        activityRule.onNodeWithText("显示课表二维码").performScrollTo().performClick()
        activityRule.waitForIdle()
        saveScreen("qr-share")
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        activityRule.waitForIdle()
    }

    private fun saveScreen(screen: String) {
        activityRule.waitForIdle()
        Thread.sleep(500)
        val bitmap: Bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot()) { "设备未能截取 $screen 界面" }
        val destination = File(outputDirectory, "$round-$themeName-$screen.png")
        destination.outputStream().use { stream ->
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) { "无法保存 ${destination.name}" }
        }
        bitmap.recycle()
    }
}
