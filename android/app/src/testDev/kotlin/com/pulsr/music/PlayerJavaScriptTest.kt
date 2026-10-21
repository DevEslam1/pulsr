package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerJavaScriptTest {

    @Test
    fun testModernDecipherStepsExtraction() {
        // Synthetic modern YouTube player JS sample mirroring real 2026 player_ias.vflset structure
        val sampleJs = """
            var Nu,P1,qR;
            somePrefix=123;
            Nu="fa;1;;Z;cmo=pf;call;path;N;set;PB;slice;get;splice;url;startsWith;scheme;,\"']{;match;redirector.googlevideo.com;C;length;push;split;assign;false;fallback_count;fromCharCode;signatureCipher;local;cmo;/videoplayback;=;indexOf;X;Untrusted URL;1969-12-31T17:45:49.000-06:15;reverse;?;rr;join;youtube.player.web_20261013_08_RC00;forEach;file;toString;1969-12-31T14:00:58.000-10:00;sp;clone;/initplayback;//;,;:;Nx;rr?[1-9].*\\.c\\.youtube\\.com$;s;http://local;cmo=;%3D;B;rS;unshift;index.m3u8;\\.googlevideo\\.com$;1969-12-31T14:15:55.000-09:45;mn;cmo=td;fvip;/file/index.m3u8;1970-01-01T08:15:09.000+08:15;prototype;/;/api/manifest;xk;r;---;z9;\\.a1\\.googlevideo\\.com$;LP;www.youtube.com;NasxEk3byIkg6IB_N3-_w8_;&;1970-01-01T05:15:52.000+05:15;://;n;https://local;undefined;replace;pop;playerfallback;1970-01-01T02:31:08.000+02:30;1970-01-01T10:30:55.000+10:30;a1.googlevideo.com".split(";");
            
            qR={
                rS:function(N){N[Nu[36]]()},
                PB:function(N,L){var v=N[0];N[0]=N[L%N[Nu[20]]];N[L%N[Nu[20]]]=v},
                LP:function(N,L){N[Nu[12]](0,L)}
            };
            
            P1=function(N,L,v,a){
                var C=L^N,r;
                if(N-7>>4<3&&(N|5)>>3>=2){
                    var k=v[Nu[C^1201]](Nu[2]);
                    qR[Nu[C^1181]](k,C^1162);
                    qR[Nu[C^1259]](k,1);
                    qR[Nu[C^1198]](k,C^1170);
                    qR[Nu[C^1259]](k,3);
                    qR[Nu[C^1198]](k,C^1205);
                    qR[Nu[C^1198]](k,C^1178);
                    r=k[Nu[C^1152]](Nu[2])
                }
                return r
            };
            
            function zw8(v){
                if(k.s){var I=H,T=k.sp,l=P1(19,1204,qE(61,7141,k.s));I[Nu[8]](T,Q8(23,5014,l))}
            }
            
            var meta = {signatureTimestamp:20739};
        """.trimIndent()

        val steps = PlayerJavaScript.extractModernDecipherSteps(sampleJs)
        assertNotNull("Modern decipher steps should be extracted", steps)
        assertEquals(listOf("reverse", "splice:1", "swap:53", "splice:3", "swap:18", "swap:61"), steps)

        // Apply steps to a test signature via JsDecipherCache
        val cache = JsDecipherCache()
        val transformed = cache.applyTransforms("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", steps!!)
        assertNotNull(transformed)
        assertTrue(transformed.isNotEmpty())
    }

    @Test
    fun testCurrentBraceDelimitedDecipherStepsExtraction() {
        val table = MutableList(66) { "x$it" }
        table[2] = ""
        table[3] = "length"
        table[10] = "signatureCipher"
        table[21] = "splice"
        table[22] = "rZ"
        table[34] = "Jk"
        table[57] = "join"
        table[58] = "reverse"
        table[65] = "QD"

        val sampleJs = """
            var x=0;aa="${table.joinToString("{")}".split("{");
            zN={QD:function(a,b){a[aa[21]](0,b)},rZ:function(a){a[aa[58]]()},Jk:function(a,b){var c=a[0];a[0]=a[b%a[aa[3]]];a[b%a[aa[3]]]=c}};
            Ww=function(a,b,c,d){var e=b^a;if(!(a<<2&7)){var f=op(e^7297,e^752,c);d[aa[e^7383]](aa[e^7404],f);var h=[]}(a-8|33)>=a&&(a-6^21)<a&&(f=c[aa[e^7062]](aa[2]),zN[aa[e^7080]](f,e^7092),zN[aa[e^7115]](f,2),zN[aa[e^7080]](f,e^7100),zN[aa[e^7068]](f,e^7089),zN[aa[e^7115]](f,2),zN[aa[e^7068]](f,e^7064),zN[aa[e^7080]](f,1),zN[aa[e^7115]](f,2),h=f[aa[e^7091]](aa[2]));return h};
            if(k.s){var m=l,n=h.sp,p=Ww(23,7069,mr(19,7308,h.s));}
            var meta = {signatureTimestamp:20744};
        """.trimIndent()

        val steps = PlayerJavaScript.extractModernDecipherSteps(sampleJs)
        assertNotNull("Brace-delimited modern decipher steps should be extracted", steps)
        assertEquals(
            listOf("swap:62", "splice:2", "swap:54", "reverse", "splice:2", "reverse", "swap:1", "splice:2"),
            steps
        )
    }

    @Test
    fun testModernDecipherStepsRejectsIncompleteHelperMapping() {
        val table = MutableList(66) { "x$it" }
        table[2] = ""
        table[3] = "length"
        table[10] = "signatureCipher"
        table[21] = "splice"
        table[33] = "Jk"
        table[58] = "reverse"
        table[62] = "Jk"

        val sampleJs = """
            var x=0;aa="${table.joinToString("{")}".split("{");
            zN={QD:function(a,b){a[aa[21]](0,b)},rZ:function(a){a[aa[58]]()}};
            Ww=function(a,b,c,d){var e=b^a;f=c[aa[e^7062]](aa[2]);zN[aa[e^7080]](f,e^7092);zN[aa[e^7115]](f,2);return h};
            if(k.s){var m=l,n=h.sp,p=Ww(23,7069,mr(19,7308,h.s));}
        """.trimIndent()

        assertNull(PlayerJavaScript.extractModernDecipherSteps(sampleJs))
    }

    @Test
    fun testLegacyDecipherStepsExtraction() {
        val legacyJs = """
            var a = "abc";
            var myHelper = {
                swap: function(a, b) { var c = a[0]; a[0] = a[b % a.length]; a[b] = c; },
                splice: function(a, b) { a.splice(0, b); },
                reverse: function(a) { a.reverse(); }
            };
            var decFunc = function(a) {
                a = a.split("");
                myHelper.reverse(a, 0);
                myHelper.swap(a, 2);
                myHelper.splice(a, 1);
                return a.join("");
            };
            k.set("signature", decFunc(s));
        """.trimIndent()

        val steps = PlayerJavaScript.extractLegacyDecipherSteps(legacyJs)
        assertNotNull("Legacy decipher steps should be extracted", steps)
        assertEquals(listOf("reverse", "swap:2", "splice:1"), steps)
    }

    @Test
    fun testFallbackDecipherProducesValidDecipheredSignature() {
        val rawSig = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        val deciphered = PlayerJavaScript.decipherSignature(rawSig)
        assertNotNull("decipherSignature should never return null", deciphered)
        assertTrue("Deciphered signature should be non-empty", deciphered!!.isNotEmpty())
    }
}
