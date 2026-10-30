package dev.mayon.timetable

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import dev.mayon.timetable.core.PeriodTime
import dev.mayon.timetable.core.Semester
import dev.mayon.timetable.core.TimetableV1
import dev.mayon.timetable.data.TimetableStore
import dev.mayon.timetable.photo.PaddleOcrEngine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlinx.coroutines.runBlocking

/** Device end-to-end check: test-APK image -> app FileProvider ACTION_SEND -> real bundled OCR -> review -> store. */
@RunWith(AndroidJUnit4::class)
class PhotoFlowTest {
    @get:Rule val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun actionSendRunsOfflineOcrAndSavesReviewedCourse() {
        val target = ApplicationProvider.getApplicationContext<Context>()
        for (theme in listOf(1, 0)) {
        val semesterId = "photo-e2e-20261030"
        val semester = Semester(
            id = semesterId,
            name = "OCR 仪器测试学期",
            startDate = "2026-10-26",
            totalWeeks = 16,
            timeZone = "Asia/Shanghai",
            timeSlots = listOf(
                PeriodTime(1, "08:00", "08:45"), PeriodTime(2, "09:00", "09:45"),
                PeriodTime(3, "10:00", "10:45"), PeriodTime(4, "10:55", "11:40"),
                PeriodTime(5, "13:30", "14:15"), PeriodTime(6, "14:25", "15:10"),
                PeriodTime(7, "15:20", "16:05"), PeriodTime(8, "16:15", "17:00"),
            ),
        )
        val store = TimetableStore(target)
        store.save(TimetableV1(semester = semester, courses = emptyList()).requireValid(), replace = true)
        store.activeId = semesterId
        check(target.getSharedPreferences("device", Context.MODE_PRIVATE).edit()
            .putBoolean("onboardingDone", true).putInt("theme", theme).commit())

        // Recreate after seeding so the normal first composition observes the test semester and
        // onboarding preference. This tests persisted input, not an in-memory app shortcut.
        composeRule.activityRule.scenario.recreate()

        composeRule.waitUntil(10_000) {
            composeRule.onAllNodesWithTag("settings").fetchSemanticsNodes().isNotEmpty()
        }
        val photoDirectory = File(target.cacheDir, "photo-import").apply { mkdirs() }
        val photoFile = File(photoDirectory, "synthetic-photo.png")
        InstrumentationRegistry.getInstrumentation().context.assets.open("synthetic-photo.png").use { input ->
            photoFile.outputStream().use { output -> input.copyTo(output) }
        }
        val photoUri = FileProvider.getUriForFile(target, "${target.packageName}.photos", photoFile)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            setClass(target, MainActivity::class.java)
            putExtra(Intent.EXTRA_STREAM, photoUri)
            clipData = ClipData.newUri(target.contentResolver, "synthetic timetable", photoUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        composeRule.activityRule.scenario.onActivity { it.startActivity(send) }

        composeRule.waitUntil(30_000) {
            composeRule.onAllNodesWithTag("photo-crop-image").fetchSemanticsNodes().isNotEmpty()
        }
        saveScreenshot(target, theme, "photo-crop")
        composeRule.onNodeWithTag("photo-recognize").performClick()
        // Loading two ONNX sessions on a cold app can be slow on the emulator CPU.
        composeRule.waitUntil(90_000) {
            composeRule.onAllNodesWithTag("photo-review-back").fetchSemanticsNodes().isNotEmpty()
        }

        saveScreenshot(target, theme, "photo-review")
        // This field value must come from the real detector and recognizer; no OCR result is seeded.
        composeRule.onNodeWithTag("photo-course-0").assertTextContains("高等数学")
        composeRule.onNodeWithTag("photo-weeks-0").performScrollTo()
        composeRule.onNodeWithTag("photo-weeks-0").performScrollTo().performTextClearance()
        composeRule.onNodeWithTag("photo-weeks-0").performTextInput("2-16周(双)")
        composeRule.onNodeWithTag("photo-confirm-0").performScrollTo()
        composeRule.onNodeWithTag("photo-confirm-0").performScrollTo().performClick()
        composeRule.onNodeWithTag("photo-save").performClick()

        composeRule.waitUntil(30_000) {
            runCatching { store.read(semesterId).courses.any { it.name == "高等数学" } }.getOrDefault(false)
        }
        val saved = store.read(semesterId).courses.single { it.name == "高等数学" }
        assertEquals(3, saved.weekday)
        assertEquals(2, saved.periodStart)
        assertEquals(2, saved.periodEnd)
        assertEquals(setOf(2, 4, 6, 8, 10, 12, 14, 16), saved.weeks)
        assertEquals("王老师", saved.teacher)
        assertEquals("A203", saved.classroom)
        assertTrue(saved.notes?.contains("照片导入") == true)
        }
    }

    @Test
    fun detectorAcceptsCommon2200PixelAspectRatiosWithinAreaLimit() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fixture = InstrumentationRegistry.getInstrumentation().context.assets.open("synthetic-photo.png").use {
            BitmapFactory.decodeStream(it) ?: error("synthetic-photo.png did not decode")
        }
        try {
            PaddleOcrEngine(context).use { engine ->
                for ((width, height) in listOf(2200 to 1650, 2200 to 2200)) {
                    val canvasBitmap = centerOnWhiteCanvas(fixture, width, height)
                    try {
                        val lines = runBlocking { engine.recognize(canvasBitmap) }
                        File(context.filesDir, "synthetic-ocr-lines-$width-$height.txt").writeText(lines.joinToString("\n") { it.text })
                        assertTrue(
                            "$width×$height produced no real OCR line for 高等数学",
                            lines.any { "高等数学" in it.text },
                        )
                    } finally {
                        canvasBitmap.recycle()
                    }
                }
            }
        } finally {
            fixture.recycle()
        }
    }

    private fun saveScreenshot(context: Context, theme: Int, name: String) {
        composeRule.waitForIdle()
        Thread.sleep(600)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val round = InstrumentationRegistry.getArguments().getString("round", "round1")
        val directory = File(context.getExternalFilesDir(null), "proof").apply { mkdirs() }
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        File(directory, "$round-${if (theme == 1) "dark" else "light"}-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    private fun centerOnWhiteCanvas(source: Bitmap, width: Int, height: Int): Bitmap {
        val result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val scale = minOf(width.toFloat() / source.width, height.toFloat() / source.height)
        val drawnWidth = source.width * scale
        val drawnHeight = source.height * scale
        val left = (width - drawnWidth) / 2f
        val top = (height - drawnHeight) / 2f
        Canvas(result).apply {
            drawColor(Color.WHITE)
            drawBitmap(source, null, RectF(left, top, left + drawnWidth, top + drawnHeight), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        return result
    }
}
