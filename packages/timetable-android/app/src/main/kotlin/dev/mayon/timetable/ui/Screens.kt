package dev.mayon.timetable.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.testTag
import dev.mayon.timetable.core.*
import dev.mayon.timetable.data.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

@Composable private fun clock(zone: String): ZonedDateTime {
    var now by remember(zone) { mutableStateOf(ZonedDateTime.now(ZoneId.of(zone))) }
    LaunchedEffect(zone) { while (true) { now = ZonedDateTime.now(ZoneId.of(zone)); delay(15_000) } }
    return now
}

@Composable fun TodayScreen(table: TimetableV1, onEdit: (Course) -> Unit) {
    val now = clock(table.semester.timeZone)
    val week = weekAt(table, now.toLocalDate())
    val lessons = remember(table, now.toLocalDate()) { occurrences(table).filter { it.start.toLocalDate() == now.toLocalDate() } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("${now.toLocalDate()} · 星期${"一二三四五六日"[now.dayOfWeek.value - 1]}", style = MaterialTheme.typography.titleLarge)
        Text(if (week in 1..table.semester.totalWeeks) "第 $week 周" else "学期外")
        if (lessons.isEmpty()) Text("今天没有课，留点时间给自己。", modifier = Modifier.padding(vertical = 40.dp))
        lessons.forEach { occurrence ->
            val current = !now.isBefore(occurrence.start) && now.isBefore(occurrence.end)
            val finished = !now.isBefore(occurrence.end)
            Card(onClick = { onEdit(occurrence.course) }, modifier = Modifier.fillMaxWidth().testTag("today-course-${occurrence.course.id}"), colors = CardDefaults.cardColors(
                containerColor = if (current) MaterialTheme.colorScheme.primary.copy(alpha = .13f) else MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(when { current -> "正在上课"; finished -> "已结束"; else -> "接下来" }, color = MaterialTheme.colorScheme.primary)
                    Text(occurrence.course.name, style = MaterialTheme.typography.titleLarge)
                    Text("${occurrence.start.toLocalTime()}–${occurrence.end.toLocalTime()} · 第${occurrence.course.periodStart}–${occurrence.course.periodEnd}节")
                    Text(listOfNotNull(occurrence.course.classroom, occurrence.course.teacher).joinToString(" · "))
                    occurrence.course.notes?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable fun WeekScreen(table: TimetableV1, onEdit: (Course) -> Unit) {
    val now = clock(table.semester.timeZone)
    val actualWeek = weekAt(table, now.toLocalDate())
    val pager = rememberPagerState(initialPage = (actualWeek - 1).coerceIn(0, table.semester.totalWeeks - 1),
        pageCount = { table.semester.totalWeeks })
    val scope = rememberCoroutineScope()
    val slots = table.semester.timeSlots.sortedBy { it.period }
    Column {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { scope.launch { pager.animateScrollToPage((pager.currentPage - 1).coerceAtLeast(0)) } }, modifier = Modifier.testTag("week-previous")) { Text("上一周") }
            Text("第 ${pager.currentPage + 1} 周${if (pager.currentPage + 1 == actualWeek) " · 本周" else ""}")
            TextButton(onClick = { scope.launch { pager.animateScrollToPage((pager.currentPage + 1).coerceAtMost(table.semester.totalWeeks - 1)) } }, modifier = Modifier.testTag("week-next")) { Text("下一周") }
        }
        HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { table.semester.id + it }) { page ->
            BoxWithConstraints(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                val gridWidth = maxWidth
                val labelWidth = 28.dp; val columnWidth = (gridWidth - labelWidth) / 7
                val rowHeight = 76.dp; val headerHeight = 44.dp
                val monday = LocalDate.parse(table.semester.startDate).plusWeeks(page.toLong())
                Box(Modifier.width(gridWidth).height(headerHeight + rowHeight * slots.size)) {
                    (1..7).forEach { day ->
                        val today = monday.plusDays(day - 1L) == now.toLocalDate()
                        Text("${"一二三四五六日"[day - 1]}\n${monday.plusDays(day - 1L).dayOfMonth}",
                            modifier = Modifier.offset(labelWidth + columnWidth * (day - 1), 0.dp).width(columnWidth).height(headerHeight)
                                .background(if (today) MaterialTheme.colorScheme.primary.copy(alpha = .15f) else Color.Transparent),
                            color = if (today) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, fontSize = 12.sp)
                    }
                    slots.forEachIndexed { row, slot ->
                        val currentSlot = page + 1 == actualWeek && now.toLocalTime() >= java.time.LocalTime.parse(slot.start) && now.toLocalTime() < java.time.LocalTime.parse(slot.end)
                        Text(slot.period.toString(), modifier = Modifier.offset(0.dp, headerHeight + rowHeight * row).width(labelWidth), fontSize = 11.sp,
                            color = if (currentSlot) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                            fontWeight = if (currentSlot) FontWeight.Bold else FontWeight.Normal)
                        Box(Modifier.offset(labelWidth, headerHeight + rowHeight * row).width(gridWidth - labelWidth).height(rowHeight)
                            .border(.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = .25f)))
                    }
                    table.courses.filter { page + 1 in it.weeks }.forEach { course ->
                        val first = slots.indexOfFirst { it.period == course.periodStart }
                        val last = slots.indexOfFirst { it.period == course.periodEnd }
                        if (first >= 0 && last >= first) {
                            val current = page + 1 == actualWeek && course.weekday == now.dayOfWeek.value &&
                                now.toLocalTime() >= java.time.LocalTime.parse(slots[first].start) && now.toLocalTime() < java.time.LocalTime.parse(slots[last].end)
                            val accent = course.color?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() }
                                ?: MaterialTheme.colorScheme.primary
                            Column(Modifier.offset(labelWidth + columnWidth * (course.weekday - 1), headerHeight + rowHeight * first)
                                .width(columnWidth).height(rowHeight * (last - first + 1)).padding(2.dp)
                                .background(accent.copy(alpha = .15f), RoundedCornerShape(6.dp))
                                .border(if (current) 2.dp else .5.dp, if (current) MaterialTheme.colorScheme.primary else accent.copy(alpha = .4f), RoundedCornerShape(6.dp))
                                .clickable { onEdit(course) }.padding(3.dp)) {
                                Text(course.name, fontSize = 11.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
                                course.classroom?.let { Text(it, fontSize = 9.sp, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable fun CourseEditor(table: TimetableV1, existing: Course?, onDismiss: () -> Unit, onSave: (Course) -> Unit, onDelete: (() -> Unit)? = null) {
    var name by remember(existing) { mutableStateOf(existing?.name.orEmpty()) }
    var teacher by remember(existing) { mutableStateOf(existing?.teacher.orEmpty()) }
    var room by remember(existing) { mutableStateOf(existing?.classroom.orEmpty()) }
    var day by remember(existing) { mutableStateOf((existing?.weekday ?: 1).toString()) }
    var first by remember(existing) { mutableStateOf((existing?.periodStart ?: 1).toString()) }
    var last by remember(existing) { mutableStateOf((existing?.periodEnd ?: 1).toString()) }
    var weeks by remember(existing) { mutableStateOf(existing?.weeks?.sorted()?.joinToString(",") ?: "1-${table.semester.totalWeeks}周") }
    var color by remember(existing) { mutableStateOf(existing?.color ?: "#98c379") }
    var notes by remember(existing) { mutableStateOf(existing?.notes.orEmpty()) }
    var validation by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember(existing) { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(if (existing == null) "添加课程" else "编辑课程") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(name, { name = it }, label = { Text("课程名") }, modifier = Modifier.fillMaxWidth().testTag("course-name"), singleLine = true)
            OutlinedTextField(teacher, { teacher = it }, label = { Text("教师") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(room, { room = it }, label = { Text("教室") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(day, { day = it }, label = { Text("星期 · 1至7") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { OutlinedTextField(first, { first = it }, label = { Text("起节") }, modifier = Modifier.weight(1f), singleLine = true)
                OutlinedTextField(last, { last = it }, label = { Text("止节") }, modifier = Modifier.weight(1f), singleLine = true) }
            OutlinedTextField(weeks, { weeks = it }, label = { Text("周次 · 1-16周(单) / 3,5,7周") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(color, { color = it }, label = { Text("颜色 · #RRGGBB") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(notes, { notes = it }, label = { Text("备注") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
            val overlap = runCatching {
                val parsedWeeks = WeekExpression.parse(weeks, table.semester.totalWeeks)
                val parsedDay = day.toInt(); val parsedFirst = first.toInt(); val parsedLast = last.toInt()
                table.courses.filter { it.id != existing?.id }.filter { other -> other.weekday == parsedDay &&
                    other.weeks.intersect(parsedWeeks).isNotEmpty() && other.periodStart <= parsedLast && parsedFirst <= other.periodEnd }
            }.getOrDefault(emptyList())
            if (overlap.isNotEmpty()) Text("时间冲突：${overlap.joinToString("、") { it.name }}", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            validation?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } }, dismissButton = { Row { if (existing != null && onDelete != null) TextButton(onClick = { confirmDelete = true }, modifier = Modifier.testTag("course-delete")) { Text("删除") }; TextButton(onClick = onDismiss) { Text("取消") } } }, confirmButton = { TextButton(onClick = {
            runCatching {
                val course = Course(id = existing?.id ?: UUID.randomUUID().toString(), name = name.trim(),
                    teacher = teacher.trim().ifEmpty { null }, classroom = room.trim().ifEmpty { null }, weekday = day.toInt(),
                    periodStart = first.toInt(), periodEnd = last.toInt(), weeks = WeekExpression.parse(weeks, table.semester.totalWeeks),
                    color = color, notes = notes.ifEmpty { null })
                table.copy(courses = table.courses.filterNot { it.id == course.id } + course).requireValid()
                course
            }.onSuccess(onSave).onFailure { validation = "请检查星期、节次、周次和颜色格式。" }
        }, modifier = Modifier.testTag("course-save")) { Text("保存") } })
    if (confirmDelete && onDelete != null) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("删除这门课程？") },
        text = { Text("删除后，这门课将从当前学期课表中移除。") },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("取消") } },
        confirmButton = { TextButton(onClick = onDelete, modifier = Modifier.testTag("course-delete-confirm")) { Text("确认删除") } },
    )
}
