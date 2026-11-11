package com.pulsr.music

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class YtmCookieStoreTest {

    @Test
    fun testEmptyCookieManagerDoesNotWipeValidSession() {
        val context = RuntimeEnvironment.getApplication()
        val store = YtmCookieStore.getInstance(context)
        store.setCookies("SAPISID=test_sapisid_token; __Secure-3PAPISID=test_3papisid_token; __Secure-3PSID=test_3psid_token; SID=valid_sid")
        assertTrue("Store must have valid session initially", store.isSessionValid())

        // Calling readFromCookieManager when CookieManager is empty
        val header = store.readFromCookieManager()
        assertTrue("Store session must still be valid after empty CookieManager read", store.isSessionValid())
        assertNotNull("Merged header must not be null", header)
        assertTrue("Merged header must retain SAPISID", header!!.contains("SAPISID=test_sapisid_token"))
    }
}
