package com.pulsr.music

import android.content.Context
import android.util.Log
import org.json.JSONObject

/**
 * Layer 3: Dynamic Data-Driven Client Capability Matrix.
 *
 * Defines capabilities, token requirements, and feature support for each Innertube client type.
 * Loaded from assets with robust fallback to compile-time defaults.
 */
internal object ClientCapabilityMatrix {
    private const val TAG = "ClientCapabilityMatrix"
    private const val ASSET_FILE = "client_capabilities.json"

    internal data class ClientCapability(
        val clientType: InnertubeClient.ClientType,
        val clientNameId: String,
        val defaultClientVersion: String,
        val requiresPoToken: Boolean,
        val requiresLogin: Boolean,
        val supportsStreamResolve: Boolean,
        val supportsSearch: Boolean,
        val supportsBrowse: Boolean,
        val requiresJsSignature: Boolean,
        val priority: Int = 0
    )

    private val defaultCapabilities: Map<InnertubeClient.ClientType, ClientCapability> = mapOf(
        InnertubeClient.ClientType.ANDROID_VR to ClientCapability(
            clientType = InnertubeClient.ClientType.ANDROID_VR,
            clientNameId = "28",
            defaultClientVersion = "1.63.27",
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = false,
            priority = 10
        ),
        InnertubeClient.ClientType.IOS_MUSIC to ClientCapability(
            clientType = InnertubeClient.ClientType.IOS_MUSIC,
            clientNameId = "26",
            defaultClientVersion = "8.32.1",
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = false,
            priority = 9
        ),
        InnertubeClient.ClientType.ANDROID_MUSIC to ClientCapability(
            clientType = InnertubeClient.ClientType.ANDROID_MUSIC,
            clientNameId = "21",
            defaultClientVersion = "8.32.50",
            requiresPoToken = true,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = false,
            priority = 8
        ),
        InnertubeClient.ClientType.ANDROID_CREATOR to ClientCapability(
            clientType = InnertubeClient.ClientType.ANDROID_CREATOR,
            clientNameId = "62",
            defaultClientVersion = "24.45.100",
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = false,
            supportsBrowse = false,
            requiresJsSignature = false,
            priority = 7
        ),
        InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER to ClientCapability(
            clientType = InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            clientNameId = "85",
            defaultClientVersion = "2.0",
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = false,
            supportsBrowse = false,
            requiresJsSignature = true,
            priority = 6
        ),
        InnertubeClient.ClientType.WEB_REMIX to ClientCapability(
            clientType = InnertubeClient.ClientType.WEB_REMIX,
            clientNameId = "67",
            defaultClientVersion = "1.20260825.01.00",
            requiresPoToken = true,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = true,
            priority = 5
        ),
        InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER to ClientCapability(
            clientType = InnertubeClient.ClientType.WEB_EMBEDDED_PLAYER,
            clientNameId = "56",
            defaultClientVersion = "1.20260825.01.00",
            requiresPoToken = true,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = false,
            supportsBrowse = false,
            requiresJsSignature = true,
            priority = 4
        ),
        InnertubeClient.ClientType.MWEB to ClientCapability(
            clientType = InnertubeClient.ClientType.MWEB,
            clientNameId = "65",
            defaultClientVersion = "2.20260825.01.00",
            requiresPoToken = true,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = true,
            priority = 3
        ),
        InnertubeClient.ClientType.ANDROID_TESTSUITE to ClientCapability(
            clientType = InnertubeClient.ClientType.ANDROID_TESTSUITE,
            clientNameId = "30",
            defaultClientVersion = "1.9",
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = false,
            supportsBrowse = false,
            requiresJsSignature = false,
            priority = 2
        )
    )

    enum class CapabilityLoadState {
        NOT_LOADED,
        LOADED_FROM_ASSETS,
        FALLBACK_DEFAULTS,
        PARSE_ERROR
    }

    @Volatile
    var loadState: CapabilityLoadState = CapabilityLoadState.NOT_LOADED
        private set

    @Volatile
    private var isInitialized = false

    @Volatile
    private var capabilities: Map<InnertubeClient.ClientType, ClientCapability> = defaultCapabilities

    /**
     * WEB_REMIX `clientVersion`, scraped from music.youtube.com by the Dart
     * [YtmClientVersionResolver] and pushed over the method channel.
     *
     * The pinned literal in `client_capabilities.json` ages out, and YouTube
     * answers a stale WEB_REMIX version with UNPLAYABLE "Video unavailable" on
     * every player request — indistinguishable at the client from a rejected
     * poToken. The synthetic `1.<today>` fallback in
     * [InnertubeClient.ClientType.effectiveClientVersion] keeps the date fresh
     * but guesses the build suffix, so the scraped value wins whenever present.
     */
    @Volatile
    private var webMusicClientVersion: String = ""

    fun setWebMusicClientVersion(version: String) {
        val normalized = version.trim()
        if (normalized.isEmpty() || normalized == webMusicClientVersion) return
        webMusicClientVersion = normalized
        Log.i(TAG, "WEB_REMIX client version updated to $normalized")
    }

    fun getWebMusicClientVersion(): String = webMusicClientVersion

    fun init(context: Context) {
        if (isInitialized) return
        synchronized(this) {
            if (isInitialized) return
            try {
                val jsonString = context.assets.open(ASSET_FILE).bufferedReader().use { it.readText() }
                loadFromJson(jsonString)
                loadPersistedRemote(context)
                loadState = CapabilityLoadState.LOADED_FROM_ASSETS
            } catch (e: Exception) {
                Log.w(TAG, "Failed loading $ASSET_FILE from assets, using built-in matrix defaults: ${e.message}")
                capabilities = defaultCapabilities
                loadState = CapabilityLoadState.FALLBACK_DEFAULTS
            }
            isInitialized = true
        }
    }

    private const val REMOTE_FILE = "client_capabilities_remote.json"

    /**
     * 2026-09 gap 3: apply a remote capability override (transport-agnostic).
     * Caller fetches the JSON (backend URL / Firestore / Remote Config) and
     * pushes it here. Persisted under filesDir; loader precedence:
     * built-in defaults -> APK asset -> persisted remote (newest wins).
     * Returns false without side effects on invalid JSON.
     */
    fun applyRemoteCapabilities(jsonString: String, context: Context): Boolean {
        return try {
            loadFromJson(jsonString)
            java.io.File(context.filesDir, REMOTE_FILE).writeText(jsonString)
            Log.i(TAG, "Remote capability overrides applied and persisted")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Rejected remote capability JSON: " + e.message)
            false
        }
    }

    /** Re-applies the persisted remote override at startup (call after asset load). */
    fun loadPersistedRemote(context: Context) {
        val f = java.io.File(context.filesDir, REMOTE_FILE)
        if (f.isFile) {
            runCatching { loadFromJson(f.readText()) }
                .onFailure { Log.w(TAG, "Persisted remote capabilities invalid, ignoring: " + it.message) }
        }
    }

    /** Diagnostic state for the MethodChannel. */
    fun remoteState(context: Context): Map<String, Any> {
        val f = java.io.File(context.filesDir, REMOTE_FILE)
        return mapOf(
            "source" to loadState.name,
            "remoteAppliedAtEpochMs" to (if (f.isFile) f.lastModified() else 0L),
            "clientCount" to capabilities.size,
        )
    }

    fun loadFromJson(jsonString: String) {
        try {
            val root = JSONObject(jsonString)
            val clientsJson = root.optJSONObject("clients") ?: run {
                loadState = CapabilityLoadState.PARSE_ERROR
                return
            }
            val mutable = mutableMapOf<InnertubeClient.ClientType, ClientCapability>()

            for (type in InnertubeClient.ClientType.entries) {
                val clientObj = clientsJson.optJSONObject(type.name)
                if (clientObj != null) {
                    // Each field falls back to the built-in capability, not to a blanket
                    // false/0: a JSON entry that only overrides `clientVersion` used to
                    // silently reset requiresPoToken, supportsSearch and priority,
                    // reordering the whole chain and dropping search-capable clients.
                    val fallback = defaultCapabilities[type]
                    mutable[type] = ClientCapability(
                        clientType = type,
                        clientNameId = clientObj.optString("clientNameId", fallback?.clientNameId ?: type.clientNameId),
                        defaultClientVersion = clientObj.optString("clientVersion", fallback?.defaultClientVersion ?: type.clientVersion),
                        requiresPoToken = clientObj.optBoolean("requiresPoToken", fallback?.requiresPoToken ?: false),
                        requiresLogin = clientObj.optBoolean("requiresLogin", fallback?.requiresLogin ?: false),
                        supportsStreamResolve = clientObj.optBoolean("supportsStreamResolve", fallback?.supportsStreamResolve ?: true),
                        supportsSearch = clientObj.optBoolean("supportsSearch", fallback?.supportsSearch ?: false),
                        supportsBrowse = clientObj.optBoolean("supportsBrowse", fallback?.supportsBrowse ?: false),
                        requiresJsSignature = clientObj.optBoolean("requiresJsSignature", fallback?.requiresJsSignature ?: false),
                        priority = clientObj.optInt("priority", fallback?.priority ?: 0)
                    )
                } else {
                    defaultCapabilities[type]?.let { mutable[type] = it }
                }
            }
            capabilities = mutable
            loadState = CapabilityLoadState.LOADED_FROM_ASSETS
            Log.i(TAG, "Successfully loaded client capabilities matrix (${mutable.size} clients)")
        } catch (e: Exception) {
            Log.w(TAG, "Error parsing client capability JSON, falling back to defaults", e)
            capabilities = defaultCapabilities
            loadState = CapabilityLoadState.PARSE_ERROR
        }
    }

    fun getCapability(type: InnertubeClient.ClientType): ClientCapability {
        return capabilities[type] ?: defaultCapabilities[type] ?: ClientCapability(
            clientType = type,
            clientNameId = type.clientNameId,
            defaultClientVersion = type.clientVersion,
            requiresPoToken = false,
            requiresLogin = false,
            supportsStreamResolve = true,
            supportsSearch = true,
            supportsBrowse = true,
            requiresJsSignature = false
        )
    }

    fun getEligibleClients(
        supportsStreamResolve: Boolean = false,
        supportsSearch: Boolean = false,
        supportsBrowse: Boolean = false,
        hasPoToken: Boolean = false,
        isLoggedIn: Boolean = false,
        hasJsSignatureEngine: Boolean = true
    ): List<InnertubeClient.ClientType> {
        return capabilities.values
            .filter { cap ->
                if (supportsStreamResolve && !cap.supportsStreamResolve) return@filter false
                if (supportsSearch && !cap.supportsSearch) return@filter false
                if (supportsBrowse && !cap.supportsBrowse) return@filter false
                if (cap.requiresPoToken && !hasPoToken) return@filter false
                if (cap.requiresLogin && !isLoggedIn) return@filter false
                if (cap.requiresJsSignature && !hasJsSignatureEngine) return@filter false
                true
            }
            .sortedByDescending { it.priority }
            .map { it.clientType }
    }
}
