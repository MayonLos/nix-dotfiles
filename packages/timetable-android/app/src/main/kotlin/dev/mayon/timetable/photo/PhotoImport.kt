package dev.mayon.timetable.photo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PointF

/** Four user-corrected corners in clockwise TL, TR, BR, BL order after EXIF orientation. */
data class CropQuad(val corners: List<PointF>) {
    init {
        require(corners.size == 4)
        require(corners.all { it.x.isFinite() && it.y.isFinite() })
        val crosses = corners.indices.map { i ->
            val a = corners[i]; val b = corners[(i + 1) % 4]; val c = corners[(i + 2) % 4]
            (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        }
        require(crosses.all { it > 1f } || crosses.all { it < -1f }) { "裁剪框必须为非退化凸四边形" }
    }
}

/** Four-point perspective correction. Caller decodes with sampling and applies EXIF first. */
fun rectify(source: Bitmap, quad: CropQuad, width: Int, height: Int): Bitmap {
    require(width in 64..2400 && height in 64..2400)
    require(quad.corners.all { it.x in 0f..source.width.toFloat() && it.y in 0f..source.height.toFloat() })
    val src = quad.corners.flatMap { listOf(it.x, it.y) }.toFloatArray()
    val dst = floatArrayOf(0f, 0f, width.toFloat(), 0f, width.toFloat(), height.toFloat(), 0f, height.toFloat())
    val matrix = Matrix()
    require(matrix.setPolyToPoly(src, 0, dst, 0, 4)) { "无法校正此裁剪框" }
    return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
        Canvas(it).apply { drawColor(android.graphics.Color.WHITE); drawBitmap(source, matrix, Paint(Paint.FILTER_BITMAP_FLAG)) }
    }
}

data class RecognizedLine(val text: String, val corners: List<PointF>, val confidence: Float)
interface OfflineOcrEngine : AutoCloseable {
    /** Models are bundled; no download, telemetry or network. Caller dispatches off main thread. */
    suspend fun recognize(rectifiedImage: Bitmap): List<RecognizedLine>
}

/** Network implementation intentionally absent. Future consent must bind image hash + endpoint. */
data class UploadConsent(val imageSha256: String, val endpoint: String, val expiresAtEpochMillis: Long)
interface OptionalPhotoFallback {
    val enabled: Boolean
    suspend fun recognize(imageBytes: ByteArray, consent: UploadConsent): List<RecognizedLine>
}
