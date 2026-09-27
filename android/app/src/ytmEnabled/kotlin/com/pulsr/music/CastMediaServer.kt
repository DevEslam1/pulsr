package com.pulsr.music

import android.util.Log
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

data class ServedFile(val path: String, val mime: String, @Volatile var timestampMs: Long)

/**
 * Minimal local HTTP server used to expose one local audio file to a Cast
 * receiver over the LAN. Cast receivers fetch media by URL, so `file://` paths
 * cannot be cast directly; this bridges a local file to an `http://` URL with
 * HTTP Range support (required for seeking).
 */
class CastMediaServer {
    companion object {
        private const val TAG = "CastMediaServer"
        private const val EVICTION_TTL_MS = 5 * 60 * 1000L

        private fun logD(tag: String, msg: String) {
            try {
                Log.d(tag, msg)
            } catch (_: Throwable) {
                println("[$tag] $msg")
            }
        }

        private fun logW(tag: String, msg: String) {
            try {
                Log.w(tag, msg)
            } catch (_: Throwable) {
                System.err.println("[$tag] $msg")
            }
        }
    }

    private var serverSocket: ServerSocket? = null
    private var thread: Thread? = null
    private val running = AtomicBoolean(false)

    private val servedFiles = java.util.concurrent.ConcurrentHashMap<String, ServedFile>()
    private val prebufferCache = java.util.concurrent.ConcurrentHashMap<String, ByteArray>()
    private data class LegacyMedia(val path: String, val mime: String)
    @Volatile private var legacyMedia: LegacyMedia? = null
    @Volatile private var currentlyServingToken: String? = null
    @Volatile private var port: Int = 0

    val isRunning: Boolean get() = running.get()

    fun start(): Boolean {
        if (running.get()) return true
        return try {
            val ss = ServerSocket(0)
            serverSocket = ss
            port = ss.localPort
            running.set(true)
            thread = Thread({ acceptLoop(ss) }, "PulsrCastServer").apply {
                isDaemon = true
                start()
            }
            true
        } catch (e: Exception) {
            logW(TAG, "start failed: ${e.message}")
            false
        }
    }

    fun stop() {
        running.set(false)
        try { serverSocket?.close() } catch (_: Exception) {}
        serverSocket = null
        thread = null
        legacyMedia = null
        currentlyServingToken = null
        servedFiles.clear()
        prebufferCache.clear()
    }

    /**
     * Serves [path] under `/media/<token>` (or fallback `/media`) and returns the LAN URL
     * a Cast receiver can fetch, or null when the file/server is unavailable.
     */
    fun serveFile(path: String, mime: String?): String? {
        val f = File(path)
        if (!f.exists() || !f.isFile) return null
        if (!start()) return null

        val now = System.currentTimeMillis()
        val activeToken = currentlyServingToken
        val it = servedFiles.entries.iterator()
        while (it.hasNext()) {
            val entry = it.next()
            // B-04: Never evict the currently active token
            if (entry.key != activeToken && (now - entry.value.timestampMs > EVICTION_TTL_MS)) {
                prebufferCache.remove(entry.key)
                it.remove()
            }
        }

        val resolvedMime = mime?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        val token = java.util.UUID.randomUUID().toString().replace("-", "").take(12)
        servedFiles[token] = ServedFile(f.absolutePath, resolvedMime, now)
        legacyMedia = LegacyMedia(f.absolutePath, resolvedMime)
        val host = localIpv4() ?: return null
        return "http://$host:$port/media/$token"
    }

    /**
     * Pre-buffers the beginning of [path] into memory and returns the Cast streaming URL.
     * Guarantees zero-latency immediate byte delivery on track change for gapless Cast playback.
     */
    fun preBufferFile(path: String, mime: String?): String? {
        val url = serveFile(path, mime) ?: return null
        val token = url.substringAfterLast("/")
        try {
            val f = File(path)
            if (f.exists() && f.isFile) {
                // Enforce max 4 prebuffer entries to prevent unbound native memory growth
                val maxPrebufferEntries = 4
                while (prebufferCache.size >= maxPrebufferEntries) {
                    val oldestKey = servedFiles.entries.minByOrNull { it.value.timestampMs }?.key
                        ?: prebufferCache.keys().toList().firstOrNull()
                    if (oldestKey != null) {
                        prebufferCache.remove(oldestKey)
                    } else {
                        break
                    }
                }
                val prebufSize = minOf(f.length(), 256 * 1024L).toInt()
                val bytes = ByteArray(prebufSize)
                f.inputStream().use { it.read(bytes, 0, prebufSize) }
                prebufferCache[token] = bytes
                logD(TAG, "Pre-buffered $prebufSize bytes for gapless Cast playback: $token")
            }
        } catch (e: Exception) {
            logW(TAG, "Pre-buffering failed non-fatally for $path: ${e.message}")
        }
        return url
    }

    private fun acceptLoop(ss: ServerSocket) {
        while (running.get()) {
            val socket = try {
                ss.accept()
            } catch (_: Exception) {
                if (running.get()) null else break
            } ?: continue
            try {
                handle(socket)
            } catch (e: Exception) {
                logW(TAG, "handle failed: ${e.message}")
            } finally {
                try { socket.close() } catch (_: Exception) {}
            }
        }
    }

    private fun handle(socket: Socket) {
        val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
        val requestLine = input.readLine() ?: return
        val parts = requestLine.split(" ")
        if (parts.size < 2 || parts[0] != "GET") return

        var rangeStart = -1L
        var rangeEnd = -1L
        while (true) {
            val line = input.readLine() ?: break
            if (line.isEmpty()) break
            if (line.startsWith("Range:", ignoreCase = true)) {
                val r = line.substringAfter("=").trim()
                val dash = r.indexOf('-')
                if (dash >= 0) {
                    rangeStart = r.substring(0, dash).toLongOrNull() ?: -1L
                    rangeEnd = r.substring(dash + 1).toLongOrNull() ?: -1L
                }
            }
        }

        val out = BufferedOutputStream(socket.getOutputStream())
        val target = parts[1].substringBefore("?")
        val resolvedFile: File?
        val resolvedMime: String
        val legacy = legacyMedia
        if (target.startsWith("/media/")) {
            val token = target.removePrefix("/media/").trimEnd('/')
            val served = servedFiles[token]
            if (served != null) {
                served.timestampMs = System.currentTimeMillis()
                currentlyServingToken = token
                resolvedFile = File(served.path)
                resolvedMime = served.mime
            } else {
                resolvedFile = null
                resolvedMime = legacy?.mime ?: "application/octet-stream"
            }
        } else if (target == "/media") {
            val path = legacy?.path
            resolvedFile = if (path != null) File(path) else null
            resolvedMime = legacy?.mime ?: "application/octet-stream"
        } else {
            resolvedFile = null
            resolvedMime = legacy?.mime ?: "application/octet-stream"
        }

        if (resolvedFile == null || !resolvedFile.exists()) {
            out.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".toByteArray())
            out.flush()
            return
        }

        val file = resolvedFile
        val length = file.length()
        val start: Long
        val end: Long
        if (rangeStart >= 0 && rangeStart < length) {
            start = rangeStart
            end = if (rangeEnd in start until length) rangeEnd else length - 1
        } else {
            start = 0
            end = length - 1
        }
        val contentLength = end - start + 1
        val header = buildString {
            append("HTTP/1.1 206 Partial Content\r\n")
            append("Content-Type: $resolvedMime\r\n")
            append("Accept-Ranges: bytes\r\n")
            append("Content-Range: bytes $start-$end/$length\r\n")
            append("Content-Length: $contentLength\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(header.toByteArray())

        val token = if (target.startsWith("/media/")) target.removePrefix("/media/").trimEnd('/') else null
        val prebuf = if (start == 0L && token != null) prebufferCache[token] else null

        file.inputStream().use { fis ->
            var remaining = contentLength
            if (prebuf != null && prebuf.isNotEmpty()) {
                val prebufToSend = minOf(prebuf.size.toLong(), remaining).toInt()
                out.write(prebuf, 0, prebufToSend)
                remaining -= prebufToSend
                var toSkipInFis = prebufToSend.toLong()
                while (toSkipInFis > 0) {
                    val s = fis.skip(toSkipInFis)
                    if (s <= 0) break
                    toSkipInFis -= s
                }
            } else {
                var skipped = 0L
                while (skipped < start) {
                    val s = fis.skip(start - skipped)
                    if (s <= 0) break
                    skipped += s
                }
            }
            val buf = ByteArray(64 * 1024)
            while (remaining > 0) {
                val toRead = minOf(buf.size.toLong(), remaining).toInt()
                val n = fis.read(buf, 0, toRead)
                if (n <= 0) break
                out.write(buf, 0, n)
                remaining -= n
            }
        }
        out.flush()
    }

    private fun localIpv4(): String? {
        return try {
            val ifaces = NetworkInterface.getNetworkInterfaces()
            while (ifaces.hasMoreElements()) {
                val iface = ifaces.nextElement()
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return addr.hostAddress
                    }
                }
            }
            "127.0.0.1"
        } catch (_: Exception) {
            "127.0.0.1"
        }
    }
}
