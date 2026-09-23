package com.ryanheise.just_audio;

import java.nio.ByteBuffer;

/**
 * JNI surface to Pulsr's native AAudio output sink (libpulsr_dsp.so).
 *
 * <p>Values mirror the AAudio enums: encoding 1 = PCM_I16, 2 = PCM_FLOAT,
 * 3 = PCM_I24_PACKED (the DoP carrier). All calls are cheap wrappers; the
 * write call blocks on the caller's thread until the stream accepts the
 * buffer. The library is loaded lazily by {@link #ensureAvailable()} so a
 * missing native library degrades to "unavailable" instead of crashing.
 */
public final class AaudioNativeBridge {
    public static final int ENCODING_PCM_I16 = 1;
    public static final int ENCODING_PCM_FLOAT = 2;
    public static final int ENCODING_PCM_I24_PACKED = 3;

    private static volatile boolean loadAttempted = false;
    private static boolean available = false;

    private AaudioNativeBridge() {}

    /** Returns true when libpulsr_dsp is present and loadable (once). */
    public static synchronized boolean ensureAvailable() {
        if (!loadAttempted) {
            loadAttempted = true;
            try {
                System.loadLibrary("pulsr_dsp");
                available = true;
            } catch (UnsatisfiedLinkError | SecurityException e) {
                available = false;
            }
        }
        return available;
    }

    /** Opens a stream; returns a native handle or 0 on failure. */
    public static native long nativeOpen(int sampleRate, int channelCount,
            int encoding, boolean preferExclusive, int targetBufferMs);

    /** Releases the stream and the native object. Idempotent with 0. */
    public static native void nativeClose(long handle);

    /**
     * Writes exactly {@code length} bytes from {@code buffer} starting at
     * {@code offset} (blocking). Returns bytes consumed, or -1 on failure.
     */
    public static native int nativeWrite(long handle, ByteBuffer buffer,
            int offset, int length);

    public static native void nativePlay(long handle);

    public static native void nativePause(long handle);

    public static native void nativeFlush(long handle);

    public static native long nativeGetFramesRead(long handle);

    public static native long nativeGetFramesWritten(long handle);

    public static native int nativeGetXRunCount(long handle);

    public static native boolean nativeIsExclusive(long handle);

    public static native void nativeSetVolume(long handle, float volume);
 
    public static native double nativeGetOutputLatencyMs(long handle);

    public static native int nativeGetFramesPerBurst(long handle);
}
