package com.pulsr.music

import android.content.Context

/**
 * Layer 3: Atomic Identity Object for Innertube Requests.
 *
 * Bundles client type, device fingerprint, visitorData, poToken, cookies, and client version.
 * Rotating an identity rotates all fields atomically to avoid detection from mismatched identity parameters.
 */
internal data class YtmIdentity(
    val clientType: InnertubeClient.ClientType,
    val fingerprint: FingerprintStore.DeviceFingerprint,
    val visitorData: String,
    val poToken: String,
    val cookies: String,
    val clientVersion: String,
    val isLimitedMode: Boolean = false
) {
    companion object {
        fun createCurrent(
            context: Context,
            clientType: InnertubeClient.ClientType,
            cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context),
            poTokenManager: PoTokenManager = PoTokenManager,
            limitedMode: Boolean = false
        ): YtmIdentity {
            val fp = FingerprintStore.getFingerprint(context)
            val capability = ClientCapabilityMatrix.getCapability(clientType)
            val version = capability.defaultClientVersion

            val authedWeb = clientType.isWeb && cookieStore.isSessionValid()
            val visitor = if (authedWeb) {
                poTokenManager.sessionVisitorData.ifEmpty { poTokenManager.visitorData }
            } else {
                poTokenManager.visitorData
            }

            val token = if (limitedMode) "" else poTokenManager.streamingPoToken
            val cookieHeader = if (clientType.isWeb) cookieStore.getMergedCookieHeader() ?: "" else ""

            return YtmIdentity(
                clientType = clientType,
                fingerprint = fp,
                visitorData = visitor,
                poToken = token,
                cookies = cookieHeader,
                clientVersion = version,
                isLimitedMode = limitedMode
            )
        }

        fun rotate(
            context: Context,
            clientType: InnertubeClient.ClientType,
            cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context)
        ): YtmIdentity {
            PoTokenManager.invalidate()
            return createCurrent(context, clientType, cookieStore)
        }
    }
}
