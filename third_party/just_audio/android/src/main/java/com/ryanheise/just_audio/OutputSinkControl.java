package com.ryanheise.just_audio;

/**
 * Control surface AudioPlayer needs from its stable sink wrapper. Kept as an
 * interface so lifecycle tests can substitute a fake without mocking a final
 * Media3-facing class.
 */
interface OutputSinkControl {
    void requestModeChange();

    void requestModeChange(boolean force);

    /** Lets the next mode request retry float output after an earlier rejection. */
    default void clearFloatFallback() {}

    /** Clears the sink's tap-SRC failure latch so a retry is possible. */
    default void clearTapSrcFailed() {}

    /**
     * Rebuilds the inner sink with the current policies on the playback thread
     * and waits (bounded) for the rebuild to finish. The integer bit-perfect
     * bypass is latched by configure(), so a policy change made mid-track needs
     * one rebuild to take effect on the track that is already playing.
     * Returns false when no stream is configured or the message was not posted.
     */
    default boolean reconfigureNow(long timeoutMs) { return false; }

    void release();
}
