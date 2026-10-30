package dev.mayon.timetable

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
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
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule
    val activityRule = createAndroidComposeRule<MainActivity>()

    private val semesterId = "ui-flow-fixture"

    @Before
    fun installFixtureAndReload() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("device", 0).edit()
            .putBoolean("onboardingDone", true)
            .putInt("theme", 1)
            .commit()
        val zone = ZoneId.of("Asia/Shanghai")
        val today = LocalDate.now(zone)
        val monday = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val slots = listOf(
            PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "08:55", "09:40"),
            PeriodTime(3, "10:00", "10:45"), PeriodTime(4, "10:55", "11:40"),
            PeriodTime(5, "13:30", "14:15"), PeriodTime(6, "14:25", "15:10"),
            PeriodTime(7, "15:30", "16:15"), PeriodTime(8, "16:25", "17:10"),
        )
        val fixture = TimetableV1(
            semester = Semester(semesterId, "自动化测试学期", monday.toString(), 16, zone.id, slots),
            courses = listOf(Course("ui-flow-course", "测试数学", "林老师", "A-101", today.dayOfWeek.value, 1, 1, setOf(1))),
        ).requireValid()
        TimetableStore(context).apply { save(fixture, replace = true); activeId = semesterId }
        activityRule.activityRule.scenario.recreate()
        activityRule.waitUntil(5_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("测试数学")).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun todayWeekCourseEditAndSemesterEdit() {
        activityRule.onNodeWithText("测试数学").assertIsDisplayed()

        activityRule.onNodeWithText("一周").performClick()
        activityRule.waitUntil(5_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("第 1 周", substring = true)).fetchSemanticsNodes().isNotEmpty()
        }
        activityRule.onNodeWithTag("week-next").performClick()
        activityRule.waitUntil(5_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("第 2 周", substring = true)).fetchSemanticsNodes().isNotEmpty()
        }
        activityRule.onNodeWithTag("week-previous").performClick()
        activityRule.onNodeWithText("今日").performClick()

        activityRule.onNodeWithText("测试数学").performClick()
        activityRule.onNodeWithTag("course-name").performScrollTo().performTextClearance()
        activityRule.onNodeWithTag("course-name").performTextInput("数据结构")
        activityRule.onNodeWithTag("course-save").performClick()
        activityRule.waitUntil(5_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("数据结构")).fetchSemanticsNodes().isNotEmpty()
        }

        activityRule.onNodeWithText("学期").performClick()
        activityRule.onNodeWithTag("semester-edit").performScrollTo().performClick()
        activityRule.onNodeWithTag("semester-name").performScrollTo().performTextClearance()
        activityRule.onNodeWithTag("semester-name").performTextInput("测试学期修订")
        activityRule.onNodeWithTag("semester-total-weeks").performScrollTo().performTextClearance()
        activityRule.onNodeWithTag("semester-total-weeks").performTextInput("15")
        activityRule.onNodeWithTag("semester-save").performClick()
        activityRule.waitUntil(5_000) {
            activityRule.onAllNodes(androidx.compose.ui.test.hasText("测试学期修订")).fetchSemanticsNodes().isNotEmpty()
        }
        activityRule.onAllNodes(androidx.compose.ui.test.hasText("测试学期修订")).onFirst().assertTextContains("测试学期修订")
    }
}
