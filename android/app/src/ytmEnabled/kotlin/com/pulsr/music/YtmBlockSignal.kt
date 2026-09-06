package com.pulsr.music

import org.json.JSONObject

/**
 * Layer 2: Precise Block Signals for YouTube Music Innertube API.
 *
 * Categorizes YouTube failure modes into discrete, actionable signals.
 *
 * [NetworkUnavailable] is deliberately distinct from [IpBlocked] and
 * [RateLimited]: the device simply having no route to YouTube must not trigger
 * proxy rotation or a global cooldown that outlives the outage.
 */
enum class YtmBlockSignal(val code: String) {
    RateLimited("RATE_LIMITED"),
    IpBlocked("IP_BLOCKED"),
    BotChallenge("BOT_CHALLENGE"),
    PoTokenInvalid("PO_TOKEN_INVALID"),
    ClientDeprecated("CLIENT_DEPRECATED"),
    GeoBlocked("GEO_BLOCKED"),
    SignInRequired("SIGN_IN_REQUIRED"),
    VideoGone("VIDEO_GONE"),
    NetworkUnavailable("YTM_NETWORK"),
    SignatureDecipherFailed("SIGNATURE_DECIPHER_FAILED");

    companion object {
        private val BOT_SUBSTRINGS = listOf(
            "not a bot",
            "robot",
            "recaptcha",
            "confirm you're not a bot",
            "confirm that you're not a bot",
            "automated queries",
            "unusual traffic",
            "botguard",
            "verification required"
        )

        private val GEO_SUBSTRINGS = listOf(
            "not available in your country",
            "not available in your region",
            "country restriction",
            "geo_restricted",
            "blocked in your country",
            "owner has not made this video available in your country",
            "uploader has not made this video available in your country",
            "not made this video available in your country",
            "unavailable in your country",
            "unavailable in your location",
            "غير متوفر في منطقتك",
            "غير متوفر في بلدك",
            "غير متاح في منطقتك",
            "غير متاح في بلدك"
        )

        // Unambiguous "this specific video is gone" wording. Anything that also
        // appears on YouTube's consent / block / captcha interstitials belongs in
        // GONE_WEAK_SUBSTRINGS instead, otherwise a 403 IP block whose body
        // mentions the Terms of Service is silently classified as VideoGone and
        // the track is skipped with no backoff or path rotation.
        private val GONE_SUBSTRINGS = listOf(
            "video unavailable",
            "removed by the user",
            "removed by user",
            "private video",
            "video has been removed",
            "no longer available",
            "does not exist"
        )

        // Only meaningful alongside a playabilityStatus that already says the
        // video itself is unusable.
        private val GONE_WEAK_SUBSTRINGS = listOf(
            "deleted",
            "terms of service",
            "account associated with this video has been terminated"
        )

        // 200 + UNPLAYABLE reasons that are genuinely about this one video and
        // must never be read as an IP-level block. Kept to distinctive phrases:
        // short fragments like "age" would match "message"/"usage".
        private val UNPLAYABLE_CONTENT_SUBSTRINGS = listOf(
            "premium",
            "members only",
            "member-only",
            "requires payment",
            "purchase",
            "rental",
            "playback on other websites",
            "watch on youtube",
            "live event has ended",
            "live stream offline",
            "premieres in",
            "confirm your age",
            "age-restricted",
            "not available on this app"
        )

        private val DEPRECATED_SUBSTRINGS = listOf(
            "api key not valid",
            "bad request",
            "invalid argument",
            "client version is no longer supported",
            "upgrade to continue",
            "unsupported client"
        )

        /**
         * Tolerantly parses HTTP response code, raw body / exception string, and optional JSON payload.
         */
        fun parse(
            httpCode: Int,
            responseBody: String? = null,
            playabilityStatus: JSONObject? = null,
            topLevelError: JSONObject? = null
        ): YtmBlockSignal {
            val body = (responseBody ?: "").lowercase()
            val status = (playabilityStatus?.optString("status") ?: "").uppercase()
            val reason = (playabilityStatus?.optString("reason") ?: "").lowercase()
            val subreason = (playabilityStatus?.optJSONObject("errorScreen")
                ?.optJSONObject("playerErrorMessageRenderer")
                ?.optJSONObject("subreason")
                ?.optString("simpleText") ?: "").lowercase()

            val combinedReasons = "$body $reason $subreason"

            // 1. Bot Challenge (highest priority detection)
            if (BOT_SUBSTRINGS.any { combinedReasons.contains(it) } ||
                status.contains("BOT") ||
                ((status == "LOGIN_REQUIRED" || status == "UNPLAYABLE") && BOT_SUBSTRINGS.any { combinedReasons.contains(it) })) {
                return BotChallenge
            }

            // 2. Rate Limited (HTTP 429 or explicit rate messages)
            if (httpCode == 429 ||
                combinedReasons.contains("too many requests") ||
                combinedReasons.contains("rate limit") ||
                combinedReasons.contains("quota exceeded") ||
                combinedReasons.contains("http 429")) {
                return RateLimited
            }

            // 3. PoToken Invalid (403 on stream URL / empty adaptiveFormats with 200)
            if (combinedReasons.contains("potoken") ||
                combinedReasons.contains("po_token_invalid") ||
                combinedReasons.contains("integrity token") ||
                combinedReasons.contains("token_expired") ||
                (httpCode == 200 && status == "OK" && combinedReasons.contains("empty_adaptive_formats"))) {
                return PoTokenInvalid
            }

            // 4. Geo Blocked
            if (status == "UNPLAYABLE" && GEO_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return GeoBlocked
            }
            if (GEO_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return GeoBlocked
            }

            // 5. Sign In Required (legitimate auth requirement without bot flags)
            if (status == "LOGIN_REQUIRED" ||
                combinedReasons.contains("login_required") ||
                combinedReasons.contains("sign in to access") ||
                combinedReasons.contains("authentication required")) {
                return SignInRequired
            }

            // 6. Video Gone / Removed / Private.
            // The status-qualified clauses can trust the wording. The bare
            // substring scan cannot — it runs against the whole raw body, which
            // for a 403/429 interstitial is an HTML page full of boilerplate —
            // so it is restricted to 404 and 2xx responses. Weak wording
            // ("deleted", "terms of service") needs a corroborating status.
            val goneWording = GONE_SUBSTRINGS.any { combinedReasons.contains(it) }
            val weakGoneWording = GONE_WEAK_SUBSTRINGS.any { combinedReasons.contains(it) }
            if (httpCode == 404 ||
                ((status == "ERROR" || status == "UNPLAYABLE") && (goneWording || weakGoneWording)) ||
                (status == "UNPLAYABLE" && UNPLAYABLE_CONTENT_SUBSTRINGS.any { combinedReasons.contains(it) }) ||
                (goneWording && httpCode in 200..299)) {
                return VideoGone
            }

            // 7. IP Blocked (403 without bot wording, or general access denied)
            if (httpCode == 403 ||
                combinedReasons.contains("forbidden") ||
                combinedReasons.contains("access denied") ||
                combinedReasons.contains("ip blocked")) {
                return IpBlocked
            }

            // 8. Client Deprecated (HTTP 400 or API key / version errors)
            if (httpCode == 400 ||
                topLevelError?.optInt("code") == 400 ||
                DEPRECATED_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return ClientDeprecated
            }

            // Fallback categorization based on HTTP codes
            return when (httpCode) {
                429 -> RateLimited
                403 -> IpBlocked
                400 -> ClientDeprecated
                404 -> VideoGone
                200 -> {
                    // A 200 + UNPLAYABLE is far more often a per-video condition
                    // (premium, members-only, ended livestream, embed-disabled)
                    // than an IP block. Declaring IpBlocked here marks the whole
                    // network path failed and trips the chain short-circuit for
                    // what is really one unplayable track, so default to
                    // VideoGone and let repeated 403/429s prove a real block.
                    if (status == "UNPLAYABLE" || status == "ERROR") VideoGone else RateLimited
                }
                else -> RateLimited
            }
        }
    }
}
