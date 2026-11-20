package com.pulsr.music

import android.util.Log
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

data class ServedFile(val path: String, val mime: String, @Volatile var timestampMs: Long)
data class ProxiedStream(val upstreamUrl: String, val mime: String, @Volatile var timestampMs: Long)

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
    private var workerPool: java.util.concurrent.ExecutorService? = null
    private val running = AtomicBoolean(false)

    private val servedFiles = java.util.concurrent.ConcurrentHashMap<String, ServedFile>()
    private val proxiedStreams = java.util.concurrent.ConcurrentHashMap<String, ProxiedStream>()
    private val prebufferCache = java.util.concurrent.ConcurrentHashMap<String, ByteArray>()
    @Volatile private var currentlyServingToken: String? = null
    @Volatile private var port: Int = 0

    val isRunning: Boolean get() = running.get()
    val boundPort: Int get() = port

    fun start(bindToLoopbackOnly: Boolean = false): Boolean {
        if (running.get()) return true
        return try {
            val ss = if (bindToLoopbackOnly) {
                ServerSocket(0, 50, java.net.InetAddress.getByName("127.0.0.1"))
            } else {
                ServerSocket(0)
            }
            serverSocket = ss
            port = ss.localPort
            workerPool = java.util.concurrent.Executors.newFixedThreadPool(4)
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
        try { workerPool?.shutdownNow() } catch (_: Exception) {}
        workerPool = null
        currentlyServingToken = null
        servedFiles.clear()
        proxiedStreams.clear()
        prebufferCache.clear()
    }

    /**
     * Returns true when [url] points at the local loopback interface (`127.0.0.1`,
     * `localhost`, or `[::1]`), which a LAN Cast receiver cannot reach directly.
     */
    fun isLoopbackUrl(url: String): Boolean {
        val uri = try { URI(url) } catch (_: Exception) { return false }
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme != "http" && scheme != "https") return false
        val host = uri.host?.lowercase()?.trim('[', ']') ?: return false
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /**
     * Bridges a loopback [upstreamUrl] (e.g. from `RemoteStreamServer`) onto the
     * LAN interface under `/proxy/<token>` so a Cast receiver can stream and seek it.
     * Rejects non-loopback URLs so the server never acts as an open LAN proxy.
     */
    fun serveProxyUrl(upstreamUrl: String, mime: String?): String? {
        if (!isLoopbackUrl(upstreamUrl)) return null
        if (!start()) return null

        val now = System.currentTimeMillis()
        val activeToken = currentlyServingToken
        val it = proxiedStreams.entries.iterator()
        while (it.hasNext()) {
            val entry = it.next()
            if (entry.key != activeToken && (now - entry.value.timestampMs > EVICTION_TTL_MS)) {
                it.remove()
            }
        }

        val resolvedMime = mime?.takeIf { it.isNotBlank() } ?: "audio/mpeg"
        val token = java.util.UUID.randomUUID().toString().replace("-", "").take(12)
        proxiedStreams[token] = ProxiedStream(upstreamUrl, resolvedMime, now)
        val host = localIpv4() ?: return null
        return "http://$host:$port/proxy/$token"
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
                var evictionLoopCount = 0
                while (prebufferCache.size >= maxPrebufferEntries && evictionLoopCount < 16) {
                    evictionLoopCount++
                    // Evict from prebufferCache's own oldest key to guarantee loop progress
                    val oldestKey = prebufferCache.keys().toList().minByOrNull { servedFiles[it]?.timestampMs ?: 0L }
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
            val pool = workerPool
            if (pool != null && !pool.isShutdown) {
                try {
                    pool.execute {
                        try {
                            handle(socket)
                        } catch (e: Exception) {
                            logW(TAG, "handle failed: ${e.message}")
                        } finally {
                            try { socket.close() } catch (_: Exception) {}
                        }
                    }
                } catch (_: Exception) {
                    try { socket.close() } catch (_: Exception) {}
                }
            } else {
                try {
                    handle(socket)
                } catch (e: Exception) {
                    logW(TAG, "handle failed: ${e.message}")
                } finally {
                    try { socket.close() } catch (_: Exception) {}
                }
            }
        }
    }

    private fun handle(socket: Socket) {
        val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
        val requestLine = input.readLine() ?: return
        val parts = requestLine.split(" ")
        if (parts.size < 2) return
        val method = parts[0].uppercase()
        if (method != "GET" && method != "HEAD") return

        var rangeHeader: String? = null
        var rangeStart = -1L
        var rangeEnd = -1L
        while (true) {
            val line = input.readLine() ?: break
            if (line.isEmpty()) break
            if (line.startsWith("Range:", ignoreCase = true)) {
                rangeHeader = line.substringAfter(":").trim()
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
        if (target.startsWith("/proxy/")) {
            val token = target.removePrefix("/proxy/").trimEnd('/')
            handleProxy(token, method, rangeHeader, out)
            return
        }

        val resolvedFile: File?
        val resolvedMime: String
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
                resolvedMime = "application/octet-stream"
            }
        } else {
            // No legacy /media fallback permitted: all requests must specify a valid, unexpired token
            resolvedFile = null
            resolvedMime = "application/octet-stream"
        }

        if (resolvedFile == null || !resolvedFile.exists()) {
            out.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".toByteArray())
            out.flush()
            return
        }

        val file = resolvedFile
        val length = file.length()
        val isRange = rangeHeader != null

        // Validate range if client supplied Range header
        if (isRange) {
            val invalidRange = (rangeStart >= length && length > 0) ||
                    (rangeStart < 0 && rangeEnd <= 0) ||
                    (rangeStart >= 0 && rangeEnd >= 0 && rangeStart > rangeEnd)
            if (invalidRange) {
                val header = "HTTP/1.1 416 Range Not Satisfiable\r\n" +
                        "Content-Range: bytes */$length\r\n" +
                        "Content-Length: 0\r\n" +
                        "Accept-Ranges: bytes\r\n" +
                        "Connection: close\r\n\r\n"
                out.write(header.toByteArray())
                out.flush()
                return
            }
        }

        val start: Long
        val end: Long
        if (rangeStart >= 0 && rangeStart < length) {
            start = rangeStart
            end = if (rangeEnd in start until length) rangeEnd else length - 1
        } else if (rangeStart < 0 && rangeEnd > 0) {
            // Suffix range: bytes=-N (last N bytes of file)
            val suffix = rangeEnd.coerceAtMost(length)
            start = (length - suffix).coerceAtLeast(0L)
            end = (length - 1).coerceAtLeast(0L)
        } else {
            start = 0
            end = (length - 1).coerceAtLeast(0L)
        }
        val contentLength = if (length == 0L) 0L else (end - start + 1).coerceAtLeast(0L)
        val statusLine = if (isRange) "206 Partial Content" else "200 OK"
        val header = buildString {
            append("HTTP/1.1 $statusLine\r\n")
            append("Content-Type: $resolvedMime\r\n")
            append("Accept-Ranges: bytes\r\n")
            if (isRange && length > 0) {
                append("Content-Range: bytes $start-$end/$length\r\n")
            }
            append("Content-Length: $contentLength\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(header.toByteArray())
        if (method == "HEAD" || contentLength == 0L) {
            out.flush()
            return
        }

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

    private fun handleProxy(
        token: String,
        method: String,
        rangeHeader: String?,
        out: BufferedOutputStream,
    ) {
        val proxied = proxiedStreams[token]
        if (proxied == null) {
            out.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".toByteArray())
            out.flush()
            return
        }
        proxied.timestampMs = System.currentTimeMillis()
        currentlyServingToken = token

        var conn: HttpURLConnection? = null
        try {
            conn = (URL(proxied.upstreamUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                instanceFollowRedirects = false
                connectTimeout = 5_000
                readTimeout = 20_000
                if (!rangeHeader.isNullOrBlank()) {
                    setRequestProperty("Range", rangeHeader)
                }
            }
            val code = conn.responseCode
            val statusLine = when (code) {
                200 -> "200 OK"
                206 -> "206 Partial Content"
                416 -> "416 Range Not Satisfiable"
                404 -> "404 Not Found"
                403 -> "403 Forbidden"
                else -> "$code ${conn.responseMessage ?: "Error"}"
            }
            val contentType = conn.contentType?.takeIf { it.isNotBlank() } ?: proxied.mime
            val contentLength = conn.contentLengthLong
            val contentRange = conn.getHeaderField("Content-Range")
            val acceptRanges = conn.getHeaderField("Accept-Ranges") ?: "bytes"

            val header = buildString {
                append("HTTP/1.1 $statusLine\r\n")
                append("Content-Type: $contentType\r\n")
                append("Accept-Ranges: $acceptRanges\r\n")
                if (!contentRange.isNullOrBlank()) {
                    append("Content-Range: $contentRange\r\n")
                }
                if (contentLength >= 0) {
                    append("Content-Length: $contentLength\r\n")
                }
                append("Connection: close\r\n\r\n")
            }
            out.write(header.toByteArray())
            if (method != "HEAD") {
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                if (stream != null) {
                    stream.use { input ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            out.write(buf, 0, n)
                        }
                    }
                }
            }
            out.flush()
        } catch (e: Exception) {
            logW(TAG, "proxy upstream failed: ${e.message}")
            try {
                out.write("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n".toByteArray())
                out.flush()
            } catch (_: Exception) {}
        } finally {
            conn?.disconnect()
        }
    }

    private fun localIpv4(): String? {
        return try {
            val ifaces = NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
            // Prefer Wi-Fi / Ethernet LAN interfaces over VPN/tun interfaces (Part 2)
            val sorted = ifaces.sortedByDescending { iface ->
                val name = iface.name.lowercase()
                when {
                    name.startsWith("wlan") || name.startsWith("wifi") -> 3
                    name.startsWith("eth") || name.startsWith("en") -> 2
                    name.startsWith("tun") || name.startsWith("tap") || name.startsWith("ppp") -> 0
                    else -> 1
                }
            }
            for (iface in sorted) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address && !addr.isLinkLocalAddress) {
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
