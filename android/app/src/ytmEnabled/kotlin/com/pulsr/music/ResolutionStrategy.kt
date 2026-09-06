package com.pulsr.music

import android.content.Context
import android.util.Log

/**
 * Layer 3: Dynamic Resolution Strategy & Dual-Engine Fallback Chain.
 *
 * Orders client attempts per operation, skips ineligible clients based on capabilities,
 * incorporates winning client persistence, and strips non-functional audio clients (like TV)
 * from the fast path.
 */
internal class ResolutionStrategy(
    private val context: Context,
    private val cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context),
    private val poTokenManager: PoTokenManager = PoTokenManager,
    private val winnerStore: ClientWinnerStore = ClientWinnerStore.getInstance(context)
) {
    enum class Operation {
        STREAM_RESOLVE,
        SEARCH,
        BROWSE
    }

    companion object {
        private const val TAG = "ResolutionStrategy"

        // Optimized default stream chain for audio streaming.
        // The tail holds no-login last resorts for IP-flagged waves where every
        // regular client answers LOGIN_REQUIRED: ANDROID_TESTSUITE (bare test
        // client, no auth/token checks) and TVHTML5_SIMPLY_EMBEDDED_PLAYER
        // (third-party embed context). They only run after the main clients
        // fail, so the happy path is unchanged.
        val DEFAULT_STREAM_CHAIN = listOf(
            InnertubeClient.ClientType.WEB_REMIX,
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.ANDROID_MUSIC,
            InnertubeClient.ClientType.ANDROID_CREATOR,
            InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER,
            InnertubeClient.ClientType.MWEB,
            InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            InnertubeClient.ClientType.ANDROID_TESTSUITE
        )

        val DEFAULT_SEARCH_CHAIN = listOf(
            InnertubeClient.ClientType.WEB_REMIX,
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.MWEB,
            InnertubeClient.ClientType.ANDROID_MUSIC
        )

        val DEFAULT_BROWSE_CHAIN = listOf(
            InnertubeClient.ClientType.WEB_REMIX,
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.MWEB
        )
    }

    /**
     * Builds an eligible sequence of clients for [op] skipping any clients with unmet requirements.
     * For STREAM_RESOLVE, if a winning client was persisted for [trackType], it is placed at the front.
     */
    fun buildChain(
        op: Operation,
        limitedMode: Boolean = false,
        hasJsEngine: Boolean = false,
        trackType: String = ClientWinnerStore.TRACK_TYPE_MUSIC
    ): List<InnertubeClient.ClientType> {
        val baseChain = when (op) {
            Operation.STREAM_RESOLVE -> {
                val winner = winnerStore.getWinningClient(trackType)
                if (winner != null && DEFAULT_STREAM_CHAIN.contains(winner)) {
                    listOf(winner) + (DEFAULT_STREAM_CHAIN - winner)
                } else {
                    DEFAULT_STREAM_CHAIN
                }
            }
            Operation.SEARCH -> DEFAULT_SEARCH_CHAIN
            Operation.BROWSE -> DEFAULT_BROWSE_CHAIN
        }

        val hasPoToken = !limitedMode && poTokenManager.isReady && !poTokenManager.webViewBroken
        val isLoggedIn = cookieStore.isSessionValid()
        val eligible = baseChain.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)

            // Operation check
            val supportsOp = when (op) {
                Operation.STREAM_RESOLVE -> cap.supportsStreamResolve
                Operation.SEARCH -> cap.supportsSearch
                Operation.BROWSE -> cap.supportsBrowse
            }
            if (!supportsOp) return@filter false

            // Auth requirement check
            if (cap.requiresLogin && !isLoggedIn) {
                Log.d(TAG, "Skipping client ${client.name}: requires login but user not logged in")
                return@filter false
            }

            // JS signature engine check
            if (cap.requiresJsSignature && !hasJsEngine) {
                Log.d(TAG, "Skipping client ${client.name}: requires JS signature engine")
                return@filter false
            }

            true
        }

        // Partition: clients matching current poToken readiness first, secondary fallbacks at the end
        val primary = eligible.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)
            !cap.requiresPoToken || hasPoToken
        }
        val secondary = eligible.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)
            cap.requiresPoToken && !hasPoToken
        }

        val chain = if (limitedMode) primary else primary + secondary
        return chain.ifEmpty {
            // Absolute fallback filtered through capabilities
            listOf(InnertubeClient.ClientType.IOS_MUSIC, InnertubeClient.ClientType.ANDROID_VR).filter {
                val cap = ClientCapabilityMatrix.getCapability(it)
                (!cap.requiresJsSignature || hasJsEngine) && (!limitedMode || !cap.requiresPoToken)
            }.ifEmpty {
                listOf(InnertubeClient.ClientType.IOS_MUSIC)
            }
        }
    }
}
