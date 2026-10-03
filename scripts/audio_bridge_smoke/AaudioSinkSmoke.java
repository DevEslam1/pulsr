package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import java.nio.ByteBuffer;

/** Checks the Media3 sink contract against the actual native stream. */
public final class AaudioSinkSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        check(AaudioNativeBridge.ensureAvailable(), "library must load");
        AAudioAudioSink sink = new AAudioAudioSink(false, 20);
        Format format = new Format.Builder().setSampleMimeType("audio/raw")
                .setSampleRate(48000).setChannelCount(2)
                .setPcmEncoding(C.ENCODING_PCM_FLOAT).build();
        try {
            sink.setSkipSilenceEnabled(true);
            check(!sink.getSkipSilenceEnabled(), "unsupported silence skipping must report OFF");
            sink.configure(format, 0, null);
            ByteBuffer heap = ByteBuffer.allocate(48000 * 2 * 4);
            boolean complete = sink.handleBuffer(heap, 0, 1);
            check(heap.position() > 0, "heap buffer position must advance");
            check(complete == !heap.hasRemaining(), "partial writes must report remaining bytes");
            sink.play();
            for (int attempts = 0; heap.hasRemaining() && attempts < 8; attempts++) {
                sink.handleBuffer(heap, 0, 1);
            }
            check(!heap.hasRemaining(), "resumed playback must consume the remainder");
            sink.pause();
            sink.flush();
            sink.reset();
            sink.configure(format, 0, null);
            check(!sink.isEnded(), "reconfiguration must clear end-of-stream state");
        } finally {
            sink.release();
        }
        System.out.println("PASS: Media3 AAudio sink partial/heap writes, play/pause/flush/reset, silence-skip state");
    }
}
