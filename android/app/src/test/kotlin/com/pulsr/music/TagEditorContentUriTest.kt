package com.pulsr.music

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class TagEditorContentUriTest {

    class ThrowingWriteContentProvider : ContentProvider() {
        companion object {
            const val AUTHORITY = "com.pulsr.music.test.tagprovider"
            var flacBytes: ByteArray = ByteArray(0)
            val firstWriteAttemptDone = AtomicBoolean(false)
            val restoreCalled = AtomicBoolean(false)
        }

        override fun onCreate(): Boolean = true
        override fun getType(uri: Uri): String = "audio/flac"
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

        override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
            if (mode.contains("w")) {
                if (!firstWriteAttemptDone.getAndSet(true)) {
                    // First write-back attempt throws FileNotFoundException!
                    throw FileNotFoundException("Simulated storage write-back failure (permission/disk)")
                } else {
                    // Second write attempt is restoreContentUri (rollback)!
                    restoreCalled.set(true)
                    val pipe = ParcelFileDescriptor.createPipe()
                    return pipe[1]
                }
            }
            // For reading: return pipe with flacBytes
            val pipe = ParcelFileDescriptor.createPipe()
            val writePipe = pipe[1]
            val out = ParcelFileDescriptor.AutoCloseOutputStream(writePipe)
            out.write(flacBytes)
            out.close()
            return pipe[0]
        }

        override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
            val pfd = openFile(uri, mode) ?: return null
            return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
        }
    }

    @Test
    fun testContentUriWriteFailureRollsBackAndDeletesBackup() {
        val context = RuntimeEnvironment.getApplication()
        val flacSource = File("../../third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac")
            .takeIf { it.exists() }
            ?: File("third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac")
        ThrowingWriteContentProvider.flacBytes = flacSource.readBytes()
        ThrowingWriteContentProvider.firstWriteAttemptDone.set(false)
        ThrowingWriteContentProvider.restoreCalled.set(false)

        Robolectric.buildContentProvider(ThrowingWriteContentProvider::class.java)
            .create(ThrowingWriteContentProvider.AUTHORITY)

        val testUri = "content://${ThrowingWriteContentProvider.AUTHORITY}/audio/track1.flac"
        val plugin = TagEditorPlugin()
        plugin.context = context

        val latch = CountDownLatch(1)
        val errorRef = AtomicReference<String?>()
        val result = object : MethodChannel.Result {
            override fun success(res: Any?) {
                latch.countDown()
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                errorRef.set(errorCode)
                latch.countDown()
            }

            override fun notImplemented() {
                latch.countDown()
            }
        }

        plugin.onMethodCall(
            MethodCall("writeTags", mapOf(
                "path" to testUri,
                "tags" to mapOf("title" to "Updated Title")
            )),
            result
        )

        // Pump main looper while waiting for background worker to complete
        val deadline = System.currentTimeMillis() + 5000
        while (latch.count > 0 && System.currentTimeMillis() < deadline) {
            ShadowLooper.idleMainLooper(50, TimeUnit.MILLISECONDS)
            Thread.sleep(50)
        }

        assertEquals("writeTags must complete within timeout", 0L, latch.count)
        assertEquals("WRITE_TAGS_ERROR", errorRef.get())
        assertTrue("Rollback / restoreContentUri must be invoked on write failure", ThrowingWriteContentProvider.restoreCalled.get())

        // Assert NO leftover tag_backup_* or tag_write_* files in cacheDir
        val leftoverFiles = context.cacheDir.listFiles { _, name ->
            name.startsWith("tag_backup_") || name.startsWith("tag_write_")
        } ?: emptyArray()

        assertEquals("No temporary backup or write files should leak in cacheDir after failure", 0, leftoverFiles.size)
    }
}
