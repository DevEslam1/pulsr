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
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.WEB_REMIX,
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
        SabrDemotionStore.init(context)
        val isVpn = try { CellularFailoverHelper.isVpnActive(context) } catch (_: Throwable) { false }
        val baseChain = when (op) {
            Operation.STREAM_RESOLVE -> {
                val winner = winnerStore.getWinningClient(trackType)
                val defaultChain = if (isVpn) {
                    // 08-2026: VPN datacenter IPs are flagged for BotGuard. WEB_REMIX (poToken+visitorData)
                    // fails with LOGIN_REQUIRED/BOT_CHALLENGE while ANDROID_VR/IOS_MUSIC (no PoToken)
                    // still succeed. Prioritize no-PoToken clients on VPN.
                    listOf(
                        InnertubeClient.ClientType.ANDROID_VR,
                        InnertubeClient.ClientType.IOS_MUSIC,
                        InnertubeClient.ClientType.WEB_REMIX,
                        InnertubeClient.ClientType.ANDROID_MUSIC,
                        InnertubeClient.ClientType.ANDROID_CREATOR,
                        InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER,
                        InnertubeClient.ClientType.MWEB,
                        InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
                        InnertubeClient.ClientType.ANDROID_TESTSUITE
                    )
                } else DEFAULT_STREAM_CHAIN
                if (winner != null && defaultChain.contains(winner) && !isVpn) {
                    listOf(winner) + (defaultChain - winner)
                } else {
                    defaultChain
                }
            }
            Operation.SEARCH -> if (isVpn) listOf(
                InnertubeClient.ClientType.IOS_MUSIC,
                InnertubeClient.ClientType.ANDROID_VR,
                InnertubeClient.ClientType.WEB_REMIX,
                InnertubeClient.ClientType.MWEB,
                InnertubeClient.ClientType.ANDROID_MUSIC
            ) else DEFAULT_SEARCH_CHAIN
            Operation.BROWSE -> if (isVpn) listOf(
                InnertubeClient.ClientType.IOS_MUSIC,
                InnertubeClient.ClientType.ANDROID_VR,
                InnertubeClient.ClientType.WEB_REMIX,
                InnertubeClient.ClientType.MWEB
            ) else DEFAULT_BROWSE_CHAIN
        }

        // Treat a token that is about to expire as absent: `isReady` only checks
        // "not already expired", so a token with minutes left still put the
        // poToken-dependent clients (WEB_REMIX) at the front, where they fail
        // first and drag in the slow fallback. `preWarm`/`ensureReady` refresh
        // ahead of this margin, so a healthy session is unaffected.
        val hasPoToken = !limitedMode && poTokenManager.isReady &&
            !poTokenManager.isExpiringSoon() && !poTokenManager.webViewBroken
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
        // 2026-09 gap 1: SABR-demoted clients go to the BACK of the chain for
        // 24h (never removed — a YouTube-side rollback self-heals at TTL).
        val sabrDemoted = chain.filter { SabrDemotionStore.isSabrDemoted(it) }
        val orderedChain = if (sabrDemoted.isEmpty()) chain else chain.filterNot { sabrDemoted.contains(it) } + sabrDemoted
        return orderedChain.ifEmpty {
            // Absolute fallback filtered through capabilities
            listOf(InnertubeClient.ClientType.IOS_MUSIC, InnertubeClient.ClientType.ANDROID_VR).filter {
                val cap = ClientCapabilityMatrix.getCapability(it)
                (!cap.requiresJsSignature || hasJsEngine) && (!limitedMode || !cap.requiresPoToken)
            }.ifEmpty {
                baseChain.filter {
                    val cap = ClientCapabilityMatrix.getCapability(it)
                    (!cap.requiresJsSignature || hasJsEngine) && (!limitedMode || !cap.requiresPoToken)
                }
            }.ifEmpty {
                listOf(InnertubeClient.ClientType.IOS_MUSIC)
            }
        }
    }
}
