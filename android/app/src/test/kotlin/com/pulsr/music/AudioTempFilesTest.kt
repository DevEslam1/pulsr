package com.pulsr.music

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

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

    @Test
    fun mpegFrameSyncRejectsReservedVersionAndAcceptsValidFrames() {
        // 0xEB -> version bits (01 = reserved) -> must NOT sniff as MP3 (T26)
        assertEquals("", AudioTempFiles.extensionFromMagic(bytes(0xFF, 0xEB, 0x90, 0x00)))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(bytes(0xFF, 0xE3, 0x00, 0x00)))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(bytes(0xFF, 0xFA, 0x90, 0x00)))
    }

    @Test
    fun copyLimitedEnforcesExactOverflowZeroAndSilentTruncationBoundaries() {
        val payload = ByteArray(100) { (it and 0xFF).toByte() }

        val emptyOut = ByteArrayOutputStream()
        AudioTempFiles.copyLimited(ByteArrayInputStream(ByteArray(0)), emptyOut, maxBytes = 0L)
        assertEquals(0, emptyOut.toByteArray().size)

        val zeroCapOut = ByteArrayOutputStream()
        try {
            AudioTempFiles.copyLimited(ByteArrayInputStream(byteArrayOf(1)), zeroCapOut, maxBytes = 0L)
            fail("Expected TempFileSizeLimitException for non-empty input with maxBytes = 0")
        } catch (_: AudioTempFiles.TempFileSizeLimitException) {
            // expected
        }

        val overflowByOneOut = ByteArrayOutputStream()
        try {
            AudioTempFiles.copyLimited(ByteArrayInputStream(payload), overflowByOneOut, maxBytes = 99L)
            fail("Expected TempFileSizeLimitException when payload exceeds maxBytes by 1 byte")
        } catch (_: AudioTempFiles.TempFileSizeLimitException) {
            // expected
        }

        val truncatedOut = ByteArrayOutputStream()
        AudioTempFiles.copyLimited(
            ByteArrayInputStream(payload),
            truncatedOut,
            maxBytes = 40L,
            throwOnOverflow = false,
        )
        assertArrayEquals(payload.copyOfRange(0, 40), truncatedOut.toByteArray())
    }

    @Test
    fun canonicalAudioExtensionsIncludeContainersAndExcludePlaylists() {
        val expected = listOf(".webm", ".oga", ".aifc", ".wma", ".ape", ".tta", ".wv", ".aif", ".mp4", ".3gp")
        for (ext in expected) {
            assertTrue("Expected $ext in AUDIO_EXTENSIONS", ext in AudioTempFiles.AUDIO_EXTENSIONS)
        }
        assertFalse(".m3u" in AudioTempFiles.AUDIO_EXTENSIONS)
        assertFalse(".m3u8" in AudioTempFiles.AUDIO_EXTENSIONS)
    }
}
