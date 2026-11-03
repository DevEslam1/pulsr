package com.pulsr.music

import android.os.Build
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class ProxyRegressionTest {

    @Before
    fun setUp() {
        ProxyPool.clear()
        ProxyPool.setAutoRotate(true)
        ProxyPool.setOnPathChangeListener { }
        ProxyManager.dispose()
    }

    @After
    fun tearDown() {
        ProxyPool.clear()
        ProxyPool.setAutoRotate(true)
        ProxyPool.setOnPathChangeListener { }
        ProxyManager.dispose()
    }

    private fun node(
        id: String,
        host: String,
        quality: ProxyPool.Quality = ProxyPool.Quality.UNKNOWN,
        username: String = "",
    ) = ProxyPool.ProxyNode(
        id = id,
        type = Proxy.Type.HTTP,
        host = host,
        port = 8080,
        username = username,
        password = if (username.isEmpty()) "" else "secret",
        quality = quality,
    )

    @Test
    fun activeSelectionSticksToIdAndRotationFollowsStableOrder() {
        val a = node("a", "10.0.0.1")
        val b = node("b", "10.0.0.2")
        val c = node("c", "10.0.0.3", ProxyPool.Quality.RESIDENTIAL)
        ProxyPool.setProxies(listOf(b, c, a))

        // Quality first, then id: residential c leads the stable order.
        assertNotNull(ProxyPool.getActiveProxy())
        assertEquals("c", ProxyPool.getActiveNode()?.id)

        // Next alive after "c" in [c, a, b] is "a".
        ProxyPool.onPathFailed()
        assertEquals("a", ProxyPool.getActiveNode()?.id)
        ProxyPool.onPathFailed()
        assertEquals("b", ProxyPool.getActiveNode()?.id)

        // The selected id must stick even if another node's EWMA is better.
        a.ewmaSuccessRate = 0.1
        b.ewmaSuccessRate = 1.0
        repeat(5) {
            ProxyPool.getActiveProxy()
            assertEquals("b", ProxyPool.getActiveNode()?.id)
        }
    }

    @Test
    fun raceWinnerSticksWhileAlive() {
        val a = node("a", "10.0.0.1")
        val b = node("b", "10.0.0.2")
        ProxyPool.setProxies(listOf(a, b))

        // Simulate the Happy-Eyeballs winner promotion (private field).
        val field = ProxyPool.javaClass.getDeclaredField("activeProxyId")
        field.isAccessible = true
        field.set(ProxyPool, "b")

        repeat(3) {
            ProxyPool.getActiveProxy()
            assertEquals("b", ProxyPool.getActiveNode()?.id)
        }
    }

    @Test
    fun circuitBreakerTripsAndPoolNeverFallsBackToDeadNode() {
        val only = node("only", "10.0.0.9")
        ProxyPool.setProxies(listOf(only))
        assertNotNull(ProxyPool.getActiveProxy())

        repeat(3) { ProxyPool.onPathFailed() }
        assertFalse(only.isAlive)
        assertNull(ProxyPool.getActiveProxy())
        assertEquals("DIRECT", ProxyPool.currentPathLabel)
    }

    @Test
    fun defaultBypassListCoversPrivateRangesAndLocalDomains() {
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "proxy.example",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = null,
        )
        assertTrue(ProxyManager.isBypassed("http://10.1.2.3/file"))
        assertTrue(ProxyManager.isBypassed("http://172.16.5.4/file"))
        assertTrue(ProxyManager.isBypassed("http://172.31.255.254/file"))
        assertTrue(ProxyManager.isBypassed("http://192.168.1.20/file"))
        assertTrue(ProxyManager.isBypassed("http://169.254.10.10/file"))
        assertTrue(ProxyManager.isBypassed("http://[::1]:8080/"))
        assertTrue(ProxyManager.isBypassed("http://printer.local/file"))
        assertFalse(ProxyManager.isBypassed("http://172.32.0.1/file"))
        assertFalse(ProxyManager.isBypassed("https://example.com/file"))
    }

    @Test
    fun customBypassListReplacesDefaults() {
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "proxy.example",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = "example.com",
        )
        assertTrue(ProxyManager.isBypassed("https://example.com/"))
        assertFalse(ProxyManager.isBypassed("http://10.1.2.3/"))
    }

    private fun offlineConnection(urlString: String): HttpURLConnection =
        object : HttpURLConnection(URL(urlString)) {
            override fun connect() {}
            override fun disconnect() {}
            override fun usingProxy(): Boolean = false
        }

    @Test
    fun proxyAuthorizationHeaderIsOnlySentForPlainHttp() {
        val secured = node("secured", "proxy.example", username = "user")
        ProxyPool.setProxies(listOf(secured))

        val https = offlineConnection("https://origin.example")
        ProxyPool.applyAuthHeader(https, secured)
        assertNull(https.getRequestProperty("Proxy-Authorization"))

        val http = offlineConnection("http://origin.example")
        ProxyPool.applyAuthHeader(http, secured)
        assertNotNull(http.getRequestProperty("Proxy-Authorization"))
    }

    @Test
    fun getProxyHonorsBreakerAndFailClosed() {
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "127.0.0.1",
            port = 9,
            username = null,
            password = null,
            bypassHosts = null,
            failClosed = true,
        )
        assertNotNull(ProxyManager.getProxy("https://example.com"))
        assertFalse(ProxyManager.isBlocked())

        repeat(3) {
            ProxyPool.onPathFailed()
            ProxyManager.getProxy("https://example.com")
        }
        assertNull(ProxyManager.getProxy("https://example.com"))
        assertTrue(ProxyManager.isBlocked())
    }

    @Test
    fun proxyHostIsUnresolvedWhenBuildingJavaProxy() {
        val unresolved = node("u", "proxy.invalid").toJavaProxy()
        assertEquals("proxy.invalid", (unresolved.address() as java.net.InetSocketAddress).hostString)
        assertTrue((unresolved.address() as java.net.InetSocketAddress).isUnresolved)
    }
}
