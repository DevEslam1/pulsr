package com.pulsr.music

import android.util.Log

/**
 * Runs a best-effort native/channel operation without letting a single
 * platform failure escape into the MethodChannel result or the audio setup.
 * Logged at WARN so field logs still identify the failing stage.
 */
inline fun safeCall(tag: String, what: String? = null, block: () -> Unit) {
    try {
        block()
    } catch (e: Exception) {
        if (what != null) {
            Log.w(tag, "$what failed: ${e.message}")
        } else {
            Log.w(tag, "Call failed: ${e.message}")
        }
    }
}
