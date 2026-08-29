package com.pulsr.music

open class PoTokenException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    open class WebViewUnavailable(message: String = "System WebView is unavailable or damaged", cause: Throwable? = null) : PoTokenException(message, cause)
    class JsError(message: String, cause: Throwable? = null) : PoTokenException(message, cause)
    class Timeout(message: String = "PoToken generation timed out", cause: Throwable? = null) : PoTokenException(message, cause)
    class Invalidated(message: String = "PoToken state was invalidated due to bot signal", cause: Throwable? = null) : PoTokenException(message, cause)
}

/** The system WebView cannot run BotGuard, so poTokens are impossible on this device. */
class BadWebViewException(message: String) : PoTokenException.WebViewUnavailable(message)

/**
 * A syntax error means the WebView could not even parse the injected script, which
 * no retry will fix; anything else is a normal runtime failure worth retrying.
 */
internal fun buildExceptionForJsError(error: String): Exception =
    if (error.contains("SyntaxError")) BadWebViewException(error) else PoTokenException.JsError(error)

