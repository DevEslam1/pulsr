package com.ryanheise.just_audio;

/**
 * Control surface AudioPlayer needs from its stable sink wrapper. Kept as an
 * interface so lifecycle tests can substitute a fake without mocking a final
 * Media3-facing class.
 */
interface OutputSinkControl {
    void requestModeChange();

    void requestModeChange(boolean force);

    void release();
}
