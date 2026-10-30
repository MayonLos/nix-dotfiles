package dev.mayon.timetable.imports

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.PointF
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.mayon.timetable.core.*
import dev.mayon.timetable.photo.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** ImageDecoder applies EXIF orientation; software bitmap is required for pixel-based ORT preprocessing. */
suspend fun loadPhoto(context: Context, uri: Uri): Bitmap = withContext(Dispatchers.IO) {
    ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
        val scale = min(1.0, 2200.0 / max(info.size.width, info.size.height))
        decoder.setTargetSize(max(64, (info.size.width * scale).toInt()), max(64, (info.size.height * scale).toInt()))
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
}

suspend fun recognizePhoto(context: Context, bitmap: Bitmap): GridResult = withContext(Dispatchers.Default) {
    PaddleOcrEngine(context).use { engine ->
        val lines = engine.recognize(bitmap)
        val boxes = lines.mapNotNull { line ->
            val left = line.corners.minOf { it.x }.coerceIn(0f, bitmap.width.toFloat())
            val right = line.corners.maxOf { it.x }.coerceIn(0f, bitmap.width.toFloat())
            val top = line.corners.minOf { it.y }.coerceIn(0f, bitmap.height.toFloat())
            val bottom = line.corners.maxOf { it.y }.coerceIn(0f, bitmap.height.toFloat())
            if (right <= left || bottom <= top) null else TextBox(line.text.trim(), left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble(), line.confidence.toDouble().coerceIn(0.0, 1.0))
        }
        // Titles above the detected weekday header belong to the page, not the first course row.
        val headers = boxes.filter { Regex("^(周|星期)[一二三四五六日天]$").matches(it.text.trim()) }
        val headerBottom = headers.maxOfOrNull { it.bottom } ?: 0.0
        val content = boxes.filter { it in headers || it.centerY > headerBottom }
        GridReconstructor.reconstruct(content, bitmap.width.toDouble(), bitmap.height.toDouble())
    }
}

@Composable
fun PhotoCropScreen(bitmap: Bitmap, onBack: () -> Unit, onRecognize: (Bitmap) -> Unit) {
    var image by remember(bitmap) { mutableStateOf(bitmap) }
    val points = remember(image) { mutableStateListOf(Offset(.01f, .01f), Offset(.99f, .01f), Offset(.99f, .99f), Offset(.01f, .99f)) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("裁剪课表", style = MaterialTheme.typography.headlineMedium)
        Text("拖动四个角，框住星期表头、节次和课程。识别只在本机进行。")
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = androidx.compose.ui.Alignment.Center) {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val height = minOf(maxWidth * image.height.toFloat() / image.width, 480.dp)
                Box(Modifier.fillMaxWidth().height(height)) {
                    Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                    Canvas(Modifier.fillMaxSize().testTag("photo-crop-image").pointerInput(image) {
                        var selected = 0
                        detectDragGestures(onDragStart = { pos -> selected = points.indices.minBy { i -> (Offset(points[i].x * size.width, points[i].y * size.height) - pos).getDistance() } }) { change, drag ->
                            change.consume()
                            points[selected] = Offset((points[selected].x + drag.x / size.width).coerceIn(0f, 1f), (points[selected].y + drag.y / size.height).coerceIn(0f, 1f))
                        }
                    }) {
                        val p = points.map { Offset(it.x * size.width, it.y * size.height) }
                        p.indices.forEach { i -> drawLine(Color(0xff98c379), p[i], p[(i + 1) % 4], 3.dp.toPx()) }
                        p.forEach { drawCircle(Color(0xff98c379), 9.dp.toPx(), it); drawCircle(Color(0xff1e2228), 4.dp.toPx(), it) }
                    }
                }
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onBack) { Text("取消") }
            TextButton(onClick = {
                image = Bitmap.createBitmap(image, 0, 0, image.width, image.height, android.graphics.Matrix().apply { postRotate(90f) }, true)
            }) { Text("旋转") }
            Button(onClick = {
                runCatching {
                    val p = points.map { PointF(it.x * (image.width - 1), it.y * (image.height - 1)) }
                    fun distance(a: PointF, b: PointF) = hypot((a.x - b.x).toDouble(), (a.y - b.y).toDouble())
                    val width = max(distance(p[0], p[1]), distance(p[3], p[2])).toInt().coerceIn(64, 2200)
                    val height = max(distance(p[0], p[3]), distance(p[1], p[2])).toInt().coerceIn(64, 2200)
                    rectify(image, CropQuad(p), width, height)
                }.onSuccess(onRecognize).onFailure { error = "请按左上、右上、右下、左下排列四个角，避免交叉。" }
            }, modifier = Modifier.testTag("photo-recognize")) { Text("识别照片") }
        }
    }
}
