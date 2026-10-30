package dev.mayon.timetable

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.glance.appwidget.updateAll
import dev.mayon.timetable.core.*
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.imports.*
import dev.mayon.timetable.qr.*
import dev.mayon.timetable.reminders.deliverDueReminders
import dev.mayon.timetable.reminders.ReminderScheduler
import dev.mayon.timetable.ui.*
import dev.mayon.timetable.widget.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

class MainActivity : ComponentActivity() {
    private var resumeTick by mutableIntStateOf(0)
    private var incoming by mutableStateOf<Intent?>(null)
    override fun onResume() { super.onResume(); resumeTick++ }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); incoming = intent }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        incoming = intent
        setContent {
            val prefs = remember { getSharedPreferences("device", MODE_PRIVATE) }
            var theme by remember { mutableIntStateOf(prefs.getInt("theme", -1)) }
            val dark = when (theme) { 0 -> false; 1 -> true; else -> isSystemInDarkTheme() }
            SideEffect {
                val background = if (dark) 0xff1e2228.toInt() else 0xfff5f6f7.toInt()
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(background))
                window.decorView.setBackgroundColor(background)
                val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                    else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
                window.isNavigationBarContrastEnforced = false
                window.isStatusBarContrastEnforced = false
            }
            TimetableTheme(dark) { App(theme) { value -> theme = value; prefs.edit().putInt("theme", value).apply() } }
        }
    }

    @Composable private fun App(theme: Int, onTheme: (Int) -> Unit) {
        val store = remember { TimetableStore(this) }
        val prefs = remember { getSharedPreferences("device", MODE_PRIVATE) }
        val scope = rememberCoroutineScope()
        var tables by remember { mutableStateOf<List<TimetableV1>>(emptyList()) }
        var table by remember { mutableStateOf<TimetableV1?>(null) }
        var pending by remember { mutableStateOf<TimetableV1?>(null) }
        var replaceExisting by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        var message by remember { mutableStateOf<String?>(null) }
        var busy by remember { mutableStateOf(false) }
        var tab by rememberSaveable { mutableIntStateOf(0) }
        var editing by remember { mutableStateOf<Course?>(null) }
        var showEditor by remember { mutableStateOf(false) }
        var semesterEditing by remember { mutableStateOf<Semester?>(null) }
        var showSemester by remember { mutableStateOf(false) }
        var deleteSemester by remember { mutableStateOf(false) }
        var showSettings by remember { mutableStateOf(false) }
        var onboarding by remember { mutableStateOf(!prefs.getBoolean("onboardingDone", false)) }
        var enabled by remember { mutableStateOf(store.remindersEnabled) }
        var lead by remember { mutableStateOf(store.leadMinutes.toString()) }
        var photo by remember { mutableStateOf<Bitmap?>(null) }
        var review by remember { mutableStateOf<List<ReconstructedCell>?>(null) }
        var showSource by remember { mutableStateOf(false) }
        var qrSharing by remember { mutableStateOf(false) }
        val qrReceiver = remember { QrTransfer.newReceiver() }
        var qrProgress by remember { mutableStateOf("") }
        var exportText by rememberSaveable { mutableStateOf("") }
        var cameraUri by rememberSaveable { mutableStateOf<String?>(null) }
        suspend fun reload() {
            val result = withContext(Dispatchers.IO) { store.list() to store.active() }
            tables = result.first; table = result.second
        }
        suspend fun updateDependents() {
            val ready = withContext(Dispatchers.IO) { deliverDueReminders(this@MainActivity, java.time.Instant.now()); ReminderScheduler(this@MainActivity).reschedule() }
            TodayWidget().updateAll(this@MainActivity); NextWidget().updateAll(this@MainActivity)
            WidgetRefreshScheduler(this@MainActivity).reschedule()
            if (!ready) message = "精确提醒尚未获准，请在系统设置中允许闹钟和提醒。"
        }
        fun runJob(work: suspend () -> Unit) {
            scope.launch {
                busy = true
                try { work() }
                catch (_: Exception) { error = "操作未完成。请检查文件格式、学期作息和课程周次；源文件未删除。" }
                finally { busy = false }
            }
        }
        suspend fun acceptFile(uri: Uri) {
            val source = withContext(Dispatchers.IO) {
                contentResolver.openInputStream(uri)?.use { stream ->
                    val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (true) { val count = stream.read(buffer); if (count < 0) break
                        require(output.size() + count <= 2 * 1024 * 1024); output.write(buffer, 0, count) }
                    Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(output.toByteArray())).toString()
                } ?: throw IllegalArgumentException("cannot open")
            }
            pending = when {
                source.trimStart().startsWith("BEGIN:VCALENDAR") -> IcsCodec.import(source, table?.semester ?: throw IllegalArgumentException("create semester first"))
                else -> runCatching { TimetableJson.decode(source) }.getOrElse { WakeUpParser.parseBackup(source) }
            }
            replaceExisting = false
        }
        suspend fun acceptPhoto(uri: Uri) {
            require(table != null) { "create semester first" }
            photo = loadPhoto(this@MainActivity, uri); review = null
        }
        LaunchedEffect(resumeTick) { runJob { reload(); updateDependents() } }
        LaunchedEffect(incoming) {
            val request = incoming ?: return@LaunchedEffect
            incoming = null
            val uri = if (request.action == Intent.ACTION_SEND) {
                @Suppress("DEPRECATION") request.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            } else if (request.action == Intent.ACTION_VIEW) request.data else null
            if (uri != null) runJob {
                reload()
                if (request.type?.startsWith("image/") == true) acceptPhoto(uri) else acceptFile(uri)
            }
        }
        val document = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) runJob { acceptFile(uri) } }
        val image = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri -> if (uri != null) runJob { acceptPhoto(uri) } }
        val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
            val uri = cameraUri
            if (success && uri != null) runJob { acceptPhoto(Uri.parse(uri)) }
        }
        val scan = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
            if (uris.isNotEmpty()) runJob {
                for (uri in uris) {
                    val bitmap = loadPhoto(this@MainActivity, uri)
                    val frame = withContext(Dispatchers.Default) { decodeQr(bitmap) }
                    bitmap.recycle()
                    require(frame != null) { "no QR frame" }
                    val progress = qrReceiver.accept(frame)
                    qrProgress = "已接收 ${progress.receivedFrames}/${progress.totalFrames} 帧"
                    if (progress.resultJson != null) {
                        pending = TimetableJson.decode(progress.resultJson!!); replaceExisting = false
                        qrReceiver.reset(); qrProgress = "已收齐，请确认导入"; break
                    }
                }
            }
        }
        val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
            if (uri != null) runJob { withContext(Dispatchers.IO) { contentResolver.openOutputStream(uri, "wt")?.use { it.write(exportText.toByteArray(Charsets.UTF_8)) } ?: throw IllegalArgumentException("cannot write") }; message = "文件已导出。" }
        }
        val notification = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (!granted) message = "通知未获准，请在系统设置允许本应用通知。"
        }
        BackHandler(photo != null || review != null || qrSharing || showSettings) {
            if (showSettings) showSettings = false else { photo = null; review = null; qrSharing = false }
        }
        if (photo != null && review == null) {
            if (busy) Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center) { CircularProgressIndicator(); Text("正在本机识别课表，请稍候…") }
            else PhotoCropScreen(photo!!, onBack = { photo = null }) { cropped ->
                runJob {
                    val result = recognizePhoto(this@MainActivity, cropped)
                    require(result.cells.isNotEmpty()) { "no cells" }
                    photo?.takeUnless { it === cropped }?.recycle()
                    photo = cropped
                    review = result.cells
                }
            }
        } else if (review != null) {
            PhotoReviewScreen(review!!, { review = it }, onSave = {
                runJob {
                    val current = table ?: throw IllegalArgumentException("semester missing")
                    val courses = review!!.map { cell -> Course(UUID.randomUUID().toString(), cell.courseName.trim(), cell.teacher, cell.classroom,
                        cell.weekday, cell.periodStart, cell.periodEnd, cell.weeks, "#98c379", "照片导入后校对") }
                    val updated = current.copy(courses = current.courses + courses).requireValid()
                    withContext(Dispatchers.IO) { store.save(updated, true) }
                    review = null; photo?.recycle(); photo = null
                    cameraUri?.let { runCatching { contentResolver.delete(Uri.parse(it), null, null) } }; cameraUri = null
                    reload(); updateDependents(); tab = 0
                }
            }, onBack = { review = null }, totalWeeks = table?.semester?.totalWeeks ?: 60, validPeriods = table?.semester?.timeSlots?.map { it.period }?.toSet().orEmpty(), onPreview = { showSource = true })
        } else if (qrSharing && table != null) {
            QrShareScreen(TimetableJson.encode(table!!)) { qrSharing = false }
        } else Scaffold(bottomBar = {
            NavigationBar { listOf("今日", "一周", "导入导出", "学期").forEachIndexed { i, label ->
                NavigationBarItem(selected = tab == i, onClick = { tab = i }, icon = { Text(listOf("◷", "▦", "⇄", "≡")[i]) }, label = { Text(label) })
            } }
        }) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("课表 · Mayon", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 16.dp))
                    TextButton(onClick = { showSettings = true }, modifier = Modifier.testTag("settings")) { Text("设置") }
                }
                Text(table?.semester?.name ?: "开始自己的课表", style = MaterialTheme.typography.headlineSmall)
                if (onboarding) Card(Modifier.fillMaxWidth().padding(vertical = 8.dp)) { Column(Modifier.padding(12.dp)) {
                    Text("课表离线保存在本机。需要课前提醒时，请完成通知与 ColorOS 后台设置。")
                    TextButton(onClick = { onboarding = false; prefs.edit().putBoolean("onboardingDone", true).apply(); showSettings = true }) { Text("设置提醒") }
                    TextButton(onClick = { onboarding = false; prefs.edit().putBoolean("onboardingDone", true).apply() }) { Text("稍后设置") }
                } }
                if (tab < 2 && table != null) {
                    TextButton(onClick = { editing = null; showEditor = true }) { Text("＋ 添加课程") }
                    if (tab == 0) TodayScreen(table!!) { editing = it; showEditor = true }
                    else WeekScreen(table!!) { editing = it; showEditor = true }
                }
                if (tab < 2 && table == null) {
                    Text("所有课程保存在这台手机。无广告、无统计、不联网。", modifier = Modifier.padding(vertical = 24.dp))
                    Button(onClick = { tab = 2 }) { Text("导入第一份课表") }
                    OutlinedButton(onClick = { semesterEditing = null; showSemester = true }) { Text("创建学期") }
                }
                if (tab == 2) Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("导入与导出", style = MaterialTheme.typography.titleLarge)
                    Text("WakeUp 请导出 .wakeup_schedule；分享口令需其服务器，离线版不联网解析。")
                    OutlinedButton(onClick = { document.launch(arrayOf("*/*")) }) { Text("选择 WakeUp / JSON / ICS 文件") }
                    Text("照片不包含开学日期与作息，请先选择或创建学期。")
                    OutlinedButton(onClick = { if (table == null) { semesterEditing = null; showSemester = true } else image.launch("image/*") }) { Text("从相册选课表") }
                    OutlinedButton(onClick = {
                        if (table == null) { semesterEditing = null; showSemester = true }
                        else { val directory = File(cacheDir, "photo-import").apply { mkdirs() }; val file = File.createTempFile("camera-", ".jpg", directory)
                            val uri = FileProvider.getUriForFile(this@MainActivity, "$packageName.photos", file); cameraUri = uri.toString(); camera.launch(uri) }
                    }) { Text("拍摄课表") }
                    OutlinedButton(onClick = { scan.launch("image/*") }) { Text("从二维码图片导入（可多选）") }
                    if (qrProgress.isNotEmpty()) {
                        Text(qrProgress)
                        TextButton(onClick = { qrReceiver.reset(); qrProgress = "" }) { Text("重新接收二维码") }
                    }
                    table?.let { current ->
                        OutlinedButton(onClick = { exportText = TimetableJson.encode(current); export.launch("timetable.json") }) { Text("导出 JSON · 完整课表") }
                        OutlinedButton(onClick = { exportText = IcsCodec.export(current); export.launch("timetable.ics") }) { Text("导出 ICS · 日历事件") }
                        OutlinedButton(onClick = { qrSharing = true }) { Text("显示课表二维码") }
                    }
                    Text("大模型照片识别：关闭。当前版本只进行本机识别。", style = MaterialTheme.typography.bodySmall)
                }
                if (tab == 3) Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("我的学期", style = MaterialTheme.typography.titleLarge)
                    tables.forEach { item -> TextButton(onClick = { runJob { store.activeId = item.semester.id; reload(); updateDependents() } }) {
                        Text((if (item.semester.id == table?.semester?.id) "✓ " else "") + item.semester.name)
                    } }
                    OutlinedButton(onClick = { semesterEditing = null; showSemester = true }) { Text("创建学期") }
                    if (table != null) {
                        OutlinedButton(onClick = { semesterEditing = table!!.semester; showSemester = true }, modifier = Modifier.testTag("semester-edit")) { Text("编辑学期") }
                        TextButton(onClick = { deleteSemester = true }) { Text("删除当前学期") }
                    }
                    Text("导出 JSON 可保留完整学期与课程。换手机或卸载前请先备份。")
                }
            }
        }
        if (showSource && photo != null) AlertDialog(onDismissRequest = { showSource = false }, title = { Text("校正后的原图") },
            text = { Image(photo!!.asImageBitmap(), "课表原图", Modifier.fillMaxWidth().height(420.dp), contentScale = ContentScale.Fit) },
            confirmButton = { TextButton(onClick = { showSource = false }) { Text("返回校对") } })
        if (showEditor && table != null) CourseEditor(table!!, editing, onDismiss = { showEditor = false }, onSave = { course ->
            runJob { val current = table!!; val updated = current.copy(courses = current.courses.filterNot { it.id == course.id } + course).requireValid()
                withContext(Dispatchers.IO) { store.save(updated, true) }; showEditor = false; reload(); updateDependents() }
        }, onDelete = if (editing == null) null else ({ runJob {
            val current = table!!; withContext(Dispatchers.IO) { store.save(current.copy(courses = current.courses.filterNot { it.id == editing!!.id }), true) }
            showEditor = false; reload(); updateDependents()
        } }))
        if (showSemester) SemesterEditor(semesterEditing, onDismiss = { showSemester = false }) { semester -> runJob {
            val existing = tables.firstOrNull { it.semester.id == semester.id }
            val updated = (existing?.copy(semester = semester) ?: TimetableV1(semester = semester, courses = emptyList())).requireValid()
            withContext(Dispatchers.IO) { store.save(updated, existing != null); store.activeId = semester.id }
            showSemester = false; reload(); updateDependents()
        } }
        if (deleteSemester) AlertDialog(onDismissRequest = { deleteSemester = false }, title = { Text("删除当前学期？") },
            text = { Text("仅删除本应用中的这个学期。建议先导出 JSON 备份。") }, dismissButton = { TextButton(onClick = { deleteSemester = false }) { Text("取消") } },
            confirmButton = { TextButton(onClick = { runJob { table?.let { withContext(Dispatchers.IO) { store.delete(it.semester.id) } }; deleteSemester = false; reload(); updateDependents() } }) { Text("确认删除") } })
        pending?.let { candidate -> AlertDialog(onDismissRequest = { pending = null }, title = { Text("确认导入") }, text = { Column {
            Text("${candidate.semester.name} · ${candidate.courses.size} 门课程 · ${candidate.semester.totalWeeks} 周 · ${candidate.semester.startDate}")
            val old = tables.firstOrNull { it.semester.id == candidate.semester.id }
            if (old != null) { Text("现有 ${old.courses.size} 门 → 新 ${candidate.courses.size} 门。请先导出备份。")
                Row { Checkbox(replaceExisting, { replaceExisting = it }, modifier = Modifier.testTag("replace-semester")); Text("替换相同 ID 学期") } }
        } }, dismissButton = { TextButton(onClick = { pending = null }) { Text("取消") } }, confirmButton = { TextButton(onClick = { runJob {
            withContext(Dispatchers.IO) { store.save(candidate, replaceExisting); store.activeId = candidate.semester.id }
            pending = null; reload(); updateDependents(); tab = 0
        } }, modifier = Modifier.testTag("confirm-import")) { Text("确认导入") } }) }
        if (showSettings) AlertDialog(onDismissRequest = { showSettings = false }, title = { Text("外观与提醒") }, text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("主题"); Row { listOf(-1 to "系统", 1 to "深色", 0 to "浅色").forEach { (value, name) -> TextButton(onClick = { onTheme(value) }) { Text((if (theme == value) "✓ " else "") + name) } } }
                Row { Text("上课提醒"); Switch(enabled, { value -> enabled = value; store.remindersEnabled = value
                    if (value && Build.VERSION.SDK_INT >= 33) notification.launch(Manifest.permission.POST_NOTIFICATIONS)
                    runJob { updateDependents() } }) }
                OutlinedTextField(lead, { lead = it }, label = { Text("提前分钟 · 0至120") }, singleLine = true)
                TextButton(onClick = { runJob { store.leadMinutes = lead.toInt(); updateDependents(); message = "提醒已保存。" } }) { Text("保存提醒") }
                if (Build.VERSION.SDK_INT in 31..32) TextButton(onClick = { startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))) }) { Text("允许精确闹钟") }
                Text("ColorOS 设置指南", style = MaterialTheme.typography.titleMedium)
                Text("① 设置 → 应用 → 自启动，允许课表。\n② 设置 → 电池 → 更多设置 → 应用耗电管理 → 课表，允许后台活动/不限制。\n③ 设置 → 通知与状态栏 → 应用通知 → 课表，允许通知和上课提醒。\n不同版本可搜索“自启动”“电池优化”。强行停止后请重新打开课表。")
                TextButton(onClick = { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))) }) { Text("打开系统应用设置") }
            }
        }, confirmButton = { TextButton(onClick = { showSettings = false }) { Text("完成") } })
        (error ?: message)?.let { value -> AlertDialog(onDismissRequest = { error = null; message = null }, title = { Text(if (error != null) "操作未完成" else "提示") },
            text = { Text(value) }, confirmButton = { TextButton(onClick = { error = null; message = null }) { Text("知道了") } }) }
    }
}
