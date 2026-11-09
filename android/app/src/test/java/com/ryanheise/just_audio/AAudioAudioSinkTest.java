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
        int openedEncoding;
        byte[] writtenBytes;

        @Override public long openForDevice(int sampleRate, int channelCount, int encoding,
                boolean preferExclusive, int targetBufferMs, int deviceId) {
            openedEncoding = encoding;
            return 1L;
        }

        @Override public int getDeviceId(long handle) { return 7; }

        @Override public void close(long handle) {}

        @Override public int write(long handle, ByteBuffer buffer, int offset, int length) {
            writtenBytes = new byte[length];
            ByteBuffer view = buffer.duplicate();
            view.position(offset);
            view.get(writtenBytes);
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
    public void exclusiveRejectsInt32RatherThanClaimingExactFloatConversion() throws Exception {
        AAudioAudioSink sink = new AAudioAudioSink(true, 50);
        FakeBridge bridge = new FakeBridge();
        sink.setBridgeForTest(bridge);
        assertEquals(AudioSink.SINK_FORMAT_UNSUPPORTED, sink.getFormatSupport(pcm32()));
        try {
            sink.configure(pcm32(), 0, null);
            org.junit.Assert.fail("exclusive int32 must not open a float stream");
        } catch (AudioSink.ConfigurationException expected) {
            assertEquals(0, bridge.openedEncoding);
        }
    }

    @Test
    public void sharedInt32ReportsFloatTranscodingAndDemonstratesLostLowBits() throws Exception {
        FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 8;
        AAudioAudioSink sink = newSink(bridge);
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_WITH_TRANSCODING,
                sink.getFormatSupport(pcm32()));
        sink.configure(pcm32(), 0, null);
        assertEquals(AaudioNativeBridge.ENCODING_PCM_FLOAT, bridge.openedEncoding);
        assertEquals(android.media.AudioFormat.ENCODING_PCM_FLOAT, sink.measuredStream()[2]);
        ByteBuffer input = ByteBuffer.allocateDirect(8).order(java.nio.ByteOrder.nativeOrder());
        input.putInt(0x40000000).putInt(0x40000001).flip();
        assertTrue(sink.handleBuffer(input, 100L, 1));
        ByteBuffer written = ByteBuffer.wrap(bridge.writtenBytes).order(java.nio.ByteOrder.nativeOrder());
        assertEquals(written.getFloat(), written.getFloat(), 0f);
    }

    @Test
    public void packed24ExclusiveBypassPreservesLeastSignificantBits() throws Exception {
        FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 6;
        AAudioAudioSink sink = new AAudioAudioSink(true, 50);
        sink.setBridgeForTest(bridge);
        Format format = pcm16().buildUpon().setPcmEncoding(C.ENCODING_PCM_24BIT).build();
        sink.configure(format, 0, null);
        byte[] raw = new byte[] {0, 0, 64, 1, 0, 64};
        ByteBuffer input = ByteBuffer.allocateDirect(raw.length);
        input.put(raw).flip();
        assertTrue(sink.handleBuffer(input, 0L, 1));
        org.junit.Assert.assertArrayEquals(raw, bridge.writtenBytes);
        assertEquals(AaudioNativeBridge.ENCODING_PCM_I24_PACKED, bridge.openedEncoding);
    }

    @Test
    public void gaplessDelayPaddingAndPartialWritesNeverDropLastProgramFrame() throws Exception {
        FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 4;
        AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16().buildUpon().setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
        sink.flush();
        ByteBuffer source = ByteBuffer.allocateDirect(16).order(java.nio.ByteOrder.nativeOrder());
        source.putShort((short) 1).putShort((short) 2)
                .putShort((short) 10).putShort((short) 11)
                .putShort((short) 20).putShort((short) 21)
                .putShort((short) 30).putShort((short) 31).flip();
        assertFalse(sink.handleBuffer(source, 90, 1));
        assertEquals(0, source.position());
        ByteBuffer written = ByteBuffer.wrap(bridge.writtenBytes).order(java.nio.ByteOrder.nativeOrder());
        assertEquals(10, written.getShort());
        assertEquals(11, written.getShort());
        assertEquals(20, written.getShort());
        assertTrue(sink.hasPendingData());
        assertTrue(sink.handleBuffer(source, 90, 1));
        assertEquals(16, source.position());
        written = ByteBuffer.wrap(bridge.writtenBytes).order(java.nio.ByteOrder.nativeOrder());
        assertEquals(20, written.getShort());
        assertEquals(21, written.getShort());
        ByteBuffer next = ByteBuffer.allocateDirect(4).order(java.nio.ByteOrder.nativeOrder());
        next.putShort((short) 40).putShort((short) 41).flip();
        assertTrue(sink.handleBuffer(next, 100, 1));
        written = ByteBuffer.wrap(bridge.writtenBytes).order(java.nio.ByteOrder.nativeOrder());
        assertEquals(30, written.getShort());
        assertEquals(31, written.getShort());
        sink.playToEndOfStream();
        assertTrue(sink.isEnded());
        sink.release();
    }

    @Test
    public void byteAwareTrimRetainsPacked24AndFloatSamplesUnchanged() throws Exception {
        for (int encoding : new int[] {C.ENCODING_PCM_24BIT, C.ENCODING_PCM_FLOAT}) {
            int sampleBytes = encoding == C.ENCODING_PCM_24BIT ? 3 : 4;
            FakeBridge bridge = new FakeBridge();
            bridge.writeResult = sampleBytes * 2;
            AAudioAudioSink sink = newSink(bridge);
            sink.configure(pcm16().buildUpon().setPcmEncoding(encoding)
                    .setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
            byte[] codes = new byte[sampleBytes * 6];
            for (int i = 0; i < codes.length; i++) codes[i] = (byte) (i * 17 + 1);
            ByteBuffer source = ByteBuffer.allocateDirect(codes.length);
            source.put(codes).flip();
            assertTrue(sink.handleBuffer(source, 0, 1));
            org.junit.Assert.assertArrayEquals(java.util.Arrays.copyOfRange(codes,
                    sampleBytes * 2, sampleBytes * 4), bridge.writtenBytes);
            sink.playToEndOfStream();
            sink.release();
        }
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
        // The frames read before the new base must not be added to the new
        // presentation timestamp.
        assertEquals(1_000_000L, sink.getCurrentPositionUs(false));

        // Advance both counters by 480 frames (10 ms at 48 kHz) past the base.
        bridge.framesWritten = 250 + 480;
        bridge.framesRead = 250 + 480;
        assertEquals(1_010_000L, sink.getCurrentPositionUs(false));
    }

    @Test
    public void discontinuityRebasesPositionWithoutCountingOldFrames()
            throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 1000;
        bridge.framesWritten = 500;
        bridge.framesRead = 200;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);
        final ByteBuffer buffer = ByteBuffer.allocateDirect(1000);
        assertTrue(sink.handleBuffer(buffer, 5_000_000L, 0));
        assertEquals(5_000_000L, sink.getCurrentPositionUs(false));

        bridge.framesWritten = 900;
        bridge.framesRead = 700;
        sink.handleDiscontinuity();
        final ByteBuffer next = ByteBuffer.allocateDirect(1000);
        assertTrue(sink.handleBuffer(next, 6_000_000L, 0));
        assertEquals(6_000_000L, sink.getCurrentPositionUs(false));

        bridge.framesWritten = 900 + 480;
        bridge.framesRead = 900 + 480;
        assertEquals(6_010_000L, sink.getCurrentPositionUs(false));
    }
}
