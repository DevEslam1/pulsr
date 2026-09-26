package com.pulsr.music

import java.util.concurrent.CopyOnWriteArrayList

/**
 * 2026-09 gap 2: flavor-safe egress change signal. The main flavor publishes
 * (ProxyPool rotation), the ytmEnabled flavor subscribes (PoTokenManager).
 * No-op when YTM is disabled (no subscriber).
 */
object EgressSignals {
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()
    private var legacyListener: ((String) -> Unit)? = null

    var onEgressChanged: ((String) -> Unit)?
        get() = legacyListener ?: if (listeners.isEmpty()) null else { egressId: String -> notify(egressId) }
        set(value) {
            val old = legacyListener
            if (old != null) {
                listeners.remove(old)
            }
            legacyListener = value
            if (value != null && !listeners.contains(value)) {
                listeners.add(value)
            }
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
        for (listener in listeners) {
            try {
                listener(egressId)
            } catch (_: Throwable) {}
        }
    }
}
