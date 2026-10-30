package dev.mayon.timetable.data

import android.content.Context
import android.util.AtomicFile
import dev.mayon.timetable.core.TimetableV1
import dev.mayon.timetable.core.TimetableJson
import java.io.File

/** App-private storage. Imported documents are never silently overwritten. No source-photo access. */
class TimetableStore(context: Context) {
    companion object { private val ioLock = Any() }
    private val root = File(context.filesDir, "semesters").apply { mkdirs() }
    private val preferences = context.getSharedPreferences("device", Context.MODE_PRIVATE)
    var activeId: String?
        get() = preferences.getString("activeSemester", null)
        set(value) { require(value == null || validId(value)); preferences.edit().putString("activeSemester", value).apply() }
    var remindersEnabled: Boolean
        get() = preferences.getBoolean("remindersEnabled", false)
        set(value) { preferences.edit().putBoolean("remindersEnabled", value).apply() }
    var leadMinutes: Int
        get() = preferences.getInt("leadMinutes", 10)
        set(value) { require(value in 0..120); preferences.edit().putInt("leadMinutes", value).apply() }

    /** A persistent delivery ledger prevents close-together alarms re-notifying an older lesson. */
    fun claimReminder(key: String): Boolean = synchronized(ioLock) {
        val entries = preferences.getStringSet("delivered", emptySet()).orEmpty()
        if (key in entries) return false
        val bounded = (entries + key).sortedByDescending { it.substringBefore(':').toLongOrNull() ?: 0 }.take(512).toSet()
        return preferences.edit().putStringSet("delivered", bounded).commit()
    }

    fun delete(id: String): Unit = synchronized(ioLock) {
        file(id).delete() // Explicit user-confirmed deletion of this app's own semester only.
        if (activeId == id) activeId = list().firstOrNull()?.semester?.id
    }

    private fun validId(id: String) = id.matches(Regex("[A-Za-z0-9_-]{1,80}"))
    private fun file(id: String): AtomicFile {
        require(validId(id)) { "学期 ID 不能用作文件路径" }
        return AtomicFile(File(root, "$id.json"))
    }
    fun read(id: String): TimetableV1 = synchronized(ioLock) { file(id).openRead().use {
        require(it.available() <= 2 * 1024 * 1024)
        TimetableJson.decode(it.readBytes().toString(Charsets.UTF_8))
    } }
    fun list(): List<TimetableV1> = synchronized(ioLock) { root.listFiles().orEmpty()
        .filter { it.extension == "json" && validId(it.nameWithoutExtension) }
        .map { read(it.nameWithoutExtension) } } // Corruption is surfaced to UI; never silently dropped.
    fun active(): TimetableV1? = synchronized(ioLock) { activeId?.let { id ->
        if (file(id).baseFile.exists()) read(id) else null
    } }
    fun save(table: TimetableV1, replace: Boolean = false): Unit = synchronized(ioLock) {
        val bytes = TimetableJson.encode(table).toByteArray(Charsets.UTF_8)
        require(bytes.size <= 2 * 1024 * 1024)
        // Encoding and decoding also validates the complete snapshot before any write.
        TimetableJson.decode(bytes.toString(Charsets.UTF_8))
        val target = file(table.semester.id)
        require(replace || !target.baseFile.exists()) { "学期已存在，请确认替换或使用新 ID" }
        val stream = target.startWrite()
        try { stream.write(bytes); target.finishWrite(stream) }
        catch (error: Throwable) { target.failWrite(stream); throw error }
        if (activeId == null) activeId = table.semester.id
    }
}
