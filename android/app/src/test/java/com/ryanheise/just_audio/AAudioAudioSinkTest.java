package com.ryanheise.just_audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.exoplayer.audio.AudioSink;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.nio.ByteBuffer;

/** Sink logic tests using the injected bridge seam (no native code). */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class AAudioAudioSinkTest {

    static final class FakeBridge implements AAudioAudioSink.Bridge {
        int writeResult;
        long framesWritten;
        long framesRead;

        @Override public long openForDevice(int sampleRate, int channelCount, int encoding,
                boolean preferExclusive, int targetBufferMs, int deviceId) {
            return 1L;
        }

        @Override public int getDeviceId(long handle) { return 7; }

        @Override public void close(long handle) {}

        @Override public int write(long handle, ByteBuffer buffer, int offset, int length) {
            return writeResult;
        }

        @Override public void play(long handle) {}

        @Override public void pause(long handle) {}

        @Override public void flush(long handle) {}

        @Override public long getFramesRead(long handle) { return framesRead; }

        @Override public long getFramesWritten(long handle) { return framesWritten; }

        @Override public boolean isExclusive(long handle) { return true; }

        @Override public void setVolume(long handle, float volume) {}
    }

    private static AAudioAudioSink newSink(FakeBridge bridge) {
        final AAudioAudioSink sink = new AAudioAudioSink(false, 50);
        sink.setBridgeForTest(bridge);
        return sink;
    }

    private static Format pcm16() {
        return new Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setSampleRate(48000)
                .setChannelCount(2)
                .setPcmEncoding(C.ENCODING_PCM_16BIT)
                .build();
    }

    private static Format pcm32() {
        return new Format.Builder()
                .setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setSampleRate(48000)
                .setChannelCount(2)
                .setPcmEncoding(C.ENCODING_PCM_32BIT)
                .build();
    }

    @Test
    public void partialNativeWriteAdvancesSixteenBitBufferByConsumedBytes()
            throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 300;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);
        final ByteBuffer buffer = ByteBuffer.allocateDirect(1000);

        final boolean consumed = sink.handleBuffer(buffer, 0, 0);

        assertFalse(consumed);
        assertEquals(300, buffer.position());
    }

    @Test
    public void partialNativeWriteAdvancesThirtyTwoBitBufferByConsumedBytes()
            throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 500;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm32(), 0, null);
        final ByteBuffer buffer = ByteBuffer.allocateDirect(1000);

        final boolean consumed = sink.handleBuffer(buffer, 0, 0);

        assertFalse(consumed);
        assertEquals(500, buffer.position());
    }

    @Test
    public void positionIsUnavailableUntilTheFirstBufferRebasesIt()
            throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 1000;
        bridge.framesWritten = 250;
        bridge.framesRead = 100;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);

        assertEquals(AudioSink.CURRENT_POSITION_NOT_SET,
                sink.getCurrentPositionUs(false));

        final ByteBuffer buffer = ByteBuffer.allocateDirect(1000);
        assertTrue(sink.handleBuffer(buffer, 1_000_000L, 0));
        assertEquals(1_002_083L, sink.getCurrentPositionUs(false));
    }
}
