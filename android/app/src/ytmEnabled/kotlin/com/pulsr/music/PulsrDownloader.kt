package com.pulsr.music

import android.webkit.CookieManager
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * NewPipeExtractor's HTTP backend, on HttpURLConnection so the app does not have
 * to bundle OkHttp.
 */
class PulsrDownloader : Downloader() {

    @Throws(IOException::class, ReCaptchaException::class)
    override fun execute(request: Request): Response {
        val connection = (URL(request.url()).openConnection() as HttpURLConnection).apply {
            requestMethod = request.httpMethod()
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
        }

        request.headers().forEach { (name, values) ->
            // The first value must replace the default User-Agent above rather than
            // append to it, so set-then-add instead of add-only.
            values.forEachIndexed { index, value ->
                if (index == 0) connection.setRequestProperty(name, value)
                else connection.addRequestProperty(name, value)
            }
        }

        // Attach cookies: first check specific URL, otherwise aggregate from YouTube domains
        val cookie = resolveCookies(request.url())
        if (!cookie.isNullOrEmpty()) {
            val existing = connection.getRequestProperty("Cookie")
            if (existing.isNullOrEmpty()) {
                connection.setRequestProperty("Cookie", cookie)
            } else {
                connection.setRequestProperty("Cookie", "$existing; $cookie")
            }
        }

        try {
            request.dataToSend()?.let { body ->
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }

            val code = connection.responseCode
            if (code == HTTP_TOO_MANY_REQUESTS) {
                throw ReCaptchaException("reCaptcha challenge requested", request.url())
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
                        body.contains("Sign in to confirm you're not a bot"))) {
                throw ReCaptchaException("YouTube bot verification required: Sign in to confirm you're not a bot", request.url())
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
            throw IOException("Request to ${request.url()} failed", e)
        } finally {
            connection.disconnect()
        }
    }

    private fun resolveCookies(url: String): String? {
        return runCatching {
            val cm = CookieManager.getInstance()
            val direct = cm.getCookie(url)
            if (!direct.isNullOrEmpty()) {
                return@runCatching direct
            }
            val urls = listOf(
                "https://music.youtube.com",
                "https://www.youtube.com",
                "https://accounts.google.com",
                "https://youtube.com"
            )
            val jar = mutableMapOf<String, String>()
            for (u in urls) {
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
        // Desktop User-Agent matching the PoToken BotGuard VM so session tokens and fingerprints align
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val HTTP_TOO_MANY_REQUESTS = 429
    }
}
