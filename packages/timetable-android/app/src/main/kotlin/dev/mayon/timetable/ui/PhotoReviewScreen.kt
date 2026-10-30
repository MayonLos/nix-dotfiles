package dev.mayon.timetable.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.mayon.timetable.core.GridReconstructor
import dev.mayon.timetable.core.ReconstructedCell
import dev.mayon.timetable.core.WeekExpression

@Composable
fun PhotoReviewScreen(
    cells: List<ReconstructedCell>,
    onChange: (List<ReconstructedCell>) -> Unit,
    onSave: () -> Unit,
    onBack: () -> Unit,
    totalWeeks: Int = 60,
    validPeriods: Set<Int> = (1..60).toSet(),
    onPreview: (() -> Unit)? = null,
) {
    val edited = remember { mutableStateListOf<ReconstructedCell>().apply { addAll(cells) } }
    val confirmed = remember { mutableStateListOf<Int>() }
    val weekDrafts = remember { mutableStateMapOf<Int, String>().apply { cells.forEachIndexed { index, cell -> this[index] = cell.weeks.sorted().joinToString(",") } } }
    val weekdayDrafts = remember { mutableStateMapOf<Int, String>().apply { cells.forEachIndexed { index, cell -> this[index] = cell.weekday.toString() } } }
    val firstDrafts = remember { mutableStateMapOf<Int, String>().apply { cells.forEachIndexed { index, cell -> this[index] = cell.periodStart.toString() } } }
    val lastDrafts = remember { mutableStateMapOf<Int, String>().apply { cells.forEachIndexed { index, cell -> this[index] = cell.periodEnd.toString() } } }
    LaunchedEffect(cells) {
        if (edited.toList() != cells) {
            edited.clear(); edited.addAll(cells)
            confirmed.clear()
            weekDrafts.clear(); cells.forEachIndexed { index, cell -> weekDrafts[index] = cell.weeks.sorted().joinToString(",") }
            weekdayDrafts.clear(); cells.forEachIndexed { index, cell -> weekdayDrafts[index] = cell.weekday.toString() }
            firstDrafts.clear(); cells.forEachIndexed { index, cell -> firstDrafts[index] = cell.periodStart.toString() }
            lastDrafts.clear(); cells.forEachIndexed { index, cell -> lastDrafts[index] = cell.periodEnd.toString() }
        }
    }
    fun update(index: Int, value: ReconstructedCell) {
        edited[index] = value
        confirmed.remove(index)
        onChange(edited.toList())
    }
    fun cellCanBeConfirmed(index: Int, cell: ReconstructedCell): Boolean {
        val parsedWeeks = runCatching { WeekExpression.parse(weekDrafts[index].orEmpty(), totalWeeks) }.getOrNull()
        val weekday = weekdayDrafts[index]?.toIntOrNull()
        val first = firstDrafts[index]?.toIntOrNull()
        val last = lastDrafts[index]?.toIntOrNull()
        return cell.courseName.isNotBlank() && parsedWeeks?.isNotEmpty() == true && parsedWeeks.all { it in 1..totalWeeks } &&
            weekday != null && weekday in 1..7 && first != null && first in 1..60 && last != null && last in 1..60 && last >= first && (first..last).all { it in validPeriods }
    }
    val listState = remember { LazyListState() }
    val allConfirmed = edited.isNotEmpty() && edited.indices.all { confirmed.contains(it) && cellCanBeConfirmed(it, edited[it]) }
    Column(Modifier.fillMaxSize().systemBarsPadding().imePadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onBack, modifier = Modifier.testTag("photo-review-back")) { Text("返回") }
            Text("核对识别结果", style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = {
                val added = ReconstructedCell(1, 1, 1, "", "", null, null, emptySet(), 0.0, true)
                edited.add(added)
                val index = edited.lastIndex
                weekDrafts[index] = ""; weekdayDrafts[index] = "1"; firstDrafts[index] = "1"; lastDrafts[index] = "1"
                onChange(edited.toList())
            }, modifier = Modifier.testTag("photo-add-cell")) { Text("添加") }
        }
        Text("逐格检查课程、星期、节次与周次；节次须存在于学期作息。黄色内容建议重点核对。", style = MaterialTheme.typography.bodyMedium)
        if (onPreview != null) TextButton(onClick = onPreview) { Text("查看校正后的原图") }
        LazyColumn(Modifier.weight(1f), state = listState, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            itemsIndexed(edited.toList(), key = { index, cell -> "${cell.weekday}-${cell.periodStart}-${index}" }) { index, cell ->
                val low = cell.confidence < .85 || cell.needsReview
                val weeksText = weekDrafts[index].orEmpty()
                val weekError = runCatching { WeekExpression.parse(weeksText, totalWeeks) }.isFailure
                val canConfirm = cellCanBeConfirmed(index, cell)
                Card(
                    modifier = Modifier.fillMaxWidth().then(if (low) Modifier.border(1.dp, Color(0xffe5c07b).copy(alpha = .75f), androidx.compose.foundation.shape.RoundedCornerShape(12.dp)) else Modifier).testTag("photo-cell-$index"),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = if (low) .78f else 1f)),
                ) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("第 ${index + 1} 格 · 置信度 ${(cell.confidence * 100).toInt()}%", style = MaterialTheme.typography.titleSmall,
                                color = if (low) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant)
                            TextButton(onClick = {
                                edited.removeAt(index)
                                val oldConfirmed = confirmed.toList(); confirmed.clear(); confirmed.addAll(oldConfirmed.filter { it < index }.map { it } + oldConfirmed.filter { it > index }.map { it - 1 })
                                fun shift(values: Map<Int, String>) = values.entries.filter { it.key != index }.associate { (key, value) -> (if (key > index) key - 1 else key) to value }
                                val nextWeeks = shift(weekDrafts); val nextDays = shift(weekdayDrafts); val nextFirst = shift(firstDrafts); val nextLast = shift(lastDrafts)
                                weekDrafts.clear(); weekDrafts.putAll(nextWeeks); weekdayDrafts.clear(); weekdayDrafts.putAll(nextDays)
                                firstDrafts.clear(); firstDrafts.putAll(nextFirst); lastDrafts.clear(); lastDrafts.putAll(nextLast)
                                onChange(edited.toList())
                            }, modifier = Modifier.testTag("photo-delete-$index")) { Text("移除") }
                        }
                        if (cell.rawText.isNotBlank()) Text("识别原文：${cell.rawText}", style = MaterialTheme.typography.bodySmall)
                        OutlinedTextField(cell.courseName, { update(index, cell.copy(courseName = it, needsReview = true)) }, label = { Text("课程名") }, modifier = Modifier.fillMaxWidth().testTag("photo-course-$index"), singleLine = true)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(weekdayDrafts[index].orEmpty(), { value -> weekdayDrafts[index] = value; value.toIntOrNull()?.let { if (it in 1..7) update(index, cell.copy(weekday = it, needsReview = true)) } }, label = { Text("星期 · 1至7") }, modifier = Modifier.weight(1f), singleLine = true)
                            OutlinedTextField(firstDrafts[index].orEmpty(), { value -> firstDrafts[index] = value; value.toIntOrNull()?.let { if (it in 1..60) update(index, cell.copy(periodStart = it, needsReview = true)) } }, label = { Text("起节") }, modifier = Modifier.weight(1f), singleLine = true)
                            OutlinedTextField(lastDrafts[index].orEmpty(), { value -> lastDrafts[index] = value; value.toIntOrNull()?.let { if (it in 1..60) update(index, cell.copy(periodEnd = it, needsReview = true)) } }, label = { Text("止节") }, modifier = Modifier.weight(1f), singleLine = true)
                        }
                        OutlinedTextField(cell.teacher.orEmpty(), { update(index, cell.copy(teacher = it.ifBlank { null }, needsReview = true)) }, label = { Text("教师") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        OutlinedTextField(cell.classroom.orEmpty(), { update(index, cell.copy(classroom = it.ifBlank { null }, needsReview = true)) }, label = { Text("教室") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        OutlinedTextField(weeksText, { value ->
                            weekDrafts[index] = value
                            val parsed = runCatching { WeekExpression.parse(value, totalWeeks) }.getOrNull()
                            if (parsed != null || value.isBlank()) update(index, cell.copy(weeks = parsed.orEmpty(), needsReview = true))
                        }, label = { Text("周次 · 1-16周(单) / 3,5,7周") }, modifier = Modifier.fillMaxWidth().testTag("photo-weeks-$index"), singleLine = true,
                            supportingText = { if (weekError) Text("周次格式无效") })
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = confirmed.contains(index), onCheckedChange = { checked -> if (checked && canConfirm) confirmed.add(index) else confirmed.remove(index) }, modifier = Modifier.testTag("photo-confirm-$index"))
                            Text("已核对这一格", modifier = Modifier.testTag("photo-confirm-label-$index"))
                        }
                        if (!canConfirm) Text("请填写课程名、有效周次、星期和节次范围后再确认。", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        Button(onClick = onSave, enabled = allConfirmed, modifier = Modifier.fillMaxWidth().testTag("photo-save")) { Text(if (allConfirmed) "保存课程" else "请核对并确认每一格") }
    }
}
