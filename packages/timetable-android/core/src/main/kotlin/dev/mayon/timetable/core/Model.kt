package dev.mayon.timetable.core

import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime

@Serializable
data class TimetableV1(
    val format: String = "timetable",
    val version: Int = 1,
    val semester: Semester,
    val courses: List<Course>,
) {
    fun validate(): List<String> = buildList {
        if (format != "timetable") add("format must be timetable")
        if (version != 1) add("unsupported timetable version: $version")
        if (!semester.id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) add("semester id must match [A-Za-z0-9_-]{1,80}")
        if (semester.name.isBlank()) add("semester name cannot be blank")
        if (semester.totalWeeks !in 1..60) add("totalWeeks must be between 1 and 60")
        val parsedStartDate = runCatching { LocalDate.parse(semester.startDate) }.getOrNull()
        if (parsedStartDate == null) add("startDate must be an ISO-8601 date")
        else if (parsedStartDate.dayOfWeek != DayOfWeek.MONDAY) add("startDate must be the Monday of teaching week 1")
        if (runCatching { java.time.ZoneId.of(semester.timeZone) }.isFailure) add("timeZone must be an IANA zone")
        if (semester.timeSlots.isEmpty()) add("timeSlots cannot be empty")
        val slots = semester.timeSlots.sortedBy { it.period }
        if (slots.map { it.period }.distinct().size != slots.size) add("timeSlots period values must be unique")
        if (slots.any { it.period < 1 }) add("timeSlots period values must be positive")
        val parsedTimes = slots.map { slot ->
            val start = slot.start.takeIf { it.matches(Regex("\\d{2}:\\d{2}")) }?.let { runCatching { LocalTime.parse(it) }.getOrNull() }
            val end = slot.end.takeIf { it.matches(Regex("\\d{2}:\\d{2}")) }?.let { runCatching { LocalTime.parse(it) }.getOrNull() }
            if (start == null || end == null) add("timeSlots ${slot.period} must use HH:mm times")
            else if (start >= end) add("timeSlots ${slot.period} start must precede end")
            slot to (start to end)
        }
        for ((a, b) in parsedTimes.zipWithNext()) {
            val aEnd = a.second.second
            val bStart = b.second.first
            if (aEnd != null && bStart != null && aEnd > bStart) add("timeSlots cannot overlap")
        }
        val ids = courses.map { it.id }
        if (ids.distinct().size != ids.size) add("course ids must be unique")
        val periodNumbers = slots.map { it.period }.toSet()
        for (course in courses) {
            if (!course.id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) add("course id must match [A-Za-z0-9_-]{1,80}")
            if (course.name.isBlank()) add("course ${course.id} name cannot be blank")
            if (course.weekday !in 1..7) add("course ${course.id} weekday must be ISO 1..7")
            if (course.periodStart < 1 || course.periodEnd < course.periodStart) add("course ${course.id} has invalid period range")
            if (course.periodStart <= course.periodEnd && (course.periodStart..course.periodEnd).any { it !in periodNumbers }) {
                add("course ${course.id} period range references an undefined timeSlot")
            }
            if (course.weeks.isEmpty() || course.weeks.any { it !in 1..semester.totalWeeks }) add("course ${course.id} weeks must be within the semester")
            if (course.color != null && !course.color.matches(Regex("#[0-9A-Fa-f]{6}"))) add("course ${course.id} color must be #RRGGBB")
        }
    }

    fun requireValid(): TimetableV1 {
        val issues = validate()
        require(issues.isEmpty()) { issues.joinToString("; ") }
        return this
    }
}

@Serializable
data class Semester(
    val id: String,
    val name: String,
    /** ISO-8601 date of the Monday of teaching week 1. */
    val startDate: String,
    val totalWeeks: Int,
    val timeZone: String,
    val timeSlots: List<PeriodTime>,
)

@Serializable
data class PeriodTime(val period: Int, val start: String, val end: String)

@Serializable
data class Course(
    val id: String,
    val name: String,
    val teacher: String? = null,
    val classroom: String? = null,
    /** ISO weekday number: Monday=1 ... Sunday=7. */
    val weekday: Int,
    val periodStart: Int,
    val periodEnd: Int,
    val weeks: Set<Int>,
    val color: String? = null,
    val notes: String? = null,
)

fun Semester.firstDay(): LocalDate = LocalDate.parse(startDate)
fun Course.dayOfWeek(): DayOfWeek = DayOfWeek.of(weekday)
