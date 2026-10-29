package com.pulsr.music

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The packaged asset and the compiled defaults must describe the same matrix.
 *
 * They had drifted: `client_capabilities.json` marked ANDROID_VR and IOS_MUSIC as
 * token-requiring while [ClientCapabilityMatrix] defaulted them to token-free,
 * and [YtmResilienceTest] asserted the default - so the test could never observe
 * what production actually loads. Once the asset wins, those two clients get a
 * per-video BotGuard mint and `pot=` appended to their media URLs.
 *
 * This compares the real asset off disk against [ClientCapabilityMatrix]'s
 * compiled map, which is the state the engine runs on until (and unless) the
 * matrix is initialised. The production parser is deliberately not invoked here:
 * `ClientCapabilityMatrix.loadFromJson` logs through `android.util.Log`, which is
 * not mocked on the plain-JVM test classpath, and a swallowed parse failure would
 * make this test compare defaults with defaults and pass vacuously.
 */
class ClientCapabilityAssetParityTest {

    private fun assetBody(): String {
        val candidates = listOf(
            File("src/ytmEnabled/assets/client_capabilities.json"),
            File("app/src/ytmEnabled/assets/client_capabilities.json"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: throw AssertionError(
                "client_capabilities.json not found from " + File(".").absolutePath,
            )
        return file.readText()
    }

    @Test
    fun assetMatchesCompiledDefaults() {
        val clients = JSONObject(assetBody()).getJSONObject("clients")

        var checked = 0
        for (type in InnertubeClient.ClientType.entries) {
            if (!clients.has(type.name)) continue
            val declared = clients.getJSONObject(type.name)
            val compiled = ClientCapabilityMatrix.getCapability(type)

            for (field in REQUIRED_FIELDS) {
                assertTrue(type.name + " asset entry is missing " + field, declared.has(field))
            }
            assertTrue(
                type.name + " requiresPoToken drifted between asset and defaults",
                declared.getBoolean("requiresPoToken") == compiled.requiresPoToken,
            )
            assertTrue(
                type.name + " requiresJsSignature drifted between asset and defaults",
                declared.getBoolean("requiresJsSignature") == compiled.requiresJsSignature,
            )
            assertTrue(
                type.name + " supportsStreamResolve drifted between asset and defaults",
                declared.getBoolean("supportsStreamResolve") == compiled.supportsStreamResolve,
            )
            assertTrue(
                type.name + " supportsSearch drifted between asset and defaults",
                declared.getBoolean("supportsSearch") == compiled.supportsSearch,
            )
            assertTrue(
                type.name + " supportsBrowse drifted between asset and defaults",
                declared.getBoolean("supportsBrowse") == compiled.supportsBrowse,
            )
            assertTrue(
                type.name + " priority drifted between asset and defaults",
                declared.getInt("priority") == compiled.priority,
            )
            assertEquals(
                type.name + " clientNameId drifted between asset and defaults",
                declared.getString("clientNameId"),
                compiled.clientNameId,
            )
            assertEquals(
                type.name + " clientVersion drifted between asset and defaults",
                declared.getString("clientVersion"),
                compiled.defaultClientVersion,
            )
            checked++
        }
        assertTrue("No clients compared; the asset path is wrong", checked >= 10)
    }

    @Test
    fun primaryNoTokenClientsStayTokenFree() {
        val vr = ClientCapabilityMatrix.getCapability(InnertubeClient.ClientType.ANDROID_VR)
        val ios = ClientCapabilityMatrix.getCapability(InnertubeClient.ClientType.IOS_MUSIC)
        assertFalse("ANDROID_VR must not require a poToken", vr.requiresPoToken)
        assertFalse("IOS_MUSIC must not require a poToken", ios.requiresPoToken)
        assertTrue(vr.supportsStreamResolve)
        assertTrue(ios.supportsStreamResolve)

        val clients = JSONObject(assetBody()).getJSONObject("clients")
        assertFalse(
            "asset marks ANDROID_VR as token-requiring",
            clients.getJSONObject("ANDROID_VR").getBoolean("requiresPoToken"),
        )
        assertFalse(
            "asset marks IOS_MUSIC as token-requiring",
            clients.getJSONObject("IOS_MUSIC").getBoolean("requiresPoToken"),
        )
    }

    private companion object {
        val REQUIRED_FIELDS = listOf(
            "clientNameId",
            "clientVersion",
            "requiresPoToken",
            "requiresLogin",
            "supportsStreamResolve",
            "supportsSearch",
            "supportsBrowse",
            "requiresJsSignature",
            "priority",
        )
    }
}
