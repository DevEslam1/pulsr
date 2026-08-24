package com.pulsr.music

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

        val cookie = runCatching {
            android.webkit.CookieManager.getInstance().getCookie(request.url())
        }.getOrNull()
        if (!cookie.isNullOrEmpty()) {
            connection.setRequestProperty("Cookie", cookie)
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
                // Android decompresses transparently only when it added Accept-Encoding
                // itself. If a caller set that header the payload arrives still gzipped
                // and Content-Encoding survives, so it has to be unwrapped here.
                val decoded = if (connection.contentEncoding.equals("gzip", ignoreCase = true)) {
                    GZIPInputStream(raw)
                } else {
                    raw
                }
                decoded.use { it.readBytes().toString(Charsets.UTF_8) }
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

    companion object {
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val HTTP_TOO_MANY_REQUESTS = 429
    }
}
