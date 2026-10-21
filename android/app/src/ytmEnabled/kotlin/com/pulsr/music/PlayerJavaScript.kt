package com.pulsr.music

import android.content.Context
import android.util.Log
import org.schabi.newpipe.extractor.services.youtube.YoutubeJavaScriptPlayerManager
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Player-JS deciphering (signatureCipher `s` + throttling `n`) backed by
 * NewPipeExtractor's Rhino engine with a robust native deobfuscation engine fallback.
 *
 * Background: Modern YouTube players (2025/2026) use bytecode/VM structures and
 * an internal string array table ("Nu = '...'.split(';')") with XOR dynamic dispatch,
 * which older regex parsers (including NewPipeExtractor v0.26.5) fail to match, throwing
 * "Could not parse deobfuscation function". This class handles modern, legacy, and pinned
 * player formats with zero-delay in-memory caching and persistent JsDecipherCache integration.
 */
internal object PlayerJavaScript {
    private const val TAG = "PlayerJavaScript"

    // Pinned modern base.js URL as safety anchor
    private const val PINNED_PLAYER_URL =
        "https://www.youtube.com/s/player/67288f35/player_ias.vflset/en_US/base.js"

    // High-reliability offline fallback decipher rules matching modern player_ias.vflset builds.
    private val DEFAULT_FALLBACK_STEPS = listOf(
        "swap:62",
        "splice:2",
        "swap:54",
        "reverse",
        "splice:2",
        "reverse",
        "swap:1",
        "splice:2"
    )
    private const val DEFAULT_STS = 20744

    @Volatile
    private var playerUrl: String = ""

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var cachedJs: String? = null

    @Volatile
    private var cachedSteps: List<String>? = null

    @Volatile
    private var cachedStepsExtracted: Boolean = false

    @Volatile
    private var cachedSts: Int? = null

    private val lock = Any()
    private val warmUpInProgress = AtomicBoolean(false)

    private val N_PARAM_REGEX = Regex("""[?&]n=([^&#]*)""")

    private fun logD(tag: String, msg: String) {
        try {
            Log.d(tag, msg)
        } catch (_: Throwable) {
            println("[$tag] DEBUG: $msg")
        }
    }

    private fun logI(tag: String, msg: String) {
        try {
            Log.i(tag, msg)
        } catch (_: Throwable) {
            println("[$tag] INFO: $msg")
        }
    }

    private fun logW(tag: String, msg: String) {
        try {
            Log.w(tag, msg)
        } catch (_: Throwable) {
            System.err.println("[$tag] WARN: $msg")
        }
    }

    fun init(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
    }

    /** Best-effort record of the player URL from a `/player` response `assets.js`. */
    fun rememberPlayerUrlFromAssets(assetsJs: String?) {
        if (assetsJs.isNullOrBlank()) return
        val absolute = when {
            assetsJs.startsWith("http") -> assetsJs
            assetsJs.startsWith("/") -> "https://www.youtube.com$assetsJs"
            else -> "https://www.youtube.com/$assetsJs"
        }
        // Guard: Do not overwrite desktop player_ias.vflset with mobile/plasma player
        if (playerUrl.contains("player_ias.vflset") && !absolute.contains("player_ias.vflset")) {
            return
        }
        if (absolute != playerUrl) {
            val oldHash = playerHashFromUrl(playerUrl)
            val newHash = playerHashFromUrl(absolute)
            playerUrl = absolute
            if (oldHash != null && oldHash != newHash) {
                synchronized(lock) {
                    cachedSteps = null
                    cachedStepsExtracted = false
                    cachedJs = null
                    cachedSts = null
                    appContext?.let { ctx ->
                        runCatching { JsDecipherCache.getInstance(ctx).clearRules("default") }
                    }
                }
            }
            logD(TAG, "Player JS URL set from assets: $absolute")
        }
    }

    private fun playerHashFromUrl(url: String): String? =
        Regex("""/s/player/([a-zA-Z0-9_-]+)/""").find(url)?.groupValues?.get(1)

    /**
     * Proactively fetches the YouTube player base.js URL and warms up decipher rules.
     */
    fun warmUp(context: Context? = null) {
        context?.let { init(it) }
        if (!warmUpInProgress.compareAndSet(false, true)) return // already running
        try {
            val fetchedUrl = fetchPlayerUrlFromIframeApi()
            if (!fetchedUrl.isNullOrEmpty()) {
                rememberPlayerUrlFromAssets(fetchedUrl)
            } else if (playerUrl.isEmpty()) {
                playerUrl = PINNED_PLAYER_URL
            }

            // Proactively parse and cache steps into memory and JsDecipherCache
            parseAndCacheSteps()

            // Also trigger NewPipe to warm up STS in Rhino if possible
            synchronized(lock) {
                try {
                    YoutubeJavaScriptPlayerManager.getSignatureTimestamp(playerUrl)
                    logI(TAG, "Player JS warmed up successfully from $playerUrl")
                } catch (t: Throwable) {
                    logW(TAG, "Player JS warm-up parse failed (non-fatal): ${t.message}")
                }
            }
        } catch (t: Throwable) {
            logW(TAG, "Player JS warm-up failed (non-fatal): ${t.message}")
        } finally {
            warmUpInProgress.set(false)
        }
    }

    private fun fetchPlayerUrlFromIframeApi(): String? {
        return try {
            val conn = java.net.URL("https://www.youtube.com/iframe_api").openConnection()
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            val iframeHtml = conn.getInputStream().bufferedReader().use { it.readText() }
            val srcPatterns = listOf(
                Regex("""(/s/player/[a-zA-Z0-9_-]+/player_ias\.vflset/[^"'\s/]+/base\.js)"""),
                Regex("""src=[\"'](/s/player/[^\"']+/base\.js)[\"']"""),
                Regex("""\"PLAYER_JS_URL\":\s*\"(/s/player/[^\"]+/base\.js)\""""),
                Regex("""\"jsUrl\":\"(/s/player/[^\"]+/base\.js)\""""),
                Regex("""(/s/player/[a-zA-Z0-9_-]+/(?:player_ias\.vflset/[^\"'\s/]+|base)\.js)""")
            )
            for (pattern in srcPatterns) {
                val match = pattern.find(iframeHtml)
                if (match != null) {
                    val path = match.groupValues[1].replace("player_es6.vflset", "player_ias.vflset")
                    logD(TAG, "Player JS path from iframe_api: $path")
                    return "https://www.youtube.com$path"
                }
            }
            val widgetVersion = Regex("""/s/player/([a-zA-Z0-9_-]+)/www-widgetapi\.vflset/""")
                .find(iframeHtml)?.groupValues?.get(1)
            if (!widgetVersion.isNullOrEmpty()) {
                val path = "/s/player/$widgetVersion/player_ias.vflset/en_US/base.js"
                logD(TAG, "Derived player JS path from widget API version: $path")
                return "https://www.youtube.com$path"
            }
            fetchPlayerUrlFromWatchPage()
        } catch (t: Throwable) {
            logW(TAG, "fetchPlayerUrlFromIframeApi failed: ${t.message}")
            fetchPlayerUrlFromWatchPage()
        }
    }

    private fun fetchPlayerUrlFromWatchPage(): String? {
        return try {
            val conn = java.net.URL("https://www.youtube.com/watch?v=dQw4w9WgXcQ").openConnection()
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
            )
            conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
            val html = conn.getInputStream().bufferedReader().use { it.readText() }
            val patterns = listOf(
                Regex("""(/s/player/[a-zA-Z0-9_-]+/player_ias\.vflset/[^"'\s/]+/base\.js)"""),
                Regex("""(/s/player/[a-f0-9]+/player_ias\.vflset/[^/]+/base\.js)"""),
                Regex("""\"jsUrl\":\"(/s/player/[^\"]+/base\.js)\""""),
                Regex("""\"PLAYER_JS_URL\":\s*\"(/s/player/[^\"]+/base\.js)\""""),
                Regex("""src=[\"'](/s/player/[^\"']+/base\.js)[\"']""")
            )
            for (regex in patterns) {
                val m = regex.find(html)
                if (m != null) {
                    val path = m.groupValues[1].replace("player_es6.vflset", "player_ias.vflset")
                    logD(TAG, "Player JS path from watch page: $path")
                    return "https://www.youtube.com$path"
                }
            }
            PINNED_PLAYER_URL
        } catch (t: Throwable) {
            logW(TAG, "fetchPlayerUrlFromWatchPage failed: ${t.message}")
            PINNED_PLAYER_URL
        }
    }

    /** Deobfuscates a `signatureCipher` `s` value. */
    fun decipherSignature(signature: String): String? = synchronized(lock) {
        // Fast path: only extracted (not fallback) rules are trusted for direct use.
        cachedSteps?.let { steps ->
            if (cachedStepsExtracted && steps.isNotEmpty()) {
                return JsDecipherCache().applyTransforms(signature, steps)
            }
        }

        if (playerUrl.isEmpty()) {
            val fetched = try { fetchPlayerUrlFromIframeApi() } catch (_: Throwable) { null }
            playerUrl = if (!fetched.isNullOrEmpty()) fetched else PINNED_PLAYER_URL
            logI(TAG, "Player JS URL initialized: $playerUrl")
        }

        // Prefer the parser for the current player format over NewPipe 0.26.5's
        // older heuristics. NewPipe is still used as a fallback when extraction
        // fails, so a future player format can still resolve through its engine.
        val nativeSteps = parseAndCacheSteps()
        if (cachedStepsExtracted && nativeSteps.isNotEmpty()) {
            return JsDecipherCache().applyTransforms(signature, nativeSteps)
        }

        try {
            val deciphered: String? =
                YoutubeJavaScriptPlayerManager.deobfuscateSignature(playerUrl, signature)
            if (!deciphered.isNullOrEmpty()) {
                return deciphered
            }
        } catch (t: Throwable) {
            val msg = t.message ?: ""
            logW(TAG, "NewPipe signature decipher failed: $msg. Falling back to native deobfuscator...")
        }

        fallbackDecipher(signature)
    }

    private fun parseAndCacheSteps(): List<String> {
        cachedSteps?.let { return it }

        val targetUrl = playerUrl.ifEmpty { PINNED_PLAYER_URL }
        val js = cachedJs ?: try {
            val conn = java.net.URL(targetUrl).openConnection()
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
            )
            conn.getInputStream().bufferedReader().use { it.readText() }.also { cachedJs = it }
        } catch (e: Throwable) {
            logW(TAG, "Could not fetch base.js for parsing: ${e.message}")
            null
        }

        var steps: List<String>? = null
        if (!js.isNullOrEmpty()) {
            steps = extractModernDecipherSteps(js)
            if (steps == null) {
                steps = extractLegacyDecipherSteps(js)
            }
            // Extract and cache STS as well
            if (cachedSts == null) {
                val stsMatch = Regex("""signatureTimestamp:\s*(\d+)""").find(js)
                stsMatch?.groupValues?.get(1)?.toIntOrNull()?.let {
                    cachedSts = it
                    logD(TAG, "Extracted signatureTimestamp: $it")
                }
            }
        }

        val extracted = steps
        val resolvedSteps = if (!extracted.isNullOrEmpty()) {
            logI(TAG, "Decipher rules extracted successfully (${extracted.size} steps): $extracted")
            extracted
        } else {
            logW(TAG, "Could not extract decipher rules from JS. Using default fallback steps: $DEFAULT_FALLBACK_STEPS")
            DEFAULT_FALLBACK_STEPS
        }

        cachedSteps = resolvedSteps
        cachedStepsExtracted = !extracted.isNullOrEmpty()

        if (!extracted.isNullOrEmpty()) {
            appContext?.let { ctx ->
                runCatching {
                    JsDecipherCache.getInstance(ctx).putRules("default", resolvedSteps)
                }
            }
        }

        return resolvedSteps
    }

    private fun fallbackDecipher(signature: String): String {
        val steps = cachedSteps ?: synchronized(lock) {
            cachedSteps ?: parseAndCacheSteps()
        }
        val activeSteps = if (!steps.isNullOrEmpty()) steps else DEFAULT_FALLBACK_STEPS
        return JsDecipherCache().applyTransforms(signature, activeSteps)
    }

    internal fun extractModernDecipherSteps(js: String): List<String>? {
        return try {
            // 1. Locate string table Nu
            val sigIdx = js.indexOf("signatureCipher")
            if (sigIdx == -1) return null
            val splitMarker = ".split(\""
            val splitCall = js.indexOf(splitMarker, sigIdx)
            if (splitCall == -1) return null
            val separatorStart = splitCall + splitMarker.length
            val separatorEnd = js.indexOf("\")", separatorStart)
            if (separatorEnd == -1) return null
            val separator = js.substring(separatorStart, separatorEnd)
            if (separator.isEmpty()) return null
            val quoteEnd = splitCall - 1
            val prefix = js.substring(0, sigIdx)
            val assignRegex = Regex("""[;\n]\s*([a-zA-Z0-9$]+)\s*=\s*\"""")
            val allAssigns = assignRegex.findAll(prefix).toList()
            if (allAssigns.isEmpty()) return null
            val lastAssign = allAssigns.last()
            val nuVar = lastAssign.groupValues[1]
            val quoteStart = lastAssign.range.last + 1
            if (quoteStart >= quoteEnd) return null
            val nuRaw = js.substring(quoteStart, quoteEnd)
            val nu = nuRaw.split(separator)

            // 2. Locate signature call: e.g. .s){var ... l=P1(19,1204,qE(61,7141,k.s))
            val callRegex = Regex("""\.s\)\{var\s+[^=]+=\s*[^,]+,\s*[^=]+=\s*[^,]+,\s*([a-zA-Z0-9$]+)\s*=\s*([a-zA-Z0-9$]+)\((\d+),(\d+)""")
            val callMatch = callRegex.find(js) ?: return null
            val funcName = callMatch.groupValues[2]
            val nVal = callMatch.groupValues[3].toInt()
            val lVal = callMatch.groupValues[4].toInt()
            val cVal = lVal xor nVal

            // 3. Locate funcName definition: funcName=function(N,L,v,a){...return r}
            val defRegex = Regex(
                """${Regex.escape(funcName)}\s*=\s*function\s*\([^)]*\)\s*\{(.*?return\s+[a-zA-Z0-9$]+[^}]*)\}""",
                RegexOption.DOT_MATCHES_ALL
            )
            val nuEsc = Regex.escape(nuVar)
            var stepMatches: List<MatchResult> = emptyList()
            for (defMatch in defRegex.findAll(js)) {
                val funcBody = defMatch.groupValues[1]
                val eVar = Regex("""\bvar\s+([a-zA-Z0-9$]+)\s*=\s*[a-zA-Z0-9$]+\s*\^\s*[a-zA-Z0-9$]+""")
                    .find(funcBody)?.groupValues?.get(1) ?: continue
                val cVar = Regex.escape(eVar)
                val stepCallsRegex = Regex(
                    """([a-zA-Z0-9$]+)\[$nuEsc\[(?:$cVar\^(\d+)|(\d+))\]\]\(\s*[a-zA-Z0-9$]+(?:\s*,\s*(?:$cVar\^(\d+)|(\d+)))?\s*\)"""
                )
                val matches = stepCallsRegex.findAll(funcBody).toList()
                if (matches.isNotEmpty()) {
                    stepMatches = matches
                    break
                }
            }
            if (stepMatches.isEmpty()) return null

            var helperObjName: String? = null
            data class RawStep(val opName: String, val arg: Int?)
            val rawSteps = mutableListOf<RawStep>()
            for (m in stepMatches) {
                val obj = m.groupValues[1]
                if (helperObjName == null) {
                    helperObjName = obj
                } else if (helperObjName != obj) {
                    return null
                }
                val cIdx = m.groupValues[2]
                val directIdx = m.groupValues[3]
                val idx = if (cIdx.isNotEmpty()) (cVal xor cIdx.toInt()) else directIdx.toInt()
                if (idx !in nu.indices) continue
                val opName = nu[idx]

                val cArg = m.groupValues[4]
                val directArg = m.groupValues[5]
                val arg = when {
                    cArg.isNotEmpty() -> cVal xor cArg.toInt()
                    directArg.isNotEmpty() -> directArg.toInt()
                    else -> null
                }
                rawSteps.add(RawStep(opName, arg))
            }

            if (helperObjName == null || rawSteps.isEmpty()) return null

            // 5. Locate helperObj definition: helperObj={...};
            val objRegex = Regex("""${Regex.escape(helperObjName)}\s*=\s*\{(.*?)\}\s*;""", RegexOption.DOT_MATCHES_ALL)
            val objMatch = objRegex.find(js) ?: return null
            val objBody = objMatch.groupValues[1]

            val revIdx = nu.indexOf("reverse")
            val spliceIdx = nu.indexOf("splice")

            val steps = mutableListOf<String>()
            for ((opName, arg) in rawSteps) {
                val methRegex = Regex("""${Regex.escape(opName)}\s*:\s*function\s*\([^\)]*\)\s*\{([^}]+)\}""")
                val methMatch = methRegex.find(objBody) ?: return null
                val code = methMatch.groupValues[1]
                when {
                    (revIdx != -1 && code.contains("$nuVar[$revIdx]")) || code.contains("reverse()") -> {
                        steps.add("reverse")
                    }
                    (spliceIdx != -1 && code.contains("$nuVar[$spliceIdx]")) || code.contains("splice(") -> {
                        steps.add("splice:${arg ?: 0}")
                    }
                    code.contains("[0]") -> {
                        steps.add("swap:${arg ?: 0}")
                    }
                    else -> return null
                }
            }
            if (steps.size == rawSteps.size) steps else null
        } catch (t: Throwable) {
            logW(TAG, "extractModernDecipherSteps failed: ${t.message}")
            null
        }
    }

    internal fun extractLegacyDecipherSteps(js: String): List<String>? {
        return try {
            val funcNameRegex = Regex("""(?:\b[a-zA-Z0-9${'$'}]+\s*&&\s*)?[a-zA-Z0-9${'$'}]+\.set\(\s*['"]signature['"]\s*,\s*([a-zA-Z0-9${'$'}]+)\s*\(""")
            var funcName = funcNameRegex.find(js)?.groupValues?.get(1)

            if (funcName == null) {
                val altRegex = Regex("""([a-zA-Z0-9${'$'}]+\s*=\s*function\(\s*a\s*\)\s*\{\s*a\s*=\s*a\.split\(\s*""\s*\))""")
                funcName = altRegex.find(js)?.groupValues?.get(1)
            }

            if (funcName != null) {
                val escapedFuncName = Regex.escape(funcName)
                val bodyRegex = Regex("""(?:$escapedFuncName\s*=\s*function\([^)]*\)\s*\{|$escapedFuncName:\s*function\([^)]*\)\s*\{)(.*?)\}""", RegexOption.DOT_MATCHES_ALL)
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
                            val swapName = Regex("""([a-zA-Z0-9${'$'}]+)\s*:\s*function\([^)]*\)\s*\{\s*[^}]*[a-zA-Z0-9${'$'}]+\s*\[0\]\s*=""").find(objDef)?.groupValues?.get(1)

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
                            if (steps.isNotEmpty()) return steps
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            logW(TAG, "extractLegacyDecipherSteps failed: ${e.message}")
            null
        }
    }

    /**
     * Returns [url] with its throttling `n` parameter transformed. Null when the
     * transform is unavailable — an untransformed-`n` URL is answered with 403 by
     * googlevideo, so callers must discard the URL rather than keep it.
     */
    fun deobfuscateN(url: String): String? = synchronized(lock) {
        try {
            val deobfuscated: String? = YoutubeJavaScriptPlayerManager
                .getUrlWithThrottlingParameterDeobfuscated(playerUrl, url)
            if (deobfuscated.isNullOrEmpty()) return@synchronized null

            // NewPipe's n-function heuristics can latch onto an unrelated helper
            // whose call is a silent identity (observed: it selected a URL
            // normaliser that returns its input). The "transformed" URL then
            // still carries the original `n`, googlevideo answers every fetch
            // with 403, and nothing anywhere raises. Detect the identity result
            // so the failure is at least visible in logs instead of presenting
            // as a perfect transform.
            val before = N_PARAM_REGEX.find(url)?.groupValues?.get(1)
            val after = N_PARAM_REGEX.find(deobfuscated)?.groupValues?.get(1)
            if (before != null && before == after) {
                logW(TAG, "n-parameter deobfuscation produced an identity result; treating as unavailable")
                return@synchronized null
            }
            deobfuscated
        } catch (t: Throwable) {
            logW(TAG, "n-parameter deobfuscation failed: ${t.message}")
            null
        }
    }

    /** `signatureTimestamp` (STS) for the current base.js, or null. */
    fun signatureTimestamp(): Int? = synchronized(lock) {
        cachedSts?.let { return it }
        try {
            val sts = YoutubeJavaScriptPlayerManager.getSignatureTimestamp(playerUrl)
            if (sts != null && sts > 0) {
                cachedSts = sts
                return sts
            }
        } catch (t: Throwable) {
            logW(TAG, "signatureTimestamp extraction failed: ${t.message}")
        }
        val js = cachedJs ?: try {
            val targetUrl = playerUrl.ifEmpty { PINNED_PLAYER_URL }
            java.net.URL(targetUrl).readText().also { cachedJs = it }
        } catch (_: Throwable) { null }

        if (js != null) {
            val m = Regex("""signatureTimestamp:\s*(\d+)""").find(js)
            val parsed = m?.groupValues?.get(1)?.toIntOrNull()
            if (parsed != null) {
                cachedSts = parsed
                return parsed
            }
        }
        return DEFAULT_STS
    }

    /** Drops NewPipe's static player-JS caches (call on network/egress change). */
    fun clearCaches() {
        synchronized(lock) {
            cachedSteps = null
            cachedStepsExtracted = false
            cachedJs = null
            cachedSts = null
            try {
                YoutubeJavaScriptPlayerManager.clearAllCaches()
            } catch (t: Throwable) {
                logW(TAG, "clearAllCaches failed: ${t.message}")
            }
        }
    }
}
