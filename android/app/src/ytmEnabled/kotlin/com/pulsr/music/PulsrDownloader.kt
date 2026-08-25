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

/**
 * Hardened HTTP Downloader for NewPipeExtractor.
 *
 * Integrates token-bucket rate limiting (RateLimiter), synchronized cookie management
 * (YtmCookieStore), automatic decompression, and robust bot-detection / 429 handling.
 */
class PulsrDownloader(private val context: Context? = null) : Downloader() {

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        // 1. Rate limiting permit acquisition
        RateLimiter.shared.acquirePermit()

        var connection: HttpURLConnection? = null
        try {
            connection = (URL(request.url()).openConnection() as HttpURLConnection).apply {
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

            // Attach cookies from YtmCookieStore or native CookieManager
            val cookieHeader = resolveCookies(request.url())
            if (!cookieHeader.isNullOrEmpty()) {
                val existing = connection.getRequestProperty("Cookie")
                if (existing.isNullOrEmpty()) {
                    connection.setRequestProperty("Cookie", cookieHeader)
                } else {
                    connection.setRequestProperty("Cookie", "$existing; $cookieHeader")
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
                RateLimiter.shared.onRateLimited()
                throw ReCaptchaException("HTTP 429 Too Many Requests: Rate limited by YouTube", request.url())
            }

            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val body = stream?.let { raw ->
                val decoded = if (connection.contentEncoding.equals("gzip", ignoreCase = true)) {
                    GZIPInputStream(raw)
                } else {
                    raw
                }
                decoded.use { it.readBytes().toString(Charsets.UTF_8) }
            }

            if (body != null && (body.contains("Sign in to confirm that you're not a bot") ||
                        body.contains("LOGIN_REQUIRED") ||
                        body.contains("Sign in to confirm you're not a bot") ||
                        body.contains("recaptcha"))) {
                RateLimiter.shared.onRateLimited()
                throw ReCaptchaException("YouTube bot verification required: Sign in to confirm you're not a bot", request.url())
            }

            // Mark successful request in rate limiter
            RateLimiter.shared.onSuccess()

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
            connection?.disconnect()
        }
    }

    private fun resolveCookies(url: String): String? {
        if (context != null) {
            val store = YtmCookieStore.getInstance(context)
            val storeCookies = store.getMergedCookieHeader()
            if (!storeCookies.isNullOrEmpty()) {
                return storeCookies
            }
        }

        // Fallback to direct CookieManager lookup
        return runCatching {
            val cm = android.webkit.CookieManager.getInstance()
            val direct = cm.getCookie(url)
            if (!direct.isNullOrEmpty()) return@runCatching direct

            val jar = mutableMapOf<String, String>()
            for (u in YtmCookieStore.DOMAINS) {
                val c = cm.getCookie(u) ?: continue
                for (pair in c.split(";")) {
                    val parts = pair.trim().split("=", limit = 2)
                    if (parts.size == 2 && parts[0].isNotBlank()) {
                        jar[parts[0].trim()] = parts[1].trim()
                    }
                }
            }
            if (jar.isEmpty()) null else jar.entries.joinToString("; ") { "${it.key}=${it.value}" }
        }.getOrNull()
    }

    companion object {
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val HTTP_TOO_MANY_REQUESTS = 429
    }
}
