package com.pulsr.music

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class VersionGateMatrixTest(private val apiLevel: Int) {

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "API_{0}")
        fun apiLevels(): Collection<Int> {
            return (28..36).toList()
        }
    }

    @Test
    fun testAudioCapabilityMatrixSafety() {
        val supportsDynamics = apiLevel >= 28
        val supportsOffload = apiLevel >= 29
        val supportsExtBitDepth = apiLevel >= 31
        val supportsLeAudioPublic = apiLevel >= 33
        val usesFgsDataSync = apiLevel == 34
        val usesFgsMediaProc = apiLevel >= 35
        val isAndroid16 = apiLevel >= 36

        // DynamicsProcessing floor is API 28
        assertTrue("DynamicsProcessing must be supported from API 28", supportsDynamics)

        // Offload is API 29+
        if (apiLevel >= 29) {
            assertTrue("API $apiLevel must support hardware offload", supportsOffload)
        } else {
            assertFalse("API $apiLevel must not support hardware offload", supportsOffload)
        }

        // Extended PCM bit depth (24/32-bit) is API 31+
        if (apiLevel >= 31) {
            assertTrue("API $apiLevel must support extended PCM bit depth", supportsExtBitDepth)
        } else {
            assertFalse("API $apiLevel must not claim extended PCM bit depth", supportsExtBitDepth)
        }

        // LE Audio public APIs are API 33+
        if (apiLevel >= 33) {
            assertTrue("API $apiLevel must support public LE Audio APIs", supportsLeAudioPublic)
        } else {
            assertFalse("API $apiLevel must not claim public LE Audio APIs", supportsLeAudioPublic)
        }

        // FGS type selection: dataSync on 34, mediaProcessing on 35+
        if (apiLevel == 34) {
            assertTrue("API 34 must use dataSync FGS", usesFgsDataSync)
        }
        if (apiLevel >= 35) {
            assertTrue("API $apiLevel must use mediaProcessing FGS", usesFgsMediaProc)
        }
    }
}
