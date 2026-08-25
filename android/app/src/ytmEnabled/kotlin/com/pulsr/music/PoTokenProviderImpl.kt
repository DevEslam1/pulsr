package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.services.youtube.InnertubeClientRequestInfo
import org.schabi.newpipe.extractor.services.youtube.PoTokenProvider
import org.schabi.newpipe.extractor.services.youtube.PoTokenResult
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper

/**
 * Supplies the BotGuard proof-of-origin tokens YouTube demands before it hands out
 * stream URLs. Without them its player endpoints answer `LOGIN_REQUIRED` — "Sign in
 * to confirm that you're not a bot" — no matter what cookies are attached, which is
 * why signing in alone does not fix playback.
 *
 * Only the web client is attested, matching upstream NewPipe: the other clients get
 * `null` and the extractor falls back on its own.
 *
 * A generator is cached and reused across tracks, since standing up the BotGuard VM
 * costs two network round-trips plus JavaScript execution, while minting a token
 * from a live VM is local and fast.
 */
internal class PoTokenProviderImpl(private val context: Context) : PoTokenProvider {
    private val lock = Any()

    private var generator: PoTokenGenerator? = null
    private var visitorData: String? = null
    private var streamingPoToken: String? = null

    @Volatile
    private var webViewBroken = false

    override fun getWebClientPoToken(videoId: String): PoTokenResult? {
        if (webViewBroken || !supportsWebView()) return null
        return try {
            webClientPoToken(videoId, forceRecreate = false)
        } catch (e: BadWebViewException) {
            // Nothing to retry: this device's WebView cannot run BotGuard at all, so
            // stop paying the initialization cost on every subsequent track.
            Log.e(TAG, "Disabling poTokens, the system WebView cannot run BotGuard", e)
            webViewBroken = true
            null
        }
    }

    override fun getWebEmbedClientPoToken(videoId: String): PoTokenResult? = null

    override fun getAndroidClientPoToken(videoId: String): PoTokenResult? = null

    override fun getIosClientPoToken(videoId: String): PoTokenResult? = null

    /**
     * @param forceRecreate rebuild the generator from scratch, for when the current
     * one has just failed to mint a token
     */
    private fun webClientPoToken(videoId: String, forceRecreate: Boolean): PoTokenResult {
        val session = synchronized(lock) {
            val current = generator
            if (current == null || forceRecreate || current.isExpired()) {
                createSession()
            } else {
                Session(current, visitorData!!, streamingPoToken!!, recreated = false)
            }
        }

        val playerPoToken = try {
            // Deliberately outside the lock: a live VM can mint tokens in parallel, and
            // only the one-visitorData-and-streaming-token-first ordering needs guarding.
            session.generator.generatePoToken(videoId)
        } catch (t: Throwable) {
            if (session.recreated) throw t
            // The WebView loses its BotGuard state when the app is backgrounded, so one
            // retry against a fresh VM is expected rather than exceptional.
            Log.w(TAG, "Failed to mint a poToken, retrying with a fresh WebView", t)
            return webClientPoToken(videoId, forceRecreate = true)
        }

        return PoTokenResult(session.visitorData, playerPoToken, session.streamingPoToken)
    }

    private fun createSession(): Session {
        val previous = generator
        // Cleared up front so a failure below cannot leave a closed generator installed.
        generator = null
        visitorData = null
        streamingPoToken = null
        previous?.let { old -> Handler(Looper.getMainLooper()).post { old.close() } }

        val clientRequestInfo = InnertubeClientRequestInfo.ofWebClient()
        clientRequestInfo.clientInfo.clientVersion = YoutubeParsingHelper.getClientVersion()
        val newVisitorData = YoutubeParsingHelper.getVisitorDataFromInnertube(
            clientRequestInfo,
            NewPipe.getPreferredLocalization(),
            NewPipe.getPreferredContentCountry(),
            YoutubeParsingHelper.getYouTubeHeaders(),
            YoutubeParsingHelper.YOUTUBEI_V1_URL,
            null,
            false,
        )

        val newGenerator = PoTokenWebView.newPoTokenGenerator(context)
        // The streaming token has to be the first thing this generator mints; YouTube
        // rejects it if any player token was minted before it.
        val newStreamingPoToken = newGenerator.generatePoToken(newVisitorData)

        generator = newGenerator
        visitorData = newVisitorData
        streamingPoToken = newStreamingPoToken
        return Session(newGenerator, newVisitorData, newStreamingPoToken, recreated = true)
    }

    /** False on the rare device whose WebView provider is missing or disabled. */
    private fun supportsWebView(): Boolean = runCatching { CookieManager.getInstance() }.isSuccess

    private class Session(
        val generator: PoTokenGenerator,
        val visitorData: String,
        val streamingPoToken: String,
        val recreated: Boolean,
    )

    private companion object {
        private const val TAG = "PoTokenProvider"
    }
}
