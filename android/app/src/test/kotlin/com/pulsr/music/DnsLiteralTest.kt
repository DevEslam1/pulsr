package com.pulsr.music

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DnsLiteralTest {

    @Test
    fun acceptsValidIpv4Literals() {
        assertTrue(DnsOverHttpsResolver.isNumericIp("127.0.0.1"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("8.8.8.8"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("0.0.0.0"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("255.255.255.255"))
        assertTrue(DnsOverHttpsResolver.isNumericIp(" 192.168.1.10 "))
    }

    @Test
    fun rejectsMalformedOrLeadingZeroIpv4AndHostnames() {
        assertFalse(DnsOverHttpsResolver.isNumericIp(""))
        assertFalse(DnsOverHttpsResolver.isNumericIp("   "))
        assertFalse(DnsOverHttpsResolver.isNumericIp("999.1.1.1"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("01.2.3.4"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1.2.3"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1.2.3.4.5"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("[127.0.0.1]"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("youtube.com"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("dns.google"))
    }

    @Test
    fun acceptsValidIpv6AndEmbeddedIpv4Literals() {
        assertTrue(DnsOverHttpsResolver.isNumericIp("::1"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("2001:db8::1"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("fe80::1ff:fe23:4567:890a"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("1:2:3:4:5:6:7:8"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("::ffff:192.0.2.1"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("2001:db8:0:0:1::192.0.2.33"))
        assertTrue(DnsOverHttpsResolver.isNumericIp("2001:db8::"))
    }

    @Test
    fun rejectsMalformedIpv6GroupCountsCompressionsAndEmbeddedIpv4() {
        assertFalse(DnsOverHttpsResolver.isNumericIp("::"))
        assertFalse(DnsOverHttpsResolver.isNumericIp(":::"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1::2::3"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1:2:3:4:5:6:7:8:9"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1:2:3:4:5:6:7::8"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("::ffff:999.0.0.1"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("::ffff:01.0.0.1"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("192.0.2.1::"))
        assertFalse(DnsOverHttpsResolver.isNumericIp(":1:2:3:4:5:6:7:8"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1:2:3:4:5:6:7:8:"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("1:2:3:4:5:6:192.0.2.1:0"))
        assertFalse(DnsOverHttpsResolver.isNumericIp("gggg::1"))
    }
}
