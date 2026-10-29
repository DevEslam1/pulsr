package com.ryanheise.just_audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** JVM tests for the dither/quantisation helpers (no Android framework needed). */
public class Pcm16QuantizerTest {

    @Test
    public void fullScaleClampsToPcm16Bounds() {
        assertEquals(Short.MAX_VALUE, Pcm16Quantizer.fromFloat(1.0f));
        assertEquals(Short.MAX_VALUE, Pcm16Quantizer.fromFloat(2.0f));
        assertEquals(Short.MIN_VALUE, Pcm16Quantizer.fromFloat(-1.0f));
        assertEquals(Short.MIN_VALUE, Pcm16Quantizer.fromFloat(-2.0f));
    }

    @Test
    public void tpdfDitherStaysWithinOneLsb() {
        // TPDF dither deliberately perturbs the sample by up to +/-1 LSB, but
        // never more; this is the invariant the old smoke test got wrong.
        for (int sample = Short.MIN_VALUE; sample <= Short.MAX_VALUE; sample++) {
            final short quantised = Pcm16Quantizer.fromFloat(sample / 32768f);
            assertTrue("sample " + sample + " drifted to " + quantised,
                    Math.abs(quantised - sample) <= 1);
        }
    }

    @Test
    public void silenceOnlyProducesDitherNoise() {
        for (int i = 0; i < 10_000; i++) {
            final short value = Pcm16Quantizer.fromFloat(0f);
            assertTrue("silence produced " + value,
                    value >= -1 && value <= 1);
        }
    }
}
