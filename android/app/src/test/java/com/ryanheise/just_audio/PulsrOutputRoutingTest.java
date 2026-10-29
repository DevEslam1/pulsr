package com.ryanheise.just_audio;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import androidx.media3.exoplayer.ExoPlayer;

import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.lang.reflect.Field;
import java.util.Set;

/** Routing registry tests: no stale sinks, and one bad player cannot abort a route. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class PulsrOutputRoutingTest {

    private final ExoPlayer playerA = mock(ExoPlayer.class);
    private final ExoPlayer playerB = mock(ExoPlayer.class);

    @After
    public void tearDown() {
        PulsrOutputRouting.unregister(playerA);
        PulsrOutputRouting.unregister(playerB);
        PulsrOutputRouting.select(null);
    }

    @Test
    public void selectStillRoutesRemainingPlayersWhenOneThrows() {
        // Start from a known (null) preference so register() is not the call
        // that throws.
        PulsrOutputRouting.select(null);
        PulsrOutputRouting.register(playerA, false);
        PulsrOutputRouting.register(playerB, false);
        doThrow(new IllegalStateException("released"))
                .when(playerA).setPreferredAudioDevice(any());

        assertFalse(PulsrOutputRouting.select(null));
        verify(playerB, atLeastOnce()).setPreferredAudioDevice(null);
    }

    @Test
    public void observeAndUnobserveRemoveSinkReferences() throws Exception {
        // AAudioAudioSink is final and constructible without touching native
        // code, so it serves as a real registry member here.
        final AAudioAudioSink sink = new AAudioAudioSink(false, 50);
        PulsrOutputRouting.observe(sink);
        assertTrue(nativeSinks().contains(sink));
        PulsrOutputRouting.unobserve(sink);
        assertFalse(nativeSinks().contains(sink));
    }

    @SuppressWarnings("unchecked")
    private static Set<AAudioAudioSink> nativeSinks() throws Exception {
        final Field field = PulsrOutputRouting.class.getDeclaredField("nativeSinks");
        field.setAccessible(true);
        return (Set<AAudioAudioSink>) field.get(null);
    }
}
