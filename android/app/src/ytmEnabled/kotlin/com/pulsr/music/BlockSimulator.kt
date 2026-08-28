package com.pulsr.music

import org.json.JSONArray
import org.json.JSONObject

/**
 * Phase 0 & 1: BlockSimulator Test Harness.
 *
 * Provides fixture responses for all 8 failure signals.
 * Injectable at the InnertubeClient / network abstraction layer.
 */
object BlockSimulator {

    fun fixtureRateLimited(): FixtureResponse {
        return FixtureResponse(
            httpCode = 429,
            headers = mapOf("Retry-After" to "45"),
            body = """{"error":{"code":429,"message":"Too Many Requests","status":"RESOURCE_EXHAUSTED"}}"""
        )
    }

    fun fixtureIpBlocked(): FixtureResponse {
        return FixtureResponse(
            httpCode = 403,
            headers = emptyMap(),
            body = """{"error":{"code":403,"message":"Your IP address has been blocked due to suspicious activity","status":"PERMISSION_DENIED"}}"""
        )
    }

    fun fixtureBotChallenge(): FixtureResponse {
        val playability = JSONObject().apply {
            put("status", "LOGIN_REQUIRED")
            put("reason", "Sign in to confirm you're not a bot")
            put("errorScreen", JSONObject().apply {
                put("playerErrorMessageRenderer", JSONObject().apply {
                    put("subreason", JSONObject().put("simpleText", "This helps protect our community. Learn more"))
                })
            })
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixturePoTokenInvalid(): FixtureResponse {
        val playability = JSONObject().apply {
            put("status", "OK")
        }
        val streamingData = JSONObject().apply {
            put("adaptiveFormats", JSONArray()) // Empty adaptiveFormats with 200 OK
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
            put("streamingData", streamingData)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixtureClientDeprecated(): FixtureResponse {
        val root = JSONObject().apply {
            put("error", JSONObject().apply {
                put("code", 400)
                put("message", "API key not valid. Please pass a valid API key or client version is no longer supported.")
                put("status", "INVALID_ARGUMENT")
            })
        }
        return FixtureResponse(
            httpCode = 400,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixtureGeoBlocked(): FixtureResponse {
        val playability = JSONObject().apply {
            put("status", "UNPLAYABLE")
            put("reason", "The uploader has not made this video available in your country.")
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixtureSignInRequired(): FixtureResponse {
        val playability = JSONObject().apply {
            put("status", "LOGIN_REQUIRED")
            put("reason", "This video is private. Sign in to access your purchased content.")
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixtureVideoGone(): FixtureResponse {
        val playability = JSONObject().apply {
            put("status", "ERROR")
            put("reason", "This video has been removed by the user.")
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    fun fixtureValidPlayer(videoId: String = "dQw4w9WgXcQ"): FixtureResponse {
        val format = JSONObject().apply {
            put("itag", 140)
            put("mimeType", "audio/mp4; codecs=\"mp4a.40.2\"")
            put("bitrate", 128000)
            put("approxDurationMs", "213000")
            put("url", "https://rr1---sn-fake.googlevideo.com/videoplayback?expire=123&id=$videoId&itag=140")
        }
        val playability = JSONObject().apply {
            put("status", "OK")
        }
        val streamingData = JSONObject().apply {
            put("adaptiveFormats", JSONArray().put(format))
        }
        val videoDetails = JSONObject().apply {
            put("videoId", videoId)
            put("title", "Never Gonna Give You Up")
            put("author", "Rick Astley")
        }
        val root = JSONObject().apply {
            put("playabilityStatus", playability)
            put("streamingData", streamingData)
            put("videoDetails", videoDetails)
        }
        return FixtureResponse(
            httpCode = 200,
            headers = emptyMap(),
            body = root.toString()
        )
    }

    data class FixtureResponse(
        val httpCode: Int,
        val headers: Map<String, String>,
        val body: String
    ) {
        val json: JSONObject? get() = runCatching { JSONObject(body) }.getOrNull()
    }
}
