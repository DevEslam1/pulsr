package com.pulsr.music

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msdtyp.FileTime
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.msfscc.fileinformation.FileIdBothDirectoryInformation
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.EnumSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * SMB2/3 bridge for the "remote sources" feature (`com.pulsr.music/smb`).
 *
 * Methods: `probe`, `list`, `stat`, `openReadChunk`, `close`.
 *
 * Path contract with `SmbFsProvider` (Dart):
 *  - `basePath` is the share-relative root of the source ("" or "Music").
 *  - `path` is *also* share-relative ("" or "Albums/a.mp3") and must never
 *    include `basePath`; this side performs the single join in [joinPath].
 *  - Replies carry native paths that include `basePath`; Dart strips it.
 * Prepending the base on both sides resolves every request to
 * "Music/Music/...", so the Dart tests assert the joined result explicitly.
 *
 * Design notes:
 *  - Every SMB call runs on one dedicated executor, because smbj objects are not
 *    safe for concurrent use from several threads and NTLM re-authentication is
 *    chatty. Channel replies are posted back to the main looper.
 *  - Sessions are cached per `host:port/share/user` *and a digest of the
 *    password*, so editing a password never reuses an authenticated session
 *    opened with the old one. The digest is never logged.
 *  - Credentials are never logged. Only host, port and share appear in logs.
 *  - `openReadChunk` opens, reads and closes the file per call: simple and
 *    leak-free, at the cost of one extra round-trip per chunk.
 *  - Connect/login timeouts come from [SmbConfig]; smbj 0.13 exposes no
 *    per-call connect timeout, and an unbounded connect would pin the single
 *    executor thread (and therefore every later call) indefinitely.
 *
 * The `com.hierynomus:smbj` Gradle dependency is added by the app wiring; without
 * it the class fails to load and `register()` must not be called.
 */
class SmbPlugin internal constructor() : MethodChannel.MethodCallHandler {

    private class SessionHolder(
        val key: String,
        val client: SMBClient,
        val connection: Connection,
        val session: Session,
        val share: DiskShare,
    )

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "PulsrSmb").apply { isDaemon = true }
        }
    private val sessions = ConcurrentHashMap<String, SessionHolder>()
    private val closed = AtomicBoolean(false)
    internal var clientFactory: (SmbConfig) -> SMBClient = { config -> SMBClient(config) }

    internal fun cachedSessionCount(): Int = sessions.size

    companion object {
        private const val TAG = "SmbPlugin"
        const val CHANNEL_NAME = "com.pulsr.music/smb"
        private const val DEFAULT_PORT = 445
        private const val MAX_CHUNK_BYTES = 4 * 1024 * 1024
        private const val CONNECT_TIMEOUT_MS = 15_000L

        /**
         * Registers the channel on [engine]. Safe to call once per engine; the
         * returned instance must be cleaned up with [cleanup] when the engine is
         * destroyed.
         */
        fun register(engine: FlutterEngine): SmbPlugin {
            val plugin = SmbPlugin()
            val methodChannel =
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = methodChannel
            methodChannel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGUMENT", "Missing arguments.", null)
            return
        }
        if (closed.get()) {
            result.error("UNAVAILABLE", "The SMB plugin is shutting down.", null)
            return
        }
        val method = call.method
        executor.execute {
            try {
                when (method) {
                    "probe" -> postSuccess(result, probe(args))
                    "list" -> postSuccess(result, list(args))
                    "stat" -> postSuccess(result, stat(args))
                    "openReadChunk" -> postSuccess(result, openReadChunk(args))
                    "close" -> postSuccess(result, closeSession(args))
                    else -> mainHandler.post { result.notImplemented() }
                }
            } catch (error: Throwable) {
                postError(result, method, error)
            }
        }
    }

    /** Closes every cached session and stops the executor. */
    fun cleanup() {
        if (!closed.compareAndSet(false, true)) return
        channel?.setMethodCallHandler(null)
        channel = null
        try {
            executor.execute {
                sessions.keys.toList().forEach { key ->
                    sessions.remove(key)?.let { closeQuietly(it) }
                }
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "SMB cleanup could not be queued: ${error.message}")
        }
        executor.shutdown()
    }

    private fun probe(args: Map<*, *>): Boolean {
        val basePath = normalizeBasePath(args["basePath"] as? String)
        val share = shareFor(args)
        if (basePath.isNotEmpty()) {
            val exists = share.folderExists(basePath) || share.fileExists(basePath)
            if (!exists) {
                throw IllegalArgumentException("STATUS_OBJECT_NAME_NOT_FOUND $basePath")
            }
        }
        return true
    }

    private fun list(args: Map<*, *>): List<Map<String, Any?>> {
        val basePath = normalizeBasePath(args["basePath"] as? String)
        val path = joinPath(basePath, args["path"] as? String)
        val share = shareFor(args)
        val output = ArrayList<Map<String, Any?>>()
        val children: List<FileIdBothDirectoryInformation> = share.list(path)
        for (child in children) {
            val name = child.fileName ?: continue
            if (name == "." || name == "..") continue
            val isDirectory = isDirectory(child.fileAttributes)
            val entryPath = joinPath(path, name)
            output.add(
                mapOf(
                    "path" to entryPath,
                    "name" to name,
                    "isDirectory" to isDirectory,
                    "sizeBytes" to if (isDirectory) null else child.endOfFile,
                    "modifiedAt" to epochMillis(child.lastWriteTime),
                    "etag" to null,
                )
            )
        }
        return output
    }

    private fun stat(args: Map<*, *>): Map<String, Any?>? {
        val basePath = normalizeBasePath(args["basePath"] as? String)
        val path = joinPath(basePath, args["path"] as? String)
        val share = shareFor(args)
        if (path.isEmpty()) {
            return mapOf(
                "path" to "",
                "name" to shareNameOf(args),
                "isDirectory" to true,
                "sizeBytes" to null,
                "modifiedAt" to null,
                "etag" to null,
            )
        }
        val info = try {
            share.getFileInformation(path)
        } catch (error: SMBApiException) {
            if (isNotFound(error)) return null
            throw error
        }
        val attributes = info.basicInformation?.fileAttributes ?: 0L
        val size = info.standardInformation?.endOfFile
        return mapOf(
            "path" to path,
            "name" to path.substringAfterLast('/').substringAfterLast('\\'),
            "isDirectory" to isDirectory(attributes),
            "sizeBytes" to size,
            "modifiedAt" to epochMillis(info.basicInformation?.lastWriteTime),
            "etag" to null,
        )
    }

    internal fun openReadChunk(args: Map<*, *>): ByteArray {
        val basePath = normalizeBasePath(args["basePath"] as? String)
        val path = joinPath(basePath, args["path"] as? String)
        val offset = (args["offset"] as? Number)?.toLong() ?: 0L
        val length = (args["length"] as? Number)?.toInt() ?: 0
        if (offset < 0) throw IllegalArgumentException("offset must be >= 0")
        if (length <= 0) return ByteArray(0)
        val safeLength = minOf(length, MAX_CHUNK_BYTES)
        val share = shareFor(args)
        val buffer = ByteArray(safeLength)
        var totalRead = 0
        share.openFile(
            path,
            EnumSet.of(AccessMask.GENERIC_READ),
            null,
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OPEN,
            null,
        ).use { file ->
            while (totalRead < safeLength) {
                val read = file.read(
                    buffer,
                    offset + totalRead,
                    totalRead,
                    safeLength - totalRead,
                )
                if (read <= 0) break
                totalRead += read
            }
        }
        if (totalRead <= 0) return ByteArray(0)
        return if (totalRead == safeLength) buffer else buffer.copyOf(totalRead)
    }

    private fun closeSession(args: Map<*, *>): Boolean {
        val host = (args["host"] as? String)?.lowercase() ?: return false
        val port = (args["port"] as? Number)?.toInt() ?: DEFAULT_PORT
        val shareName = args["share"] as? String ?: return false
        val prefix = "$host:$port/$shareName/"
        val keys = sessions.keys.filter { it.startsWith(prefix) }
        keys.forEach { key -> sessions.remove(key)?.let { closeQuietly(it) } }
        return true
    }

    internal fun shareFor(args: Map<*, *>): DiskShare {
        val host = args["host"] as? String
        if (host.isNullOrBlank()) throw IllegalArgumentException("host is required")
        val port = (args["port"] as? Number)?.toInt() ?: DEFAULT_PORT
        val shareName = args["share"] as? String
        if (shareName.isNullOrBlank()) {
            throw IllegalArgumentException("share is required (set root to /<share>)")
        }
        val username = (args["username"] as? String).orEmpty()
        val password = (args["password"] as? String).orEmpty()
        val domain = (args["domain"] as? String).orEmpty()
        val userKey = if (domain.isEmpty()) username else "$domain\\$username"
        // The password digest is part of the key: a session authenticated with
        // an old secret must never be reused after the user changed it.
        val keyPrefix = "${host.lowercase()}:$port/$shareName/$userKey#"
        val key = keyPrefix + secretDigest(domain, username, password)
        val cached = sessions[key]
        if (cached != null) {
            if (cached.connection.isConnected) return cached.share
            sessions.remove(key)
            closeQuietly(cached)
        }
        Log.d(TAG, "Opening SMB session to $host:$port/$shareName")
        val client = clientFactory(
            SmbConfig.builder()
                .withTimeout(CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                .withSoTimeout(CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                .build()
        )
        try {
            val connection = client.connect(host, port)
            val authentication = AuthenticationContext(
                username,
                password.toCharArray(),
                if (domain.isEmpty()) null else domain,
            )
            val session = connection.authenticate(authentication)
            val share = session.connectShare(shareName) as? DiskShare
                ?: throw IllegalArgumentException("Share is not a disk share")
            val staleKeys = sessions.keys.filter { it.startsWith(keyPrefix) }
            staleKeys.forEach { staleKey ->
                sessions.remove(staleKey)?.let { closeQuietly(it) }
            }
            sessions[key] = SessionHolder(key, client, connection, session, share)
            return share
        } catch (error: Throwable) {
            // Drop the half-open connection so the next attempt starts clean.
            try {
                client.close()
            } catch (closeError: Exception) {
                Log.w(TAG, "SMB client did not close: ${closeError.message}")
            }
            throw error
        }
    }

    private fun closeQuietly(holder: SessionHolder) {
        try {
            holder.share.close()
        } catch (error: Exception) {
            Log.w(TAG, "SMB share did not close: ${error.message}")
        }
        try {
            holder.session.close()
        } catch (error: Exception) {
            Log.w(TAG, "SMB session did not close: ${error.message}")
        }
        try {
            holder.connection.close()
        } catch (error: Exception) {
            Log.w(TAG, "SMB connection did not close: ${error.message}")
        }
        try {
            holder.client.close()
        } catch (error: Exception) {
            Log.w(TAG, "SMB client did not close: ${error.message}")
        }
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post {
            try {
                result.success(value)
            } catch (error: IllegalStateException) {
                Log.w(TAG, "SMB reply was dropped: ${error.message}")
            }
        }
    }

    private fun postError(
        result: MethodChannel.Result,
        method: String,
        error: Throwable,
    ) {
        val code = errorCode(error)
        val message = error.message ?: error.javaClass.simpleName
        Log.w(TAG, "SMB $method failed with $code: $message")
        mainHandler.post {
            try {
                result.error(code, message, null)
            } catch (stateError: IllegalStateException) {
                Log.w(TAG, "SMB error reply was dropped: ${stateError.message}")
            }
        }
    }

    /**
     * Maps a failure to the small vocabulary the Dart provider understands.
     *
     * smbj surfaces protocol failures as [SMBApiException] whose message starts
     * with the status name, so the classification is message-based on purpose:
     * it keeps this file compiling against several smbj minor versions without
     * pinning a status-enum type.
     */
    private fun errorCode(error: Throwable): String {
        if (error is LinkageError) {
            return "UNSUPPORTED"
        }
        if (error is SMBApiException) {
            val text = (error.message ?: "").uppercase()
            return when {
                text.contains("LOGON_FAILURE") ||
                    text.contains("ACCESS_DENIED") ||
                    text.contains("ACCOUNT_RESTRICTION") ||
                    text.contains("PASSWORD") -> "AUTH"
                isNotFound(error) -> "NOT_FOUND"
                text.contains("TIMEOUT") ||
                    text.contains("DISCONNECTED") ||
                    text.contains("NETWORK_NAME_DELETED") ||
                    text.contains("CONNECTION") -> "UNAVAILABLE"
                else -> "PROTOCOL"
            }
        }
        if (error is IllegalArgumentException) {
            return if ((error.message ?: "").contains("NOT_FOUND")) "NOT_FOUND"
            else "INVALID_ARGUMENT"
        }
        val text = (error.message ?: "").uppercase()
        if (text.contains("TIMEOUT") ||
            text.contains("UNREACHABLE") ||
            text.contains("CONNECT") ||
            text.contains("SOCKET")
        ) {
            return "UNAVAILABLE"
        }
        return "PROTOCOL"
    }

    private fun isNotFound(error: SMBApiException): Boolean {
        val text = (error.message ?: "").uppercase()
        return text.contains("NOT_FOUND") ||
            text.contains("NO_SUCH_FILE") ||
            text.contains("BAD_NETWORK_NAME") ||
            text.contains("OBJECT_PATH_NOT_FOUND")
    }

    private fun isDirectory(attributes: Long): Boolean =
        (attributes and FileAttributes.FILE_ATTRIBUTE_DIRECTORY.value) != 0L

    private fun epochMillis(time: FileTime?): Long? = time?.toEpochMillis()

    private fun normalizeBasePath(raw: String?): String {
        var value = (raw ?: "").replace('\\', '/').trim()
        while (value.startsWith("/")) value = value.substring(1)
        while (value.endsWith("/")) value = value.substring(0, value.length - 1)
        guardAgainstTraversal(value)
        return value
    }

    /** Joins a share-relative [rawPath] onto [basePath] exactly once. */
    private fun joinPath(basePath: String, rawPath: String?): String {
        var value = (rawPath ?: "").replace('\\', '/').trim()
        while (value.startsWith("/")) value = value.substring(1)
        while (value.endsWith("/")) value = value.substring(0, value.length - 1)
        guardAgainstTraversal(value)
        if (value.isEmpty()) return basePath
        if (basePath.isEmpty()) return value
        return "$basePath/$value"
    }

    private fun guardAgainstTraversal(path: String) {
        if (path.isEmpty()) return
        val segments = path.split('/')
        if (segments.any { it == ".." }) {
            throw IllegalArgumentException("Path traversal is not allowed.")
        }
    }

    /**
     * Stable, non-reversible fingerprint of the logon secret.
     *
     * Used only as a session-cache key component; the plaintext password is
     * never stored on this side.
     */
    private fun secretDigest(domain: String, username: String, password: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$domain\\$username:$password".toByteArray(Charsets.UTF_8))
        val hex = StringBuilder(digest.size * 2)
        for (byte in digest) {
            hex.append("%02x".format(byte.toInt() and 0xff))
        }
        return hex.toString()
    }

    private fun shareNameOf(args: Map<*, *>): String = args["share"] as? String ?: ""
}
