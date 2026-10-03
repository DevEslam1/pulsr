package com.ryanheise.just_audio;

import java.nio.ByteBuffer;
import java.util.Arrays;

/** Standalone app_process smoke test; requires libpulsr_dsp on LD_LIBRARY_PATH. */
public final class AaudioBridgeSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        for (int sample = Short.MIN_VALUE; sample <= Short.MAX_VALUE; sample++) {
            check(Pcm16Quantizer.fromFloat(sample / 32768f) == sample,
                    "PCM16 unity round trip must preserve sample " + sample);
        }
        check(AaudioNativeBridge.ensureAvailable(), "native library must load");
        for (int iteration = 0; iteration < 5; iteration++) {
            long handle = AaudioNativeBridge.nativeOpen(48000, 2,
                    AaudioNativeBridge.ENCODING_PCM_FLOAT, false, 50);
            check(handle != 0, "shared float stream must open");
            try {
                ByteBuffer pcm = ByteBuffer.allocateDirect(512 * 2 * 4);
                byte[] source = new byte[pcm.capacity()];
                Arrays.fill(source, (byte) 0);
                pcm.put(source).flip();
                check(AaudioNativeBridge.nativeWrite(handle, pcm, -1, 8) == -1,
                        "negative offset must be rejected");
                check(AaudioNativeBridge.nativeWrite(handle, pcm, 0, pcm.capacity() + 8) == -1,
                        "buffer overrun must be rejected");
                check(AaudioNativeBridge.nativeWrite(handle, pcm, 0, 3) == -1,
                        "partial frame must be rejected");
                AaudioNativeBridge.nativeSetVolume(handle, 0.25f);
                AaudioNativeBridge.nativePlay(handle);
                int written = AaudioNativeBridge.nativeWrite(handle, pcm, 0, pcm.capacity());
                check(written > 0 && written <= pcm.capacity(), "PCM write must progress");
                check(AaudioNativeBridge.nativeGetFramesWritten(handle) == written / 8,
                        "written frames must match consumed bytes");
                AaudioNativeBridge.nativeGetFramesRead(handle);
                AaudioNativeBridge.nativeGetXRunCount(handle);
                AaudioNativeBridge.nativeGetOutputLatencyMs(handle);
                check(AaudioNativeBridge.nativeGetFramesPerBurst(handle) > 0,
                        "burst query must resolve");
                AaudioNativeBridge.nativePause(handle);
                AaudioNativeBridge.nativeFlush(handle);
                check(AaudioNativeBridge.nativeGetFramesWritten(handle) == 0,
                        "flush must rebase written frames");
                byte[] after = new byte[pcm.capacity()];
                pcm.position(0);
                pcm.get(after);
                check(Arrays.equals(source, after), "sink must not mutate caller PCM");
            } finally {
                AaudioNativeBridge.nativeClose(handle);
            }
        }
        long exclusive = AaudioNativeBridge.nativeOpen(48000, 2,
                AaudioNativeBridge.ENCODING_PCM_I16, true, 50);
        if (exclusive != 0) {
            check(AaudioNativeBridge.nativeIsExclusive(exclusive),
                    "exclusive request must never degrade to shared");
            AaudioNativeBridge.nativeClose(exclusive);
        }
        AaudioNativeBridge.nativeClose(0);
        check(AaudioNativeBridge.nativeWrite(0, null, 0, 0) == -1,
                "null handle must be harmless");
        System.out.println("PASS: all 65536 PCM16 values; AAudio JNI open/write/play/pause/flush/close, bounds, and exclusive policy");
    }
}
