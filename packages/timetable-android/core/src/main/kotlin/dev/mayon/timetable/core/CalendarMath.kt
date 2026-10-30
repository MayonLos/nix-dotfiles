package dev.mayon.timetable.core

import java.time.LocalTime
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

data class Occurrence(val course: Course, val start: ZonedDateTime, val end: ZonedDateTime)
fun weekAt(table: TimetableV1, date: LocalDate): Int =
    Math.floorDiv(ChronoUnit.DAYS.between(LocalDate.parse(table.semester.startDate), date), 7L).toInt() + 1

fun occurrences(table: TimetableV1): List<Occurrence> {
    table.requireValid()
    val semester = table.semester
    val zone = ZoneId.of(semester.timeZone)
    val slots = semester.timeSlots.associateBy { it.period }
    return table.courses.flatMap { course -> course.weeks.sorted().map { week ->
        val date = LocalDate.parse(semester.startDate).plusWeeks((week - 1).toLong()).plusDays((course.weekday - 1).toLong())
        Occurrence(course, date.atTime(LocalTime.parse(slots.getValue(course.periodStart).start)).atZone(zone),
            date.atTime(LocalTime.parse(slots.getValue(course.periodEnd).end)).atZone(zone))
    } }.sortedBy { it.start.toInstant() }
}
