package com.ryanheise.just_audio;

import org.junit.Assert;
import org.junit.Test;

import java.lang.reflect.Field;

public class JustAudioHardeningTest {

    @Test
    public void testPulsrAudioSinkReconfigureNowDoesNotSetInterruptedOnRuntimeException() {
        // Clear any existing interrupt flag
        Thread.interrupted();

        PulsrAudioSink sink = new PulsrAudioSink(
                null,
                () -> false,
                () -> false,
                () -> 100,
                () -> false,
                () -> false,
                () -> {
                    throw new RuntimeException("Simulated player failure during createMessage");
                },
                null,
                null,
                null
        );

        boolean result = sink.reconfigureNow(50);
        Assert.assertFalse("reconfigureNow should return false on exception", result);
        Assert.assertFalse("Thread interrupt flag must NOT be set on RuntimeException",
                Thread.currentThread().isInterrupted());
    }

    @Test
    public void testNativeDspAudioProcessorOnResetZeroesSampleRate() throws Exception {
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        Field sampleRateField = NativeDspAudioProcessor.class.getDeclaredField("sampleRate");
        sampleRateField.setAccessible(true);

        // Artificially set sampleRate to 96000
        sampleRateField.setInt(processor, 96000);
        Assert.assertEquals(96000, sampleRateField.getInt(processor));

        // Call onReset()
        processor.onReset();

        // Verify sampleRate is reset to 0
        Assert.assertEquals("sampleRate must be reset to 0 in onReset()", 0, sampleRateField.getInt(processor));
    }
}
