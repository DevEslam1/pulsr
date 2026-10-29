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
        // VISIONOS leads the chain: it needs neither a poToken nor JS
        // deciphering (both s and n are pre-applied server-side, formats carry
        // plain URLs), and it accepts the session visitorData that keeps the
        // player request out of the BotChallenge path. Its one known gap —
        // "made for kids" videos are not offered — is covered by the rest of
        // the chain.
        // The tail holds no-login last resorts for IP-flagged waves where every
        // regular client answers LOGIN_REQUIRED: ANDROID_TESTSUITE (bare test
        // client, no auth/token checks) and TVHTML5_SIMPLY_EMBEDDED_PLAYER
        // (third-party embed context). They only run after the main clients
        // fail, so the happy path is unchanged.
        val DEFAULT_STREAM_CHAIN = listOf(
            InnertubeClient.ClientType.VISIONOS,
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
        val baseOpChain = when (op) {
            Operation.STREAM_RESOLVE -> DEFAULT_STREAM_CHAIN
            Operation.SEARCH -> DEFAULT_SEARCH_CHAIN
            Operation.BROWSE -> DEFAULT_BROWSE_CHAIN
        }

        // A persisted winner is promoted only on the direct path: on a VPN the egress
        // itself is what changed, so a client that won on the home connection is not
        // evidence of anything.
        val winnerPromoted = if (op == Operation.STREAM_RESOLVE && !isVpn) {
            val winner = winnerStore.getWinningClient(trackType)
            if (winner != null && baseOpChain.contains(winner)) {
                listOf(winner) + (baseOpChain - winner)
            } else {
                baseOpChain
            }
        } else {
            baseOpChain
        }

        // 08-2026: VPN datacenter IPs are flagged for BotGuard. WEB_REMIX
        // (poToken + visitorData) answers LOGIN_REQUIRED/BOT_CHALLENGE there while the
        // token-free clients still resolve, so on a VPN the token-free clients go first.
        //
        // Derived from capabilities instead of a second hard-coded list: the previous
        // VPN branches were a byte-identical copy of the defaults for stream (so the
        // documented reordering never happened) and drifted independently for
        // search/browse. `partition` is stable, so the order inside each group survives.
        val baseChain = if (isVpn) {
            val (tokenFree, tokenBound) = winnerPromoted.partition { client ->
                !ClientCapabilityMatrix.getCapability(client).requiresPoToken
            }
            tokenFree + tokenBound
        } else {
            winnerPromoted
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
            // Absolute fallback, still filtered through the same gate. The old tail
            // returned IOS_MUSIC unconditionally, which contradicted the filter two
            // lines above it as soon as IOS_MUSIC carried a token requirement in the
            // capability asset.
            val gate: (InnertubeClient.ClientType) -> Boolean = { client ->
                val cap = ClientCapabilityMatrix.getCapability(client)
                (!cap.requiresJsSignature || hasJsEngine) && (!limitedMode || !cap.requiresPoToken)
            }
            listOf(InnertubeClient.ClientType.IOS_MUSIC, InnertubeClient.ClientType.ANDROID_VR)
                .filter(gate)
                .ifEmpty { baseChain.filter(gate) }
                .ifEmpty { listOf(baseChain.first()) }
        }
    }
}
