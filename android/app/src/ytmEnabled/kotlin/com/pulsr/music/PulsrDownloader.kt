package com.pulsr.music

import android.content.Context
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/** Thrown when YouTube responds with HTTP 429 Too Many Requests. Extends IOException for NewPipe compatibility. */
class RateLimitedException(message: String, val retryAfterMs: Long? = null) : IOException(message)

/**
 * Hardened HTTP Downloader for NewPipeExtractor.
 *
 * Integrates token-bucket rate limiting (RateLimiter), synchronized cookie management
 * (YtmCookieStore), automatic decompression, and robust bot-detection / 429 handling.
 */
class PulsrDownloader(private val context: Context? = null) : Downloader() {

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        // 1. Rate limiting permit acquisition, paced per endpoint. Everything
        //    used to share Bucket.PLAYER's 200ms floor, so NewPipe's search
        //    calls bypassed the 1500ms gap that keeps /search off YouTube's
        //    throttle — the endpoint that rate-limits soonest.
        val bucket = bucketFor(request.url())
        val permitHeld = RateLimiter.shared.acquirePermit(bucket)
        if (!permitHeld) {
            Thread.currentThread().interrupt()
            throw IOException("Rate limiter wait interrupted for ${request.url()}")
        }

        var connection: HttpURLConnection? = null
        try {
            val proxy = ProxyManager.getProxy(request.url())
            val url = URL(request.url())
            val rawConn = if (proxy != null) url.openConnection(proxy) else url.openConnection()
            connection = (rawConn as HttpURLConnection).apply {
                requestMethod = request.httpMethod()
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", USER_AGENT)
            }

            // Apply caller headers
            request.headers().forEach { (name, values) ->
                values.forEachIndexed { index, value ->
                    if (index == 0) connection.setRequestProperty(name, value)
                    else connection.addRequestProperty(name, value)
                }
            }

            // Attach cookies from YtmCookieStore or native CookieManager.
            // When user is signed in with a valid session, allow attaching cookies
            // to player requests as well so age-restricted/member streams can resolve.
            val allowCookiesForPlayer = context?.let { YtmCookieStore.getInstance(it).isSessionValid() } == true
            if (!isPlayerRequest(request.url()) || allowCookiesForPlayer) {
                val rawCookieHeader = resolveCookies(request.url())
                if (!rawCookieHeader.isNullOrEmpty()) {
                    val cookieHeader = sanitizeCookieHeader(rawCookieHeader)
                    if (cookieHeader.isNotEmpty()) {
                        val existing = connection.getRequestProperty("Cookie")
                        if (existing.isNullOrEmpty()) {
                            connection.setRequestProperty("Cookie", cookieHeader)
                        } else {
                            val combined = sanitizeCookieHeader("$existing; $cookieHeader")
                            connection.setRequestProperty("Cookie", combined)
                        }
                    }
                }
            }

            // Write request body if present
            request.dataToSend()?.let { body ->
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }

            val code = connection.responseCode

            // Ingest any Set-Cookie headers into store
            if (context != null) {
                val setCookies = connection.headerFields["Set-Cookie"]
                if (!setCookies.isNullOrEmpty()) {
                    YtmCookieStore.getInstance(context).ingestSetCookieHeaders(setCookies)
                }
            }

            if (code == HTTP_TOO_MANY_REQUESTS) {
                val retryAfter = connection.getHeaderField("Retry-After")?.trim()?.toLongOrNull()
                RateLimiter.shared.onRateLimited(retryAfter)
                ProxyManager.onPathFailed(request.url())
                throw RateLimitedException("HTTP 429 Too Many Requests: Rate limited by YouTube", retryAfter)
            }

            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val body = stream?.let { raw ->
                val isGzip = connection.contentEncoding?.equals("gzip", ignoreCase = true) == true
                val decoded = if (isGzip) {
                    GZIPInputStream(raw)
                } else {
                    raw
                }
                decoded.use { it.readBytes().toString(Charsets.UTF_8) }
            }

            // Bot-detection body scan, restricted to failed responses.
            //
            // Running it on 2xx bodies made benign traffic trip a global
            // backoff: `LOGIN_REQUIRED` is the normal 200 playabilityStatus of a
            // private or members-only track, and a bare "recaptcha" appears in
            // the markup of ordinary YouTube HTML pages — which is exactly what
            // YoutubeParsingHelper.getClientVersion() scrapes. One such request
            // then throttled every path and marked the network failed.
            if (code >= 400 && body != null && BOT_MARKERS.any { body.contains(it, ignoreCase = true) }) {
                RateLimiter.shared.onRateLimited()
                ProxyManager.onPathFailed(request.url())
                throw ReCaptchaException("YouTube bot verification required: Sign in to confirm you're not a bot", request.url())
            }

            // Mark successful request in rate limiter
            if (code in 200..299) {
                RateLimiter.shared.onSuccess()
            }

            return Response(
                code,
                connection.responseMessage,
                connection.headerFields,
                body,
                connection.url.toString(),
            )
        } catch (e: ReCaptchaException) {
            throw e
        } catch (e: IOException) {
            throw e
        } catch (e: Exception) {
            throw IOException("Request to ${request.url()} failed: ${e.message}", e)
        } finally {
            // Deliberately not calling connection.disconnect(): it tears down the
            // underlying socket and defeats HttpURLConnection keep-alive, so every
            // extractor request paid a fresh TCP + TLS handshake. The streams are
            // already fully read and closed above, which returns the connection to
            // the pool for reuse.
            RateLimiter.shared.releasePermit()
        }
    }

    private fun isPlayerRequest(url: String): Boolean {
        val path = runCatching { URL(url).path }.getOrNull() ?: url
        return path.contains("/youtubei/v1/player")
    }

    private fun bucketFor(url: String): RateLimiter.Bucket {
        val path = runCatching { URL(url).path }.getOrNull() ?: url
        return when {
            path.contains("/youtubei/v1/search") -> RateLimiter.Bucket.SEARCH
            path.contains("/youtubei/v1/browse") ||
                path.contains("/youtubei/v1/next") ||
                path.contains("/youtubei/v1/music") -> RateLimiter.Bucket.BROWSE
            path.contains("/youtubei/v1/player") -> RateLimiter.Bucket.PLAYER
            // base.js / iframe_api / HTML scrapes: cheap, and stalling them
            // behind the player floor delays every resolution that needs them.
            else -> RateLimiter.Bucket.STREAM
        }
    }

    private fun resolveCookies(url: String): String? {
        if (context != null) {
            val store = YtmCookieStore.getInstance(context)
            // Host-scoped: the store answers for google.com and youtube.com at
            // once, but the header must only carry what the target host would
            // legitimately receive.
            val storeCookies = store.getMergedCookieHeader(url)
            if (!storeCookies.isNullOrEmpty()) {
                return storeCookies
            }
        }

        // Fallback to direct CookieManager lookup. Only the target URL's own jar:
        // aggregating every Google domain here sent accounts.google.com
        // credentials to youtube.com, which is the leak the store now filters.
        return runCatching {
            val cm = android.webkit.CookieManager.getInstance()
            cm.getCookie(url)?.takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    companion object {
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0"
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val HTTP_TOO_MANY_REQUESTS = 429

        // Phrases that only appear on a genuine interstitial. Deliberately no
        // bare "recaptcha" or "LOGIN_REQUIRED": both occur in ordinary
        // responses, see the scan site above.
        private val BOT_MARKERS = listOf(
            "Sign in to confirm that you're not a bot",
            "Sign in to confirm you're not a bot",
            "/recaptcha/api2",
            "g-recaptcha",
            "unusual traffic from your computer network",
            "automated queries"
        )

        fun sanitizeCookieHeader(cookies: String): String {
            return cookies.split(';')
                .map { it.trim() }
                .filter { it.contains('=') && !it.startsWith('=') }
                .joinToString("; ")
        }
    }
}
