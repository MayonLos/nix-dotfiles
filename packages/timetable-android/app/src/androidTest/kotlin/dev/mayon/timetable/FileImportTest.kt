package dev.mayon.timetable

import android.content.Intent
import android.content.ClipData
import android.content.Context
import android.graphics.Bitmap
import androidx.core.content.FileProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import dev.mayon.timetable.core.*
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.qr.decodeQr
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FileImportTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    @Test fun wakeupFileOpensThroughNormalViewIntentAndNeedsConfirmation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val target = instrumentation.targetContext
        target.getSharedPreferences("device", 0).edit().putBoolean("onboardingDone", true).commit()
        rule.activityRule.scenario.recreate()
        val lines = instrumentation.context.assets.open("synthetic.wakeup_schedule").bufferedReader().use { it.readLines() }.toMutableList()
        val id = (System.currentTimeMillis() % 1_000_000_000).toString()
        lines[2] = lines[2].replace(Regex("\"id\":\\s*[-0-9]+"), "\"id\":$id")
        val directory = File(target.cacheDir, "photo-import").apply { mkdirs() }
        val source = File(directory, "wakeup-test.wakeup_schedule").apply { writeText(lines.joinToString("\n")) }
        val uri = FileProvider.getUriForFile(target, "${target.packageName}.photos", source)
        rule.activityRule.scenario.onActivity { activity ->
            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/octet-stream"); setClass(target, MainActivity::class.java)
                clipData = ClipData.newUri(target.contentResolver, "synthetic backup", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            })
        }
        rule.waitUntil(20_000) { rule.onAllNodesWithTag("confirm-import").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("confirm-import").performClick()
        val store = TimetableStore(target)
        rule.waitUntil(20_000) { runCatching { store.active()?.semester?.id == id }.getOrDefault(false) }
        assertEquals(2, store.read(id).courses.size)
        assertTrue(store.read(id).courses.all { it.name == "测试物理" })
        val json = TimetableJson.encode(store.read(id))
        assertEquals(store.read(id), TimetableJson.decode(json))
        assertEquals(store.read(id), IcsCodec.import(IcsCodec.export(store.read(id)), store.read(id).semester))
    }

    @Test fun realQrBitmapsDecodeAndReassembleOffline() {
        val json = "{\"synthetic\":\"" + (1..100).joinToString(",") + "\"}"
        val receiver = QrTransfer.newReceiver()
        var restored: String? = null
        for (frame in QrTransfer.encode(json)) {
            val matrix = QRCodeWriter().encode(frame, BarcodeFormat.QR_CODE, 768, 768)
            val pixels = IntArray(matrix.width * matrix.height) { i -> if (matrix[i % matrix.width, i / matrix.width]) 0xff000000.toInt() else -1 }
            val image = Bitmap.createBitmap(pixels, matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
            val decoded = decodeQr(image); image.recycle()
            assertNotNull(decoded)
            restored = receiver.accept(decoded!!).resultJson
        }
        assertEquals(json, restored)
    }
}
