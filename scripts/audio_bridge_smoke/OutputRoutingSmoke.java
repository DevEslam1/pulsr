package com.ryanheise.just_audio;

import android.app.Application;
import android.content.AttributionSource;
import android.content.Context;
import android.content.ContextWrapper;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Looper;
import android.os.Process;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Exercises route requests and readback against real Android AudioTracks. */
public final class OutputRoutingSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        System.out.println("ROUTE: entering main");
        Looper.prepareMainLooper();
        Object thread = Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        Context systemContext = (Context) thread.getClass().getMethod("getSystemContext").invoke(thread);
        Context context = new ContextWrapper(systemContext.createPackageContext("com.android.shell", 0)) {
            @Override public Context getApplicationContext() { return this; }
            @Override public String getOpPackageName() { return "com.android.shell"; }
            @Override public AttributionSource getAttributionSource() {
                return new AttributionSource.Builder(Process.myUid()).setPackageName("com.android.shell").build();
            }
        };
        // app_process runs as shell. Give AudioTrack the matching shell identity,
        // rather than ActivityThread.systemMain's Android-system identity.
        Application application = new Application();
        java.lang.reflect.Method attach = Application.class.getDeclaredMethod("attach", Context.class);
        attach.setAccessible(true);
        attach.invoke(application, context);
        java.lang.reflect.Field initialApplication = thread.getClass().getDeclaredField("mInitialApplication");
        initialApplication.setAccessible(true);
        initialApplication.set(thread, application);
        System.out.println("ROUTE: system context ready");
        AudioManager manager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        AudioDeviceInfo speaker = null;
        for (AudioDeviceInfo device : manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            if (device.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) speaker = device;
        }
        check(speaker != null, "Phone output must exist");
        for (int encoding : new int[] {C.ENCODING_PCM_16BIT, C.ENCODING_PCM_FLOAT}) {
            System.out.println("ROUTE: building sink " + encoding);
            DefaultAudioSink sink = new DefaultAudioSink.Builder()
                    .setEnableFloatOutput(encoding == C.ENCODING_PCM_FLOAT).build();
            System.out.println("ROUTE: sink ready");
            try {
                PulsrOutputRouting.observe(sink);
                sink.configure(new Format.Builder().setSampleMimeType("audio/raw")
                        .setSampleRate(44100).setChannelCount(2).setPcmEncoding(encoding).build(), 0, null);
                System.out.println("ROUTE: configured");
                sink.play();
                sink.setPreferredDevice(speaker);
                for (int i = 0; i < 30; i++) {
                    ByteBuffer buffer = ByteBuffer.allocateDirect(441 * 2 * (encoding == C.ENCODING_PCM_FLOAT ? 4 : 2)).order(ByteOrder.nativeOrder());
                    int retry = 0;
                    while (!sink.handleBuffer(buffer, i * 10000L, 1)) {
                        check(retry++ < 200, "AudioTrack must consume PCM within one second");
                        Thread.sleep(5);
                    }
                    if (PulsrOutputRouting.snapshot()[0] == speaker.getId()) break;
                    Thread.sleep(10);
                }
                int[] measured = PulsrOutputRouting.snapshot();
                check(measured[0] == speaker.getId(), "Phone must be the actual routed device");
                check(measured[1] == 44100, "App rate must retain 44.1 kHz precision");
                check(measured[2] == encoding, "Readback must report actual PCM encoding");
                sink.setPreferredDevice(null);
            } finally {
                sink.reset();
                sink.release();
            }
        }
        check(PulsrOutputRouting.snapshot()[1] == 0, "Released streams must become unverified");
        System.out.println("PASS: Phone routing/readback for real PCM16 and float AudioTracks, preference clearing, released-stream truth");
        System.exit(0);
    }
}
