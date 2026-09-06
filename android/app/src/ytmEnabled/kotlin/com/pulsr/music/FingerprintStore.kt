package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import java.util.UUID

/**
 * Layer 3: Stable Fingerprint Store for YouTube Music Innertube Clients.
 *
 * Generates and persists a stable per-installation device identity.
 * Prevents detection caused by fluctuating or mixed device fingerprints.
 */
internal object FingerprintStore {
    private const val PREFS_NAME = "ytm_fingerprint_store"
    private const val KEY_INSTALL_ID = "ytm_install_uuid"
    private const val KEY_DEVICE_MAKE = "ytm_device_make"
    private const val KEY_DEVICE_MODEL = "ytm_device_model"
    private const val KEY_OS_VERSION = "ytm_os_version"
    private const val KEY_SDK_INT = "ytm_sdk_int"
    private const val KEY_HL = "ytm_hl"
    private const val KEY_GL = "ytm_gl"

    // The whole YTM surface pins one region: the sign-in WebView's
    // anti-fingerprint script hardcodes Africa/Cairo and Cairo coordinates, and
    // the Dart Innertube contexts send the same pair. A native fingerprint that
    // disagrees with those is a stronger bot signal than a "wrong" but coherent
    // one, so this is the single source of truth rather than four literals.
    val DEFAULT_HL: String
        get() = java.util.Locale.getDefault().language.ifBlank { "en" }.lowercase()
    val DEFAULT_GL: String
        get() = java.util.Locale.getDefault().country.ifBlank { "US" }.uppercase()

    internal data class DeviceFingerprint(
        val installUuid: String,
        val deviceMake: String,
        val deviceModel: String,
        val osVersion: String,
        val sdkInt: Int,
        val hl: String = DEFAULT_HL,
        val gl: String = DEFAULT_GL
    ) {
        fun buildUserAgent(clientType: InnertubeClient.ClientType): String {
            val ver = clientType.effectiveClientVersion
            return when (clientType) {
                InnertubeClient.ClientType.ANDROID_MUSIC ->
                    "com.google.android.apps.youtube.music/$ver (Linux; U; Android $osVersion; ${hl}_${gl}; $deviceModel) gzip"
                InnertubeClient.ClientType.ANDROID_VR ->
                    "com.google.android.apps.youtube.vr.oculus/$ver (Linux; U; Android 12; ${hl}_${gl}; Quest 2) gzip"
                InnertubeClient.ClientType.ANDROID_CREATOR ->
                    "com.google.android.apps.youtube.creator/$ver (Linux; U; Android 13; ${hl}_${gl}) gzip"
                InnertubeClient.ClientType.IOS_MUSIC ->
                    "com.google.ios.youtubemusic/$ver (iPhone15,3; U; CPU iOS 18_0 like Mac OS X; ${hl}_${gl})"
                InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER ->
                    "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36"
                InnertubeClient.ClientType.MWEB ->
                    "Mozilla/5.0 (Linux; Android $osVersion; $deviceModel) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36"
                InnertubeClient.ClientType.WEB_REMIX, InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER ->
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
                InnertubeClient.ClientType.ANDROID_TESTSUITE ->
                    "com.google.android.youtube/$ver (Linux; U; Android 9; gzip)"
            }
        }
    }

    @Volatile
    private var cachedFingerprint: DeviceFingerprint? = null

    fun getFingerprint(context: Context): DeviceFingerprint {
        cachedFingerprint?.let { return it }

        synchronized(this) {
            cachedFingerprint?.let { return it }

            val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            var uuid = prefs.getString(KEY_INSTALL_ID, null)

            if (uuid == null) {
                uuid = UUID.randomUUID().toString()
                val make = Build.MANUFACTURER.ifBlank { "Google" }
                val model = Build.MODEL.ifBlank { "Pixel 8" }
                val osVer = Build.VERSION.RELEASE.ifBlank { "14" }
                val sdk = if (Build.VERSION.SDK_INT > 0) Build.VERSION.SDK_INT else 34

                prefs.edit()
                    .putString(KEY_INSTALL_ID, uuid)
                    .putString(KEY_DEVICE_MAKE, make)
                    .putString(KEY_DEVICE_MODEL, model)
                    .putString(KEY_OS_VERSION, osVer)
                    .putInt(KEY_SDK_INT, sdk)
                    .putString(KEY_HL, DEFAULT_HL)
                    .putString(KEY_GL, DEFAULT_GL)
                    .apply()

                val fp = DeviceFingerprint(
                    installUuid = uuid,
                    deviceMake = make,
                    deviceModel = model,
                    osVersion = osVer,
                    sdkInt = sdk
                )
                cachedFingerprint = fp
                return fp
            } else {
                val fp = DeviceFingerprint(
                    installUuid = uuid,
                    deviceMake = prefs.getString(KEY_DEVICE_MAKE, "Google") ?: "Google",
                    deviceModel = prefs.getString(KEY_DEVICE_MODEL, "Pixel 8") ?: "Pixel 8",
                    osVersion = prefs.getString(KEY_OS_VERSION, "14") ?: "14",
                    sdkInt = prefs.getInt(KEY_SDK_INT, 34),
                    hl = prefs.getString(KEY_HL, DEFAULT_HL) ?: DEFAULT_HL,
                    gl = prefs.getString(KEY_GL, DEFAULT_GL) ?: DEFAULT_GL
                )
                cachedFingerprint = fp
                return fp
            }
        }
    }

    fun resetFingerprint(context: Context): DeviceFingerprint {
        synchronized(this) {
            val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
            cachedFingerprint = null
            return getFingerprint(context)
        }
    }

    fun updateLocale(context: Context, hl: String?, gl: String?) {
        synchronized(this) {
            val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            if (!hl.isNullOrBlank()) editor.putString(KEY_HL, hl)
            if (!gl.isNullOrBlank()) editor.putString(KEY_GL, gl)
            editor.apply()
            cachedFingerprint = null
        }
    }
}
