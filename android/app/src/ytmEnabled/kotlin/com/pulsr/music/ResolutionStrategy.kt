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
    }

    /**
     * Builds an eligible sequence of clients for [op] skipping any clients with unmet requirements
     * and strictly ordering candidates by descending capability priority.
     *
     * For STREAM_RESOLVE:
     * - If user is logged in, WEB_REMIX leads (for auth cookies).
     * - Otherwise if a winning client was persisted for [trackType], it is placed at the front.
     * - Partitioned so clients matching current PO-token readiness come first.
     * - Temporarily failing / blacklisted clients are demoted until TTL expires.
     */
    fun buildChain(
        op: Operation,
        limitedMode: Boolean = false,
        hasJsEngine: Boolean = true,
        trackType: String = ClientWinnerStore.TRACK_TYPE_MUSIC
    ): List<InnertubeClient.ClientType> {
        val isLoggedIn = cookieStore.isSessionValid()
        val allClients = InnertubeClient.ClientType.values().toList()

        // 1. Filter by operation and basic environmental capabilities
        val eligible = allClients.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)

            // Operation capability check
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
        }.sortedByDescending { ClientCapabilityMatrix.getCapability(it).priority }

        // 2. Demote temporary failing clients via session circuit breaker
        val activeClients = eligible.filter { !ClientFailureTracker.isBlacklisted(it) }
        val candidatePool = activeClients.ifEmpty { eligible }

        val hasPoToken = !limitedMode && poTokenManager.isReady && !poTokenManager.webViewBroken

        // 3. Partition: clients not requiring PO token or matching current readiness first
        val primary = candidatePool.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)
            !cap.requiresPoToken || hasPoToken
        }
        val secondary = candidatePool.filter { client ->
            val cap = ClientCapabilityMatrix.getCapability(client)
            cap.requiresPoToken && !hasPoToken
        }

        var baseChain = primary + secondary

        // 4. Operation-specific top-tier prioritization
        if (op == Operation.STREAM_RESOLVE) {
            val winner = winnerStore.getWinningClient(trackType)
            if (winner != null && baseChain.contains(winner) && !ClientFailureTracker.isBlacklisted(winner)) {
                baseChain = listOf(winner) + (baseChain - winner)
            }

            // When the user is logged in, WEB_REMIX must lead the chain.
            // IOS_MUSIC / ANDROID_MUSIC / ANDROID_VR have no session cookies;
            // if they return LOGIN_REQUIRED consecutively the LadderAbortPolicy
            // fires and aborts before WEB_REMIX is ever tried.
            if (isLoggedIn && baseChain.contains(InnertubeClient.ClientType.WEB_REMIX)) {
                baseChain = listOf(InnertubeClient.ClientType.WEB_REMIX) +
                    (baseChain - InnertubeClient.ClientType.WEB_REMIX)
            }
        }

        return baseChain.ifEmpty {
            // Absolute fallback to IOS_MUSIC / ANDROID_VR if all filtered out
            listOf(InnertubeClient.ClientType.IOS_MUSIC, InnertubeClient.ClientType.ANDROID_VR)
        }
    }
}

/**
 * Session-scoped circuit breaker for temporarily failing Innertube clients.
 * Prevents retrying dead clients on every request while ensuring automatic recovery
 * when the 10-minute TTL expires.
 */
internal object ClientFailureTracker {
    private const val FAILURE_THRESHOLD = 3
    private const val BLACKLIST_TTL_MS = 10 * 60 * 1000L // 10 minutes

    private val failures = java.util.concurrent.ConcurrentHashMap<InnertubeClient.ClientType, Pair<Int, Long>>()

    fun recordFailure(client: InnertubeClient.ClientType) {
        val now = System.currentTimeMillis()
        failures.compute(client) { _, existing ->
            val count = (existing?.first ?: 0) + 1
            val blockedUntil = if (count >= FAILURE_THRESHOLD) now + BLACKLIST_TTL_MS else (existing?.second ?: 0L)
            count to blockedUntil
        }
    }

    fun recordSuccess(client: InnertubeClient.ClientType) {
        failures.remove(client)
    }

    fun isBlacklisted(client: InnertubeClient.ClientType): Boolean {
        val record = failures[client] ?: return false
        val (count, blockedUntil) = record
        if (count < FAILURE_THRESHOLD) return false
        val now = System.currentTimeMillis()
        if (now >= blockedUntil) {
            failures.remove(client)
            return false
        }
        return true
    }

    fun clear() {
        failures.clear()
    }
}


/**
 * Pure policy for the stream ladder's early abort: when [threshold] consecutive
 * clients answer LOGIN_REQUIRED, the device/IP is almost certainly gated and
 * walking the rest of the chain cannot succeed. Kept pure for unit testing.
 *
 * When [countOnlyAuthenticatedClients] is true (user is signed in), only
 * LOGIN_REQUIRED responses from *authenticated* clients (i.e. those that actually
 * sent session cookies) count toward the threshold. Unauthenticated clients like
 * ANDROID_VR and IOS_MUSIC are expected to fail LOGIN_REQUIRED for account-gated
 * content and must not cause the ladder to abort while a valid session is active.
 */
internal class LadderAbortPolicy(
    private val threshold: Int = DEFAULT_THRESHOLD,
    private val countOnlyAuthenticatedClients: Boolean = false,
) {
    private var consecutiveLoginRequired = 0

    /**
     * Records one client outcome.
     * @param loginRequired  true when playabilityStatus was LOGIN_REQUIRED
     * @param isAuthenticatedClient  true when this client sent session cookies in the request
     */
    fun onLoginRequired(loginRequired: Boolean, isAuthenticatedClient: Boolean = true) {
        if (loginRequired) {
            // Only count toward the abort threshold if:
            //   • we're not restricting to authenticated clients, OR
            //   • this particular client actually had session cookies attached
            if (!countOnlyAuthenticatedClients || isAuthenticatedClient) {
                consecutiveLoginRequired++
            }
        } else {
            consecutiveLoginRequired = 0
        }
    }

    fun shouldAbort(): Boolean = consecutiveLoginRequired >= threshold

    companion object {
        const val DEFAULT_THRESHOLD = 4
    }
}
