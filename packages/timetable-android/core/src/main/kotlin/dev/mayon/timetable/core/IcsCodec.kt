package dev.mayon.timetable.core

import java.nio.charset.StandardCharsets
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoUnit
import java.security.MessageDigest

/** Small RFC 5545 codec for timetable events. Unsupported recurrence rules fail explicitly. */
object IcsCodec {
    private val localDateTimeFormat = DateTimeFormatter.ofPattern("uuuuMMdd'T'HHmmss").withResolverStyle(ResolverStyle.STRICT)
    private val utcDateTimeFormat = DateTimeFormatter.ofPattern("uuuuMMdd'T'HHmmssX").withResolverStyle(ResolverStyle.STRICT)
    private val utcDateTimeOutput = DateTimeFormatter.ofPattern("uuuuMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC)

    fun export(timetable: TimetableV1): String {
        timetable.requireValid()
        val semester = timetable.semester
        val zone = ZoneId.of(semester.timeZone)
        val startMonday = semester.firstDay()
        val lines = mutableListOf(
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Mayon//Timetable//ZH", "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:${escape(semester.name)}", "X-WR-TIMEZONE:${escape(semester.timeZone)}",
        )
        for (course in timetable.courses) {
            for (week in course.weeks.sorted()) {
                val date = startMonday.plusWeeks((week - 1).toLong()).plusDays((course.weekday - 1).toLong())
                val startTime = LocalTime.parse(semester.timeSlots.single { it.period == course.periodStart }.start)
                val endTime = LocalTime.parse(semester.timeSlots.single { it.period == course.periodEnd }.end)
                val start = ZonedDateTime.of(date, startTime, zone)
                val end = ZonedDateTime.of(date, endTime, zone)
                val uid = "${escapeUid(course.id)}-$week@timetable.local"
                lines += listOf(
                    "BEGIN:VEVENT", "UID:$uid", "DTSTAMP:${utcDateTimeOutput.format(Instant.EPOCH)}",
                    "DTSTART:${utcDateTimeOutput.format(start.toInstant())}",
                    "DTEND:${utcDateTimeOutput.format(end.toInstant())}",
                    "SUMMARY:${escape(course.name)}",
                    course.classroom?.let { "LOCATION:${escape(it)}" },
                    course.notes?.let { "DESCRIPTION:${escape(it)}" },
                    course.teacher?.let { "X-TIMETABLE-TEACHER:${escape(it)}" },
                    course.notes?.let { "X-TIMETABLE-NOTES:${escape(it)}" },
                    course.color?.let { "X-TIMETABLE-COLOR:$it" },
                    "X-TIMETABLE-COURSE-ID:${escapeParam(course.id)}",
                    "X-TIMETABLE-WEEK:$week", "X-TIMETABLE-WEEKDAY:${course.weekday}",
                    "X-TIMETABLE-PERIOD-START:${course.periodStart}", "X-TIMETABLE-PERIOD-END:${course.periodEnd}",
                    "END:VEVENT",
                ).filterNotNull()
            }
        }
        lines += "END:VCALENDAR"
        return lines.joinToString("\r\n", postfix = "\r\n") { fold(it) }
    }

    fun import(source: String, semester: Semester): TimetableV1 {
        val unfolded = source.replace("\r\n ", "").replace("\n ", "").replace("\r\n\t", "").replace("\n\t", "")
        require("BEGIN:VCALENDAR" in unfolded && "END:VCALENDAR" in unfolded) { "invalid iCalendar document" }
        val events = mutableListOf<Map<String, String>>()
        var current: MutableMap<String, String>? = null
        for (line in unfolded.lines()) {
            when (line.trim()) {
                "BEGIN:VEVENT" -> current = linkedMapOf()
                "END:VEVENT" -> current?.let(events::add).also { current = null }
                else -> if (current != null) {
                    val split = line.indexOf(':')
                    if (split > 0) {
                        val rawKey = line.substring(0, split)
                        val key = rawKey.substringBefore(';').uppercase()
                        val value = line.substring(split + 1)
                        Regex("(?i)(?:^|;)TZID=([^;:]+)").find(rawKey)?.groupValues?.get(1)?.let { current!!["$key-TZID"] = it }
                        current!![key] = when (key) {
                            "SUMMARY", "LOCATION", "DESCRIPTION", "X-TIMETABLE-TEACHER", "X-TIMETABLE-NOTES" -> unescape(value)
                            else -> value
                        }
                    }
                }
            }
        }
        require(events.isNotEmpty()) { "iCalendar contains no VEVENT" }
        val grouped = linkedMapOf<String, MutableList<Pair<Map<String, String>, LocalDateTime>>>()
        val zone = ZoneId.of(semester.timeZone)
        for (event in events) {
            val dtStart = event["DTSTART"] ?: error("VEVENT has no DTSTART")
            val (initial, start) = parseDateTime(dtStart, event, zone, "DTSTART")
            val initialWeekday = event["X-TIMETABLE-WEEKDAY"]?.toIntOrNull()
            require(initialWeekday == null || initialWeekday == start.dayOfWeek.value) { "X-TIMETABLE-WEEKDAY disagrees with DTSTART" }
            val initialWeek = (ChronoUnit.DAYS.between(semester.firstDay(), initial) / 7 + 1).toInt()
            val declaredWeek = event["X-TIMETABLE-WEEK"]?.toIntOrNull()
            require(declaredWeek == null || declaredWeek == initialWeek) { "X-TIMETABLE-WEEK disagrees with DTSTART" }
            val declaredStartPeriod = event["X-TIMETABLE-PERIOD-START"]?.toIntOrNull()
            require(declaredStartPeriod == null || semester.timeSlots.singleOrNull { it.period == declaredStartPeriod }?.let { LocalTime.parse(it.start) == start.toLocalTime() } == true) {
                "X-TIMETABLE-PERIOD-START disagrees with DTSTART"
            }
            require(event["EXDATE"] == null && event["RDATE"] == null) { "EXDATE/RDATE recurrence exceptions are unsupported; preserve and review this calendar before import" }
            val rr = event["RRULE"]
            val dates = if (rr == null) listOf(initial) else expandWeekly(initial, rr, semester, zone)
            val baseId = event["X-TIMETABLE-COURSE-ID"] ?: event["UID"] ?: "external-${grouped.size}"
            val endRaw = event["DTEND"] ?: error("VEVENT has no DTEND")
            val (endDate, end) = parseDateTime(endRaw, event, zone, "DTEND")
            require(endDate == initial && end.toLocalTime() > start.toLocalTime()) { "VEVENT must start and end on the same local date with positive duration" }
            val declaredEndPeriod = event["X-TIMETABLE-PERIOD-END"]?.toIntOrNull()
            require(declaredEndPeriod == null || semester.timeSlots.singleOrNull { it.period == declaredEndPeriod }?.let { LocalTime.parse(it.end) == end.toLocalTime() } == true) {
                "X-TIMETABLE-PERIOD-END disagrees with DTEND"
            }
            for (date in dates) {
                require(initialWeekday == null || initialWeekday == date.dayOfWeek.value) { "X-TIMETABLE-WEEKDAY disagrees with recurrence date" }
                require(declaredWeek == null || declaredWeek == (ChronoUnit.DAYS.between(semester.firstDay(), date) / 7 + 1).toInt()) {
                    "X-TIMETABLE-WEEK disagrees with recurrence date"
                }
                val occurrence = LocalDateTime.of(date, start.toLocalTime())
                val weekday = event["X-TIMETABLE-WEEKDAY"]?.toIntOrNull() ?: occurrence.dayOfWeek.value
                val signature = listOf(
                    baseId, weekday, start.toLocalTime(), end.toLocalTime(), event["SUMMARY"], event["LOCATION"],
                    event["DESCRIPTION"], event["X-TIMETABLE-TEACHER"], event["X-TIMETABLE-NOTES"], event["X-TIMETABLE-COLOR"],
                    event["X-TIMETABLE-PERIOD-START"], event["X-TIMETABLE-PERIOD-END"],
                ).joinToString("|")
                grouped.getOrPut(signature, ::mutableListOf) += event to occurrence
            }
        }
        val usedIds = mutableSetOf<String>()
        val courses = grouped.map { (groupKey, occurrences) ->
            val first = occurrences.first()
            val rawId = first.first["X-TIMETABLE-COURSE-ID"]?.also { require(it.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "invalid X-TIMETABLE-COURSE-ID=$it" } }
                ?: safeId(groupKey)
            var id = rawId
            if (!usedIds.add(id)) {
                val suffix = safeId(groupKey).takeLast(10)
                id = "${rawId.take(68)}-$suffix"
                require(usedIds.add(id)) { "duplicate ICS course identity cannot be resolved" }
            }
            val event = first.first
            val firstStart = first.second
            val startDate = semester.firstDay()
            val weekNumbers = occurrences.map { (_, dt) ->
                val date = dt.toLocalDate()
                val dayOffset = ChronoUnit.DAYS.between(startDate, date)
                require(dayOffset >= 0) { "event $id occurs before semester start" }
                val week = (dayOffset / 7 + 1).toInt()
                require(week <= semester.totalWeeks) { "event $id occurs after semester end" }
                week
            }.toSet()
            val weekday = event["X-TIMETABLE-WEEKDAY"]?.toIntOrNull() ?: firstStart.dayOfWeek.value
            val periodStart = event["X-TIMETABLE-PERIOD-START"]?.toIntOrNull()
                ?: semester.timeSlots.firstOrNull { LocalTime.parse(it.start) == firstStart.toLocalTime() }?.period
                ?: error("cannot map DTSTART to a period; add X-TIMETABLE-PERIOD-START")
            val periodEnd = event["X-TIMETABLE-PERIOD-END"]?.toIntOrNull() ?: run {
                val endProp = event["DTEND"] ?: error("VEVENT has no DTEND")
                val (_, end) = parseDateTime(endProp, event, zone, "DTEND")
                semester.timeSlots.firstOrNull { LocalTime.parse(it.end) == end.toLocalTime() }?.period
                    ?: error("cannot map DTEND to a period; add X-TIMETABLE-PERIOD-END")
            }
            Course(
                id = id,
                name = event["SUMMARY"] ?: error("VEVENT has no SUMMARY"),
                teacher = event["X-TIMETABLE-TEACHER"],
                classroom = event["LOCATION"],
                weekday = weekday,
                periodStart = periodStart,
                periodEnd = periodEnd,
                weeks = weekNumbers,
                color = event["X-TIMETABLE-COLOR"],
                notes = event["X-TIMETABLE-NOTES"] ?: event["DESCRIPTION"],
            )
        }
        return TimetableV1(semester = semester, courses = courses).requireValid()
    }

    private fun parseDateTime(raw: String, event: Map<String, String>, fallback: ZoneId, property: String): Pair<LocalDate, LocalDateTime> {
        val value = raw
        require(Regex("^\\d{8}T\\d{6}Z?$").matches(value)) { "all-day or malformed $property is not supported; timetable events require local start/end times" }
        val valueZone = try {
            event["$property-TZID"]?.let(ZoneId::of) ?: fallback
        } catch (failure: DateTimeException) {
            throw IllegalArgumentException("invalid TZID on $property", failure)
        }
        val local = try {
            when {
                value.endsWith('Z') -> LocalDateTime.ofInstant(Instant.from(utcDateTimeFormat.parse(value)), ZoneOffset.UTC)
                else -> LocalDateTime.parse(value, localDateTimeFormat)
            }
        } catch (failure: DateTimeException) {
            throw IllegalArgumentException("invalid $property date-time", failure)
        }
        val converted = if (value.endsWith('Z')) local.atZone(ZoneOffset.UTC).withZoneSameInstant(fallback).toLocalDateTime()
            else local.atZone(valueZone).withZoneSameInstant(fallback).toLocalDateTime()
        return converted.toLocalDate() to converted
    }

    private fun expandWeekly(start: LocalDate, rule: String, semester: Semester, zone: ZoneId): List<LocalDate> {
        val fields = rule.split(';').mapNotNull { part -> part.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0].uppercase() to it[1] } }.toMap()
        val supported = setOf("FREQ", "INTERVAL", "BYDAY", "UNTIL")
        val unsupported = fields.keys - supported
        require(unsupported.isEmpty()) { "unsupported RRULE fields ${unsupported.joinToString()}: $rule" }
        require(fields["FREQ"] == "WEEKLY") { "unsupported RRULE (only FREQ=WEEKLY is supported): $rule" }
        val interval = fields["INTERVAL"]?.let { it.toIntOrNull() ?: throw IllegalArgumentException("invalid RRULE INTERVAL=$it") } ?: 1
        require(interval > 0) { "invalid RRULE INTERVAL" }
        val byDay = fields["BYDAY"]?.split(',')?.map { token ->
            require(Regex("^(MO|TU|WE|TH|FR|SA|SU)$").matches(token)) { "unsupported RRULE BYDAY=$token" }
            when (token) { "MO" -> 1; "TU" -> 2; "WE" -> 3; "TH" -> 4; "FR" -> 5; "SA" -> 6; "SU" -> 7; else -> error("unsupported RRULE BYDAY=$token") }
        }?.toSet() ?: setOf(start.dayOfWeek.value)
        val until = fields["UNTIL"]?.let { raw ->
            require(Regex("^\\d{8}$").matches(raw)) { "only DATE-form UNTIL is supported; datetime UNTIL requires review" }
            runCatching { LocalDate.parse(raw, DateTimeFormatter.BASIC_ISO_DATE) }.getOrElse { error("invalid RRULE UNTIL") }
        } ?: semester.firstDay().plusWeeks(semester.totalWeeks.toLong()).minusDays(1)
        val last = minOf(until, semester.firstDay().plusWeeks(semester.totalWeeks.toLong()).minusDays(1))
        val startWeekMonday = start.with(java.time.temporal.TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val semesterStart = semester.firstDay()
        return generateSequence(start) { it.plusDays(1) }.takeWhile { !it.isAfter(last) }.filter { date ->
            val days = ChronoUnit.DAYS.between(startWeekMonday, date)
            !date.isBefore(semesterStart) && days >= 0 && (days / 7) % interval == 0L && date.dayOfWeek.value in byDay
        }.toList()
    }

    private fun escape(text: String): String = text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n").replace("\r", "")
    private fun unescape(text: String): String {
        val result = StringBuilder()
        var index = 0
        while (index < text.length) {
            val char = text[index]
            if (char == '\\' && index + 1 < text.length) {
                when (val escaped = text[index + 1]) {
                    'n', 'N' -> result.append('\n')
                    ',', ';', '\\' -> result.append(escaped)
                    else -> result.append('\\').append(escaped)
                }
                index += 2
            } else {
                result.append(char)
                index++
            }
        }
        return result.toString()
    }
    private fun escapeParam(text: String): String = text.replace(":", "\\:").replace(";", "\\;").replace(",", "\\,")
    private fun escapeUid(text: String): String = text.replace(Regex("[^A-Za-z0-9._-]"), "_")
    private fun safeId(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(StandardCharsets.UTF_8))
            .take(10).joinToString("") { "%02x".format(it) }
        return "external_$digest"
    }
    private fun fold(line: String): String {
        val out = StringBuilder()
        var bytes = 0
        var index = 0
        while (index < line.length) {
            val codePoint = line.codePointAt(index)
            val chunk = String(Character.toChars(codePoint))
            val size = chunk.toByteArray(StandardCharsets.UTF_8).size
            if (bytes + size > 75) { out.append("\r\n "); bytes = 1 }
            out.append(chunk)
            bytes += size
            index += Character.charCount(codePoint)
        }
        return out.toString()
    }
}
