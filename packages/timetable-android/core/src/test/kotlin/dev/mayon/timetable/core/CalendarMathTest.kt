package dev.mayon.timetable.core

import java.time.LocalDate
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CalendarMathTest {
    private fun fixture(zone: String = "Asia/Shanghai") = TimetableV1(
        semester = Semester("synthetic-2026", "合成学期", "2026-09-07", 18, zone,
            listOf(PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "08:55", "09:40"))),
        courses = listOf(Course("lesson", "合成课程", weekday = 1, periodStart = 1, periodEnd = 2,
            weeks = setOf(1, 3, 18))),
    )

    @Test fun weekBoundariesUseMondayAndFloorBeforeSemester() {
        val table = fixture()
        assertEquals(0, weekAt(table, LocalDate.parse("2026-09-06")))
        assertEquals(-1, weekAt(table, LocalDate.parse("2026-08-30")))
        assertEquals(1, weekAt(table, LocalDate.parse("2026-09-07")))
        assertEquals(1, weekAt(table, LocalDate.parse("2026-09-13")))
        assertEquals(2, weekAt(table, LocalDate.parse("2026-09-14")))
        assertEquals(18, weekAt(table, LocalDate.parse("2027-01-10")))
        assertEquals(19, weekAt(table, LocalDate.parse("2027-01-11")))
    }

    @Test fun explicitWeeksGenerateExactlyTheCorrectDatesAndEndTime() {
        val values = occurrences(fixture())
        assertEquals(listOf("2026-09-07", "2026-09-21", "2027-01-04"), values.map { it.start.toLocalDate().toString() })
        assertEquals(Instant.parse("2026-09-07T00:00:00Z"), values.first().start.toInstant())
        assertEquals("09:40", values.first().end.toLocalTime().toString())
        assertEquals(3, values.size)
    }

    @Test fun daySevenAndSemesterZoneAreIndependentOfDeviceDefaultZone() {
        val table = fixture().let { it.copy(courses = listOf(it.courses.first().copy(weekday = 7, weeks = setOf(1)))) }
        val saved = java.util.TimeZone.getDefault()
        try {
            java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("America/Los_Angeles"))
            val lesson = occurrences(table).single()
            assertEquals("2026-09-13", lesson.start.toLocalDate().toString())
            assertEquals(Instant.parse("2026-09-13T00:00:00Z"), lesson.start.toInstant())
        } finally { java.util.TimeZone.setDefault(saved) }
    }

    @Test fun zoneRulesApplyDifferentUtcOffsetsAcrossDstBoundary() {
        val table = fixture("America/New_York").let { it.copy(courses = listOf(it.courses.first().copy(weeks = setOf(1, 10)))) }
        val values = occurrences(table)
        assertEquals("-04:00", values.first().start.offset.toString())
        assertEquals("-05:00", values.last().start.offset.toString())
    }

    @Test fun invalidSnapshotDoesNotProducePartialOccurrences() {
        val table = fixture().let { it.copy(courses = listOf(it.courses.first().copy(weeks = setOf(19)))) }
        assertFailsWith<IllegalArgumentException> { occurrences(table) }
    }
}
