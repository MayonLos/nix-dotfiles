package dev.mayon.timetable.photo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PointF
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Fully offline PP-OCRv4 mobile detector/recognizer. All inference and bitmap work is serialized
 * and dispatched to a worker thread; only a bounded number of pixels and line crops are retained.
 */
class PaddleOcrEngine(context: Context) : OfflineOcrEngine {
    private val appContext = context.applicationContext
    private val environment = OrtEnvironment.getEnvironment().apply { setTelemetry(false) }
    private val lock = Mutex()
    private var detector: OrtSession? = null
    private var recognizer: OrtSession? = null
    @Volatile private var closed = false

    override suspend fun recognize(rectifiedImage: Bitmap): List<RecognizedLine> = withContext(Dispatchers.Default) {
        require(!rectifiedImage.isRecycled) { "图片已释放" }
        require(rectifiedImage.width in 64..MAX_INPUT_SIDE && rectifiedImage.height in 64..MAX_INPUT_SIDE) {
            "照片尺寸超出 OCR 安全范围（最大 ${MAX_INPUT_SIDE}px）"
        }
        require(rectifiedImage.width.toLong() * rectifiedImage.height <= MAX_INPUT_PIXELS) {
            "照片像素过多，请先裁剪课表区域"
        }
        lock.withLock {
            check(!closed) { "OCR 引擎已关闭" }
            ensureSessions()
            val boxes = detect(rectifiedImage)
            boxes.mapNotNull { box ->
                val crop = crop(rectifiedImage, box) ?: return@mapNotNull null
                try {
                    val (text, recScore) = recognizeCrop(crop)
                    if (text.isBlank()) null else RecognizedLine(
                        text = text,
                        corners = box.corners.map { PointF(it.x, it.y) },
                        confidence = sqrt((box.score * recScore).coerceIn(0f, 1f)),
                    )
                } finally {
                    crop.recycle()
                }
            }.sortedWith(compareBy<RecognizedLine> { it.corners.map(PointF::y).average() }
                .thenBy { it.corners.map(PointF::x).average() })
        }
    }

    private fun ensureSessions() {
        if (detector != null && recognizer != null) return
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(2)
            setInterOpNumThreads(1)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
        }
        try {
            detector = appContext.assets.open("ocr/det.onnx").use { environment.createSession(it.readBytes(), options) }
            recognizer = appContext.assets.open("ocr/rec.onnx").use { environment.createSession(it.readBytes(), options) }
        } catch (failure: Throwable) {
            detector?.close(); detector = null
            recognizer?.close(); recognizer = null
            throw IllegalStateException("无法加载内置离线 OCR 模型", failure)
        } finally {
            options.close()
        }
    }

    private fun detect(source: Bitmap): List<Detection> {
        // RapidOCR PP-OCRv4 preprocessing: resize shortest edge to 736, round both axes to 32,
        // RGB/BGR channels normalized with mean=std=0.5. Clamp longest edge to keep tensors bounded.
        val shrink = min(1f, MAX_DETECT_SIDE.toFloat() / max(source.width, source.height))
        val boundedW = max(1, (source.width * shrink).toInt())
        val boundedH = max(1, (source.height * shrink).toInt())
        val shortest = min(boundedW, boundedH)
        val scale = if (shortest < DET_LIMIT) DET_LIMIT.toFloat() / shortest else 1f
        val requestedW = boundedW * scale
        val requestedH = boundedH * scale
        val capScale = min(1f, MAX_DETECT_SIDE / max(requestedW, requestedH))
        val w = alignedDimension((requestedW * capScale).toInt()).coerceAtMost(MAX_DETECT_SIDE)
        val h = alignedDimension((requestedH * capScale).toInt()).coerceAtMost(MAX_DETECT_SIDE)
        val resized = if (source.width == w && source.height == h) source else Bitmap.createScaledBitmap(source, w, h, true)
        val input = floatBuffer(w * h * 3)
        val pixels = IntArray(w * h)
        resized.getPixels(pixels, 0, w, 0, 0, w, h)
        for (channel in 0..2) for (pixel in pixels) {
            val component = when (channel) {
                0 -> pixel and 0xff        // BGR order used by the reference OpenCV pipeline
                1 -> (pixel ushr 8) and 0xff
                else -> (pixel ushr 16) and 0xff
            }
            input.put(component / 127.5f - 1f)
        }
        input.rewind()
        if (resized !== source) resized.recycle()

        val shape = longArrayOf(1, 3, h.toLong(), w.toLong())
        val tensor = OnnxTensor.createTensor(environment, input, shape)
        val result = try {
            detector!!.run(mapOf(detector!!.inputNames.first() to tensor))
        } finally { tensor.close() }
        result.use {
            val output = it[0].value as Array<Array<Array<FloatArray>>>
            val map = output[0][0]
            return postProcess(map, source.width, source.height)
        }
    }

    /** DB threshold map connected components; each component becomes an expanded text crop. */
    private fun postProcess(map: Array<FloatArray>, sourceW: Int, sourceH: Int): List<Detection> {
        val h = map.size
        val w = map.firstOrNull()?.size ?: return emptyList()
        if (h == 0 || w == 0) throw IllegalStateException("OCR 检测模型返回空概率图")
        require(w.toLong() * h <= MAX_MAP_PIXELS) {
            "OCR 检测图超过安全面积（${w}×${h}），请缩小课表裁剪区域后重试"
        }
        val count = w * h
        val visited = ByteArray(count)
        val queue = IntArray(count)
        val found = ArrayList<Detection>()
        for (start in 0 until count) {
            val sy = start / w; val sx = start - sy * w
            if (visited[start].toInt() != 0 || map[sy][sx] <= DB_THRESH) continue
            var head = 0; var tail = 0
            queue[tail++] = start; visited[start] = 1
            var left = sx; var right = sx; var top = sy; var bottom = sy
            var sum = 0.0; var area = 0
            while (head < tail) {
                val index = queue[head++]
                val y = index / w; val x = index - y * w
                val value = map[y][x]
                sum += value; area++
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                for (dy in -1..1) for (dx in -1..1) {
                    if (dx == 0 && dy == 0) continue
                    val nx = x + dx; val ny = y + dy
                    if (nx !in 0 until w || ny !in 0 until h) continue
                    val next = ny * w + nx
                    if (visited[next].toInt() == 0 && map[ny][nx] > DB_THRESH) {
                        visited[next] = 1
                        queue[tail++] = next
                    }
                }
            }
            val score = (sum / area).toFloat()
            if (area < MIN_COMPONENT_PIXELS || score < DB_BOX_THRESH) continue
            val bw = right - left + 1; val bh = bottom - top + 1
            if (min(bw, bh) < 2) continue
            // DB's polygon unclip ratio is 1.6. A bounded axis-aligned expansion gives useful
            // recognition margins while keeping this Android implementation independent of OpenCV.
            val expandX = max(2, (bw * 0.30f).toInt())
            val expandY = max(2, (bh * 0.30f).toInt())
            val x0 = ((left - expandX).coerceAtLeast(0) * sourceW.toFloat() / w).coerceIn(0f, sourceW.toFloat())
            val x1 = ((right + expandX + 1).coerceAtMost(w) * sourceW.toFloat() / w).coerceIn(0f, sourceW.toFloat())
            val y0 = ((top - expandY).coerceAtLeast(0) * sourceH.toFloat() / h).coerceIn(0f, sourceH.toFloat())
            val y1 = ((bottom + expandY + 1).coerceAtMost(h) * sourceH.toFloat() / h).coerceIn(0f, sourceH.toFloat())
            found += Detection(listOf(PointF(x0, y0), PointF(x1, y0), PointF(x1, y1), PointF(x0, y1)), score)
            if (found.size >= MAX_BOXES) break
        }
        return found.sortedWith(compareBy<Detection> { it.corners[0].y }.thenBy { it.corners[0].x })
    }

    private fun crop(source: Bitmap, box: Detection): Bitmap? {
        val x0 = box.corners[0].x.toInt().coerceIn(0, source.width - 1)
        val y0 = box.corners[0].y.toInt().coerceIn(0, source.height - 1)
        val x1 = box.corners[1].x.toInt().coerceIn(x0 + 1, source.width)
        val y1 = box.corners[2].y.toInt().coerceIn(y0 + 1, source.height)
        if ((x1 - x0) * (y1 - y0) < 16) return null
        return Bitmap.createBitmap(source, x0, y0, x1 - x0, y1 - y0)
    }

    private fun recognizeCrop(crop: Bitmap): Pair<String, Float> {
        val h = REC_HEIGHT
        val aspect = crop.width.toFloat() / crop.height
        val contentWidth = ceil(h * aspect).toInt().coerceIn(1, REC_MAX_WIDTH)
        val width = max(REC_BASE_WIDTH, contentWidth)
        val resized = Bitmap.createScaledBitmap(crop, contentWidth, h, true)
        val buffer = floatBuffer(3 * h * width)
        val pixels = IntArray(contentWidth * h)
        resized.getPixels(pixels, 0, contentWidth, 0, 0, contentWidth, h)
        // RapidOCR pads each normalized CHW row with zeros to at least 48*320.
        for (channel in 0..2) for (y in 0 until h) {
            val rowStart = y * contentWidth
            repeat(width) { x ->
                buffer.put(if (x < contentWidth) {
                    val p = pixels[rowStart + x]
                    val component = when (channel) { 0 -> p and 0xff; 1 -> (p ushr 8) and 0xff; else -> (p ushr 16) and 0xff }
                    component / 127.5f - 1f
                } else 0f)
            }
        }
        resized.recycle()
        buffer.rewind()
        val tensor = OnnxTensor.createTensor(environment, buffer, longArrayOf(1, 3, h.toLong(), width.toLong()))
        try {
            recognizer!!.run(mapOf(recognizer!!.inputNames.first() to tensor)).use { result ->
                val output = result[0] as OnnxTensor
                val classes = output.info.shape.last().toInt()
                val data = output.floatBuffer
                val timeSteps = data.remaining() / classes
                val dictionary = characters()
                require(dictionary.size == classes) { "OCR 字典与识别模型不匹配（${dictionary.size}/$classes）" }
                val text = StringBuilder()
                var previous = -1
                var score = 0.0
                var decoded = 0
                repeat(timeSteps) { t ->
                    var best = 0; var confidence = Float.NEGATIVE_INFINITY
                    val offset = t * classes
                    for (c in 0 until classes) {
                        val value = data.get(offset + c)
                        if (value > confidence) { confidence = value; best = c }
                    }
                    if (best != 0 && best != previous) {
                        text.append(dictionary[best])
                        score += confidence
                        decoded++
                    }
                    previous = best
                }
                return text.toString() to if (decoded == 0) 0f else (score / decoded).toFloat().coerceIn(0f, 1f)
            }
        } finally { tensor.close() }
    }

    @Volatile private var cachedCharacters: List<String>? = null
    private fun characters(): List<String> = cachedCharacters ?: synchronized(this) {
        cachedCharacters ?: appContext.assets.open("ocr/keys.txt").bufferedReader(Charsets.UTF_8).useLines { lines ->
            val dictionary = listOf("<blank>") + lines.toList() + " "
            cachedCharacters = dictionary
            dictionary
        }
    }

    override fun close() {
        closed = true
        detector?.close(); detector = null
        recognizer?.close(); recognizer = null
    }

    private fun floatBuffer(size: Int): FloatBuffer = ByteBuffer.allocateDirect(size * 4)
        .order(ByteOrder.nativeOrder()).asFloatBuffer()

    private fun alignedDimension(value: Int): Int = max(32, ((value + 16) / 32) * 32)

    private data class Detection(val corners: List<PointF>, val score: Float)

    private companion object {
        const val MAX_INPUT_SIDE = 4096
        const val MAX_INPUT_PIXELS = 12_000_000L
        const val MAX_DETECT_SIDE = 1536
        const val DET_LIMIT = 736
        const val MAX_MAP_PIXELS = 2_500_000L
        const val MAX_BOXES = 300
        const val MIN_COMPONENT_PIXELS = 3
        const val DB_THRESH = 0.30f
        const val DB_BOX_THRESH = 0.50f
        const val REC_HEIGHT = 48
        const val REC_BASE_WIDTH = 320
        const val REC_MAX_WIDTH = 1280
    }
}
