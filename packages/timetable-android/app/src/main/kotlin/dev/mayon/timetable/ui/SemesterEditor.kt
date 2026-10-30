package dev.mayon.timetable.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.mayon.timetable.core.PeriodTime
import dev.mayon.timetable.core.Semester
import dev.mayon.timetable.core.TimetableV1
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

@Composable
fun SemesterEditor(existing: Semester?, onDismiss: () -> Unit, onSave: (Semester) -> Unit) {
    var id by remember(existing) { mutableStateOf(existing?.id ?: "semester-${UUID.randomUUID()}") }
    var name by remember(existing) { mutableStateOf(existing?.name ?: "新学期") }
    var startDate by remember(existing) { mutableStateOf(existing?.startDate ?: LocalDate.now().with(java.time.DayOfWeek.MONDAY).toString()) }
    var totalWeeks by remember(existing) { mutableStateOf((existing?.totalWeeks ?: 16).toString()) }
    var timeZone by remember(existing) { mutableStateOf(existing?.timeZone ?: ZoneId.systemDefault().id) }
    val slots = remember(existing) { mutableStateListOf<PeriodTime>().apply {
        addAll(existing?.timeSlots ?: listOf(PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "08:55", "09:40")))
    } }
    var error by remember(existing) { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "添加学期" else "编辑学期") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("学期名称") }, modifier = Modifier.fillMaxWidth().testTag("semester-name"), singleLine = true)
                OutlinedTextField(startDate, { startDate = it }, label = { Text("开学日期 · YYYY-MM-DD（第 1 周周一）") }, modifier = Modifier.fillMaxWidth().testTag("semester-start-date"), singleLine = true)
                OutlinedTextField(totalWeeks, { totalWeeks = it }, label = { Text("总周数 · 1 至 60") }, modifier = Modifier.fillMaxWidth().testTag("semester-total-weeks"), singleLine = true)
                OutlinedTextField(timeZone, { timeZone = it }, label = { Text("时区 · IANA 名称") }, modifier = Modifier.fillMaxWidth().testTag("semester-time-zone"), singleLine = true)
                Text("每日作息", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)
                slots.forEachIndexed { index, slot ->
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text("${slot.period}节", modifier = Modifier.weight(.55f))
                        OutlinedTextField(slot.start, { slots[index] = slot.copy(start = it) }, label = { Text("开始") }, modifier = Modifier.weight(1f), singleLine = true)
                        OutlinedTextField(slot.end, { slots[index] = slot.copy(end = it) }, label = { Text("结束") }, modifier = Modifier.weight(1f), singleLine = true)
                        TextButton(onClick = {
                            slots.removeAt(index)
                        }, modifier = Modifier.testTag("semester-remove-period-$index")) { Text("删除") }
                    }
                }
                TextButton(onClick = { val next = (slots.maxOfOrNull { it.period } ?: 0) + 1; slots.add(PeriodTime(next, "12:00", "12:45")) }, modifier = Modifier.testTag("semester-add-period")) { Text("添加一节") }
                error?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
        confirmButton = {
            TextButton(onClick = {
                runCatching {
                    require(name.isNotBlank())
                    val semester = Semester(id.trim(), name.trim(), LocalDate.parse(startDate.trim()).toString(), totalWeeks.toInt(), timeZone.trim(), slots.toList())
                    TimetableV1(semester = semester, courses = emptyList()).requireValid()
                    semester
                }.onSuccess(onSave).onFailure {
                    error = "请检查学期名称、周一开学日期、总周数、时区和作息时间。"
                }
            }, modifier = Modifier.testTag("semester-save")) { Text("保存") }
        },
    )
}
