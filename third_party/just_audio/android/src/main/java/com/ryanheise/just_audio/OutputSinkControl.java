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

    void release();
}
