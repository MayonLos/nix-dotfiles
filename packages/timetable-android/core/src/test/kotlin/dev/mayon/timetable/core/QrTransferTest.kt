package dev.mayon.timetable.core

import org.junit.Assert.*
import org.junit.Test

class QrTransferTest {
    @Test fun roundTripsOneAndManyFramesOutOfOrder() {
        val documents = listOf("{\"format\":\"timetable\"}", noisyText(12_000))
        documents.forEachIndexed { i, json ->
            val frames = QrTransfer.encode(json, "%032x".format(i + 1))
            assertTrue(frames.size in 1..QrTransfer.MAX_FRAMES)
            val receiver = QrTransfer.newReceiver()
            var progress: QrTransferProgress? = null
            frames.reversed().forEach { progress = receiver.accept(it) }
            assertEquals(json, progress?.resultJson)
            assertTrue(progress!!.complete)
        }
    }

    @Test fun identicalDuplicateIsIdempotentAndConflictsAreRejected() {
        val frames = QrTransfer.encode(noisyText(20_000), "a".repeat(32))
        val receiver = QrTransfer.newReceiver()
        val first = frames.first()
        assertEquals(1, receiver.accept(first).receivedFrames)
        assertEquals(1, receiver.accept(first).receivedFrames)
        val parsed = QrTransfer.parseFrame(first)
        val altered = "mayon-tt:1:${parsed.transferId}:${parsed.index}/${parsed.count}:${parsed.sha256}:${
            java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(20) { 7 })}"
        try {
            receiver.accept(altered)
            fail("conflicting duplicate must fail")
        } catch (_: IllegalArgumentException) { }
        try {
            receiver.accept(QrTransfer.encode("other", "b".repeat(32)).single())
            fail("mixed transfer must fail")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun completedFramesMustMatchShaAndGzipAndUtf8Limits() {
        val valid = QrTransfer.encode("payload", "c".repeat(32)).single()
        val altered = valid.replace(Regex(":([0-9a-f]{64}):"), ":${"0".repeat(64)}:")
        try {
            QrTransfer.newReceiver().accept(altered)
            fail("hash mismatch must fail")
        } catch (_: IllegalArgumentException) { }

        val oversized = ByteArray(QrTransfer.MAX_UNCOMPRESSED_BYTES + 1) { 65 }
        val gzip = java.io.ByteArrayOutputStream().also { out ->
            java.util.zip.GZIPOutputStream(out).use { it.write(oversized) }
        }.toByteArray()
        try {
            QrTransfer.inflate(gzip)
            fail("decompression limit must fail")
        } catch (_: IllegalArgumentException) { }
    }

    @Test fun partialTransferExpiresAndCanStartAgain() {
        var now = 1000L
        val first = QrTransfer.encode(noisyText(40_000), "d".repeat(32))
        val other = QrTransfer.encode("new", "e".repeat(32)).single()
        val receiver = QrTransfer.newReceiver { now }
        receiver.accept(first.first())
        now += QrTransfer.EXPIRY_MILLIS
        assertEquals("new", receiver.accept(other).resultJson)
    }

    @Test fun rejectsMalformedAndOversizedFrames() {
        val valid = QrTransfer.encode("x", "f".repeat(32)).single()
        listOf("", "mayon-tt:1:bad", valid.replace(":1/1:", ":2/1:"), valid + "=").forEach { frame ->
            try { QrTransfer.parseFrame(frame); fail("expected invalid frame") } catch (_: IllegalArgumentException) { }
        }
        try {
            QrTransfer.encode("a".repeat(QrTransfer.MAX_UNCOMPRESSED_BYTES + 1))
            fail("oversized JSON must fail")
        } catch (_: IllegalArgumentException) { }
    }

    private fun noisyText(length: Int): String {
        val alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        val random = java.util.Random(20261030L + length)
        return buildString(length) { repeat(length) { append(alphabet[random.nextInt(alphabet.length)]) } }
    }
}
