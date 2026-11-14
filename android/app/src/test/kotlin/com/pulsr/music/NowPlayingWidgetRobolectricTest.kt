package com.pulsr.music

import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.FrameLayout
import android.widget.TextView
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class NowPlayingWidgetRobolectricTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        NowPlayingWidget.clearWidgetToken(context)
        NowPlayingWidget.resetTokenCacheForTesting()
        NowPlayingWidget.pendingUpdateRunnable = null
    }

    @After
    fun tearDown() {
        NowPlayingWidget.pendingUpdateRunnable = null
        NowPlayingWidget.clearWidgetToken(context)
        NowPlayingWidget.resetTokenCacheForTesting()
    }

    @Test
    fun rotatedTokenKeepsPreviousTokenValidDuringGraceWindowUntilExpired() {
        val firstToken = NowPlayingWidget.getWidgetToken(context)
        assertTrue(NowPlayingWidget.isValidWidgetToken(context, firstToken))

        val rotatedToken = NowPlayingWidget.rotateWidgetToken(context)
        assertTrue(rotatedToken.isNotBlank())
        assertTrue(NowPlayingWidget.isValidWidgetToken(context, rotatedToken))
        // T9 grace window: taps using the just-superseded RemoteViews token stay accepted briefly.
        assertTrue(NowPlayingWidget.isValidWidgetToken(context, firstToken))

        val prefs = context.getSharedPreferences("widget_tokens", Context.MODE_PRIVATE)
        prefs.edit().putLong("token_prev_expires_at", System.currentTimeMillis() - 1_000L).apply()
        NowPlayingWidget.resetTokenCacheForTesting()

        assertTrue(NowPlayingWidget.isValidWidgetToken(context, rotatedToken))
        assertFalse(NowPlayingWidget.isValidWidgetToken(context, firstToken))
    }

    @Test
    fun rejectedStaleWidgetActionSchedulesSelfHealRefreshWithoutThrowing() {
        NowPlayingWidget.getWidgetToken(context)
        val staleBroadcast = Intent(NowPlayingWidget.ACTION_PLAY_PAUSE).apply {
            putExtra(NowPlayingWidget.EXTRA_WIDGET_TOKEN, "stale-or-foreign-token")
        }

        NowPlayingWidget().onReceive(context, staleBroadcast)

        assertNotNull(NowPlayingWidget.pendingUpdateRunnable)
    }

    @Test
    fun allFiveWidgetLayoutsInflateAndBindMetadataSafely() {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("title", "Analog Dreams")
            .putString("artist", "Pulsr Ensemble")
            .putString("album", "Master Tape")
            .putLong("durationMs", 240_000L)
            .putLong("positionMs", 60_000L)
            .putBoolean("isPlaying", true)
            .putBoolean("isFavorite", true)
            .putBoolean("isShuffle", true)
            .putString("repeatMode", "all")
            .commit()

        val layouts = listOf(
            R.layout.widget_now_playing to 56,
            R.layout.widget_now_playing_compact to 44,
            R.layout.widget_now_playing_medium to 68,
            R.layout.widget_now_playing_large to 88,
            R.layout.widget_now_playing_tiny to 44,
        )

        val parent = FrameLayout(context)
        for ((layoutId, artDp) in layouts) {
            val remoteViews = NowPlayingWidget.createPopulatedRemoteViews(
                context = context,
                layoutId = layoutId,
                data = prefs,
                targetArtDp = artDp,
            )
            val inflated = remoteViews.apply(context, parent)
            val titleView = inflated.findViewById<TextView>(R.id.widget_title)
            val artistView = inflated.findViewById<TextView>(R.id.widget_artist)
            assertNotNull("Expected widget_title in layout $layoutId", titleView)
            assertNotNull("Expected widget_artist in layout $layoutId", artistView)
            assertEquals("Analog Dreams", titleView.text.toString())
            assertEquals("Pulsr Ensemble", artistView.text.toString())
        }
    }
}
