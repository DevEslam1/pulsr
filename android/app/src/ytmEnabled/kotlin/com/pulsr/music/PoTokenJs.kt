package com.pulsr.music

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reshapes the raw challenge from the BotGuard `Create` endpoint into a JSON object
 * that can be embedded straight into a JavaScript snippet.
 *
 * Fields the injected script never reads are carried through anyway to stay close
 * to NewPipe's upstream shape, since this whole subsystem has to be re-synced
 * whenever YouTube changes BotGuard.
 */
internal fun parseChallengeData(rawChallengeData: String): String {
    val scrambled = JSONArray(rawChallengeData)
    val challengeData = if (scrambled.length() > 1 && scrambled.opt(1) is String) {
        JSONArray(descramble(scrambled.getString(1)))
    } else {
        scrambled.getJSONArray(0)
    }

    val interpreterJavascript = JSONObject()
        .putOpt(
            "privateDoNotAccessOrElseSafeScriptWrappedValue",
            firstStringIn(challengeData.optJSONArray(1)),
        )
        .putOpt(
            "privateDoNotAccessOrElseTrustedResourceUrlWrappedValue",
            firstStringIn(challengeData.optJSONArray(2)),
        )

    return JSONObject()
        .put("messageId", challengeData.optString(0))
        .put("interpreterJavascript", interpreterJavascript)
        .put("interpreterHash", challengeData.optString(3))
        .put("program", challengeData.getString(4))
        .put("globalName", challengeData.getString(5))
        .put("clientExperimentsStateBlob", challengeData.optString(7))
        .toString()
}

/**
 * Splits the raw `GenerateIT` response into the integrity token, as a JavaScript
 * `Uint8Array` literal, and its lifetime in seconds.
 *
 * Handles both protobuf JSON variants:
 * - Direct token at index 0: `[ "token", ttlSecs, ... ]`
 * - Websafe fallback at index 3: `[ null, ttlSecs, null, "token" ]`
 */
internal fun parseIntegrityTokenData(rawIntegrityTokenData: String): Pair<String, Long> {
    val data = JSONArray(rawIntegrityTokenData)
    val tokenStr = when {
        !data.isNull(0) && data.optString(0).isNotBlank() -> data.getString(0)
        !data.isNull(3) && data.optString(3).isNotBlank() -> data.getString(3)
        else -> firstStringIn(data) ?: throw PoTokenException("No integrity token found in GenerateIT response: $rawIntegrityTokenData")
    }
    val ttl = when {
        !data.isNull(1) -> data.getLong(1)
        else -> 43200L // Default 12 hours
    }
    return base64ToU8(tokenStr) to ttl
}


/** Renders [identifier] as a JavaScript `Uint8Array` literal. */
internal fun stringToU8(identifier: String): String = newUint8Array(identifier.toByteArray())

/**
 * Converts the output of JavaScript's `Uint8Array::toString()` — byte values joined
 * by commas, e.g. "97,98,99" for "abc" — into the base64 flavour poTokens use.
 */
internal fun u8ToBase64(poToken: String): String {
    val bytes = poToken.split(",").map { it.trim().toUByte().toByte() }.toByteArray()
    return try {
        java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    } catch (_: Throwable) {
        Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
    }
}

/** The scrambled challenge is base64 with 97 subtracted from every byte. */
private fun descramble(scrambledChallenge: String): String =
    base64ToBytes(scrambledChallenge)
        .map { (it + 97).toByte() }
        .toByteArray()
        .decodeToString()

private fun base64ToU8(base64: String): String = newUint8Array(base64ToBytes(base64))

private fun newUint8Array(contents: ByteArray): String =
    contents.joinToString(separator = ",", prefix = "new Uint8Array([", postfix = "])") {
        it.toUByte().toString()
    }

private fun base64ToBytes(base64: String): ByteArray {
    val normalized = base64.replace('-', '+').replace('_', '/').replace('.', '=')
    return try {
        java.util.Base64.getDecoder().decode(normalized)
    } catch (_: Throwable) {
        try {
            Base64.decode(normalized, Base64.DEFAULT)
        } catch (e: IllegalArgumentException) {
            throw PoTokenException("Cannot base64 decode: ${e.message}")
        }
    }
}


private fun firstStringIn(array: JSONArray?): String? {
    if (array == null) return null
    for (i in 0 until array.length()) {
        val value = array.opt(i)
        if (value is String) return value
    }
    return null
}
