package com.pulsr.music

import java.util.concurrent.CopyOnWriteArrayList

/**
 * 2026-09 gap 2: flavor-safe egress change signal. The main flavor publishes
 * (ProxyPool rotation), the ytmEnabled flavor subscribes (PoTokenManager).
 * No-op when YTM is disabled (no subscriber).
 */
object EgressSignals {
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()

    // Legacy single-slot listener. Kept out of [listeners] so assigning the
    // property cannot enqueue the same lambda twice (which made notify()
    // recurse through its own synthetic getter lambda).
    @Volatile
    private var legacyListener: ((String) -> Unit)? = null

    var onEgressChanged: ((String) -> Unit)?
        get() = if (legacyListener != null || listeners.isNotEmpty()) {
            { egressId: String -> notify(egressId) }
        } else {
            null
        }
        set(value) {
            legacyListener = value
        }

    fun addListener(listener: (String) -> Unit) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
        }
    }

    fun removeListener(listener: (String) -> Unit) {
        if (legacyListener == listener) {
            legacyListener = null
        }
        listeners.remove(listener)
    }

    fun notify(egressId: String) {
        try {
            legacyListener?.invoke(egressId)
        } catch (_: Throwable) {}
        for (listener in listeners) {
            try {
                listener(egressId)
            } catch (_: Throwable) {}
        }
    }
}