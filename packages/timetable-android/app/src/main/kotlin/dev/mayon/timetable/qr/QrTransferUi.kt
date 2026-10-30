package dev.mayon.timetable.qr

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import dev.mayon.timetable.core.QrTransfer

/** Shows the transfer as swipeable QR frames. A receiver scans each frame once. */
@Composable
fun QrShareScreen(json: String, onBack: () -> Unit) {
    val frames = remember(json) { runCatching { QrTransfer.encode(json) }.getOrElse { emptyList() } }
    val pager = rememberPagerState(pageCount = { frames.size.coerceAtLeast(1) })
    Column(
        Modifier.fillMaxSize().padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("二维码互传", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(10.dp))
        when {
            frames.isEmpty() -> Text("课表超过二维码传输上限（解压后最多 2 MiB）。请改用文件导出。", color = MaterialTheme.colorScheme.error)
            else -> {
                Text("逐帧扫描 · 离线传输", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(16.dp))
                HorizontalPager(state = pager, modifier = Modifier.fillMaxWidth(), key = { it }) { page ->
                    val bitmap = remember(frames[page]) { encodeQr(frames[page], 720) }
                    Image(bitmap.asImageBitmap(), contentDescription = "传输二维码，第 ${page + 1} 帧", modifier = Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(12.dp))
                Text("第 ${pager.currentPage + 1} / ${frames.size} 帧", style = MaterialTheme.typography.titleMedium)
                Text("请在接收设备依次扫描全部帧；二维码内容不加密。", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall)
                Text("左右滑动切换二维码帧", style = MaterialTheme.typography.labelMedium)
            }
        }
        Spacer(Modifier.height(20.dp))
        Button(onClick = onBack) { Text("返回") }
    }
}

/** Decode one QR code from a user-selected bitmap without camera, GMS, or network access. */
fun decodeQr(bitmap: Bitmap): String? = runCatching {
    require(bitmap.width > 0 && bitmap.height > 0 && bitmap.width.toLong() * bitmap.height <= 20_000_000L)
    val pixels = IntArray(bitmap.width * bitmap.height)
    bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    val source = RGBLuminanceSource(bitmap.width, bitmap.height, pixels)
    val binary = BinaryBitmap(HybridBinarizer(source))
    MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true))
    }.decodeWithState(binary).text
}.getOrNull()

private fun encodeQr(value: String, size: Int): Bitmap {
    val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, size, size)
    val colors = IntArray(size * size) { index ->
        val x = index % size; val y = index / size
        if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE
    }
    return Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).apply { setPixels(colors, 0, size, 0, 0, size, size) }
}
