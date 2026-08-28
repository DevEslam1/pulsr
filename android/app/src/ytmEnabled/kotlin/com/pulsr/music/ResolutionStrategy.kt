package com.pulsr.music

import android.content.Context
import android.util.Log

/**
 * Layer 3: Dynamic Resolution Strategy & Dual-Engine Fallback Chain.
 *
 * Orders client attempts per operation, skips ineligible clients based on capabilities,
 * and orchestrates dual-engine fallback (Native Innertube -> NewPipeExtractor).
 */
internal class ResolutionStrategy(
    private val context: Context,
    private val cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context),
    private val poTokenManager: PoTokenManager = PoTokenManager
) {
    enum class Operation {
        STREAM_RESOLVE,
        SEARCH,
        BROWSE
    }

    companion object {
        private const val TAG = "ResolutionStrategy"

        // Default priority chains
        val DEFAULT_STREAM_CHAIN = listOf(
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_MUSIC,
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.ANDROID_CREATOR,
            InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            InnertubeClient.ClientType.WEB_REMIX,
            InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER,
            InnertubeClient.ClientType.MWEB,
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
     */
    fun buildChain(
        op: Operation,
        limitedMode: Boolean = false,
        hasJsEngine: Boolean = true
    ): List<InnertubeClient.ClientType> {
        val baseChain = when (op) {
            Operation.STREAM_RESOLVE -> DEFAULT_STREAM_CHAIN
            Operation.SEARCH -> DEFAULT_SEARCH_CHAIN
            Operation.BROWSE -> DEFAULT_BROWSE_CHAIN
        }

        val hasPoToken = !limitedMode && poTokenManager.isReady && !poTokenManager.webViewBroken
        val isLoggedIn = cookieStore.isSessionValid()

        val chain = baseChain.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)

            // Operation check
            val supportsOp = when (op) {
                Operation.STREAM_RESOLVE -> cap.supportsStreamResolve
                Operation.SEARCH -> cap.supportsSearch
                Operation.BROWSE -> cap.supportsBrowse
            }
            if (!supportsOp) return@filter false

            // PoToken requirement check
            if (cap.requiresPoToken && !hasPoToken) {
                Log.d(TAG, "Skipping client ${client.name}: requires poToken but unavailable/limitedMode")
                return@filter false
            }

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

        return chain.ifEmpty {
            // Absolute fallback to ANDROID_VR / IOS_MUSIC if all filtered out
            listOf(InnertubeClient.ClientType.IOS_MUSIC, InnertubeClient.ClientType.ANDROID_VR)
        }
    }
}
