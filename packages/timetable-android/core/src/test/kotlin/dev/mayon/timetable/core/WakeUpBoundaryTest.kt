package dev.mayon.timetable.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class WakeUpBoundaryTest {
    private fun records(): List<String> = File("fixtures/wakeup/backup-lines.jsonl").readLines().filter(String::isNotBlank)

    @Test fun emptyCourseAndMeetingArraysAreValidForFiveAndFourRecordBackups() {
        val lines = records().toMutableList()
        lines[3] = "[]"; lines[4] = "[]"
        val five = WakeUpParser.parseBackup(lines.joinToString("\n"))
        assertTrue(five.courses.isEmpty())
        assertTrue(five.semester.timeSlots.isNotEmpty())
        assertEquals(five, WakeUpParser.parseBackup(lines.drop(1).joinToString("\n")))
    }

    @Test fun aDamagedExtraJsonRecordMustNotBeSilentlyDiscarded() {
        assertFailsWith<IllegalArgumentException> {
            WakeUpParser.parseBackup(records().joinToString("\n") + "\n{broken json}")
        }
    }

    @Test fun literalRecordSeparatorsRemainSupportedWithoutDroppingAnyRecord() {
        val lines = records()
        assertEquals(WakeUpParser.parseBackup(lines.joinToString("\n")),
            WakeUpParser.parseBackup(lines.joinToString("\\n")))
    }

    @Test fun quotedOpaqueTokensAreSyntheticAndPreserveTheirCase() {
        assertEquals("合成口令-仅供测试", WakeUpParser.extractShareKey("分享口令为「合成口令-仅供测试」"))
        assertEquals("0123456789abcdef0123456789abcdef", WakeUpParser.extractShareKey("0123456789ABCDEF0123456789ABCDEF"))
    }
}
