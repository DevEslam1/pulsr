package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.webkit.CookieManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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
    private val legacyPrefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Never fall back to plaintext SharedPreferences for Google session
    // credentials. If the keystore is unavailable we keep the current process
    // session in memory and ask the user to sign in again after a restart.
    private val prefs: SharedPreferences? = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            SECURE_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (_: Throwable) { null }

    // Keyed by cookie name -> cookie value
    private val cookies = ConcurrentHashMap<String, String>()
    private val lock = Any()

    init {
        loadFromPrefs()
    }

    private fun loadFromPrefs() {
        synchronized(lock) {
            var saved = prefs?.getString(KEY_COOKIES, null)
            // One-time migration: check legacy plaintext prefs
            if (saved.isNullOrEmpty() && prefs != null) {
                val legacySaved = legacyPrefs.getString(KEY_COOKIES, null)
                if (!legacySaved.isNullOrEmpty()) {
                    try {
                        prefs.edit().putString(KEY_COOKIES, legacySaved).apply()
                        if (prefs.getString(KEY_COOKIES, null) == legacySaved) {
                            legacyPrefs.edit().remove(KEY_COOKIES).apply()
                        }
                        saved = legacySaved
                    } catch (_: Throwable) {
                        saved = legacySaved
                    }
                }
            }
            if (!saved.isNullOrEmpty()) {
                if (saved.startsWith("{")) {
                    try {
                        val json = org.json.JSONObject(saved)
                        val keys = json.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            cookies[k] = json.getString(k)
                        }
                    } catch (_: Throwable) {
                        parseAndPut(saved)
                    }
                } else {
                    parseAndPut(saved)
                }
            } else {
                // Read from native CookieManager if prefs are empty
                readFromCookieManager()
            }
        }
    }

    /**
     * Reads and aggregates cookies from all relevant YouTube and Google domains in CookieManager.
     *
     * Returns null once the user has explicitly disconnected: with the store
     * cleared, an unconditional re-read here resurrected the session straight
     * out of the WebView jar on the next process start, and Dart's `init()`
     * prefers native cookies over its own — so a disconnect silently undid
     * itself. Only [setCookies] with a real jar lifts the tombstone.
     */
    fun readFromCookieManager(): String? {
        synchronized(lock) {
            if (isSignedOut()) return null
            val cm = runCatching { CookieManager.getInstance() }.getOrNull() ?: return null
            // The Google account hosts are read into a side map and only fill
            // gaps: `SIDCC`, `PREF` and the `PSIDTS` pair exist on both
            // google.com and youtube.com with different values, and a flat
            // name-keyed merge picked the winner by iteration order — so a
            // youtube.com request could go out carrying a google.com value.
            val googleOnly = LinkedHashMap<String, String>()
            for (domain in GOOGLE_DOMAINS) {
                val c = cm.getCookie(domain) ?: continue
                parseInto(googleOnly, c)
            }
            // Clear existing cookies before refresh so stale/expired session entries don't linger (Y-H11)
            cookies.clear()
            for (domain in YOUTUBE_DOMAINS) {
                val c = cm.getCookie(domain) ?: continue
                parseAndPut(c)
            }
            for ((name, value) in googleOnly) {
                cookies.putIfAbsent(name, value)
            }
            saveToPrefs()
            return getMergedCookieHeader()
        }
    }

    /**
     * Replaces the store with the cookies in a raw header string
     * (e.g. "name=val; name2=val2") and persists them.
     *
     * This is a replace, not a merge: Dart owns the authoritative jar, and
     * merging left cookie names that Dart had dropped alive forever. After an
     * account switch the native store then sent a blend of two accounts'
     * cookies, which YouTube answers with LOGIN_REQUIRED.
     */
    fun setCookies(rawCookieHeader: String) {
        synchronized(lock) {
            if (rawCookieHeader.isBlank()) {
                clearStoredCookies()
                markSignedOut(true)
                return
            }
            cookies.clear()
            parseAndPut(rawCookieHeader)
            markSignedOut(false)
            saveToPrefs()
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

                val expiresAttr = parts.find { it.trim().startsWith("expires=", true) }
                if (expiresAttr != null) {
                    val dateStr = expiresAttr.substringAfter("=").trim()
                    val isExpired = try {
                        val format = java.text.SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", java.util.Locale.US)
                        val date = format.parse(dateStr)
                        date != null && date.before(java.util.Date())
                    } catch (_: Exception) {
                        false
                    }
                    if (isExpired) {
                        cookies.remove(kv[0].trim())
                        updated = true
                        continue
                    }
                }

                // Validate domain if present (only accept .youtube.com, .google.com or subdomains)
                val domainAttr = parts.find { it.trim().startsWith("domain=", true) }
                if (domainAttr != null) {
                    val domainVal = domainAttr.substringAfter("=").trim().lowercase().removePrefix(".")
                    val isAllowed = domainVal == "youtube.com" || domainVal.endsWith(".youtube.com") ||
                                    domainVal == "google.com" || domainVal.endsWith(".google.com") ||
                                    domainVal == "googleusercontent.com" || domainVal.endsWith(".googleusercontent.com")
                    if (!isAllowed) {
                        continue // Reject cookies from untrusted/unrelated domains
                    }
                }

                val name = kv[0].trim()
                val value = kv[1].trim()
                if (value.isEmpty() || value.equals("EXPIRED", ignoreCase = true)) {
                    cookies.remove(name)
                } else if (name.none { it.isISOControl() } && value.none { it.isISOControl() }) {
                    cookies[name] = value
                }
                updated = true
            }
            if (updated) {
                saveToPrefs()
            }
        }
    }

    /**
     * Returns the formatted `Cookie` header string for a request to [targetHost]
     * (a URL or bare host; null means "a YouTube host", which is what every
     * caller is).
     *
     * The store is deliberately domain-blind so a single jar can answer for both
     * google.com and youtube.com, but the *header* must not be: a browser never
     * sends the Google account-management cookies to youtube.com, and shipping
     * `LSID` / `ACCOUNT_CHOOSER` / `__Host-GAPS` on an InnerTube call is both a
     * credential leak to a host that has no business seeing them and a strong
     * automation signal. Everything the InnerTube session actually needs — the
     * SID / APISID / PSID / SIDCC / SIDTS families, LOGIN_INFO, PREF, the
     * VISITOR_* pair — is kept.
     */
    fun getMergedCookieHeader(targetHost: String? = null): String? {
        synchronized(lock) {
            if (cookies.isEmpty()) return null

            // Refuse non-YouTube / non-Google hosts explicitly to avoid credential leakage (Y-C5)
            if (targetHost != null && !isYouTubeOrGoogleHost(targetHost)) {
                return null
            }

            val youtubeTarget = isYouTubeHost(targetHost)
            val entries = cookies.entries.filter {
                if (youtubeTarget) isSendableToYouTube(it.key) else true
            }
            if (entries.isEmpty()) return null
            return entries.joinToString("; ") { "${it.key}=${it.value}" }
        }
    }

    private fun isYouTubeOrGoogleHost(targetHost: String?): Boolean {
        if (targetHost == null) return true
        val host = runCatching { java.net.URI(targetHost).host }.getOrNull()
            ?: targetHost.substringAfter("//").substringBefore("/").substringBefore(":")
        val lower = host.lowercase().removePrefix(".")
        return lower == "youtube.com" || lower.endsWith(".youtube.com") ||
               lower == "google.com" || lower.endsWith(".google.com") ||
               lower == "googleusercontent.com" || lower.endsWith(".googleusercontent.com")
    }

    private fun isYouTubeHost(targetHost: String?): Boolean {
        if (targetHost == null) return true
        val host = runCatching { java.net.URI(targetHost).host }.getOrNull()
            ?: targetHost.substringAfter("//").substringBefore("/")
        val lower = host.lowercase().removePrefix(".")
        return lower == "youtube.com" || lower.endsWith(".youtube.com")
    }

    private fun isSendableToYouTube(name: String): Boolean {
        // `__Host-` cookies are host-locked by definition, so one captured on an
        // accounts.google.com response can never legitimately appear on a
        // youtube.com request.
        if (name.startsWith("__Host-", ignoreCase = true)) return false
        return !GOOGLE_ACCOUNT_ONLY_COOKIE_NAMES.contains(name)
    }

    /**
     * Returns a specific cookie value (e.g. "SAPISID", "__Secure-3PSID").
     */
    fun getCookie(name: String): String? = cookies[name]

    /**
     * Checks if the session has valid authentication credentials.
     *
     * Presence alone is not enough: CookieManager readily hands back names whose
     * value is empty or the literal "EXPIRED", and counting those as signed in
     * made the native side attach cookies plus a SAPISIDHASH while Dart's
     * `looksLikeSignedInCookies` correctly reported logged out. The two must
     * agree, so this mirrors Dart: a non-blank *APISID and a non-blank
     * __Secure-1PSID/3PSID. Bare `SID` is not sufficient — it is present for
     * signed-out browsing too.
     */
    fun isSessionValid(): Boolean {
        val hasSapisid = hasUsableCookie("SAPISID") ||
                hasUsableCookie("__Secure-3PAPISID") ||
                hasUsableCookie("__Secure-1PAPISID")

        val hasPsid = hasUsableCookie("__Secure-3PSID") ||
                hasUsableCookie("__Secure-1PSID")

        return hasSapisid && hasPsid
    }

    private fun hasUsableCookie(name: String): Boolean {
        val value = cookies[name]?.trim() ?: return false
        return value.isNotEmpty() && !value.equals("EXPIRED", ignoreCase = true)
    }

    /**
     * Clears the cookies Pulsr tracks, in the store and in CookieManager.
     *
     * Scoped on purpose: `CookieManager.removeAllCookies(null)` wipes every
     * WebView cookie in the app — including unrelated in-app browsing and the
     * login WebView's own state — which contradicted the deliberately narrow
     * `_deleteSessionWebViewCookies` on the Dart side.
     */
    fun clear() {
        synchronized(lock) {
            val trackedNames = cookies.keys.toSet() + AUTH_COOKIE_NAMES
            clearStoredCookies()
            markSignedOut(true)
            runCatching {
                val cm = CookieManager.getInstance()
                val explicitDomains = listOf(
                    ".youtube.com",
                    ".music.youtube.com",
                    "music.youtube.com",
                    "www.youtube.com",
                    "youtube.com",
                    ".google.com",
                    "accounts.google.com"
                )
                for (domain in DOMAINS) {
                    for (name in trackedNames) {
                        cm.setCookie(domain, "$name=; Max-Age=0; Path=/")
                        for (d in explicitDomains) {
                            cm.setCookie(domain, "$name=; Max-Age=0; Path=/; Domain=$d")
                        }
                    }
                }
                cm.flush()
            }
        }
    }

    private fun clearStoredCookies() {
        cookies.clear()
        prefs?.edit()?.remove(KEY_COOKIES)?.apply()
        // Remove historic plaintext storage during logout/migration; it is
        // never used as a fallback for a new session.
        legacyPrefs.edit().remove(KEY_COOKIES).apply()
    }

    fun clearCookies() = clear()

    /**
     * Whether the user explicitly disconnected. Persisted so it outlives the
     * process: without it, an empty cookie store is indistinguishable from a
     * first run, and [readFromCookieManager] re-adopts whatever the WebView jar
     * still holds.
     */
    fun isSignedOut(): Boolean = prefs?.getBoolean(KEY_SIGNED_OUT, false) ?: signedOutMemory

    private fun markSignedOut(value: Boolean) {
        signedOutMemory = value
        try {
            if (value) {
                prefs?.edit()?.putBoolean(KEY_SIGNED_OUT, true)?.apply()
            } else {
                prefs?.edit()?.remove(KEY_SIGNED_OUT)?.apply()
            }
        } catch (_: Throwable) {
            // In-memory flag already set; a keystore failure must not make a
            // disconnect look like a fresh install.
        }
    }

    private fun parseAndPut(cookieString: String) = parseInto(cookies, cookieString)

    private fun parseInto(target: MutableMap<String, String>, cookieString: String) {
        for (pair in cookieString.split(";")) {
            val trimmed = pair.trim()
            if (trimmed.isEmpty()) continue
            val parts = trimmed.split("=", limit = 2)
            if (parts.size != 2 || parts[0].isBlank()) continue
            val name = parts[0].trim()
            val value = parts[1].trim()
            // Strip control characters: a pasted cookie blob containing CR/LF/TAB
            // makes every later request throw on header construction, which
            // bricks an otherwise "connected" session.
            if (name.any { it.isISOControl() } || value.any { it.isISOControl() }) continue
            // Tombstones must not displace a live value.
            if (value.isEmpty() || value.equals("EXPIRED", ignoreCase = true)) {
                target.remove(name)
                continue
            }
            target[name] = value
        }
    }

    private fun saveToPrefs() {
        try {
            val json = org.json.JSONObject()
            for ((k, v) in cookies) {
                json.put(k, v)
            }
            prefs?.edit()?.putString(KEY_COOKIES, json.toString())?.apply()
        } catch (_: Throwable) {
            // Unfiltered on purpose: this is storage, not a request header.
            val merged = cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
            prefs?.edit()?.putString(KEY_COOKIES, merged)?.apply()
        }
    }

    companion object {
        private const val PREFS_NAME = "ytm_session_cookies"
        private const val SECURE_PREFS_NAME = "ytm_session_cookies_secure"
        private const val KEY_COOKIES = "cookies"
        private const val KEY_SIGNED_OUT = "signed_out"

        // Fallback for the (rare) case where EncryptedSharedPreferences is
        // unavailable: a disconnect must still hold for this process.
        @Volatile
        private var signedOutMemory = false

        private val GOOGLE_DOMAINS = listOf(
            "https://google.com",
            "https://accounts.google.com",
            "https://myaccount.google.com",
        )

        private val YOUTUBE_DOMAINS = listOf(
            "https://accounts.youtube.com",
            "https://youtube.com",
            "https://www.youtube.com",
            "https://music.youtube.com",
        )

        val DOMAINS = GOOGLE_DOMAINS + YOUTUBE_DOMAINS

        // Google account-management cookies. A browser scopes these to
        // accounts.google.com / .google.com and never sends them to youtube.com,
        // so they are dropped from an InnerTube `Cookie` header. None of them is
        // used by InnerTube auth, which needs the SID / APISID / PSID / SIDCC /
        // SIDTS families plus LOGIN_INFO, PREF and the VISITOR_* pair.
        private val GOOGLE_ACCOUNT_ONLY_COOKIE_NAMES = setOf(
            "LSID", "LSOLH", "ACCOUNT_CHOOSER", "SMSV", "GAPS",
            "OSID", "__Secure-OSID", "NID", "AEC", "1P_JAR", "OTZ",
            "SEARCH_SAMESITE", "COMPASS", "S", "SSOSID",
        )

        // Names that must be expired on logout even if they were never read into
        // the store (CookieManager may hold HttpOnly variants we skipped).
        private val AUTH_COOKIE_NAMES = setOf(
            "SID", "HSID", "SSID", "APISID", "SAPISID", "LOGIN_INFO", "PREF",
            "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID",
            "__Secure-1PSIDTS", "__Secure-3PSIDTS", "__Secure-1PSIDCC", "__Secure-3PSIDCC",
            "SIDCC", "__Secure-YEC", "VISITOR_INFO1_LIVE", "VISITOR_PRIVACY_METADATA",
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
