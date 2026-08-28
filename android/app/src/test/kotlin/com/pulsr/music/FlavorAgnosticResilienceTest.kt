package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.Proxy

/**
 * Flavor-agnostic tests running under ALL flavors (including prod).
 * Strictly contains NO references to NewPipe, YTM, or GPL classes.
 */
class FlavorAgnosticResilienceTest {

    @Test
    fun testProxyPoolCircuitBreakerAndRotation() {
        val node1 = ProxyPool.ProxyNode("1", Proxy.Type.HTTP, "1.1.1.1", 8080)
        val node2 = ProxyPool.ProxyNode("2", Proxy.Type.HTTP, "2.2.2.2", 8080)
        ProxyPool.setProxies(listOf(node1, node2))
        ProxyPool.setAutoRotate(false)

        val p1 = ProxyPool.getActiveProxy()
        assertNotNull(p1)

        // Fail node 1 three times -> trip circuit breaker
        ProxyPool.onPathFailed()
        ProxyPool.onPathFailed()
        ProxyPool.onPathFailed()

        assertFalse(node1.isAlive)
        assertTrue(node2.isAlive)

        // Now active proxy should be node 2
        ProxyPool.setAutoRotate(true)
        val p2 = ProxyPool.getActiveProxy()
        assertNotNull(p2)
        assertEquals(Proxy.Type.HTTP, p2?.type())
    }
}
