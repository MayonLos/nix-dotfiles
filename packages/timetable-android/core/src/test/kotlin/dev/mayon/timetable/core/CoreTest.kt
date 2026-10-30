package dev.mayon.timetable.core

import org.junit.Test
import java.io.File
import java.time.LocalDate
import java.time.DayOfWeek
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CoreTest {
    private val timetable = TimetableV1(
        semester = Semester(
            id = "test-fall", name = "测试学期", startDate = "2026-09-07", totalWeeks = 16,
            timeZone = "Asia/Shanghai",
            timeSlots = listOf(PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "08:55", "09:40"), PeriodTime(3, "10:00", "10:45")),
        ),
        courses = listOf(Course("math", "数学", "王老师", "教 1-203", 1, 1, 2, setOf(1, 3, 5), "#61AFEF", "备注")),
    )

    @Test fun `week expression parses ranges parity and lists`() {
        assertEquals((1..16 step 2).toSet(), WeekExpression.parse("1-16周(单)", 16))
        assertEquals((2..16 step 2).toSet(), WeekExpression.parse("第2-16周（双）", 16))
        assertEquals((1..7 step 2).toSet() + (10..16 step 2).toSet(), WeekExpression.parse("1-8周(单),9-16周(双)", 16))
        assertFailsWith<IllegalArgumentException> { WeekExpression.parse("1-8周单双", 16) }
        assertEquals(setOf(1, 5, 7), WeekExpression.parse("1,5、7周", 16))
        assertEquals(setOf(16), WeekExpression.parse("16周", 16))
        assertFailsWith<IllegalArgumentException> { WeekExpression.parse("16-1周", 16) }
        assertFailsWith<IllegalArgumentException> { WeekExpression.parse("1-17周", 16) }
    }

    @Test fun `JSON round trip validates format and ISO weekday semantics`() {
        assertEquals(timetable, TimetableJson.decode(TimetableJson.encode(timetable)))
        assertTrue(timetable.validate().isEmpty())
        assertFailsWith<IllegalArgumentException> { TimetableJson.decode(TimetableJson.encode(timetable).replace("\"weekday\": 1", "\"weekday\": 8")) }
        assertFailsWith<IllegalArgumentException> { TimetableJson.decode(TimetableJson.encode(timetable).replace("\"version\": 1,", "")) }
        assertEquals(LocalDate.parse("2026-09-07"), timetable.semester.firstDay())
        assertFalse(timetable.copy(semester = timetable.semester.copy(startDate = "2026-09-08")).validate().isEmpty())
        assertFalse(timetable.copy(semester = timetable.semester.copy(startDate = "2026-02-30")).validate().isEmpty())
        assertFalse(timetable.copy(semester = timetable.semester.copy(timeSlots = listOf(PeriodTime(1, "08:00:00", "08:45")))).validate().isEmpty())
        assertFalse(timetable.copy(semester = timetable.semester.copy(timeSlots = listOf(PeriodTime(1, "08:00", "08:45"), PeriodTime(3, "09:00", "09:45"))), courses = listOf(timetable.courses.single().copy(periodEnd = 3))).validate().isEmpty())
    }

    @Test fun `WakeUp share response and offline backup fixtures parse`() {
        val online = WakeUpParser.parseShareResponse(File("fixtures/wakeup/share-response.json").readText())
        assertEquals(2, online.courses.size)
        assertEquals("测试数学", online.courses.first().name)
        assertEquals(2, online.courses.first().periodEnd)
        assertEquals((1..15 step 2).toSet(), online.courses.first().weeks)
        assertEquals((2..16 step 2).toSet(), online.courses.last().weeks)
        assertEquals("自建分享课表", online.semester.name)
        val legacyCandidate = WakeUpParser.parseShareResponse(File("fixtures/wakeup/legacy-share-candidate.json").readText())
        assertEquals("旧格式数学", legacyCandidate.courses.single().name)
        val backup = WakeUpParser.parseBackup(File("fixtures/wakeup/backup-lines.jsonl").readText())
        assertEquals(2, backup.courses.size)
        assertEquals("测试物理", backup.courses.first().name)
        assertEquals(setOf(2, 4, 6, 8, 10, 12, 14, 16), backup.courses.first().weeks)
        assertEquals("实验报告", backup.courses.first().notes)
        assertEquals(setOf(1, 3, 5, 7, 9, 11, 13, 15), backup.courses.last().weeks)
        assertFailsWith<IllegalArgumentException> {
            WakeUpParser.parseBackup(File("fixtures/wakeup/backup-lines.jsonl").readText().replace("\"ownTime\":false", "\"ownTime\":true"))
        }
        assertEquals("A02+/=share-token", WakeUpParser.extractShareKey("分享口令为「A02+/=share-token」"))
        assertEquals("0123456789ABCDEF0123456789ABCDEF", WakeUpParser.extractShareKey("分享口令为「0123456789ABCDEF0123456789ABCDEF」"))
        assertEquals("0123456789abcdef0123456789abcdef", WakeUpParser.extractShareKey("share key 0123456789abcdef0123456789abcdef"))
        assertFailsWith<IllegalArgumentException> { WakeUpParser.parseShareResponse("{\"status\":0,\"data\":{}}") }
    }

    @Test fun `ICS round trip retains periods week set and escaped text`() {
        val encoded = IcsCodec.export(timetable)
        assertTrue(encoded.contains("SUMMARY:数学"))
        assertTrue(encoded.contains("X-TIMETABLE-WEEK:3"))
        val decoded = IcsCodec.import(encoded, timetable.semester)
        assertEquals(timetable, decoded)
        assertTrue(encoded.contains("DTSTART:20260907T000000Z"))
        val emptyOptional = timetable.copy(courses = listOf(timetable.courses.single().copy(teacher = "", classroom = "", notes = "")))
        assertEquals(emptyOptional, IcsCodec.import(IcsCodec.export(emptyOptional), timetable.semester))
        val emojiCourse = timetable.copy(courses = listOf(timetable.courses.single().copy(name = "复杂😀课程名".repeat(12) + "literal\\ntext", notes = "line1\nline2")))
        val folded = IcsCodec.export(emojiCourse)
        assertTrue(folded.contains("\r\n "))
        assertEquals(emojiCourse, IcsCodec.import(folded, timetable.semester))
    }

    @Test fun `ICS weekly external recurrence expands and unsupported recurrence fails`() {
        val ics = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:external
DTSTART;TZID=Asia/Shanghai:20260907T080000
DTEND;TZID=Asia/Shanghai:20260907T084500
SUMMARY:External
LOCATION:Room 1
DESCRIPTION:external event note
RRULE:FREQ=WEEKLY;BYDAY=MO;INTERVAL=2;UNTIL=20261005
X-TIMETABLE-PERIOD-START:1
X-TIMETABLE-PERIOD-END:1
END:VEVENT
END:VCALENDAR
"""
        val imported = IcsCodec.import(ics, timetable.semester)
        assertEquals(setOf(1, 3, 5), imported.courses.single().weeks)
        assertEquals("external event note", imported.courses.single().notes)
        assertEquals(null, imported.courses.single().teacher)
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("FREQ=WEEKLY", "FREQ=DAILY"), timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("INTERVAL=2", "INTERVAL=nope"), timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("20260907T080000", "20260230T080000"), timetable.semester) }
        val multiDay = ics.replace("BYDAY=MO", "BYDAY=MO,WE").replace("UNTIL=20261005", "UNTIL=20261012")
        assertEquals(setOf(1, 3, 5), IcsCodec.import(multiDay, timetable.semester).courses.single { it.weekday == 1 }.weeks)
        assertEquals(setOf(1, 3, 5), IcsCodec.import(multiDay, timetable.semester).courses.single { it.weekday == 3 }.weeks)
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("RRULE:FREQ=WEEKLY;BYDAY=MO;INTERVAL=2;UNTIL=20261005", "RRULE:FREQ=WEEKLY;COUNT=3"), timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("BYDAY=MO;INTERVAL=2", "BYDAY=1MO;INTERVAL=2"), timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("UNTIL=20261005", "UNTIL=20261005T235959Z"), timetable.semester) }
        val allDay = ics.replace("DTSTART;TZID=Asia/Shanghai:20260907T080000", "DTSTART;VALUE=DATE:20260907")
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(allDay, timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("X-TIMETABLE-PERIOD-START:1", "X-TIMETABLE-WEEKDAY:2\nX-TIMETABLE-PERIOD-START:1"), timetable.semester) }
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("X-TIMETABLE-PERIOD-END:1", "X-TIMETABLE-PERIOD-END:2"), timetable.semester) }
        val wednesdayStart = ics.replace("20260907T080000", "20260909T080000").replace("20260907T084500", "20260909T084500")
            .replace("BYDAY=MO;INTERVAL=2;UNTIL=20261005", "BYDAY=MO,WE;INTERVAL=2;UNTIL=20261012")
        assertEquals(setOf(1, 3, 5), IcsCodec.import(wednesdayStart, timetable.semester).courses.single { it.weekday == DayOfWeek.WEDNESDAY.value }.weeks)
        assertEquals(setOf(3, 5), IcsCodec.import(wednesdayStart, timetable.semester).courses.single { it.weekday == DayOfWeek.MONDAY.value }.weeks)
        val uidCalendar = ics.replace("UID:external", "UID:external-event@example.com")
        assertTrue(IcsCodec.import(uidCalendar, timetable.semester).courses.single().id.startsWith("external_"))
        assertFailsWith<IllegalArgumentException> { IcsCodec.import(ics.replace("END:VEVENT", "EXDATE:20260921T080000\nEND:VEVENT"), timetable.semester) }
    }

    @Test fun `layout reconstruction clusters independent OCR lines without merging adjacent classes`() {
        val boxes = buildList {
            listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日").forEachIndexed { index, day ->
                val x = 100.0 + index * 100.0
                add(TextBox(day, x, 10.0, x + 40.0, 30.0, .99))
            }
            add(TextBox("第1节", 10.0, 90.0, 60.0, 110.0, .95))
            add(TextBox("第2节", 10.0, 190.0, 60.0, 210.0, .95))
            add(TextBox("第3节", 10.0, 290.0, 60.0, 310.0, .95))
            add(TextBox("高等数学", 110.0, 70.0, 190.0, 90.0, .97))
            add(TextBox("老师：王老师", 110.0, 94.0, 190.0, 110.0, .91))
            add(TextBox("教室：A101", 110.0, 112.0, 190.0, 128.0, .90))
            add(TextBox("3,5,7周", 110.0, 130.0, 190.0, 146.0, .89))
            add(TextBox("线性代数", 110.0, 170.0, 190.0, 190.0, .96))
            add(TextBox("2,4,6周", 110.0, 205.0, 190.0, 222.0, .90))
            add(TextBox("星期一选修", 110.0, 270.0, 190.0, 290.0, .94))
        }
        val result = GridReconstructor.reconstruct(boxes, 800.0, 400.0)
        assertEquals(3, result.cells.size)
        assertEquals(listOf("高等数学", "线性代数", "星期一选修"), result.cells.map { it.courseName })
        assertEquals(setOf(3, 5, 7), result.cells[0].weeks)
        assertEquals("王老师", result.cells[0].teacher)
        assertEquals("A101", result.cells[0].classroom)
        assertEquals(setOf(2, 4, 6), result.cells[1].weeks)
        assertEquals(1, result.cells[0].periodStart)
        assertEquals(2, result.cells[1].periodStart)
        assertTrue(result.cells[2].needsReview, "a cell with no week expression requires correction")
        assertTrue(result.cells.none { it.periodEnd > it.periodStart })
    }

    @Test fun `grid-stroke metadata stays attached and raw OCR remains visible`() {
        val boxes = listOf(
            TextBox("周三", 300.0, 10.0, 350.0, 30.0, .99),
            TextBox("第2节", 10.0, 180.0, 60.0, 200.0, .99),
            TextBox("高等数学", 300.0, 110.0, 380.0, 130.0, .99),
            TextBox("」教师：王老师」", 300.0, 140.0, 380.0, 155.0, .99),
            TextBox("教至：A203", 300.0, 165.0, 380.0, 180.0, .99),
            TextBox("周次：1-16周（单厂", 300.0, 190.0, 380.0, 205.0, .99),
        )
        val cell = GridReconstructor.reconstruct(boxes, 800.0, 400.0).cells.single()
        assertEquals("高等数学", cell.courseName)
        assertEquals("王老师", cell.teacher)
        assertEquals("A203", cell.classroom)
        assertTrue(cell.rawText.contains("教至：A203"))
        assertTrue(cell.weeks.isEmpty(), "damaged week text must require manual correction")
        assertTrue(cell.needsReview)
    }

    @Test fun `same-center period range labels form one row band`() {
        val boxes = listOf(
            TextBox("周一", 100.0, 10.0, 150.0, 30.0, .99), TextBox("周二", 200.0, 10.0, 250.0, 30.0, .99),
            TextBox("周三", 300.0, 10.0, 350.0, 30.0, .99), TextBox("周四", 400.0, 10.0, 450.0, 30.0, .99),
            TextBox("周五", 500.0, 10.0, 550.0, 30.0, .99), TextBox("周六", 600.0, 10.0, 650.0, 30.0, .99),
            TextBox("周日", 700.0, 10.0, 750.0, 30.0, .99),
            TextBox("第1-2节", 10.0, 100.0, 60.0, 120.0, .95), TextBox("第3节", 10.0, 200.0, 60.0, 220.0, .95),
            TextBox("通识课 1-16周", 110.0, 90.0, 190.0, 130.0, .94),
        )
        val result = GridReconstructor.reconstruct(boxes, 800.0, 400.0)
        assertEquals(1, result.cells.single().periodStart)
        assertEquals(2, result.cells.single().periodEnd)
        assertTrue(result.cells.single().needsReview, "inferred multi-period cells remain highlighted for confirmation")
    }

    @Test fun `layout reconstruction finds headers rows and merged period spans`() {
        val boxes = listOf(
            TextBox("周一", 100.0, 10.0, 150.0, 30.0, .99), TextBox("周二", 200.0, 10.0, 250.0, 30.0, .98),
            TextBox("周三", 300.0, 10.0, 350.0, 30.0, .98), TextBox("周四", 400.0, 10.0, 450.0, 30.0, .98),
            TextBox("周五", 500.0, 10.0, 550.0, 30.0, .98), TextBox("周六", 600.0, 10.0, 650.0, 30.0, .98),
            TextBox("周日", 700.0, 10.0, 750.0, 30.0, .98),
            TextBox("第1节", 10.0, 100.0, 60.0, 120.0, .95), TextBox("第2节", 10.0, 200.0, 60.0, 220.0, .95),
            TextBox("高数\n老师：李老师\n教室：A101\n1-16周(单)", 110.0, 90.0, 190.0, 230.0, .62),
        )
        val result = GridReconstructor.reconstruct(boxes, 800.0, 400.0)
        val cell = result.cells.single()
        assertEquals(1, cell.weekday)
        assertEquals(1, cell.periodStart)
        assertEquals(2, cell.periodEnd)
        assertEquals("高数", cell.courseName)
        assertEquals("李老师", cell.teacher)
        assertEquals("A101", cell.classroom)
        assertEquals((1..15 step 2).toSet(), cell.weeks)
        assertTrue(cell.needsReview)
        assertFalse(result.columnHeaders.isEmpty())
    }
}
