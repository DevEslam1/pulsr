package com.pulsr.music

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException
import java.io.InputStream

/**
 * Content URIs carry no filename, but jaudiotagger and MediaMetadataRetriever
 * choose a reader from the file extension. Copying every URI into "tag_*.tmp"
 * makes MP3/FLAC/etc. unreadable. Resolve the real extension from the
 * provider's display name, its MIME type, or the bytes themselves.
 */
object AudioTempFiles {
    private val MIME_TO_EXTENSION = mapOf(
        "audio/mpeg" to ".mp3",
        "audio/mp3" to ".mp3",
        "audio/mp4" to ".m4a",
        "audio/m4a" to ".m4a",
        "audio/x-m4a" to ".m4a",
        "audio/aac" to ".aac",
        "audio/flac" to ".flac",
        "audio/x-flac" to ".flac",
        "audio/ogg" to ".ogg",
        "audio/opus" to ".opus",
        "audio/x-wav" to ".wav",
        "audio/wav" to ".wav",
        "audio/wave" to ".wav",
        "audio/webm" to ".webm",
        "audio/x-ms-wma" to ".wma",
        "audio/x-aiff" to ".aiff",
        "audio/x-ape" to ".ape",
        "audio/x-dsf" to ".dsf",
        "audio/x-dff" to ".dff",
        "audio/3gpp" to ".3gp",
    )

    fun extensionFor(context: Context, uri: Uri): String {
        val fromName = runCatching { displayName(context, uri) }
            .getOrNull()
            ?.substringAfterLast('.', "")
            ?.lowercase()
            ?.filter { it in 'a'..'z' || it in '0'..'9' }
            ?.takeIf { it.length in 1..8 }
        if (fromName != null) return ".$fromName"

        val mime = runCatching { context.contentResolver.getType(uri) }
            .getOrNull()
            ?.substringBefore(';')
            ?.trim()
            ?.lowercase()
        if (mime != null) {
            MIME_TO_EXTENSION[mime]?.let { return it }
        }

        return sniffExtension(context, uri)
    }

    @Throws(IOException::class)
    fun copyToTempFile(
        context: Context,
        uri: Uri,
        prefix: String,
        maxBytes: Long = Long.MAX_VALUE,
    ): File {
        val suffix = extensionFor(context, uri).ifEmpty { ".tmp" }
        val temp = File.createTempFile(prefix, suffix, context.cacheDir)
        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IOException("Cannot open $uri")
            input.use { src ->
                temp.outputStream().use { out -> copyLimited(src, out, maxBytes) }
            }
        } catch (e: Exception) {
            runCatching { temp.delete() }
            throw if (e is IOException) e else IOException("Failed to copy $uri", e)
        }
        return temp
    }

    fun displayName(context: Context, uri: Uri): String? {
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return null
    }

    private fun sniffExtension(context: Context, uri: Uri): String {
        val header = ByteArray(12)
        val read = runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                var total = 0
                while (total < header.size) {
                    val n = input.read(header, total, header.size - total)
                    if (n <= 0) break
                    total += n
                }
                total
            } ?: 0
        }.getOrDefault(0)
        return extensionFromMagic(header, read)
    }

    /** Magic-byte sniffing, exposed for regression tests. */
    fun extensionFromMagic(h: ByteArray, len: Int = h.size): String {
        fun ascii(offset: Int, count: Int): String {
            if (len < offset + count) return ""
            return String(h, offset, count, Charsets.US_ASCII)
        }

        if (ascii(0, 4) == "fLaC") return ".flac"
        if (ascii(0, 4) == "OggS") return ".ogg"
        if (ascii(0, 4) == "RIFF" && ascii(8, 4) == "WAVE") return ".wav"
        if (ascii(0, 4) == "FORM" && (ascii(8, 4) == "AIFF" || ascii(8, 4) == "AIFC")) return ".aiff"
        if (ascii(4, 4) == "ftyp") return ".m4a"
        if (ascii(0, 4) == "DSD ") return ".dsf"
        if (ascii(0, 4) == "FRM8") return ".dff"
        if (ascii(0, 3) == "ID3") return ".mp3"
        if (len >= 2 && h[0] == 0xFF.toByte() &&
            (h[1].toInt() and 0xE0) == 0xE0 &&
            (h[1].toInt() and 0x06) != 0
        ) {
            return ".mp3"
        }
        return ""
    }

    private fun copyLimited(input: InputStream, out: java.io.OutputStream, maxBytes: Long) {
        val buffer = ByteArray(64 * 1024)
        var remaining = maxBytes
        while (remaining > 0) {
            val want = minOf(buffer.size.toLong(), remaining).toInt()
            val n = input.read(buffer, 0, want)
            if (n < 0) break
            out.write(buffer, 0, n)
            remaining -= n
        }
    }
}
