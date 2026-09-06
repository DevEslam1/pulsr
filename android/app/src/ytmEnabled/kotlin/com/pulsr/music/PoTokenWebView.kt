package com.pulsr.music

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
import org.json.JSONObject
import org.schabi.newpipe.extractor.NewPipe
import java.time.Instant
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Mints poTokens by running YouTube's BotGuard attestation JavaScript inside an
 * offscreen [WebView].
 *
 * YouTube refuses to serve stream URLs to a client that cannot prove it executed
 * BotGuard, so this is not optional for playback. The attestation cannot be
 * reimplemented in Kotlin — the program is obfuscated JavaScript that YouTube ships
 * fresh on every request — hence the WebView, which has network loads blocked and
 * only ever runs the bundled `po_token.html` asset.
 *
 * Ported from NewPipe (GPL-3.0), with RxJava replaced by [CompletableFuture].
 * Unlike upstream, every wait here is bounded: a WebView that never calls back
 * would otherwise wedge the extractor's request executor permanently.
 */
internal class PoTokenWebView private constructor(
    context: Context,
    private val generatorFuture: CompletableFuture<PoTokenGenerator>,
) : PoTokenGenerator {
    private val webView = WebView(context)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val poTokenFutures = mutableListOf<Pair<String, CompletableFuture<String>>>()
    private val closed = AtomicBoolean(false)

    @Volatile
    private var expirationInstant: Instant? = null

    //region Initialization
    init {
        Log.d(TAG, "Initializing PoTokenWebView instance")
        configureWebView()

        webView.webViewClient = object : WebViewClient() {
            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                super.onReceivedError(view, request, error)
                Log.w(TAG, "WebView onReceivedError: ${error?.description} (code=${error?.errorCode}) for ${request?.url}")
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                Log.d(TAG, "WebView onPageFinished: $url")
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(m: ConsoleMessage): Boolean {
                Log.d(TAG, "WebView console [${m.messageLevel()}]: ${m.message()} (${m.sourceId()}:${m.lineNumber()})")
                if (m.message().contains("Uncaught")) {
                    // Everything that can legitimately fail is wrapped in try/catch and
                    // reported through the JS interface, so an uncaught error means the
                    // WebView could not parse our script — i.e. its JS engine is too old.
                    val detail = "\"${m.message()}\", source: ${m.sourceId()} (${m.lineNumber()})"
                    Log.e(TAG, "WebView implementation is broken: $detail")
                    val exception = BadWebViewException(detail)
                    closeAndCancelInitialization(exception)
                    popAllPoTokenFutures().forEach { (_, f) -> f.completeExceptionally(exception) }
                }
                return super.onConsoleMessage(m)
            }
        }
    }


    @SuppressLint("SetJavaScriptEnabled") // BotGuard *is* JavaScript
    @Suppress("DEPRECATION") // setSafeBrowsingEnabled, still the only pre-manifest switch
    private fun configureWebView() {
        webView.settings.apply {
            javaScriptEnabled = true
            // The page is a local asset and the interpreter arrives as a string, so
            // neither Safe Browsing nor network access buys anything here.
            safeBrowsingEnabled = false
            blockNetworkLoads = true
            userAgentString = USER_AGENT
        }
        webView.addJavascriptInterface(this, JS_INTERFACE)
    }

    /**
     * Kicks off initialization: load the local page, fetch and run BotGuard, then
     * obtain an `integrityToken`, completing [generatorFuture]. Must be called
     * immediately after construction.
     */
    private fun loadHtmlAndObtainBotguard(context: Context) {
        executor.execute {
            try {
                Log.d(TAG, "loadHtmlAndObtainBotguard: loading asset $HTML_ASSET")
                val html = context.assets.open(HTML_ASSET).bufferedReader().use { it.readText() }
                if (!html.contains("</script>")) {
                    closeAndCancelInitialization(
                        PoTokenException("po_token.html is invalid: missing </script>")
                    )
                    return@execute
                }
                runOnMainThread(generatorFuture) {
                    Log.d(TAG, "loadHtmlAndObtainBotguard: injecting downloadAndRunBotguard into WebView")
                    webView.loadDataWithBaseURL(
                        "https://www.youtube.com",
                        // Calls downloadAndRunBotguard() once the page has loaded.
                        html.replaceFirst(
                            "</script>",
                            "\n$JS_INTERFACE.downloadAndRunBotguard()</script>",
                        ),
                        "text/html",
                        "utf-8",
                        null,
                    )
                }
            } catch (t: Throwable) {
                Log.e(TAG, "loadHtmlAndObtainBotguard failed: ${t.message}", t)
                closeAndCancelInitialization(t)
            }
        }
    }

    /** Called from the snippet appended to the page in [loadHtmlAndObtainBotguard]. */
    @JavascriptInterface
    fun downloadAndRunBotguard() {
        Log.d(TAG, "downloadAndRunBotguard: invoked from WebView JS interface")
        makeBotguardServiceRequest(
            "https://www.youtube.com/api/jnn/v1/Create",
            "[ \"$REQUEST_KEY\" ]",
        ) { responseBody ->
            Log.d(TAG, "downloadAndRunBotguard: parsing challenge response (${responseBody.length} bytes)")
            val challengeData = parseChallengeData(responseBody)
            webView.evaluateJavascript(
                """try {
                    data = $challengeData
                    runBotGuard(data).then(function (result) {
                        this.webPoSignalOutput = result.webPoSignalOutput
                        $JS_INTERFACE.onRunBotguardResult(result.botguardResponse)
                    }, function (error) {
                        $JS_INTERFACE.onJsInitializationError(error + "\n" + error.stack)
                    })
                } catch (error) {
                    $JS_INTERFACE.onJsInitializationError(error + "\n" + error.stack)
                }""",
                null,
            )
        }
    }

    /** Called from the JS snippets in [downloadAndRunBotguard] or [onRunBotguardResult]. */
    @JavascriptInterface
    fun onJsInitializationError(error: String) {
        Log.e(TAG, "Initialization error from JavaScript: $error")
        closeAndCancelInitialization(buildExceptionForJsError(error))
    }

    /** Called from the JS snippet in [downloadAndRunBotguard] with BotGuard's output. */
    @JavascriptInterface
    fun onRunBotguardResult(botguardResponse: String) {
        Log.d(TAG, "onRunBotguardResult: botguardResponse received (len=${botguardResponse.length})")
        makeBotguardServiceRequest(
            "https://www.youtube.com/api/jnn/v1/GenerateIT",
            "[ \"$REQUEST_KEY\", \"$botguardResponse\" ]",
        ) { responseBody ->
            Log.d(TAG, "onRunBotguardResult: parsing GenerateIT response")
            val (integrityToken, expirationTimeInSeconds) = parseIntegrityTokenData(responseBody)
            // 10 minutes of margin, so a token cannot expire mid-request.
            expirationInstant = Instant.now().plusSeconds(expirationTimeInSeconds - 600)

            webView.evaluateJavascript("this.integrityToken = $integrityToken") {
                Log.i(TAG, "BotGuard generator successfully initialized! Valid until epoch: $expirationInstant")
                generatorFuture.complete(this)
            }
        }
    }
    //endregion

    //region Obtaining poTokens
    @WorkerThread
    override fun generatePoToken(identifier: String): String {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw IllegalStateException(
                "generatePoToken() must not be called from the Main UI thread as it blocks waiting for WebView execution."
            )
        }
        if (closed.get()) {
            throw java.util.concurrent.CancellationException("PoTokenWebView is closed")
        }
        val future = CompletableFuture<String>()
        addPoTokenFuture(identifier, future)
        runOnMainThread(future) {
            webView.evaluateJavascript(
                """try {
                        identifier = ${JSONObject.quote(identifier)}
                        u8Identifier = ${stringToU8(identifier)}
                        poTokenU8 = obtainPoToken(webPoSignalOutput, integrityToken, u8Identifier)
                        poTokenU8String = ""
                        for (i = 0; i < poTokenU8.length; i++) {
                            if (i != 0) poTokenU8String += ","
                            poTokenU8String += poTokenU8[i]
                        }
                        $JS_INTERFACE.onObtainPoTokenResult(identifier, poTokenU8String)
                    } catch (error) {
                        $JS_INTERFACE.onObtainPoTokenError(identifier, error + "\n" + error.stack)
                    }""",
                null,
            )
        }
        return future.await(TOKEN_TIMEOUT_SECONDS, "minting a poToken for $identifier") {
            popPoTokenFuture(identifier)
        }
    }

    /** Called from the JS snippet in [generatePoToken] when `obtainPoToken()` throws. */
    @JavascriptInterface
    fun onObtainPoTokenError(identifier: String, error: String) {
        Log.e(TAG, "obtainPoToken error from JavaScript: $error")
        popPoTokenFuture(identifier)?.completeExceptionally(buildExceptionForJsError(error))
    }

    /** Called from the JS snippet in [generatePoToken] with `obtainPoToken()`'s result. */
    @JavascriptInterface
    fun onObtainPoTokenResult(identifier: String, poTokenU8: String) {
        val future = popPoTokenFuture(identifier) ?: return
        try {
            future.complete(u8ToBase64(poTokenU8))
        } catch (t: Throwable) {
            future.completeExceptionally(t)
        }
    }

    /** An uninitialized generator counts as expired, so callers recreate it. */
    override fun isExpired(): Boolean =
        expirationInstant?.let { Instant.now().isAfter(it) } ?: true

    override fun expirationInstant(): Instant? = expirationInstant
    //endregion

    //region Handling multiple pending tokens

    /**
     * Pending tokens are keyed by identifier so several can be minted in parallel
     * and each result still reaches the caller that asked for it.
     */
    private fun addPoTokenFuture(identifier: String, future: CompletableFuture<String>) {
        synchronized(poTokenFutures) { poTokenFutures.add(identifier to future) }
    }

    private fun popPoTokenFuture(identifier: String): CompletableFuture<String>? =
        synchronized(poTokenFutures) {
            poTokenFutures.indexOfFirst { it.first == identifier }
                .takeIf { it >= 0 }
                ?.let { poTokenFutures.removeAt(it).second }
        }

    private fun popAllPoTokenFutures(): List<Pair<String, CompletableFuture<String>>> =
        synchronized(poTokenFutures) {
            val result = poTokenFutures.toList()
            poTokenFutures.clear()
            result
        }
    //endregion

    //region Utils

    /**
     * POSTs [data] to [url] with BotGuard's expected headers, then hands the body to
     * [handleResponseBody] on the main thread. Any network error, non-200 response or
     * parse failure aborts initialization, so this is only usable while initializing.
     */
    private fun makeBotguardServiceRequest(
        url: String,
        data: String,
        handleResponseBody: (String) -> Unit,
    ) {
        executor.execute {
            try {
                Log.d(TAG, "makeBotguardServiceRequest: POST $url")
                val response = NewPipe.getDownloader().post(
                    url,
                    mapOf(
                        // Must match the WebView's UA, or BotGuard rejects the attestation.
                        "User-Agent" to listOf(USER_AGENT),
                        "Accept" to listOf("application/json"),
                        "Content-Type" to listOf("application/json+protobuf"),
                        "x-goog-api-key" to listOf(GOOGLE_API_KEY),
                        "x-user-agent" to listOf("grpc-web-javascript/0.1"),
                    ),
                    data.toByteArray(),
                )
                Log.d(TAG, "makeBotguardServiceRequest: responseCode=${response.responseCode()} for $url")
                if (response.responseCode() != 200) {
                    throw PoTokenException("Invalid response code: ${response.responseCode()} from $url")
                }
                val body = response.responseBody()
                runOnMainThread(generatorFuture) {
                    try {
                        handleResponseBody(body)
                    } catch (t: Throwable) {
                        Log.e(TAG, "handleResponseBody failed for $url: ${t.message}", t)
                        closeAndCancelInitialization(t)
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "makeBotguardServiceRequest failed for $url: ${t.message}", t)
                closeAndCancelInitialization(t)
            }
        }
    }

    /** Fails [generatorFuture] with [error] and releases resources. */
    private fun closeAndCancelInitialization(error: Throwable) {
        Log.e(TAG, "closeAndCancelInitialization: ${error.message}", error)
        // Failed first so the waiting extractor thread is released without depending
        // on the main thread ever getting around to the cleanup below.
        generatorFuture.completeExceptionally(error)
        runOnMainThread(generatorFuture) { close() }
    }

    @MainThread
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        val exception = PoTokenException("PoTokenGenerator closed")
        popAllPoTokenFutures().forEach { (_, f) -> f.completeExceptionally(exception) }
        executor.shutdownNow()

        webView.clearHistory()
        // Clears the RAM and disk cache, globally for every WebView in the process.
        webView.clearCache(true)
        // Stops the page doing anything further before it is torn down.
        webView.loadUrl("about:blank")
        webView.onPause()
        webView.webChromeClient = null
        webView.removeAllViews()
        webView.destroy()
    }

    /**
     * Posts [runnable] to the main thread, where all WebView interaction has to
     * happen, failing [futureIfPostFails] if the post cannot even be scheduled.
     * Work queued before [close] is dropped, since the WebView is gone by then.
     */
    private fun runOnMainThread(futureIfPostFails: CompletableFuture<*>, runnable: Runnable) {
        val posted = mainHandler.post { if (!closed.get()) runnable.run() }
        if (!posted) {
            futureIfPostFails.completeExceptionally(
                PoTokenException("Could not run on main thread"),
            )
        }
    }
    //endregion

    companion object {
        private const val TAG = "PoTokenWebView"
        private const val HTML_ASSET = "po_token.html"

        // Public API key and request key used by BotGuard, taken from its own requests.
        var GOOGLE_API_KEY: String = YtmConfig.getGoogleApiKey()
        private const val REQUEST_KEY = "O43z0dpjhgX20SCx4KAo"
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0"
        private const val JS_INTERFACE = "PoTokenWebView"

        // Initialization is two network round-trips plus a JS handshake that upstream
        // allows 10s of its own, so it needs a generous ceiling; minting afterwards is
        // pure local computation.
        private const val INIT_TIMEOUT_SECONDS = 30L
        private const val TOKEN_TIMEOUT_SECONDS = 15L

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * Loads the BotGuard VM and obtains an `integrityToken`, returning a generator
         * that can then mint many poTokens. Blocks, so call it off the main thread.
         */
        fun newPoTokenGenerator(context: Context): PoTokenGenerator {
            val future = CompletableFuture<PoTokenGenerator>()
            val instance = java.util.concurrent.atomic.AtomicReference<PoTokenWebView?>(null)
            val posted = mainHandler.post {
                PoTokenWebView(context, future).also {
                    instance.set(it)
                    it.loadHtmlAndObtainBotguard(context)
                }
            }
            if (!posted) throw PoTokenException("Could not run on main thread")
            return future.await(INIT_TIMEOUT_SECONDS, "initializing BotGuard") {
                // On timeout the WebView never called back, so nothing else will
                // ever release it: each failed attempt otherwise strands a WebView
                // and a single-thread executor for the life of the process. The
                // handler is FIFO, so the construction above has already run by
                // the time this close is dispatched.
                mainHandler.post { instance.get()?.close() }
            }
        }

        /**
         * Blocks for the result, unwrapping [ExecutionException] so callers can react
         * to the real cause (notably [BadWebViewException]) instead of a wrapper.
         */
        private fun <T> CompletableFuture<T>.await(
            timeoutSeconds: Long,
            what: String,
            onTimeout: () -> Unit = {},
        ): T = try {
            get(timeoutSeconds, TimeUnit.SECONDS)
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        } catch (e: TimeoutException) {
            onTimeout()
            throw PoTokenException("Timed out after ${timeoutSeconds}s $what")
        }
    }
}
