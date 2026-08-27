package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.webkit.CookieManager
import java.util.concurrent.ConcurrentHashMap

/**
 * Thread-safe Cookie Store for YouTube & Google session management.
 *
 * Acts as the single source of truth for cookies across:
 * - https://music.youtube.com
 * - https://www.youtube.com
 * - https://accounts.google.com
 * - https://youtube.com
 *
 * Handles persistence, CookieManager synchronization, Set-Cookie header extraction,
 * and session health / expiry detection (SAPISID + __Secure-3PSID presence).
 */
internal class YtmCookieStore private constructor(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Keyed by cookie name -> cookie value
    private val cookies = ConcurrentHashMap<String, String>()
    private val lock = Any()

    init {
        loadFromPrefs()
    }

    private fun loadFromPrefs() {
        synchronized(lock) {
            val saved = prefs.getString(KEY_COOKIES, null)
            if (!saved.isNullOrEmpty()) {
                parseAndPut(saved)
            } else {
                // Read from native CookieManager if prefs are empty
                readFromCookieManager()
            }
        }
    }

    /**
     * Reads and aggregates cookies from all relevant YouTube and Google domains in CookieManager.
     */
    fun readFromCookieManager(): String? {
        synchronized(lock) {
            val cm = runCatching { CookieManager.getInstance() }.getOrNull() ?: return null
            for (domain in DOMAINS) {
                val c = cm.getCookie(domain) ?: continue
                parseAndPut(c)
            }
            val merged = getMergedCookieHeader()
            if (merged != null) {
                saveToPrefs(merged)
            }
            return merged
        }
    }

    /**
     * Sets cookies from a raw header string (e.g. "name=val; name2=val2") and persists them.
     */
    fun setCookies(rawCookieHeader: String) {
        synchronized(lock) {
            if (rawCookieHeader.isBlank()) {
                clear()
                return
            }
            parseAndPut(rawCookieHeader)
            val merged = getMergedCookieHeader() ?: ""
            saveToPrefs(merged)
        }
    }

    /**
     * Parses Set-Cookie response headers and updates the store.
     */
    fun ingestSetCookieHeaders(headerValues: List<String>?) {
        if (headerValues.isNullOrEmpty()) return
        synchronized(lock) {
            var updated = false
            for (header in headerValues) {
                val parts = header.split(";")
                val nameValue = parts.firstOrNull()?.trim() ?: continue
                val kv = nameValue.split("=", limit = 2)
                if (kv.size != 2 || kv[0].isBlank()) continue

                // Check if cookie specifies max-age=0 or expired
                val maxAgeAttr = parts.find { it.trim().startsWith("max-age=", true) }
                if (maxAgeAttr != null) {
                    val maxAgeVal = maxAgeAttr.substringAfter("=").trim().toLongOrNull()
                    if (maxAgeVal != null && maxAgeVal <= 0) {
                        cookies.remove(kv[0].trim())
                        updated = true
                        continue
                    }
                }

                cookies[kv[0].trim()] = kv[1].trim()
                updated = true
            }
            if (updated) {
                val merged = getMergedCookieHeader() ?: ""
                saveToPrefs(merged)
            }
        }
    }

    /**
     * Returns the formatted `Cookie` header string for HTTP requests.
     */
    fun getMergedCookieHeader(): String? {
        synchronized(lock) {
            if (cookies.isEmpty()) return null
            return cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
        }
    }

    /**
     * Returns a specific cookie value (e.g. "SAPISID", "__Secure-3PSID").
     */
    fun getCookie(name: String): String? = cookies[name]

    /**
     * Checks if the session has valid authentication credentials.
     * Both SAPISID (or variant) and __Secure-3PSID (or __Secure-1PSID) are required for full access.
     */
    fun isSessionValid(): Boolean {
        val hasSapisid = cookies.containsKey("SAPISID") ||
                cookies.containsKey("__Secure-3PAPISID") ||
                cookies.containsKey("__Secure-1PAPISID")

        val hasPsid = cookies.containsKey("__Secure-3PSID") ||
                cookies.containsKey("__Secure-1PSID") ||
                cookies.containsKey("SID")

        return hasSapisid && hasPsid
    }

    /**
     * Clears all stored cookies.
     */
    fun clear() {
        synchronized(lock) {
            cookies.clear()
            prefs.edit().remove(KEY_COOKIES).apply()
            runCatching {
                val cm = CookieManager.getInstance()
                cm.removeAllCookies(null)
                cm.flush()
            }
        }
    }

    private fun parseAndPut(cookieString: String) {
        for (pair in cookieString.split(";")) {
            val trimmed = pair.trim()
            if (trimmed.isEmpty()) continue
            val parts = trimmed.split("=", limit = 2)
            if (parts.size == 2 && parts[0].isNotBlank()) {
                cookies[parts[0].trim()] = parts[1].trim()
            }
        }
    }

    private fun saveToPrefs(cookieString: String) {
        prefs.edit().putString(KEY_COOKIES, cookieString).apply()
    }

    companion object {
        private const val PREFS_NAME = "ytm_session_cookies"
        private const val KEY_COOKIES = "cookies"

        val DOMAINS = listOf(
            "https://google.com",
            "https://accounts.google.com",
            "https://myaccount.google.com",
            "https://accounts.youtube.com",
            "https://youtube.com",
            "https://www.youtube.com",
            "https://music.youtube.com",
        )

        @Volatile
        private var instance: YtmCookieStore? = null

        fun getInstance(context: Context): YtmCookieStore {
            return instance ?: synchronized(this) {
                instance ?: YtmCookieStore(context.applicationContext).also { instance = it }
            }
        }
    }
}
