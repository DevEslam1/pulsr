package com.pulsr.music

import java.util.concurrent.CopyOnWriteArrayList

/**
 * 2026-09 gap 2: flavor-safe egress change signal. The main flavor publishes
 * (ProxyPool rotation), the ytmEnabled flavor subscribes (PoTokenManager).
 * No-op when YTM is disabled (no subscriber).
 */
object EgressSignals {
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()

    var onEgressChanged: ((String) -> Unit)?
        get() = if (listeners.isEmpty()) null else { egressId: String -> notify(egressId) }
        set(value) {
            listeners.clear()
            if (value != null) {
                listeners.add(value)
            }
        }

    fun addListener(listener: (String) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (String) -> Unit) {
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
