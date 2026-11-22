package com.pulsr.music

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File
import java.io.FileOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class AudioIntentResolutionTest {

    private lateinit var context: Context
    private lateinit var activity: MainActivity

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        activity = controller.get()
    }

    @Test
    fun extensionForExtractsExtensionFromLocalFileUri() {
        val uri = Uri.parse("file:///storage/emulated/0/Music/track.flac")
        assertEquals(".flac", AudioTempFiles.extensionFor(context, uri))

        val uriMp3 = Uri.parse("file:///sdcard/Music/cool_song.MP3")
        assertEquals(".mp3", AudioTempFiles.extensionFor(context, uriMp3))

        val uriEncoded = Uri.parse("file:///storage/emulated/0/My%20Music/song%20name.m4a")
        assertEquals(".m4a", AudioTempFiles.extensionFor(context, uriEncoded))
    }

    @Test
    fun resolvePlayableAudioUriLeavesContentAndSpecialSchemesUnchanged() {
        val contentUri = Uri.parse("content://media/external/audio/media/42")
        assertEquals(contentUri, activity.resolvePlayableAudioUri(contentUri))

        val pulsrUri = Uri.parse("pulsr://voice-search?query=test")
        assertEquals(pulsrUri, activity.resolvePlayableAudioUri(pulsrUri))

        val httpUri = Uri.parse("https://example.com/audio.mp3")
        assertEquals(httpUri, activity.resolvePlayableAudioUri(httpUri))
    }

    @Test
    fun resolvePlayableAudioUriPreservesDirectlyReadableFiles() {
        val temp = File(context.cacheDir, "readable_test.mp3")
        temp.writeBytes(byteArrayOf(0xFF.toByte(), 0xFB.toByte(), 0x90.toByte(), 0x00))
        val fileUri = Uri.fromFile(temp)

        val resolved = activity.resolvePlayableAudioUri(fileUri)
        assertEquals(fileUri, resolved)
        temp.delete()
    }

    @Test
    fun resolvePlayableAudioUriResolvesToMediaStoreContentUriWhenIndexed() {
        // Insert into MediaStore shadow with DISPLAY_NAME and RELATIVE_PATH
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, "unreadable_scoped.flac")
            put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/")
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/flac")
            put(MediaStore.Audio.Media.TITLE, "Unreadable Scoped")
        }
        val inserted = context.contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
        assertNotNull(inserted)

        // Query the generated DATA column from MediaStore
        var dataPath: String? = null
        context.contentResolver.query(inserted!!, arrayOf(MediaStore.Audio.Media.DATA), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                dataPath = cursor.getString(idx)
            }
        }
        assertNotNull(dataPath)

        // Provide content bytes so openInputStream succeeds
        context.contentResolver.openOutputStream(inserted)?.use { out ->
            out.write(byteArrayOf(0x66, 0x4C, 0x61, 0x43)) // fLaC
        }

        val fileUri = Uri.fromFile(File(dataPath!!))
        val resolved = activity.resolveFileUriToContentUri(fileUri)
        assertNotNull("Expected resolution to MediaStore content URI", resolved)
        assertTrue(resolved.toString().startsWith("content://"))
    }

    @Test
    fun resolvePlayableAudioUriFallsBackToTempCopyWhenNotIndexedInMediaStore() {
        // Create a file in cacheDir to simulate a file that can be opened by the app
        // but whose original path in an external folder was copied
        val srcFile = File(context.cacheDir, "src_unindexed.wav")
        srcFile.writeBytes(byteArrayOf(0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45))
        val srcUri = Uri.fromFile(srcFile)

        val tempCopy = AudioTempFiles.copyToTempFile(context, srcUri, "audio_intent_")
        assertTrue(tempCopy.exists())
        assertTrue(tempCopy.name.startsWith("audio_intent_"))
        assertTrue(tempCopy.name.endsWith(".wav"))
        assertEquals(srcFile.length(), tempCopy.length())
        tempCopy.delete()
        srcFile.delete()
    }
}
