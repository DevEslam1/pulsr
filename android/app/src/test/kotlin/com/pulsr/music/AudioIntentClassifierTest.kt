package com.pulsr.music

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit tests for [AudioIntentClassifier]'s pure decision cores. These cover
 * the inbound-intent matrix (file-open, share, YouTube/proxy links, unsafe
 * schemes/paths) without needing an Android runtime.
 */
class AudioIntentClassifierTest {

    private val roots = listOf("/storage", "/sdcard", "/data/user/0/com.pulsr.music/files")

    // ---- Proxy detection ----

    @Test
    fun detectsValidProxyStrings() {
        assertTrue(AudioIntentClassifier.isProxyText("connect to 192.168.1.10:8080 please"))
        assertTrue(AudioIntentClassifier.isProxyText("10.0.0.1:1"))
    }

    @Test
    fun rejectsInvalidProxyStrings() {
        assertFalse(AudioIntentClassifier.isProxyText("999.1.1.1:8080")) // octet >255
        assertFalse(AudioIntentClassifier.isProxyText("1.2.3.4:70000")) // port >65535
        assertFalse(AudioIntentClassifier.isProxyText("1.2.3.4:0")) // port 0
        assertFalse(AudioIntentClassifier.isProxyText("no proxy here"))
    }

    // ---- YouTube host/url ----

    @Test
    fun detectsYouTubeHosts() {
        assertTrue(AudioIntentClassifier.isYouTubeHost("youtu.be"))
        assertTrue(AudioIntentClassifier.isYouTubeHost("music.youtube.com"))
        assertTrue(AudioIntentClassifier.isYouTubeHost("WWW.YOUTUBE.COM"))
        assertFalse(AudioIntentClassifier.isYouTubeHost("youtube.com.evil.net"))
        assertFalse(AudioIntentClassifier.isYouTubeHost(null))
    }

    @Test
    fun detectsYouTubeUrlsInText() {
        assertTrue(AudioIntentClassifier.isYouTubeUrl("check https://youtu.be/abc"))
        assertTrue(AudioIntentClassifier.isYouTubeUrl("https://music.youtube.com/watch?v=x"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("just some text"))
    }

    // ---- Safe URI ----

    @Test
    fun allowsContentHttpAndPulsrSchemes() {
        assertTrue(AudioIntentClassifier.isSafeUriParts("content", "/x", roots))
        assertTrue(AudioIntentClassifier.isSafeUriParts("http", null, roots))
        assertTrue(AudioIntentClassifier.isSafeUriParts("https", null, roots))
        assertTrue(AudioIntentClassifier.isSafeUriParts("pulsr", null, roots))
    }

    @Test
    fun rejectsUnknownSchemes() {
        assertFalse(AudioIntentClassifier.isSafeUriParts("javascript", "/x", roots))
        assertFalse(AudioIntentClassifier.isSafeUriParts("ftp", "/x", roots))
        assertFalse(AudioIntentClassifier.isSafeUriParts(null, "/x", roots))
    }

    @Test
    fun fileUrisMustLiveUnderAllowedRoots() {
        assertTrue(
            AudioIntentClassifier.isSafeUriParts("file", "/storage/emulated/0/song.mp3", roots)
        )
        assertFalse(
            AudioIntentClassifier.isSafeUriParts("file", "/etc/passwd", roots)
        )
        assertFalse(AudioIntentClassifier.isSafeUriParts("file", null, roots))
    }

    // ---- Audio intent matrix ----

    @Test
    fun widgetSchemeIsNeverAnAudioIntent() {
        assertFalse(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.VIEW",
                scheme = "pulsrwidget",
                path = null,
                host = null,
                mimeType = null,
                textExtra = null,
            )
        )
    }

    @Test
    fun audioFileExtensionIsAnAudioIntent() {
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.VIEW",
                scheme = "content",
                path = "/music/track.FLAC",
                host = null,
                mimeType = null,
                textExtra = null,
            )
        )
    }

    @Test
    fun dsdAndOpusExtensionsAreRecognised() {
        for (ext in listOf("dsf", "dff", "opus", "mka", "aiff", "alac")) {
            assertTrue(
                "expected .$ext to be an audio intent",
                AudioIntentClassifier.isAudioIntentParts(
                    action = "android.intent.action.VIEW",
                    scheme = "content",
                    path = "/music/track.$ext",
                    host = null,
                    mimeType = null,
                    textExtra = null,
                )
            )
        }
    }

    @Test
    fun textImportExtensionsAreRecognised() {
        for (ext in listOf("txt", "list", "conf", "csv")) {
            assertTrue(
                "expected .$ext to be an importable text intent",
                AudioIntentClassifier.isAudioIntentParts(
                    action = "android.intent.action.VIEW",
                    scheme = "content",
                    path = "/import.$ext",
                    host = null,
                    mimeType = null,
                    textExtra = null,
                )
            )
        }
    }

    @Test
    fun audioMimeTypeIsAnAudioIntent() {
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.VIEW",
                scheme = "content",
                path = null,
                host = null,
                mimeType = "audio/mpeg",
                textExtra = null,
            )
        )
    }

    @Test
    fun sharedYouTubeTextIsAnAudioIntent() {
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.SEND",
                scheme = "content",
                path = null,
                host = null,
                mimeType = "text/plain",
                textExtra = "https://youtu.be/abc",
            )
        )
    }

    @Test
    fun sharedProxyTextIsAnAudioIntent() {
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.SEND",
                scheme = "content",
                path = null,
                host = null,
                mimeType = "text/plain",
                textExtra = "proxy 10.0.0.1:8080",
            )
        )
    }

    @Test
    fun unrelatedSharedTextWithTextMimeIsStillAcceptedForImport() {
        // A plain text share is accepted at the intent gate (it may be an LRC,
        // playlist, or a config file); the Dart layer decides what to do with
        // it. Only non-text, non-audio shares are rejected here.
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.SEND",
                scheme = "content",
                path = null,
                host = null,
                mimeType = "text/plain",
                textExtra = "just a normal message",
            )
        )
    }

    @Test
    fun sharedBinaryWithoutAudioOrTextMimeIsRejected() {
        assertFalse(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.SEND",
                scheme = "content",
                path = null,
                host = null,
                mimeType = "image/png",
                textExtra = "https://example.com/pic.png",
            )
        )
    }

    @Test
    fun youtubeViewUriIsAnAudioIntent() {
        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.VIEW",
                scheme = "https",
                path = "/watch",
                host = "music.youtube.com",
                mimeType = null,
                textExtra = null,
            )
        )
    }

    @Test
    fun nullSchemeIsNotAnAudioIntent() {
        assertFalse(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.VIEW",
                scheme = null,
                path = "/x.mp3",
                host = null,
                mimeType = null,
                textExtra = null,
            )
        )
    }
}
