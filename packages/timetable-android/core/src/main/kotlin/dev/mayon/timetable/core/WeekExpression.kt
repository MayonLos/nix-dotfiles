package dev.mayon.timetable.core

/** Parses common Chinese academic-week expressions into 1-based teaching-week numbers. */
object WeekExpression {
    fun parse(expression: String, totalWeeks: Int): Set<Int> {
        require(totalWeeks in 1..60) { "totalWeeks must be between 1 and 60" }
        val source = expression.trim()
            .replace("第", "")
            .replace(Regex("[\\s周次]"), "")
            .replace('，', ',')
            .replace('、', ',')
            .replace('；', ',')
            .replace(';', ',')
            .replace('－', '-')
            .replace('—', '-')
            .replace('~', '-')
            .replace('～', '-')
        require(source.isNotEmpty()) { "week expression is empty" }
        val result = sortedSetOf<Int>()
        for (untrimmedPart in source.split(',')) {
            val part = untrimmedPart.trim()
            require(part.isNotBlank()) { "empty week item" }
            val hasOdd = part.contains("单")
            val hasEven = part.contains("双")
            require(!(hasOdd && hasEven)) { "one week item cannot be both odd and even: $part" }
            val parity = when { hasOdd -> 1; hasEven -> 0; else -> null }
            val numeric = part.replace(Regex("[()（）单双]"), "")
            val range = Regex("^(\\d+)(?:-(\\d+))?$").matchEntire(numeric)
                ?: throw IllegalArgumentException("invalid week item: $part")
            val first = range.groupValues[1].toInt()
            val last = range.groupValues[2].takeIf(String::isNotEmpty)?.toInt() ?: first
            require(first in 1..totalWeeks && last in 1..totalWeeks && first <= last) {
                "week range $part is outside 1..$totalWeeks or reversed"
            }
            (first..last).filter { parity == null || it % 2 == parity }.forEach(result::add)
        }
        require(result.isNotEmpty()) { "week expression selects no weeks" }
        return result
    }
}
