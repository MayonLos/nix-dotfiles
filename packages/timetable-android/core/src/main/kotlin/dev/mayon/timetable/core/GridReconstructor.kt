package dev.mayon.timetable.core

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** OCR text geometry consumed by the offline layout reconstruction prototype. */
data class TextBox(val text: String, val left: Double, val top: Double, val right: Double, val bottom: Double, val confidence: Double) {
    init {
        require(left >= 0 && top >= 0 && right > left && bottom > top) { "invalid OCR box bounds" }
        require(confidence in 0.0..1.0) { "confidence must be in 0..1" }
    }
    val centerX get() = (left + right) / 2
    val centerY get() = (top + bottom) / 2
}

data class ReconstructedCell(
    val weekday: Int,
    val periodStart: Int,
    val periodEnd: Int,
    val rawText: String,
    val courseName: String,
    val teacher: String?,
    val classroom: String?,
    val weeks: Set<Int>,
    val confidence: Double,
    val needsReview: Boolean,
)

data class GridResult(
    val columnHeaders: Map<Int, Double>,
    val periodCenters: Map<Int, Double>,
    val cells: List<ReconstructedCell>,
    val warnings: List<String>,
)

object GridReconstructor {
    private val dayPatterns = listOf(
        Regex("周一|星期一|礼拜一") to 1, Regex("周二|星期二|礼拜二") to 2,
        Regex("周三|星期三|礼拜三") to 3, Regex("周四|星期四|礼拜四") to 4,
        Regex("周五|星期五|礼拜五") to 5, Regex("周六|星期六|礼拜六") to 6,
        Regex("周日|周天|星期日|星期天|礼拜日") to 7,
    )
    private val periodPattern = Regex("(?:第\\s*)?(\\d{1,2})(?:\\s*[-~～]\\s*(\\d{1,2}))?\\s*节")
    private val fieldPattern = Regex("(?:教师|老师|任课教师|教室|地点|上课地点|周次|周数)\\s*[:：]\\s*([^\\n]+)")

    fun reconstruct(boxes: List<TextBox>, imageWidth: Double, imageHeight: Double, lowConfidenceThreshold: Double = 0.85): GridResult {
        require(imageWidth > 0 && imageHeight > 0) { "image dimensions must be positive" }
        require(lowConfidenceThreshold in 0.0..1.0)
        val inBounds = boxes.filter { it.left < imageWidth && it.top < imageHeight && it.right <= imageWidth && it.bottom <= imageHeight }
        val warnings = mutableListOf<String>()
        if (inBounds.size != boxes.size) warnings += "${boxes.size - inBounds.size} OCR boxes fell outside image bounds"
        val headers = inBounds.mapNotNull { box -> dayPatterns.firstNotNullOfOrNull { (pattern, day) ->
            if (pattern.matches(box.text.trim())) day to box.centerX else null
        } }.groupBy({ it.first }, { it.second }).mapValues { (_, xs) -> xs.average() }.toSortedMap()
        if (headers.size < 5) warnings += "only ${headers.size}/7 weekday headers detected"
        if (headers.isEmpty()) return GridResult(headers, emptyMap(), emptyList(), warnings + "weekday columns cannot be inferred")
        val periodAnchors = inBounds.mapNotNull { box ->
            periodPattern.matchEntire(box.text.trim())?.let { match ->
                val first = match.groupValues[1].toInt()
                val last = match.groupValues[2].takeIf(String::isNotBlank)?.toInt() ?: first
                (first..last).map { it to box.centerY }
            }
        }.flatten().groupBy({ it.first }, { it.second }).mapValues { (_, ys) -> ys.average() }.toSortedMap()
        if (periodAnchors.isEmpty()) return GridResult(headers, emptyMap(), emptyList(), warnings + "period rows cannot be inferred")
        val xBounds = boundaries(headers.values.sorted(), 0.0, imageWidth)
        data class RowBand(val firstPeriod: Int, val lastPeriod: Int, val center: Double)
        val rowBands = mutableListOf<RowBand>()
        for ((period, center) in periodAnchors.toList().sortedBy { it.second }) {
            val previous = rowBands.lastOrNull()
            if (previous != null && abs(previous.center - center) <= 2.0) {
                rowBands[rowBands.lastIndex] = previous.copy(firstPeriod = min(previous.firstPeriod, period), lastPeriod = max(previous.lastPeriod, period))
            } else rowBands += RowBand(period, period, center)
        }
        val yBounds = boundaries(rowBands.map { it.center }, 0.0, imageHeight)
        val dayByColumn = headers.entries.sortedBy { it.value }
        val anchors = inBounds.filter { box -> dayPatterns.any { it.first.matches(box.text.trim()) } || periodPattern.matches(box.text.trim()) }.toSet()
        data class Located(val box: TextBox, val column: Int, val weekday: Int, val rows: List<Int>)
        val located = (inBounds - anchors).mapNotNull { box ->
            val column = xBounds.indexOfFirst { box.centerX >= it.first && box.centerX < it.second }
            if (column !in dayByColumn.indices) return@mapNotNull null
            val rows = rowBands.indices.filter { row ->
                val bounds = yBounds[row]
                val intersection = max(0.0, min(box.bottom, bounds.second) - max(box.top, bounds.first))
                intersection >= min(box.bottom - box.top, bounds.second - bounds.first) * 0.25
            }.ifEmpty {
                listOf(rowBands.indices.minByOrNull { abs(rowBands[it].center - box.centerY) } ?: return@mapNotNull null)
            }
            Located(box, column, dayByColumn[column].key, rows)
        }
        val rowSpacing = rowBands.zipWithNext().map { (a, b) -> b.center - a.center }.filter { it > 0 }.sorted().let { values -> values.getOrNull(values.size / 2) ?: imageHeight }
        val annotation = located.filter { isAnnotationOnly(it.box.text) }
        val titles = located - annotation.toSet()
        val fragmentsByTitle = titles.associateWith { mutableListOf(it.box) }
        val unattached = mutableListOf<Located>()
        for (fragment in annotation) {
            val previous = titles.filter { it.column == fragment.column && it.box.centerY <= fragment.box.centerY }
                .filter { fragment.box.centerY - it.box.centerY <= rowSpacing * 1.5 }
                .maxByOrNull { it.box.centerY }
            val nearest = previous ?: titles.filter { it.column == fragment.column }
                .filter { abs(fragment.box.centerY - it.box.centerY) <= rowSpacing * 0.8 }
                .minByOrNull { abs(fragment.box.centerY - it.box.centerY) }
            if (nearest == null) unattached += fragment else fragmentsByTitle.getValue(nearest).add(fragment.box)
        }
        val groups = fragmentsByTitle.map { (title, fragments) -> title to fragments.toList() } + unattached.map { it to listOf(it.box) }
        val cells = groups.map { (anchor, fragments) ->
            val raw = fragments.sortedBy { it.top }.joinToString("\n") { it.text.trim() }
            val rows = fragments.flatMap { fragment -> located.first { it.box == fragment }.rows }.distinct().sorted()
            val firstBand = rows.firstOrNull()?.let(rowBands::get) ?: rowBands[anchor.rows.first()]
            val lastBand = rows.lastOrNull()?.let(rowBands::get) ?: rowBands[anchor.rows.last()]
            val periodStart = min(firstBand.firstPeriod, lastBand.firstPeriod)
            val periodEnd = max(firstBand.lastPeriod, lastBand.lastPeriod)
            val parsed = splitFields(raw)
            val confidence = fragments.minOf(TextBox::confidence)
            val weeks = parsed.weekExpression?.let { expression ->
                runCatching { WeekExpression.parse(expression, 60) }.getOrElse {
                    warnings += "could not parse week expression in ${anchor.weekday} / $periodStart: $expression"
                    emptySet()
                }
            } ?: emptySet()
            ReconstructedCell(
                weekday = anchor.weekday,
                periodStart = periodStart,
                periodEnd = periodEnd,
                rawText = raw,
                courseName = parsed.courseName,
                teacher = parsed.teacher,
                classroom = parsed.classroom,
                weeks = weeks,
                confidence = confidence,
                needsReview = fragments.any { normalizeFieldLine(it.text) != it.text.trim() } || confidence < lowConfidenceThreshold || parsed.courseName.isBlank() || weeks.isEmpty() || periodEnd > periodStart,
            )
        }.sortedWith(compareBy(ReconstructedCell::weekday, ReconstructedCell::periodStart))
        val inferredSpans = cells.count { it.periodEnd > it.periodStart }
        if (inferredSpans > 0) warnings += "$inferredSpans multi-period span(s) inferred from OCR box geometry; confirm against table lines"
        if (annotation.isNotEmpty() && annotation.size > fragmentsByTitle.values.sumOf { group -> group.count { isAnnotationOnly(it.text) } }) {
            warnings += "some OCR metadata fragments could not be confidently associated with a course cell"
        }
        return GridResult(headers, periodAnchors, cells, warnings)
    }

    // Grid strokes are sometimes decoded as brackets; normalize only labelled metadata,
    // retain rawText verbatim and always flag any repaired line for manual confirmation.
    private fun normalizeFieldLine(text: String): String {
        val trimmed = text.trim()
        val unframed = trimmed.trim('「', '」', '|', '丨', '[', ']', '【', '】').trim()
        val repaired = unframed.replace(Regex("^教[至宝](\\s*[:：])"), "教室$1")
        val label = Regex("^(任课教师|上课地点|教师|老师|教室|地点|周次|周数)\\s*[:：]?\\s*")
        return if (label.containsMatchIn(repaired)) repaired.replace(label) { it.groupValues[1] + "：" } else trimmed
    }

    private fun isAnnotationOnly(text: String): Boolean {
        val value = normalizeFieldLine(text)
        val labelled = Regex("^(?:教师|老师|任课教师|教室|地点|上课地点|周次|周数)\\s*[:：]").containsMatchIn(value)
        val weeks = Regex("^(?:第)?\\d+(?:\\s*[-~～,，、]\\s*\\d+)*\\s*周(?:\\s*[（(](?:单|双)[)）])?$").matches(value)
        return labelled || weeks
    }

    private data class Fields(val courseName: String, val teacher: String?, val classroom: String?, val weekExpression: String?)

    private fun splitFields(raw: String): Fields {
        val values = linkedMapOf<String, String>()
        val fieldText = raw.lines().joinToString("\n") { normalizeFieldLine(it) }
        val withoutFields = fieldPattern.replace(fieldText) { match ->
            val label = match.value.substringBefore(':').substringBefore('：').trim()
            val value = match.groupValues[1].trim()
            val canonical = when {
                label in listOf("教师", "老师", "任课教师") -> "teacher"
                label in listOf("教室", "地点", "上课地点") -> "classroom"
                else -> "weeks"
            }
            values.putIfAbsent(canonical, value)
            ""
        }
        val lines = withoutFields.split(Regex("[\\n;；|]+" )).map(String::trim).filter(String::isNotBlank)
        var course = lines.joinToString(" ")
        val inlineWeeks = Regex("(?:第)?\\d+(?:\\s*[-~～,，、]\\s*\\d+)*\\s*周(?:\\s*[（(](?:单|双)[)）])?").find(course)
        if (values["weeks"] == null && inlineWeeks != null) values["weeks"] = inlineWeeks.value
        if (inlineWeeks != null) course = course.replace(inlineWeeks.value, " ")
        val inlineTeacher = Regex("(?:教师|老师)\\s*[:：]?\\s*([^\\s]+)").find(course)
        if (values["teacher"] == null && inlineTeacher != null) values["teacher"] = inlineTeacher.groupValues[1]
        if (inlineTeacher != null) course = course.replace(inlineTeacher.value, " ")
        val inlineRoom = Regex("(?:教室|地点)\\s*[:：]?\\s*([^\\s]+)").find(course)
        if (values["classroom"] == null && inlineRoom != null) values["classroom"] = inlineRoom.groupValues[1]
        if (inlineRoom != null) course = course.replace(inlineRoom.value, " ")
        return Fields(course.replace(Regex("\\s+"), " ").trim(), values["teacher"], values["classroom"], values["weeks"])
    }

    private fun boundaries(centers: List<Double>, start: Double, end: Double): List<Pair<Double, Double>> {
        if (centers.size == 1) return listOf(start to end)
        return centers.indices.map { index ->
            val left = if (index == 0) start else (centers[index - 1] + centers[index]) / 2
            val right = if (index == centers.lastIndex) end else (centers[index] + centers[index + 1]) / 2
            left to right
        }
    }
}
