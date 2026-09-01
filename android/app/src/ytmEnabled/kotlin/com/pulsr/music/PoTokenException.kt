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
 * Distinguishes fatal BotGuard JS failures (bad JS engine, missing VM, syntax error)
 * from transient runtime failures worth retrying.
 */
internal fun isFatalBotGuardError(error: String): Boolean {
    val lower = error.lowercase()
    return lower.contains("syntaxerror") ||
        lower.contains("vm not found") ||
        lower.contains("could not load vm") ||
        lower.contains("could not load program") ||
        lower.contains("not a function")
}

internal fun buildExceptionForJsError(error: String): Exception =
    if (isFatalBotGuardError(error)) BadWebViewException(error) else PoTokenException.JsError(error)

