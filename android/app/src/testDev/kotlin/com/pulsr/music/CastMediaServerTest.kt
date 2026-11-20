package com.pulsr.music

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class CastMediaServerTest {

    private lateinit var server: CastMediaServer
    private lateinit var tempFile: File

    @Before
    fun setUp() {
        server = CastMediaServer()
        assertTrue(server.start(bindToLoopbackOnly = true))
        tempFile = File.createTempFile("pulsr_cast_test_", ".mp3").apply {
            deleteOnExit()
            writeBytes(ByteArray(1024) { (it % 256).toByte() })
        }
    }

    @After
    fun tearDown() {
        server.stop()
        if (tempFile.exists()) tempFile.delete()
    }

    @Test
    fun unknownOrExpiredTokenReturns404() {
        val url = URL("http://127.0.0.1:${server.boundPort}/media/nonexistent123")
        val conn = url.openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = false
        assertEquals(404, conn.responseCode)
    }

    @Test
    fun legacyMediaUrlWithoutTokenReturns404() {
        server.serveFile(tempFile.absolutePath, "audio/mpeg")
        val url = URL("http://127.0.0.1:${server.boundPort}/media")
        val conn = url.openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = false
        assertEquals(404, conn.responseCode)
    }

    @Test
    fun getWithoutRangeReturns200WithFullContentAndNoContentRange() {
        val rawUrl = server.serveFile(tempFile.absolutePath, "audio/mpeg")
        assertNotNull(rawUrl)
        val token = rawUrl!!.substringAfterLast("/")
        val url = URL("http://127.0.0.1:${server.boundPort}/media/$token")
        val conn = url.openConnection() as HttpURLConnection
        assertEquals(200, conn.responseCode)
        assertEquals("audio/mpeg", conn.contentType)
        assertEquals(1024L, conn.contentLengthLong)
        assertEquals("bytes", conn.getHeaderField("Accept-Ranges"))
        assertEquals(null, conn.getHeaderField("Content-Range"))
        val body = conn.inputStream.readBytes()
        assertEquals(1024, body.size)
    }

    @Test
    fun getWithRangeReturns206PartialContent() {
        val rawUrl = server.serveFile(tempFile.absolutePath, "audio/mpeg")
        assertNotNull(rawUrl)
        val token = rawUrl!!.substringAfterLast("/")
        val url = URL("http://127.0.0.1:${server.boundPort}/media/$token")
        val conn = url.openConnection() as HttpURLConnection
        conn.setRequestProperty("Range", "bytes=100-199")
        assertEquals(206, conn.responseCode)
        assertEquals("bytes 100-199/1024", conn.getHeaderField("Content-Range"))
        assertEquals(100L, conn.contentLengthLong)
        val body = conn.inputStream.readBytes()
        assertEquals(100, body.size)
        assertEquals((100 % 256).toByte(), body[0])
    }

    @Test
    fun getWithInvalidRangeReturns416() {
        val rawUrl = server.serveFile(tempFile.absolutePath, "audio/mpeg")
        assertNotNull(rawUrl)
        val token = rawUrl!!.substringAfterLast("/")
        val url = URL("http://127.0.0.1:${server.boundPort}/media/$token")
        val conn = url.openConnection() as HttpURLConnection
        conn.setRequestProperty("Range", "bytes=5000-6000")
        assertEquals(416, conn.responseCode)
        assertEquals("bytes */1024", conn.getHeaderField("Content-Range"))
    }

    @Test
    fun headRequestReturnsHeadersWithoutBody() {
        val rawUrl = server.serveFile(tempFile.absolutePath, "audio/mpeg")
        assertNotNull(rawUrl)
        val token = rawUrl!!.substringAfterLast("/")
        val url = URL("http://127.0.0.1:${server.boundPort}/media/$token")
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "HEAD"
        assertEquals(200, conn.responseCode)
        assertEquals(1024L, conn.contentLengthLong)
        val stream = conn.inputStream
        val body = stream.readBytes()
        assertEquals(0, body.size)
    }

    @Test
    fun prebufferEvictionCapsCacheSizeAndDoesNotHang() {
        val files = (1..6).map { i ->
            File.createTempFile("pulsr_prebuf_$i", ".mp3").apply {
                deleteOnExit()
                writeBytes(ByteArray(512) { (it + i).toByte() })
            }
        }
        try {
            for (f in files) {
                val url = server.preBufferFile(f.absolutePath, "audio/mpeg")
                assertNotNull(url)
            }
            val lastUrl = server.serveFile(files.last().absolutePath, "audio/mpeg")
            assertNotNull(lastUrl)
        } finally {
            files.forEach { it.delete() }
        }
    }
}
