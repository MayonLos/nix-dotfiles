package dev.mayon.timetable.widget

import android.content.Context
import android.content.res.Configuration
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.updateAll
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.mayon.timetable.MainActivity
import dev.mayon.timetable.core.occurrences
import dev.mayon.timetable.data.TimetableStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private data class WidgetContent(val heading: String, val lines: List<String>, val updatedAt: String)

open class LessonWidget(private val nextOnly: Boolean) : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val content = withContext(Dispatchers.IO) { readWidgetContent(context, nextOnly) }
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val background = if (dark) Color(0xff1e2228) else Color(0xfff5f6f7)
        val foreground = if (dark) Color(0xffd7dae0) else Color(0xff20252c)
        val accent = if (dark) Color(0xff98c379) else Color(0xff416737)
        provideContent {
            Column(GlanceModifier.fillMaxSize().background(background).padding(14.dp)
                .clickable(actionStartActivity<MainActivity>())) {
                Row(GlanceModifier.fillMaxWidth()) {
                    Text(content.heading, modifier = GlanceModifier.defaultWeight(),
                        style = TextStyle(color = ColorProvider(accent)))
                    Text("刷新", modifier = GlanceModifier.clickable(actionRunCallback<WidgetRefreshAction>()),
                        style = TextStyle(color = ColorProvider(accent)))
                }
                content.lines.forEach { line -> Text(line, style = TextStyle(color = ColorProvider(foreground))) }
                Text("更新于 ${content.updatedAt}", style = TextStyle(color = ColorProvider(foreground.copy(alpha = .72f))))
            }
        }
    }
}

private fun readWidgetContent(context: Context, nextOnly: Boolean): WidgetContent = runCatching {
    val now = Instant.now()
    val table = TimetableStore(context).active()
        ?: return WidgetContent("今日课程", listOf("打开应用，导入第一份课表"), now.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm")))
    val zone = ZoneId.of(table.semester.timeZone)
    val localNow = now.atZone(zone)
    val today = localNow.toLocalDate()
    val all = occurrences(table)
    val updated = localNow.format(DateTimeFormatter.ofPattern("HH:mm"))
    if (nextOnly) {
        val next = all.firstOrNull { it.start.toInstant().isAfter(now) }
        WidgetContent("下一节课", listOfNotNull(next?.let {
            "${it.start.format(DateTimeFormatter.ofPattern("MM-dd E HH:mm", java.util.Locale.SIMPLIFIED_CHINESE))}  ${it.course.name}"
        }, next?.course?.classroom?.takeIf { it.isNotBlank() }?.let { "教室 · $it" }
            ?: if (next == null) "学期内没有下一节课" else null), updated)
    } else {
        val lessons = all.filter { it.start.toLocalDate() == today }
        val current = lessons.firstOrNull { !now.isBefore(it.start.toInstant()) && now.isBefore(it.end.toInstant()) }
        val lines = buildList {
            if (current != null) add("现在上课 · ${current.course.name}")
            lessons.take(5).forEach { occurrence ->
                val marker = if (occurrence == current) "● " else "  "
                add("$marker${occurrence.start.toLocalTime()}  ${occurrence.course.name} · ${occurrence.course.classroom.orEmpty()}")
            }
            if (isEmpty()) add("今天没有课")
        }
        WidgetContent("今日课程 · ${today.format(DateTimeFormatter.ofPattern("M月d日 E", java.util.Locale.SIMPLIFIED_CHINESE))}", lines, updated)
    }
}.getOrElse {
    WidgetContent("课表", listOf("课表读取失败，请打开应用检查"), Instant.now().atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm")))
}

class TodayWidget : LessonWidget(false)
class NextWidget : LessonWidget(true)
class TodayWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = TodayWidget() }
class NextWidgetReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget = NextWidget() }

/** User-triggered widget refresh action; updates both widgets and reinstates the next boundary. */
class WidgetRefreshAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        refreshTimetableWidgets(context)
    }
}

/** Public entry point for the app after a timetable or reminder preference changes. */
suspend fun refreshTimetableWidgets(context: Context) {
    TodayWidget().updateAll(context)
    NextWidget().updateAll(context)
    WidgetRefreshScheduler(context).reschedule()
}
