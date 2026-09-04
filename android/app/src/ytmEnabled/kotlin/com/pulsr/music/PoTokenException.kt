package com.pulsr.music

class PoTokenException(message: String) : Exception(message)

/** The system WebView cannot run BotGuard, so poTokens are impossible on this device. */
class BadWebViewException(message: String) : Exception(message)

/**
 * A syntax error means the WebView could not even parse the injected script, which
 * no retry will fix; anything else is a normal runtime failure worth retrying.
 */
internal fun buildExceptionForJsError(error: String): Exception =
    if (error.contains("SyntaxError")) BadWebViewException(error) else PoTokenException(error)
