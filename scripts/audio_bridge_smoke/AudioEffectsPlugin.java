package com.pulsr.music;

/** Minimal JNI control fixture for the standalone smoke process, never packaged. */
public final class AudioEffectsPlugin {
    public static native void nativeSetBitPerfectParams(boolean enabled, boolean isDop);
    public static native void nativeSetActiveStages(int stages);
}
