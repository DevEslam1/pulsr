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
