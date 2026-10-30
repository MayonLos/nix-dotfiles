package dev.mayon.timetable.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** Offline, bounded QR framing for transferring one timetable JSON document. */
object QrTransfer {
    const val MAX_CHUNK_BYTES = 600
    const val MAX_FRAMES = 128
    const val MAX_COMPRESSED_BYTES = MAX_CHUNK_BYTES * MAX_FRAMES
    const val MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024
    const val EXPIRY_MILLIS = 10 * 60 * 1000L
    private val random = SecureRandom()
    private val frameRegex = Regex("^mayon-tt:1:([0-9a-f]{32}):([1-9][0-9]{0,2})/([1-9][0-9]{0,2}):([0-9a-f]{64}):([A-Za-z0-9_-]+)$")

    /** Compress and frame UTF-8 JSON. transferId can be supplied to make fixtures deterministic. */
    fun encode(json: String, transferId: String = newTransferId()): List<String> {
        require(transferId.matches(Regex("[0-9a-f]{32}"))) { "transferId must be 128-bit lowercase hex" }
        val plain = json.toByteArray(Charsets.UTF_8)
        require(plain.size <= MAX_UNCOMPRESSED_BYTES) { "JSON exceeds 2 MiB limit" }
        val digest = sha256(plain)
        val compressed = ByteArrayOutputStream().also { output ->
            GZIPOutputStream(output).use { it.write(plain) }
        }.toByteArray()
        require(compressed.size <= MAX_COMPRESSED_BYTES) { "compressed JSON exceeds transfer limit" }
        val count = (compressed.size + MAX_CHUNK_BYTES - 1) / MAX_CHUNK_BYTES
        require(count in 1..MAX_FRAMES) { "transfer requires too many QR frames" }
        return (0 until count).map { index ->
            val start = index * MAX_CHUNK_BYTES
            val chunk = compressed.copyOfRange(start, minOf(start + MAX_CHUNK_BYTES, compressed.size))
            "mayon-tt:1:$transferId:${index + 1}/$count:$digest:${Base64Url.encode(chunk)}"
        }
    }

    fun newReceiver(clock: () -> Long = System::currentTimeMillis): QrTransferReceiver = QrTransferReceiver(clock)

    fun newTransferId(): String = ByteArray(16).also(random::nextBytes).joinToString("") {
        (it.toInt() and 0xff).toString(16).padStart(2, '0')
    }

    internal fun parseFrame(source: String): ParsedQrFrame {
        val match = frameRegex.matchEntire(source.trim()) ?: throw IllegalArgumentException("invalid timetable QR frame")
        val transferId = match.groupValues[1]
        val index = match.groupValues[2].toIntOrNull() ?: throw IllegalArgumentException("invalid frame index")
        val count = match.groupValues[3].toIntOrNull() ?: throw IllegalArgumentException("invalid frame count")
        require(count in 1..MAX_FRAMES && index in 1..count) { "frame index/count out of range" }
        val hash = match.groupValues[4]
        val encoded = match.groupValues[5]
        val chunk = Base64Url.decode(encoded)
        require(chunk.size in 1..MAX_CHUNK_BYTES) { "frame chunk exceeds 600 bytes" }
        require(Base64Url.encode(chunk) == encoded) { "non-canonical base64url frame" }
        return ParsedQrFrame(transferId, index, count, hash, chunk)
    }

    internal fun inflate(compressed: ByteArray): ByteArray {
        require(compressed.size <= MAX_COMPRESSED_BYTES) { "compressed transfer exceeds limit" }
        try {
            val out = ByteArrayOutputStream()
            GZIPInputStream(ByteArrayInputStream(compressed)).use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    require(out.size() + read <= MAX_UNCOMPRESSED_BYTES) { "decompressed JSON exceeds 2 MiB limit" }
                    out.write(buffer, 0, read)
                }
            }
            return out.toByteArray()
        } catch (e: IOException) {
            throw IllegalArgumentException("invalid GZIP transfer", e)
        }
    }

    internal fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
}

data class QrTransferProgress(
    val transferId: String,
    val receivedFrames: Int,
    val totalFrames: Int,
    /** Set only after all frames, gzip bounds, UTF-8, and full-document SHA-256 pass. */
    val resultJson: String? = null,
) {
    val complete: Boolean get() = resultJson != null
}

/** Stateful one-transfer receiver. Conflicts and mixed transfers are rejected without merging. */
class QrTransferReceiver internal constructor(private val clock: () -> Long) {
    private var transferId: String? = null
    private var frameCount: Int? = null
    private var expectedHash: String? = null
    private var startedAt: Long? = null
    private val chunks = mutableMapOf<Int, ByteArray>()
    private var result: String? = null

    @Synchronized
    fun accept(frame: String): QrTransferProgress {
        expireIfNeeded()
        val parsed = QrTransfer.parseFrame(frame)
        val active = transferId
        if (active != null) {
            require(parsed.transferId == active) { "frame belongs to a different transfer" }
            require(parsed.count == frameCount && parsed.sha256 == expectedHash) { "frame metadata conflicts with active transfer" }
        } else {
            transferId = parsed.transferId
            frameCount = parsed.count
            expectedHash = parsed.sha256
            startedAt = clock()
        }
        val existing = chunks[parsed.index]
        if (existing != null) require(existing.contentEquals(parsed.chunk)) { "conflicting duplicate frame" }
        else chunks[parsed.index] = parsed.chunk

        if (result == null && chunks.size == frameCount) {
            val compressedSize = chunks.values.sumOf { it.size }
            require(compressedSize in 1..QrTransfer.MAX_COMPRESSED_BYTES) { "compressed transfer size out of range" }
            val compressed = ByteArrayOutputStream(compressedSize).also { out ->
                for (i in 1..frameCount!!) out.write(chunks.getValue(i))
            }.toByteArray()
            val plain = QrTransfer.inflate(compressed)
            require(QrTransfer.sha256(plain) == expectedHash) { "transfer SHA-256 mismatch" }
            result = try {
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(plain)).toString()
            } catch (e: Exception) {
                throw IllegalArgumentException("transfer is not valid UTF-8", e)
            }
        }
        return QrTransferProgress(transferId!!, chunks.size, frameCount!!, result)
    }

    @Synchronized
    fun reset() {
        transferId = null; frameCount = null; expectedHash = null; startedAt = null
        chunks.clear(); result = null
    }

    private fun expireIfNeeded() {
        val start = startedAt ?: return
        if (clock() - start >= QrTransfer.EXPIRY_MILLIS) reset()
    }
}

internal data class ParsedQrFrame(val transferId: String, val index: Int, val count: Int, val sha256: String, val chunk: ByteArray)

private object Base64Url {
    private val encoder = java.util.Base64.getUrlEncoder().withoutPadding()
    private val decoder = java.util.Base64.getUrlDecoder()
    fun encode(bytes: ByteArray): String = encoder.encodeToString(bytes)
    fun decode(source: String): ByteArray = try { decoder.decode(source) } catch (e: IllegalArgumentException) {
        throw IllegalArgumentException("invalid base64url frame", e)
    }
}
