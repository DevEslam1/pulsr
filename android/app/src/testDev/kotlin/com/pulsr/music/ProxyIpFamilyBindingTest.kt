package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Test

class ProxyIpFamilyBindingTest {

    @Test
    fun testProxyManagerPinnedIpFamilyBinding() {
        ProxyManager.setPinnedIpFamily("ipv4")
        assertEquals("ipv4", ProxyManager.pinnedIpFamily)

        ProxyManager.setPinnedIpFamily("ipv6")
        assertEquals("ipv6", ProxyManager.pinnedIpFamily)

        ProxyManager.setPinnedIpFamily(null)
        assertEquals(null, ProxyManager.pinnedIpFamily)
    }
}
