package com.ryanheise.just_audio;

/** Symmetric PCM16 conversion: every short survives a unity float round trip. */
final class Pcm16Quantizer {
    private Pcm16Quantizer() {}

    static short fromFloat(float value) {
        int sample = Math.round(value * 32768f);
        return (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, sample));
    }
}
