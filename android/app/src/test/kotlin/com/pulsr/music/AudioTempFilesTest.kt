package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Test

class AudioTempFilesTest {

    private fun bytes(vararg values: Int): ByteArray = ByteArray(values.size) { values[it].toByte() }

    private fun ascii(text: String): ByteArray = text.toByteArray(Charsets.US_ASCII)

    @Test
    fun sniffsFlacOggWavM4aAndDsf() {
        assertEquals(".flac", AudioTempFiles.extensionFromMagic(ascii("fLaC") + ByteArray(8)))
        assertEquals(".ogg", AudioTempFiles.extensionFromMagic(ascii("OggS") + ByteArray(8)))
        assertEquals(
            ".wav",
            AudioTempFiles.extensionFromMagic(ascii("RIFF") + ByteArray(4) + ascii("WAVE"))
        )
        assertEquals(
            ".m4a",
            AudioTempFiles.extensionFromMagic(ByteArray(4) + ascii("ftyp") + ByteArray(4))
        )
        assertEquals(".dsf", AudioTempFiles.extensionFromMagic(ascii("DSD ") + ByteArray(8)))
        assertEquals(".dff", AudioTempFiles.extensionFromMagic(ascii("FRM8") + ByteArray(8)))
    }

    @Test
    fun sniffsMp3ById3AndFrameSync() {
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(ascii("ID3") + ByteArray(9)))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(bytes(0xFF, 0xFB, 0x90, 0x00)))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(bytes(0xFF, 0xF3, 0x00, 0x00)))
    }

    @Test
    fun unknownMagicFallsBackToEmptySuffix() {
        assertEquals("", AudioTempFiles.extensionFromMagic(ascii("NOPE") + ByteArray(8)))
        assertEquals("", AudioTempFiles.extensionFromMagic(ByteArray(0)))
    }
}
