package com.ryanheise.just_audio;

/**
 * Symmetric PCM16 conversion: every short survives a unity float round trip.
 *
 * Note on standard integer asymmetry: PCM 16-bit spans [-32768, +32767].
 * Multiplying by 32768 maps +1.0f -> +32768 which clamps to Short.MAX_VALUE (32767,
 * 1 LSB below mathematical unity), while -1.0f maps to Short.MIN_VALUE (-32768).
 */
final class Pcm16Quantizer {
    private Pcm16Quantizer() {}

    static short fromFloat(float value) {
        int sample = Math.round(value * 32768f);
        return (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, sample));
    }
}
