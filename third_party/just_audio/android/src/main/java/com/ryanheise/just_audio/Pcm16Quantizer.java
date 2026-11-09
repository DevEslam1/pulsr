package com.ryanheise.just_audio;

import java.util.concurrent.ThreadLocalRandom;

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
 * <p>The native C++ chain already noise-shapes AND dithers to 16-bit when its
 * dither stage is active, so samples that arrive already sitting exactly on a
 * 16-bit integer step are rounded without adding a second TPDF layer. This
 * prevents doubled dither noise (and the extra ~3 dB noise floor it causes).
 *
 * <p>Note on standard integer asymmetry: PCM 16-bit spans [-32768, +32767].
 * Multiplying by 32768 maps +1.0f -> +32768 which clamps to Short.MAX_VALUE
 * (32767, 1 LSB below mathematical unity), while -1.0f maps to Short.MIN_VALUE
 * (-32768).
 */
final class Pcm16Quantizer {
    private Pcm16Quantizer() {}

    /**
     * Requantises a DSP float sample to dithered 16-bit PCM (default path only).
     */
    static short fromFloat(float value) {
        if (!Float.isFinite(value)) return 0;
        final double scaled = (double) value * 32768.0;
        final double dither;
        if (scaled == Math.rint(scaled)) {
            // Already quantised by the native 16-bit noise-shaped dither stage;
            // do not add a second layer of TPDF dither.
            dither = 0.0;
        } else {
            // TPDF dither: the difference of two independent [0,1) uniforms is
            // a triangular distribution over (-1, +1), i.e. +/-1 LSB.
            final ThreadLocalRandom rng = ThreadLocalRandom.current();
            dither = rng.nextDouble() - rng.nextDouble();
        }
        final long sample = Math.round(scaled + dither);
        if (sample > Short.MAX_VALUE) return Short.MAX_VALUE;
        if (sample < Short.MIN_VALUE) return Short.MIN_VALUE;
        return (short) sample;
    }
}
