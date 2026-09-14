package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsbAudioControlParserTest {

    private fun uac2Config(): ByteArray = byteArrayOf(
        // Audio Control interface (class 0x01 / subclass 0x01 / protocol 0x20)
        9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
        // Feature Unit (subtype 0x06), unitId 3, source 2, controlSize 2,
        // master + 2 channels each advertising Volume (0x02) + Mute (0x01).
        12, 0x24, 0x06, 0x03, 0x02, 0x02,
        0x03, 0x00,
        0x03, 0x00,
        0x03, 0x00,
        // AudioStreaming interface #1
        9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x20, 0x00,
        // Isochronous OUT endpoint (addr 0x01, attrs 0x01, max packet 0x0040)
        7, 0x05, 0x01, 0x01, 0x40, 0x00, 0x01,
    )

    @Test
    fun parsesIsochronousOutEndpoint() {
        val result = UsbAudioControlParser.parse(uac2Config())
        val ep = result.streamingEndpoint
        assertNotNull(ep)
        assertEquals(0x01, ep!!.address)
        assertEquals(1, ep.interfaceNumber)
        assertEquals(0, ep.altSetting)
        assertEquals(0x40, ep.maxPacketSize)
    }

    @Test
    fun parsesUac2FeatureUnitVolume() {
        val result = UsbAudioControlParser.parse(uac2Config())
        assertEquals(UsbAudioControlParser.UAC2, result.uacVersion)
        assertTrue(result.hasVolumeControl)
        val vu = result.volumeUnit
        assertNotNull(vu)
        assertEquals(3, vu!!.unitId)
        assertEquals(0, vu.interfaceNumber)
        assertEquals(2, vu.channels)
        assertTrue(vu.volumeOnMaster)
        assertEquals(1, result.streamingInterface)
    }

    @Test
    fun parsesUac1Protocol() {
        val data = uac2Config()
        data[7] = 0x00 // Audio Control protocol -> UAC1
        val result = UsbAudioControlParser.parse(data)
        assertEquals(UsbAudioControlParser.UAC1, result.uacVersion)
    }

    @Test
    fun noFeatureUnitWhenVolumeBitAbsent() {
        val data = uac2Config()
        // Clear the Volume bit, keep Mute (0x01) in every control bitmap.
        // FU control bitmaps start at index 15 (master), 17 (ch1), 19 (ch2).
        for (offset in intArrayOf(15, 17, 19)) {
            data[offset] = 0x01
            data[offset + 1] = 0x00
        }
        val result = UsbAudioControlParser.parse(data)
        assertNull(result.volumeUnit)
    }

    @Test
    fun malformedDescriptorsDoNotThrow() {
        assertNull(UsbAudioControlParser.parse(null).volumeUnit)
        assertEquals(0, UsbAudioControlParser.parse(ByteArray(0)).uacVersion)
        assertEquals(
            0,
            UsbAudioControlParser.parse(byteArrayOf(0xFF.toByte(), 0x24, 0x06)).uacVersion,
        )
    }
}
