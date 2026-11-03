package com.pulsr.music

import android.content.Intent
import android.net.Uri
import java.io.File

/**
 * Pure, side-effect-free classification of inbound audio intents.
 *
 * Extracted from [MainActivity] so the decision logic (which URIs are audio,
 * which shared texts are proxy/YouTube links, and which URI schemes are safe)
 * is unit-testable without an Android runtime. `isSafeUri` takes the app's
 * allowed filesystem roots as a parameter instead of reading them from the
 * Activity.
 */
object AudioIntentClassifier {

    private val AUDIO_EXTENSIONS = listOf(
        ".mp3", ".flac", ".wav", ".aac", ".m4a", ".ogg", ".opus",
        ".mka", ".dsf", ".dff", ".aiff", ".alac",
    )

    private val TEXT_EXTENSIONS = listOf(".txt", ".list", ".conf", ".csv")

    private val PROXY_PATTERN =
        Regex("""\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}):(\d{1,5})\b""")

    private val ALLOWED_SCHEMES = setOf("content", "file", "http", "https", "pulsr")

    /** True when [text] contains a syntactically valid `host:port` proxy string. */
    fun isProxyText(text: String): Boolean {
        val m = PROXY_PATTERN.find(text) ?: return false
        val octets = (1..4).map { m.groupValues[it].toIntOrNull() ?: 256 }
        val port = m.groupValues[5].toIntOrNull() ?: 0
        return octets.all { it in 0..255 } && port in 1..65535
    }

    fun isYouTubeUri(uri: Uri): Boolean = isYouTubeHost(uri.host)

    /** Host-based check (kept `Uri`-free so it is unit-testable). */
    fun isYouTubeHost(host: String?): Boolean {
        val h = host?.lowercase() ?: return false
        return h == "youtube.com" || h.endsWith(".youtube.com") ||
            h == "youtu.be" || h.endsWith(".youtu.be")
    }

    fun isYouTubeUrl(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("youtu.be") || lower.contains("youtube.com")
    }

    /**
     * True when [uri] uses an allowed scheme. `file` URIs must live under one of
     * [allowedFileRoots] (external storage, app dirs) to prevent path traversal
     * into arbitrary filesystem locations.
     */
    fun isSafeUri(uri: Uri, allowedFileRoots: List<String>): Boolean =
        isSafeUriParts(uri.scheme, uri.path, allowedFileRoots)

    /** Scheme/path core of [isSafeUri] (kept `Uri`-free so it is unit-testable). */
    fun isSafeUriParts(
        scheme: String?,
        path: String?,
        allowedFileRoots: List<String>,
    ): Boolean {
        val s = scheme?.lowercase() ?: return false
        if (s !in ALLOWED_SCHEMES) return false
        if (s == "file") {
            val p = path ?: return false
            // Reject traversal segments before canonicalization; canonicalPath
            // alone still resolves them, which would let `root/../secret` pass
            // the prefix test below if the resolved file happens to stay inside
            // the root, and silently import a file outside it otherwise.
            if (p.split('/', '\\').any { it == ".." }) return false
            val normalized = runCatching { File(p).canonicalPath }.getOrNull() ?: return false
            return allowedFileRoots.any { root ->
                val cleanRoot = runCatching { File(root).canonicalPath }.getOrNull()
                    ?: return@any false
                normalized == cleanRoot ||
                    normalized.startsWith("$cleanRoot/") ||
                    normalized.startsWith("$cleanRoot${File.separator}")
            }
        }
        return true
    }

    /**
     * Whether an ACTION_VIEW / ACTION_SEND intent targeting [uri] should be
     * treated as an audio (or importable text) open request.
     */
    fun isAudioIntent(intent: Intent, uri: Uri): Boolean =
        isAudioIntentParts(
            action = intent.action,
            scheme = uri.scheme,
            path = uri.path,
            host = uri.host,
            mimeType = intent.type,
            textExtra = intent.getStringExtra(Intent.EXTRA_TEXT),
        )

    /**
     * `Uri`/`Intent`-free core of [isAudioIntent] so the decision table can be
     * unit-tested on the JVM without an Android runtime.
     */
    fun isAudioIntentParts(
        action: String?,
        scheme: String?,
        path: String?,
        host: String?,
        mimeType: String?,
        textExtra: String?,
    ): Boolean {
        // Plain-text ACTION_SEND intents carry no data URI, so scheme is null;
        // the shared link must be classified before the scheme gate rejects it.
        if (action == Intent.ACTION_SEND &&
            !textExtra.isNullOrEmpty() &&
            (isYouTubeUrl(textExtra) || isProxyText(textExtra))
        ) {
            return true
        }
        val s = scheme?.lowercase() ?: return false
        if (s == "pulsrwidget") return false
        if (s == "pulsr") return true
        if (isYouTubeHost(host)) return true
        if (action == Intent.ACTION_SEND) {
            return mimeType?.startsWith("audio/") == true ||
                mimeType?.startsWith("text/") == true ||
                (s == "content" && mimeType == null)
        }
        if (mimeType?.startsWith("audio/") == true ||
            mimeType?.startsWith("text/") == true
        ) {
            return true
        }
        val p = path?.lowercase() ?: ""
        val isAudioExt = AUDIO_EXTENSIONS.any { p.endsWith(it) }
        val isTextExt = TEXT_EXTENSIONS.any { p.endsWith(it) }
        return isAudioExt || isTextExt || (s == "content" && mimeType == null)
    }
}
