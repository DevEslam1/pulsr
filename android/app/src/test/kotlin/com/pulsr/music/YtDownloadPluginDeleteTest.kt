package com.pulsr.music

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class YtDownloadPluginDeleteTest {
    @Test
    fun `deleteFromMusic removes a file MediaStore does not index`() {
        val context = RuntimeEnvironment.getApplication()
        val file = File(context.cacheDir, "delete-test-${System.nanoTime()}.mp3")
        file.writeText("audio")

        val deleted = YtDownloadPlugin().deleteFromMusic(
            context,
            file.absolutePath,
            null,
        )

        assertTrue(deleted)
        assertFalse(file.exists())
    }

    @Test
    fun `deleteFromMusic reports false when the file is already gone`() {
        val context = RuntimeEnvironment.getApplication()
        val file = File(context.cacheDir, "gone-${System.nanoTime()}.mp3")

        assertFalse(
            YtDownloadPlugin().deleteFromMusic(context, file.absolutePath, null),
        )
    }
}
