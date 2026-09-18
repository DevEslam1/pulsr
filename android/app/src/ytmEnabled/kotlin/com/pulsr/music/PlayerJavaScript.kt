package com.pulsr.music

import android.util.Log
import org.schabi.newpipe.extractor.services.youtube.YoutubeJavaScriptPlayerManager

/**
 * Player-JS deciphering (signatureCipher `s` + throttling `n`) backed by
 * NewPipeExtractor's Rhino engine.
 *
 * Background: [JsDecipherCache] modelled a signature as a short list of
 * `reverse`/`splice`/`swap` steps and nothing in production ever called
 * `putRules()`. Real YouTube ciphers are obfuscated JavaScript functions, so
 * every ciphered format was discarded ("No cached decipher rules for player
 * hash default") and only clients that happened to return a direct URL could
 * play. [YoutubeJavaScriptPlayerManager] fetches base.js, extracts the actual
 * functions and executes them in Rhino — the same path NewPipe's own extractor
 * uses, so it tracks YouTube's changes without a second implementation here.
 *
 * All calls are serialized: the manager keeps mutable static caches and Rhino
 * contexts are not thread-safe. The first call pays a base.js download plus a
 * JS parse (a few hundred ms to a couple of seconds); every later call reuses
 * the extracted function source.
 */
internal object PlayerJavaScript {
    private const val TAG = "PlayerJavaScript"

    /**
     * NewPipe ignores this argument on its primary path (it re-derives the
     * base.js URL from `iframe_api`). It is kept so the manager's embed-watch
     * fallback, which builds `.../embed/<arg>`, receives the real video URL when
     * we happen to know it. A base.js URL is also accepted.
     */
    @Volatile
    private var playerUrl: String = ""

    private val lock = Any()

    /** Best-effort record of the player URL from a `/player` response `assets.js`. */
    fun rememberPlayerUrlFromAssets(assetsJs: String?) {
        if (assetsJs.isNullOrBlank()) return
        val absolute = when {
            assetsJs.startsWith("http") -> assetsJs
            assetsJs.startsWith("/") -> "https://www.youtube.com$assetsJs"
            else -> "https://www.youtube.com/$assetsJs"
        }
        if (absolute != playerUrl) {
            playerUrl = absolute
            Log.d(TAG, "Player JS URL set from assets: $absolute")
        }
    }

    /** Deobfuscates a `signatureCipher` `s` value. Null when it cannot be done. */
    fun decipherSignature(signature: String): String? = synchronized(lock) {
        try {
            val deciphered: String? =
                YoutubeJavaScriptPlayerManager.deobfuscateSignature(playerUrl, signature)
            deciphered?.takeIf { it.isNotEmpty() }
        } catch (t: Throwable) {
            val msg = t.message ?: ""
            if (msg.contains("Could not parse deobfuscation function")) {
                Log.w(TAG, "Signature decipher failed: Could not parse deobfuscation function from playerUrl: $playerUrl")
                fallbackDecipher(signature)
            } else {
                Log.w(TAG, "Signature decipher failed: $msg (playerUrl: $playerUrl)")
                null
            }
        }
    }

    private fun fallbackDecipher(signature: String): String? {
        if (playerUrl.isEmpty()) return null
        return try {
            val js = java.net.URL(playerUrl).readText()
            
            // Broader regex pattern to find the decipher function name
            val funcNameRegex = Regex("""\b[a-zA-Z0-9${'$'}]+\s*&&\s*[a-zA-Z0-9${'$'}]+\.set\(\s*['"]signature['"]\s*,\s*([a-zA-Z0-9${'$'}]+)\s*\(""")
            var funcName = funcNameRegex.find(js)?.groupValues?.get(1)
            
            if (funcName == null) {
                val altRegex = Regex("""([a-zA-Z0-9${'$'}]+)\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\)""")
                funcName = altRegex.find(js)?.groupValues?.get(1)
            }

            if (funcName != null) {
                Log.i(TAG, "Fallback extracted function name: $funcName")
                val escapedFuncName = Regex.escape(funcName)
                
                // Extract body
                val bodyRegex = Regex("""(?:$escapedFuncName\s*=\s*function\([^)]*\)\s*\{|$escapedFuncName:\s*function\([^)]*\)\s*\{)(.*?)\}""")
                val bodyMatch = bodyRegex.find(js)
                if (bodyMatch != null) {
                    val body = bodyMatch.groupValues[1]
                    val objNameMatch = Regex("""([a-zA-Z0-9${'$'}]+)\.[a-zA-Z0-9${'$'}]+\(\s*a\s*,\s*\d+\s*\)""").find(body)
                    if (objNameMatch != null) {
                        val objName = objNameMatch.groupValues[1]
                        val objEscaped = Regex.escape(objName)
                        
                        val objDefRegex = Regex("""var\s+$objEscaped\s*=\s*\{(.*?)\}\s*;""", RegexOption.DOT_MATCHES_ALL)
                        val objDefMatch = objDefRegex.find(js)
                        if (objDefMatch != null) {
                            val objDef = objDefMatch.groupValues[1]
                            val reverseName = Regex("""([a-zA-Z0-9${'$'}]+)\s*:\s*function\([^)]*\)\s*\{\s*[^}]*reverse\(\)""").find(objDef)?.groupValues?.get(1)
                            val spliceName = Regex("""([a-zA-Z0-9${'$'}]+)\s*:\s*function\([^)]*\)\s*\{\s*[^}]*splice\(""").find(objDef)?.groupValues?.get(1)
                            val swapName = Regex("""([a-zA-Z0-9${'$'}]+)\s*:\s*function\([^)]*\)\s*\{\s*[^}]*c\[0\]\s*=""").find(objDef)?.groupValues?.get(1)
                            
                            val steps = mutableListOf<String>()
                            val callsRegex = Regex("""$objEscaped\.([a-zA-Z0-9${'$'}]+)\(\s*a\s*,\s*(\d+)\s*\)""")
                            for (call in callsRegex.findAll(body)) {
                                val method = call.groupValues[1]
                                val arg = call.groupValues[2]
                                when (method) {
                                    reverseName -> steps.add("reverse")
                                    spliceName -> steps.add("splice:$arg")
                                    swapName -> steps.add("swap:$arg")
                                }
                            }
                            
                            if (steps.isNotEmpty()) {
                                Log.i(TAG, "Fallback decipher parsed steps: $steps")
                                return JsDecipherCache().applyTransforms(signature, steps)
                            }
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "Fallback decipher failed: ${e.message}")
            null
        }
    }

    /**
     * Returns [url] with its throttling `n` parameter transformed. Null when the
     * transform is unavailable, so the caller can keep the original URL.
     */
    fun deobfuscateN(url: String): String? = synchronized(lock) {
        try {
            val deobfuscated: String? = YoutubeJavaScriptPlayerManager
                .getUrlWithThrottlingParameterDeobfuscated(playerUrl, url)
            deobfuscated?.takeIf { it.isNotEmpty() }
        } catch (t: Throwable) {
            Log.w(TAG, "n-parameter deobfuscation failed: ${t.message}")
            null
        }
    }

    /** `signatureTimestamp` (STS) for the current base.js, or null. */
    fun signatureTimestamp(): Int? = synchronized(lock) {
        try {
            YoutubeJavaScriptPlayerManager.getSignatureTimestamp(playerUrl)
        } catch (t: Throwable) {
            Log.w(TAG, "signatureTimestamp extraction failed: ${t.message}")
            null
        }
    }

    /** Drops NewPipe's static player-JS caches (call on network/egress change). */
    fun clearCaches() {
        synchronized(lock) {
            try {
                YoutubeJavaScriptPlayerManager.clearAllCaches()
            } catch (t: Throwable) {
                Log.w(TAG, "clearAllCaches failed: ${t.message}")
            }
        }
    }
}
