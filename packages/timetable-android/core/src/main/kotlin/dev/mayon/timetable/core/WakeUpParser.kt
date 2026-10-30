package dev.mayon.timetable.core

import kotlinx.serialization.json.*
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

/** Pure adapter for WakeUp export/share data. Network access belongs in the Android app layer. */
object WakeUpParser {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun extractShareKey(text: String): String? {
        val quoted = Regex("分享口令(?:为)?[：:]?\\s*[「『\"“']([^」』\"”'\\r\\n]{1,512})[」』\"”']").find(text)
        val token = quoted?.groupValues?.get(1)?.trim()?.takeIf(String::isNotEmpty)
        return token ?: Regex("(?<![a-fA-F0-9])[a-fA-F0-9]{32}(?![a-fA-F0-9])").find(text)?.value?.lowercase()
    }

    /** Parses the community-described legacy endpoint envelope; it performs no request itself. */
    fun parseShareResponse(source: String): TimetableV1 {
        val envelope = json.parseToJsonElement(source).jsonObject
        val status = envelope["status"]?.jsonPrimitive?.contentOrNull
        require(status == "1" || status == "success") { "WakeUp share request was not successful (status=$status)" }
        val payload = envelope["data"] ?: error("WakeUp response has no data")
        val normalized = resolvePayload(payload, 0) ?: error("WakeUp share payload has an unsupported shape")
        return if (normalized["courseList"] != null) convertLegacyShare(normalized) else convertWakeupRecords(normalized)
    }

    /** Parses a `.wakeup_schedule` export using the public converters’ four- or five-record JSON-lines shape. */
    fun parseBackup(bytes: ByteArray): TimetableV1 = parseBackup(bytes.toString(StandardCharsets.UTF_8))

    fun parseBackup(source: String): TimetableV1 {
        val text = source.trimStart('\uFEFF', ' ', '\t', '\r', '\n')
        val direct = runCatching { json.parseToJsonElement(text) }.getOrNull()
        if (direct != null) {
            val normalized = resolvePayload(direct, 0)
            if (normalized != null) {
                if (normalized["courseList"] != null) return convertLegacyShare(normalized)
                return convertWakeupRecords(normalized)
            }
            if (direct is JsonObject && direct["courseList"] != null) return convertLegacyShare(direct)
        }
        val chunks = parseRecordText(text)
        require(chunks.isNotEmpty()) { "WakeUp backup contains no JSON records" }
        val normalized = resolveRecords(chunks)
            ?: error("WakeUp records do not contain timeTable/settings/courses/schedule")
        return convertWakeupRecords(normalized)
    }

    private fun parseLines(source: String): List<JsonElement> = source.lineSequence().map(String::trim)
        .filter(String::isNotEmpty).mapIndexed { index, line ->
            runCatching { json.parseToJsonElement(line) }.getOrElse {
                throw IllegalArgumentException("invalid JSON in WakeUp record ${index + 1}", it)
            }
        }.toList()

    private fun parseRecordText(source: String): List<JsonElement> {
        val original = runCatching { parseLines(source) }
        if (original.isSuccess) return original.getOrThrow()
        // Some public share wrappers pass literal record separators. Never skip damaged rows.
        if (!source.contains('\n') && source.contains("\\n")) return parseLines(source.replace("\\n", "\n"))
        throw original.exceptionOrNull()!!
    }

    private fun resolvePayload(payload: JsonElement, depth: Int): JsonObject? {
        if (depth > 5) return null
        when (payload) {
            is JsonObject -> {
                if (payload["timeTable"] != null && payload["settings"] != null && payload["courses"] != null && payload["schedule"] != null) {
                    return normalizeFourParts(payload)
                }
                for (key in listOf("shareData", "data")) {
                    payload[key]?.let { resolvePayload(it, depth + 1)?.let { result -> return result } }
                }
                if (payload["courseList"] != null) return payload
            }
            is JsonPrimitive -> if (payload.isString) {
                val text = payload.content.trim()
                runCatching { json.parseToJsonElement(text) }.getOrNull()?.let { resolvePayload(it, depth + 1)?.let { result -> return result } }
                resolveRecords(parseRecordText(text))?.let { return it }
            }
            is JsonArray -> resolveRecords(payload.toList())?.let { return it }
        }
        return null
    }

    private fun resolveRecords(records: List<JsonElement>): JsonObject? {
        // Preserve the confirmed record order, which also identifies empty course/meeting arrays.
        val parts = if (records.size == 5 && records[0] is JsonObject) records.drop(1) else records
        if (parts.size == 4 && parts[0] is JsonArray && parts[1] is JsonObject &&
            parts[2] is JsonArray && parts[3] is JsonArray) {
            return normalizeFourParts(buildJsonObject {
                put("timeTable", parts[0]); put("settings", parts[1])
                put("courses", parts[2]); put("schedule", parts[3])
            })
        }
        val timeTable = records.firstOrNull { it is JsonArray && it.isNotEmpty() && it.firstOrNull()?.jsonObjectOrNull()?.get("node") != null } as? JsonArray
        val settings = records.firstOrNull { it is JsonObject && (it["maxWeek"] != null || it["startDate"] != null || it["nodes"] != null) } as? JsonObject
        val courses = records.firstOrNull { it is JsonArray && it.isNotEmpty() && it.firstOrNull()?.jsonObjectOrNull()?.get("courseName") != null } as? JsonArray
        val schedule = records.firstOrNull { it is JsonArray && it.isNotEmpty() && it.firstOrNull()?.jsonObjectOrNull()?.get("day") != null && it.firstOrNull()?.jsonObjectOrNull()?.get("startNode") != null } as? JsonArray
        if (timeTable == null || settings == null || courses == null || schedule == null) return null
        return buildJsonObject {
            put("timeEntries", timeTable)
            put("scheduleMetadata", settings)
            put("courseEntries", courses)
            put("classEntries", schedule)
        }
    }

    private fun normalizeFourParts(payload: JsonObject): JsonObject? {
        val timeTable = payload["timeTable"] as? JsonArray ?: return null
        val settings = payload["settings"] as? JsonObject ?: return null
        val courses = payload["courses"] as? JsonArray ?: return null
        val schedule = payload["schedule"] as? JsonArray ?: return null
        return buildJsonObject {
            put("timeEntries", timeTable)
            put("scheduleMetadata", settings)
            put("courseEntries", courses)
            put("classEntries", schedule)
        }
    }

    private fun JsonElement.jsonObjectOrNull(): JsonObject? = this as? JsonObject

    private fun convertWakeupRecords(root: JsonObject): TimetableV1 {
        val meta = root["scheduleMetadata"]?.jsonObject ?: error("WakeUp data has no ScheduleMetadata")
        val timeEntries = root["timeEntries"]?.jsonArray ?: error("WakeUp data has no TimeEntry[]")
        val courseEntries = root["courseEntries"]?.jsonArray ?: error("WakeUp data has no CourseEntry[]")
        val classEntries = root["classEntries"]?.jsonArray ?: error("WakeUp data has no ClassEntry[]")
        val nodes = meta.int("nodes") ?: timeEntries.mapNotNull { it.jsonObject.int("node") }.maxOrNull()
            ?: error("WakeUp ScheduleMetadata has no nodes and timeTable is empty")
        val timeSlots = timeEntries.map { it.jsonObject }.filter { (it.int("node") ?: Int.MAX_VALUE) <= nodes }
            .map { item ->
                PeriodTime(
                    item.int("node") ?: error("WakeUp TimeEntry has no node"),
                    normalizeTime(item.string("startTime") ?: error("WakeUp TimeEntry has no startTime")),
                    normalizeTime(item.string("endTime") ?: error("WakeUp TimeEntry has no endTime")),
                )
            }.sortedBy(PeriodTime::period)
        val baseEntries = courseEntries.map { it.jsonObject }
        val baseIds = baseEntries.map { it.int("id") ?: error("WakeUp CourseEntry has no id") }
        require(baseIds.distinct().size == baseIds.size) { "WakeUp CourseEntry contains duplicate ids" }
        val courseBases = baseEntries.associateBy { it.int("id")!! }
        val totalWeeks = meta.int("maxWeek") ?: error("WakeUp ScheduleMetadata has no maxWeek")
        require(totalWeeks in 1..60) { "WakeUp maxWeek must be in 1..60" }
        val meetings = classEntries.mapIndexed { index, raw ->
            val item = raw.jsonObject
            require(item["ownTime"]?.jsonPrimitive?.booleanOrNull != true) {
                "WakeUp class entry ${item.int("id")} uses ownTime; custom-time classes cannot be mapped without losing their time data"
            }
            val baseId = item.int("id") ?: error("WakeUp ClassEntry[$index] has no id")
            val base = courseBases[baseId] ?: error("WakeUp ClassEntry[$index] references missing CourseEntry id=$baseId")
            val start = item.int("startNode") ?: error("WakeUp ClassEntry[$index] has no startNode")
            val step = item.int("step") ?: error("WakeUp ClassEntry[$index] has no step")
            require(start in 1..60 && step in 1..60 && start + step - 1 <= 60) { "WakeUp ClassEntry[$index] has invalid period span" }
            val firstWeek = item.int("startWeek") ?: error("WakeUp ClassEntry[$index] has no startWeek")
            val lastWeek = item.int("endWeek") ?: error("WakeUp ClassEntry[$index] has no endWeek")
            require(firstWeek in 1..totalWeeks && lastWeek in 1..totalWeeks && firstWeek <= lastWeek) { "WakeUp ClassEntry[$index] has invalid week range" }
            val parity = item.int("type") ?: error("WakeUp ClassEntry[$index] has no week type")
            require(parity in 0..2) { "WakeUp ClassEntry[$index] has unsupported type=$parity" }
            val weeks = (firstWeek..lastWeek).filter { week ->
                parity == 0 || (parity == 1 && week % 2 == 1) || (parity == 2 && week % 2 == 0)
            }.toSet()
            val weekday = item.int("day") ?: error("WakeUp ClassEntry[$index] has no day")
            val teacher = item.string("teacher").cleanOrNull()
            val room = item.string("room").cleanOrNull()
            Course(
                id = "wakeup-$baseId-$weekday-$start-$step-$index",
                name = base.string("courseName")?.takeIf(String::isNotBlank) ?: error("WakeUp CourseEntry id=$baseId has no courseName"),
                teacher = teacher,
                classroom = room,
                weekday = weekday,
                periodStart = start,
                periodEnd = start + step - 1,
                weeks = weeks,
                notes = base.string("note").cleanOrNull(),
            )
        }
        val startDate = meta.string("startDate") ?: error("WakeUp ScheduleMetadata has no startDate")
        val monday = LocalDate.parse(startDate).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val result = TimetableV1(
            semester = Semester(
                id = meta.int("id")?.toString() ?: stableId(0, meta),
                name = meta.string("tableName") ?: "WakeUp",
                startDate = monday.format(DateTimeFormatter.ISO_LOCAL_DATE),
                totalWeeks = totalWeeks,
                timeZone = "Asia/Shanghai",
                timeSlots = timeSlots,
            ),
            courses = meetings,
        )
        return result.requireValid()
    }

    private fun convertLegacyShare(root: JsonObject): TimetableV1 {
        val rawCourses = root["courseList"]?.jsonArray ?: error("WakeUp payload has no courseList")
        val rawTimes = root["timeList"]?.jsonArray ?: error("WakeUp payload has no timeList")
        val startDate = root.string("startDate") ?: error("WakeUp payload has no startDate")
        val monday = LocalDate.parse(startDate).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val timeSlots = rawTimes.mapIndexed { index, raw ->
            val item = raw.jsonObject
            PeriodTime(
                item.int("node") ?: item.int("period") ?: item.int("id") ?: index + 1,
                normalizeTime(item.string("startTime") ?: item.string("start") ?: error("timeList[$index] has no start time")),
                normalizeTime(item.string("endTime") ?: item.string("end") ?: error("timeList[$index] has no end time")),
            )
        }.sortedBy(PeriodTime::period)
        val maxWeeks = rawCourses.flatMap { course -> course.jsonObject.weekValues() }.maxOrNull() ?: 1
        val courses = rawCourses.mapIndexed { index, raw ->
            val item = raw.jsonObject
            val start = item.int("startNode") ?: item.int("startPeriod") ?: error("courseList[$index] has no startNode")
            val step = item.int("step") ?: item.int("stepCount") ?: run {
                val end = item.int("endNode") ?: item.int("periodEnd") ?: error("courseList[$index] has no step/endNode")
                end - start + 1
            }
            val weeks = item.weekValues().ifEmpty {
                val first = item.int("startWeek") ?: error("courseList[$index] has no week data")
                val last = item.int("endWeek") ?: first
                require(first in 1..60 && last in 1..60 && first <= last) { "courseList[$index] has invalid week range" }
                val type = item.int("type") ?: 0
                require(type in 0..2) { "unsupported WakeUp week type=$type" }
                (first..last).filter { type == 0 || (type == 1 && it % 2 == 1) || (type == 2 && it % 2 == 0) }.toSet()
            }
            Course(
                id = item.string("id")?.takeIf(String::isNotBlank)?.let { "wakeup-${it.replace(Regex("[^A-Za-z0-9_-]"), "_")}" } ?: stableId(index, item),
                name = item.string("courseName") ?: item.string("name") ?: error("courseList[$index] has no courseName"),
                teacher = item.string("teacher").cleanOrNull(),
                classroom = (item.string("room") ?: item.string("classroom")).cleanOrNull(),
                weekday = item.int("day") ?: error("courseList[$index] has no day"),
                periodStart = start,
                periodEnd = start + step - 1,
                weeks = weeks,
                color = item.string("color")?.takeIf { it.matches(Regex("#[0-9A-Fa-f]{6}")) },
                notes = (item.string("note") ?: item.string("remark")).cleanOrNull(),
            )
        }
        val result = TimetableV1(
            semester = Semester(
                id = stableId(0, buildJsonObject { put("name", root.string("tableName") ?: "WakeUp") }),
                name = root.string("tableName") ?: "WakeUp",
                startDate = monday.format(DateTimeFormatter.ISO_LOCAL_DATE),
                totalWeeks = root.int("totalWeeks") ?: maxWeeks,
                timeZone = root.string("timeZone") ?: "Asia/Shanghai",
                timeSlots = timeSlots,
            ),
            courses = courses,
        )
        return result.requireValid()
    }

    private fun JsonObject.weekValues(): Set<Int> {
        val list = this["stepWeekList"] ?: this["weeks"]
        if (list is JsonArray) return list.map { it.jsonPrimitive.intOrNull ?: error("WakeUp week list contains a non-integer") }.toSet()
        val start = int("startWeek") ?: return emptySet()
        val end = int("endWeek") ?: start
        val maxWeek = 60
        require(start in 1..maxWeek && end in 1..maxWeek && start <= end) { "invalid WakeUp week range $start..$end" }
        val type = int("type") ?: 0
        require(type in 0..2) { "unsupported WakeUp week type=$type" }
        return (start..end).filter { type == 0 || (type == 1 && it % 2 == 1) || (type == 2 && it % 2 == 0) }.toSet()
    }

    private fun normalizeTime(value: String): String = when {
        Regex("^\\d{2}:\\d{2}$").matches(value) -> value
        Regex("^\\d{1}:\\d{2}$").matches(value) -> "0$value"
        else -> value
    }

    private fun stableId(index: Int, value: JsonObject): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest("$index:$value".toByteArray(StandardCharsets.UTF_8))
        return bytes.take(8).joinToString("") { "%02x".format(it) }
    }

    private fun String?.cleanOrNull(): String? = this?.trim()?.takeIf(String::isNotEmpty)?.takeUnless { it == "无" }
    private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
    private fun JsonObject.int(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
}
