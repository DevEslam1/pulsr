package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import java.nio.ByteBuffer;
import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Looper;

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
            Looper.prepareMainLooper();
            Object thread = Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
            Context context = (Context) thread.getClass().getMethod("getSystemContext").invoke(thread);
            AudioManager manager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
            AudioDeviceInfo speaker = null;
            for (AudioDeviceInfo device : manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                if (device.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) speaker = device;
            }
            check(speaker != null, "phone speaker must be available");
            sink.setPreferredDevice(speaker);
            sink.play();
            sink.handleBuffer(ByteBuffer.allocateDirect(3840), 1_000_000, 1);
            check(sink.measuredStream()[0] == speaker.getId(), "AAudio must actually route to Phone");
            check(sink.measuredStream()[1] == 48000, "AAudio reports negotiated stream rate");
            sink.setPreferredDevice(null);
            sink.handleBuffer(ByteBuffer.allocateDirect(3840), 1_010_000, 1);
            check(sink.measuredStream()[0] > 0, "clearing preference must preserve a measured route");
        } finally {
            sink.release();
        }
        System.out.println("PASS: Media3 AAudio sink partial/heap writes, play/pause/flush/reset, silence-skip state");
        System.exit(0);
    }
}
