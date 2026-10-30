package dev.mayon.timetable.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

object TimetableJson {
    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
    }

    fun encode(timetable: TimetableV1): String = json.encodeToString(
        timetable.requireValid().copy(courses = timetable.courses.map { it.copy(weeks = it.weeks.toSortedSet()) }),
    )
    fun decode(source: String): TimetableV1 {
        val element = json.parseToJsonElement(source).jsonObject
        require(element["format"]?.jsonPrimitive?.contentOrNull == "timetable") { "format marker is required and must equal timetable" }
        require(element["version"]?.jsonPrimitive?.intOrNull == 1) { "version marker is required and must equal 1" }
        return json.decodeFromJsonElement<TimetableV1>(element).requireValid()
    }
}
