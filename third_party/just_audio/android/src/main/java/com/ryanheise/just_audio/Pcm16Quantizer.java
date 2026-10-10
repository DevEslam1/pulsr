package com.ryanheise.just_audio;

import java.util.Random;

/**
 * PCM16 requantisation for the default (non-bit-perfect) output path.
 *
 * <p>Reducing arbitrary DSP float output to 16 bits discards up to ~8 bits of a
 * 24-bit source. Plain rounding correlates the quantisation error with the
 * signal, which is audible as low-level distortion on quiet fades and decays.
 * TPDF (triangular probability density function) dither decorrelates that error
 * so it becomes a benign, signal-independent noise floor — the standard
 * treatment when leaving the hi-res domain for a 16-bit sink.
 *
 * <p>This runs ONLY on the default path. The bit-perfect path copies the decoded
 * bytes verbatim and never calls this, so bit-perfect output stays undithered.
 *
 * <p>Note on standard integer asymmetry: PCM 16-bit spans [-32768, +32767].
 * Multiplying by 32768 maps +1.0f -> +32768 which clamps to Short.MAX_VALUE
 * (32767, 1 LSB below mathematical unity), while -1.0f maps to Short.MIN_VALUE
 * (-32768).
 */
final class Pcm16Quantizer {
    private Pcm16Quantizer() {}

    // Per-thread RNG so the playback thread never contends on a shared Random.
    // Anonymous subclass (not ThreadLocal.withInitial) so it links on every
    // supported API level without relying on Java-8 default-method desugaring.
    private static final ThreadLocal<Random> DITHER_RNG = new ThreadLocal<Random>() {
        @Override
        protected Random initialValue() {
            return new Random();
        }
    };

    /**
     * Requantises a DSP float sample to dithered 16-bit PCM (default path only).
     */
    static short fromFloat(float value) {
        final Random rng = DITHER_RNG.get();
        // TPDF dither: the difference of two independent [0,1) uniforms is a
        // triangular distribution over (-1, +1) peaking at 0, i.e. +/-1 LSB of
        // triangular dither added in the integer-sample domain before rounding.
        final double dither = rng.nextDouble() - rng.nextDouble();
        final long sample = Math.round((double) value * 32768.0 + dither);
        if (sample > Short.MAX_VALUE) return Short.MAX_VALUE;
        if (sample < Short.MIN_VALUE) return Short.MIN_VALUE;
        return (short) sample;
    }
}
