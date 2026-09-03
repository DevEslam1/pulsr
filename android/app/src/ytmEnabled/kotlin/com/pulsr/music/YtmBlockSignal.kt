package com.pulsr.music

import org.json.JSONObject

/**
 * Layer 2: Precise Block Signals for YouTube Music Innertube API.
 *
 * Categorizes YouTube failure modes into 8 discrete, actionable signals.
 */
enum class YtmBlockSignal(val code: String) {
    RateLimited("RATE_LIMITED"),
    IpBlocked("IP_BLOCKED"),
    BotChallenge("BOT_CHALLENGE"),
    PoTokenInvalid("PO_TOKEN_INVALID"),
    ClientDeprecated("CLIENT_DEPRECATED"),
    GeoBlocked("GEO_BLOCKED"),
    SignInRequired("SIGN_IN_REQUIRED"),
    VideoGone("VIDEO_GONE");

    companion object {
        private val BOT_SUBSTRINGS = listOf(
            "not a bot",
            "robot",
            "recaptcha",
            "confirm you're not a bot",
            "confirm that you're not a bot",
            "sign in to confirm",
            "confirm you are not",
            "confirm you are a human",
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
            "unavailable in your location"
        )

        private val GONE_SUBSTRINGS = listOf(
            "video unavailable",
            "removed by the user",
            "private video",
            "video has been removed",
            "deleted",
            "terms of service",
            "no longer available",
            "does not exist"
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

            // 3. Client Deprecated (HTTP 400 or API key / version errors)
            if (httpCode == 400 ||
                topLevelError?.optInt("code") == 400 ||
                DEPRECATED_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return ClientDeprecated
            }

            // 4. PoToken Invalid (403 on stream URL / empty adaptiveFormats with 200)
            if (combinedReasons.contains("potoken") ||
                combinedReasons.contains("po_token_invalid") ||
                combinedReasons.contains("integrity token") ||
                combinedReasons.contains("token_expired") ||
                (httpCode == 200 && status == "OK" && combinedReasons.contains("empty_adaptive_formats"))) {
                return PoTokenInvalid
            }

            // 5. Geo Blocked
            if (status == "UNPLAYABLE" && GEO_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return GeoBlocked
            }
            if (GEO_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return GeoBlocked
            }

            // 6. Video Gone / Removed / Private
            if (status == "ERROR" ||
                status == "UNPLAYABLE" && GONE_SUBSTRINGS.any { combinedReasons.contains(it) } ||
                httpCode == 404 ||
                GONE_SUBSTRINGS.any { combinedReasons.contains(it) }) {
                return VideoGone
            }

            // 7. Sign In Required (legitimate auth requirement without bot flags)
            if (status == "LOGIN_REQUIRED" ||
                combinedReasons.contains("login_required") ||
                combinedReasons.contains("sign in to access") ||
                combinedReasons.contains("authentication required")) {
                return SignInRequired
            }

            // 8. IP Blocked (403 without bot wording, or general access denied)
            if (httpCode == 403 ||
                combinedReasons.contains("forbidden") ||
                combinedReasons.contains("access denied") ||
                combinedReasons.contains("ip blocked")) {
                return IpBlocked
            }

            // Fallback categorization based on HTTP codes
            return when (httpCode) {
                429 -> RateLimited
                403 -> IpBlocked
                400 -> ClientDeprecated
                404 -> VideoGone
                else -> RateLimited
            }
        }
    }
}
