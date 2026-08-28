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

    @Volatile
    private var capabilities: Map<InnertubeClient.ClientType, ClientCapability> = defaultCapabilities

    fun init(context: Context) {
        try {
            val jsonString = context.assets.open(ASSET_FILE).bufferedReader().use { it.readText() }
            loadFromJson(jsonString)
        } catch (e: Exception) {
            Log.w(TAG, "Failed loading $ASSET_FILE from assets, using built-in matrix defaults: ${e.message}")
            capabilities = defaultCapabilities
        }
    }

    fun loadFromJson(jsonString: String) {
        try {
            val root = JSONObject(jsonString)
            val clientsJson = root.optJSONObject("clients") ?: return
            val mutable = mutableMapOf<InnertubeClient.ClientType, ClientCapability>()

            for (type in InnertubeClient.ClientType.values()) {
                val clientObj = clientsJson.optJSONObject(type.name)
                if (clientObj != null) {
                    mutable[type] = ClientCapability(
                        clientType = type,
                        clientNameId = clientObj.optString("clientNameId", type.clientNameId),
                        defaultClientVersion = clientObj.optString("clientVersion", type.clientVersion),
                        requiresPoToken = clientObj.optBoolean("requiresPoToken", false),
                        requiresLogin = clientObj.optBoolean("requiresLogin", false),
                        supportsStreamResolve = clientObj.optBoolean("supportsStreamResolve", true),
                        supportsSearch = clientObj.optBoolean("supportsSearch", false),
                        supportsBrowse = clientObj.optBoolean("supportsBrowse", false),
                        requiresJsSignature = clientObj.optBoolean("requiresJsSignature", false),
                        priority = clientObj.optInt("priority", 0)
                    )
                } else {
                    defaultCapabilities[type]?.let { mutable[type] = it }
                }
            }
            capabilities = mutable
            Log.i(TAG, "Successfully loaded client capabilities matrix (${mutable.size} clients)")
        } catch (e: Exception) {
            Log.w(TAG, "Error parsing client capability JSON, falling back to defaults", e)
            capabilities = defaultCapabilities
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
