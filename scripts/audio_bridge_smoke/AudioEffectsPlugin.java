package com.pulsr.music;

/** Minimal JNI control fixture for the standalone smoke process, never packaged. */
public final class AudioEffectsPlugin {
    public static native void nativeSetBitPerfectParams(boolean enabled, boolean isDop);
    public static native void nativeSetActiveStages(int stages);
    public static native void nativeSetSaturationEnabled(boolean enabled);
    public static native void nativeSetSaturationParams(double drive, double mix,
            double tilt, int mode, boolean multiband);
}
