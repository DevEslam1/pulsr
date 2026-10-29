package com.pulsr.music

import android.content.Context
import android.util.Log
import org.schabi.newpipe.extractor.services.youtube.PoTokenProvider
import org.schabi.newpipe.extractor.services.youtube.PoTokenResult

/**
 * Supplies BotGuard proof-of-origin tokens (poToken) to NewPipeExtractor.
 *
 * Ensures synchronous readiness and delegates lifecycle, LRU caching,
 * proactive refresh, and fallback logic to [PoTokenManager].
 *
 * Only the web client is implemented. [getWebEmbedClientPoToken],
 * [getAndroidClientPoToken] and [getIosClientPoToken] return null on purpose:
 * the BotGuard session this app mints is a web-player session, and a token
 * minted in the wrong context is rejected rather than ignored. The cost is that
 * NewPipeExtractor is limited to its web-client path, which is the path this app
 * exercises.
 */
internal class PoTokenProviderImpl(context: Context) : PoTokenProvider {

    init {
        PoTokenManager.init(context)
    }

    override fun getWebClientPoToken(videoId: String): PoTokenResult? {
        return try {
            PoTokenManager.ensureReadySync()
            val visitorData = PoTokenManager.visitorData
            val playerPoToken = PoTokenManager.poTokenForSync(videoId)
            val streamingPoToken = PoTokenManager.streamingPoToken

            if (visitorData.isEmpty() || playerPoToken.isEmpty()) {
                Log.w(TAG, "Empty poToken result generated for videoId: $videoId")
                return null
            }

            PoTokenResult(visitorData, playerPoToken, streamingPoToken)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to get web client poToken: ${t.message}", t)
            null
        }
    }

    override fun getWebEmbedClientPoToken(videoId: String): PoTokenResult? = null

    override fun getAndroidClientPoToken(videoId: String): PoTokenResult? = null

    override fun getIosClientPoToken(videoId: String): PoTokenResult? = null

    companion object {
        private const val TAG = "PoTokenProviderImpl"
    }
}
