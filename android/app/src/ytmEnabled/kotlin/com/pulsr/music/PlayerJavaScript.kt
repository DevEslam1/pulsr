package com.pulsr.music

import android.content.Context
import android.util.Log
import org.mozilla.javascript.Context as RhinoContext
import org.mozilla.javascript.Function as RhinoFunction
import org.mozilla.javascript.Scriptable as RhinoScriptable
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

    private const val DESKTOP_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    private const val FETCH_RETRY_COOLDOWN_MS = 60_000L

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

    @Volatile
    private var rhinoNScope: RhinoScriptable? = null

    @Volatile
    private var rhinoNSolverFunc: RhinoFunction? = null

    @Volatile
    private var rhinoNSolverPlayerUrl: String? = null

    @Volatile
    private var nextFetchAttemptAt: Long = 0L

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
        val normalized = normalizePlayerUrl(assetsJs)
        if (normalized == null) {
            if (!assetsJs.isNullOrBlank()) {
                logD(TAG, "Ignoring non-desktop player JS asset: $assetsJs")
            }
            return
        }
        if (adoptPlayerUrl(normalized)) {
            logD(TAG, "Player JS URL set from assets: $normalized")
        }
    }

    /** Swaps the active player build and drops everything derived from the old one. */
    private fun adoptPlayerUrl(url: String): Boolean {
        synchronized(lock) {
            if (url == playerUrl) return false
            val previousUrl = playerUrl
            playerUrl = url
            cachedSteps = null
            cachedStepsExtracted = false
            cachedJs = null
            cachedSts = null
            rhinoNScope = null
            rhinoNSolverFunc = null
            rhinoNSolverPlayerUrl = null
            nextFetchAttemptAt = 0L
            appContext?.let { ctx ->
                val cache = JsDecipherCache.getInstance(ctx)
                runCatching { cache.clearRules("default") }
                playerHashFromUrl(previousUrl)?.let { hash ->
                    runCatching { cache.clearRules(hash) }
                }
            }
            runCatching { YoutubeJavaScriptPlayerManager.clearAllCaches() }
            return true
        }
    }

    /**
     * Normalizes an `assets.js` path to the desktop `player_ias.vflset` build.
     *
     * Modern responses usually advertise `player_es6.vflset`, whose syntax the
     * step parser historically missed and whose Rhino/NewPipe heuristics also
     * miss. Both variants share the player hash, so the desktop build is
     * equivalent for deciphering and is the one this parser supports. Mobile
     * (`player_plasma.vflset`) assets are mapped the same way; anything that is
     * not a player base.js is rejected instead of poisoning the cached URL.
     */
    internal fun normalizePlayerUrl(assetsJs: String?): String? {
        if (assetsJs.isNullOrBlank()) return null
        val absolute = when {
            assetsJs.startsWith("http") -> assetsJs
            assetsJs.startsWith("//") -> "https:$assetsJs"
            assetsJs.startsWith("/") -> "https://www.youtube.com$assetsJs"
            else -> "https://www.youtube.com/$assetsJs"
        }
        val path = absolute.substringBefore('?').substringBefore('#')
        if (!path.contains("/s/player/") || !path.endsWith("/base.js")) return null
        val desktop = absolute
            .replace("/player_es6.vflset/", "/player_ias.vflset/")
            .replace("/player_plasma.vflset/", "/player_ias.vflset/")
        return desktop.takeIf { it.substringBefore('?').contains("/player_ias.vflset/") }
    }

    private fun rulesKeyFor(url: String): String = playerHashFromUrl(url) ?: "default"

    /** Exposed so callers can address cached rules by the active player build. */
    fun currentPlayerHash(): String? = playerHashFromUrl(playerUrl)

    private fun ensurePlayerUrl() {
        if (playerUrl.isNotEmpty()) return
        val fetched = try { fetchPlayerUrlFromIframeApi() } catch (_: Throwable) { null }
        val resolved = if (!fetched.isNullOrEmpty()) fetched else PINNED_PLAYER_URL
        adoptPlayerUrl(resolved)
        logI(TAG, "Player JS URL initialized: $resolved")
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
            } else {
                ensurePlayerUrl()
            }

            // Proactively parse and cache steps into memory and JsDecipherCache
            parseAndCacheSteps()

            // Also trigger modern Rhino n-solver warmup and NewPipe STS in Rhino if possible
            synchronized(lock) {
                try {
                    ensureRhinoNSolver()
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
                val match = pattern.find(iframeHtml) ?: continue
                val candidate = normalizePlayerUrl("https://www.youtube.com${match.groupValues[1]}")
                    ?: continue
                logD(TAG, "Player JS path from iframe_api: $candidate")
                return candidate
            }
            val widgetVersion = Regex("""/s/player/([a-zA-Z0-9_-]+)/www-widgetapi\.vflset/""")
                .find(iframeHtml)?.groupValues?.get(1)
            if (!widgetVersion.isNullOrEmpty()) {
                val candidate = normalizePlayerUrl(
                    "https://www.youtube.com/s/player/$widgetVersion/player_ias.vflset/en_US/base.js"
                )
                if (candidate != null) {
                    logD(TAG, "Derived player JS path from widget API version: $candidate")
                    return candidate
                }
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
                val m = regex.find(html) ?: continue
                val candidate = normalizePlayerUrl("https://www.youtube.com${m.groupValues[1]}")
                    ?: continue
                logD(TAG, "Player JS path from watch page: $candidate")
                return candidate
            }
            PINNED_PLAYER_URL
        } catch (t: Throwable) {
            logW(TAG, "fetchPlayerUrlFromWatchPage failed: ${t.message}")
            PINNED_PLAYER_URL
        }
    }

    /**
     * Deobfuscates a `signatureCipher` `s` value. Returns null when no rule set
     * can be extracted — callers must discard the ciphered format in that case.
     */
    fun decipherSignature(signature: String): String? = synchronized(lock) {
        // Fast path: only extracted (not fallback) rules are trusted for direct use.
        cachedSteps?.let { steps ->
            if (cachedStepsExtracted && steps.isNotEmpty()) {
                return JsDecipherCache().applyTransforms(signature, steps)
            }
        }

        ensurePlayerUrl()

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
            logW(TAG, "NewPipe signature decipher failed: $msg")
        }

        // Applying guessed steps produces a signature googlevideo answers with
        // 403; that is routinely misclassified as an IP block and can trip the
        // global breaker for unrelated songs. Discarding the format instead lets
        // the caller fall through to the next client.
        logW(TAG, "Signature decipher unavailable: no extractable rules for $playerUrl")
        null
    }

    private fun ensureBaseJs(): String? {
        val current = cachedJs
        if (!current.isNullOrEmpty()) return current
        if (System.currentTimeMillis() < nextFetchAttemptAt) return null
        val targetUrl = playerUrl.ifEmpty { PINNED_PLAYER_URL }
        return try {
            val conn = java.net.URL(targetUrl).openConnection()
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("User-Agent", DESKTOP_UA)
            conn.getInputStream().bufferedReader().use { it.readText() }.also { cachedJs = it }
        } catch (e: Throwable) {
            nextFetchAttemptAt = System.currentTimeMillis() + FETCH_RETRY_COOLDOWN_MS
            logW(TAG, "Could not fetch base.js: ${e.message}")
            null
        }
    }

    private fun parseAndCacheSteps(): List<String> {
        cachedSteps?.let { steps ->
            if (cachedStepsExtracted) return steps
            // A JS body that yielded no rules fails deterministically; retry only
            // when the file could not be fetched at all, and not before cooldown.
            if (cachedJs != null || System.currentTimeMillis() < nextFetchAttemptAt) return steps
        }

        val targetUrl = playerUrl.ifEmpty { PINNED_PLAYER_URL }
        val js = ensureBaseJs()

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

        val extracted = steps?.takeIf { it.isNotEmpty() }
        if (extracted == null) {
            logW(TAG, "Could not extract decipher rules from $targetUrl; ciphered formats will be discarded until the player build changes")
        } else {
            logI(TAG, "Decipher rules extracted successfully (${extracted.size} steps): $extracted")
            appContext?.let { ctx ->
                runCatching {
                    val cache = JsDecipherCache.getInstance(ctx)
                    val rulesKey = rulesKeyFor(targetUrl)
                    cache.putRules(rulesKey, extracted)
                    cachedSts?.let { cache.putNTransform(rulesKey, emptyList(), it) }
                }
            }
        }

        cachedSteps = extracted ?: emptyList()
        cachedStepsExtracted = extracted != null
        return extracted ?: emptyList()
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

            // 2. Locate the signature call that feeds the decipher function:
            //    player_ias: .s){var m=l,n=h.sp,p=Gl(16,1453,...)
            //    player_es6: .s){var f=c,h=k.sp;let l=Gh(19,2484,...)
            val callRegex = Regex("""\.s\)\{[^}]{0,220}?\b([a-zA-Z0-9$]+)\s*=\s*([a-zA-Z0-9$]+)\((\d+),(\d+),""")
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

    private fun ensureRhinoNSolver() {
        if (rhinoNScope != null && rhinoNSolverFunc != null && rhinoNSolverPlayerUrl == playerUrl) {
            return
        }
        val targetUrl = playerUrl.ifEmpty { PINNED_PLAYER_URL }
        val js = ensureBaseJs()
        if (js.isNullOrEmpty()) return

        val modernPattern = Regex("""([a-zA-Z0-9$]+)=function\([a-zA-Z0-9$,]+\)\{[^}]*a\.set\("alr","yes"\)[^}]*\}""")
        val match = modernPattern.find(js)
        if (match == null) {
            logD(TAG, "Modern n-solver alr pattern not found in $targetUrl")
            return
        }
        val funcName = match.groupValues[1]
        val patchedJs = js.replaceRange(match.range, "globalThis._solver=" + match.value)

        val cx = RhinoContext.enter()
        try {
            cx.optimizationLevel = -1
            cx.languageVersion = RhinoContext.VERSION_ES6
            val scope = cx.initStandardObjects()

            val mockInit = """
                var window = this; var globalThis = this; var self = this;
                var location = { href: 'https://www.youtube.com', hostname: 'www.youtube.com', protocol: 'https:', host: 'www.youtube.com' };
                var document = { currentScript: { src: '$targetUrl' } };
                var navigator = { userAgent: '$DESKTOP_UA' };
                function XMLHttpRequest() {}
                XMLHttpRequest.prototype = {};
            """.trimIndent()
            cx.evaluateString(scope, mockInit, "init", 1, null)
            cx.evaluateString(scope, patchedJs, "base.js", 1, null)

            val helperScript = """
                globalThis.solveN = function(n) {
                  var url = globalThis._solver('https://youtube.com/watch?v=yt-dlp-wins', 's', undefined);
                  url.set('n', n);
                  var proto = Object.getPrototypeOf(url);
                  var keys = Object.keys(proto).concat(Object.getOwnPropertyNames(proto));
                  for (var i = 0; i < keys.length; i++) {
                    var key = keys[i];
                    if (key !== 'constructor' && key !== 'set' && key !== 'get' && key !== 'clone') {
                      url[key]();
                      break;
                    }
                  }
                  return url.get('n');
                };
            """.trimIndent()
            cx.evaluateString(scope, helperScript, "helper", 1, null)

            val solverFunc = scope.get("solveN", scope) as? RhinoFunction
            if (solverFunc != null) {
                rhinoNScope = scope
                rhinoNSolverFunc = solverFunc
                rhinoNSolverPlayerUrl = playerUrl
                logI(TAG, "Modern Rhino n-solver ($funcName) initialized successfully for $targetUrl")
            }
        } catch (t: Throwable) {
            logW(TAG, "Failed to initialize modern Rhino n-solver: ${t.message}")
        } finally {
            RhinoContext.exit()
        }
    }

    private fun transformN(n: String): String? {
        val scope = rhinoNScope ?: return null
        val func = rhinoNSolverFunc ?: return null
        val cx = RhinoContext.enter()
        return try {
            cx.optimizationLevel = -1
            cx.languageVersion = RhinoContext.VERSION_ES6
            val res = func.call(cx, scope, scope, arrayOf(n))
            val transformed = res?.toString()
            if (!transformed.isNullOrEmpty() && transformed != "null" && transformed != "undefined" && transformed != n) {
                transformed
            } else {
                null
            }
        } catch (t: Throwable) {
            logW(TAG, "Modern Rhino n-solver invocation failed: ${t.message}")
            null
        } finally {
            RhinoContext.exit()
        }
    }

    /**
     * Returns [url] with its throttling `n` parameter transformed. Null when the
     * transform is unavailable — an untransformed-`n` URL is answered with 403 by
     * googlevideo, so callers must discard the URL rather than keep it.
     */
    fun deobfuscateN(url: String): String? = synchronized(lock) {
        val nMatch = N_PARAM_REGEX.find(url)
        val nVal = nMatch?.groupValues?.get(1)
        if (!nVal.isNullOrEmpty()) {
            ensurePlayerUrl()
            ensureRhinoNSolver()
            val transformed = transformN(nVal)
            if (!transformed.isNullOrEmpty()) {
                val encodedOld = java.net.URLEncoder.encode(nVal, "UTF-8")
                val encodedNew = java.net.URLEncoder.encode(transformed, "UTF-8")
                val patternExact = Regex("([?&])n=${Regex.escape(nVal)}(?=&|$)")
                val patternEncoded = Regex("([?&])n=${Regex.escape(encodedOld)}(?=&|$)")
                val deobfuscatedUrl = when {
                    patternExact.containsMatchIn(url) -> patternExact.replaceFirst(url, "$1n=" + Regex.escapeReplacement(encodedNew))
                    patternEncoded.containsMatchIn(url) -> patternEncoded.replaceFirst(url, "$1n=" + Regex.escapeReplacement(encodedNew))
                    else -> url.replace("n=$nVal", "n=$transformed")
                }
                logI(TAG, "Modern Rhino n-transform succeeded: $nVal -> $transformed")
                return deobfuscatedUrl
            }
        }

        try {
            ensurePlayerUrl()
            val deobfuscated: String? = YoutubeJavaScriptPlayerManager
                .getUrlWithThrottlingParameterDeobfuscated(playerUrl, url)
            if (deobfuscated.isNullOrEmpty()) return@synchronized null

            // NewPipe's n-function heuristics can latch onto an unrelated helper
            // whose call is a silent identity. Detect the identity result
            // so the failure is at least visible in logs instead of presenting as a perfect transform.
            val before = N_PARAM_REGEX.find(url)?.groupValues?.get(1)
            val after = N_PARAM_REGEX.find(deobfuscated)?.groupValues?.get(1)
            if (before != null && before == after) {
                logW(TAG, "n-parameter deobfuscation produced an identity result; treating as unavailable")
                return@synchronized null
            }
            deobfuscated
        } catch (t: Throwable) {
            logW(TAG, "n-parameter deobfuscation fallback failed: ${t.message}")
            null
        }
    }

    /** `signatureTimestamp` (STS) for the current base.js, or null. */
    fun signatureTimestamp(): Int? = synchronized(lock) {
        cachedSts?.let { return it }
        ensurePlayerUrl()
        try {
            val sts: Int? = YoutubeJavaScriptPlayerManager.getSignatureTimestamp(playerUrl)
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
        null
    }

    /** Drops NewPipe's static player-JS caches (call on network/egress change). */
    fun clearCaches() {
        synchronized(lock) {
            cachedSteps = null
            cachedStepsExtracted = false
            cachedJs = null
            cachedSts = null
            rhinoNScope = null
            rhinoNSolverFunc = null
            rhinoNSolverPlayerUrl = null
            try {
                YoutubeJavaScriptPlayerManager.clearAllCaches()
            } catch (t: Throwable) {
                logW(TAG, "clearAllCaches failed: ${t.message}")
            }
        }
    }
}
