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

    static class FakeBridge implements AAudioAudioSink.Bridge {
        int writeResult;
        int writeCount;
        long framesWritten;
        long framesRead;
        int openedEncoding;
        int lastSampleRate;
        int openCount;
        int closeCount;
        int flushCount;
        byte[] writtenBytes;
        boolean bitPerfect;

        @Override public long openForDevice(int sampleRate, int channelCount, int encoding,
                boolean preferExclusive, int targetBufferMs, int deviceId) {
            openedEncoding = encoding;
            lastSampleRate = sampleRate;
            openCount++;
            return openCount;
        }

        @Override public int getDeviceId(long handle) { return 7; }

        @Override public void close(long handle) { closeCount++; }

        @Override public int write(long handle, ByteBuffer buffer, int offset, int length) {
            writeCount++;
            writtenBytes = new byte[length];
            ByteBuffer view = buffer.duplicate();
            view.position(offset);
            view.get(writtenBytes);
            return writeResult;
        }

        @Override public void play(long handle) {}

        @Override public void pause(long handle) {}

        @Override public void flush(long handle) { flushCount++; }

        @Override public long getFramesRead(long handle) { return framesRead; }

        @Override public long getFramesWritten(long handle) { return framesWritten; }

        @Override public boolean isExclusive(long handle) { return true; }

        @Override public void setVolume(long handle, float volume) {}

        @Override public void setBitPerfect(long handle, boolean bitPerfect, boolean dop) {
            this.bitPerfect = bitPerfect;
        }

        @Override public boolean isBitPerfectSink(long handle) { return bitPerfect; }
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
    public void exclusiveRejectsInt32BelowApi31RatherThanClaimingExactFloatConversion() throws Exception {
        AAudioAudioSink sink = new AAudioAudioSink(true, 50);
        FakeBridge bridge = new FakeBridge();
        sink.setBridgeForTest(bridge);
        sink.setDeviceApiLevelForTest(30);
        assertEquals(AudioSink.SINK_FORMAT_UNSUPPORTED, sink.getFormatSupport(pcm32()));
        try {
            sink.configure(pcm32(), 0, null);
            org.junit.Assert.fail("exclusive int32 below API 31 must not open a float stream");
        } catch (AudioSink.ConfigurationException expected) {
            assertEquals(0, bridge.openedEncoding);
        }
    }

    @Test
    public void exclusiveInt32Api31OpensNativeI32AndPreservesLeastSignificantBits() throws Exception {
        FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 8;
        AAudioAudioSink sink = new AAudioAudioSink(true, 50);
        sink.setBridgeForTest(bridge);
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY, sink.getFormatSupport(pcm32()));
        sink.configure(pcm32(), 0, null);
        assertEquals(AaudioNativeBridge.ENCODING_PCM_I32, bridge.openedEncoding);
        assertEquals(android.media.AudioFormat.ENCODING_PCM_32BIT, sink.measuredStream()[2]);
        ByteBuffer input = ByteBuffer.allocateDirect(8).order(java.nio.ByteOrder.nativeOrder());
        input.putInt(0x40000000).putInt(0x40000001).flip();
        assertTrue(sink.handleBuffer(input, 100L, 1));
        ByteBuffer written = ByteBuffer.wrap(bridge.writtenBytes).order(java.nio.ByteOrder.nativeOrder());
        assertEquals(0x40000000, written.getInt());
        assertEquals(0x40000001, written.getInt());
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

    @Test
    public void sameFormatConsecutiveConfigureReusesHandleWithoutCloseOrFlush() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 16;
        bridge.framesWritten = 4;
        bridge.framesRead = 4;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);
        assertEquals(1, bridge.openCount);

        final ByteBuffer first = ByteBuffer.allocateDirect(16);
        assertTrue(sink.handleBuffer(first, 1_000_000L, 1));
        sink.playToEndOfStream();
        assertTrue(sink.isEnded());

        sink.configure(pcm16().buildUpon().setEncoderDelay(0).build(), 0, null);
        assertEquals(1, bridge.openCount);
        assertEquals(0, bridge.closeCount);
        assertEquals(0, bridge.flushCount);
        assertFalse(sink.isEnded());
        assertEquals(AudioSink.CURRENT_POSITION_NOT_SET, sink.getCurrentPositionUs(false));

        final ByteBuffer second = ByteBuffer.allocateDirect(16);
        assertTrue(sink.handleBuffer(second, 2_000_000L, 1));
        assertEquals(2_000_000L, sink.getCurrentPositionUs(false));
    }

    @Test
    public void rateChangeWithQueuedFramesDrainsBeforeClosingAndReopening() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 16;
        bridge.framesWritten = 100;
        bridge.framesRead = 50;
        final long[] nowMs = {1000L};
        final AAudioAudioSink sink = newSink(bridge);
        sink.setClockForTest(() -> nowMs[0]);
        sink.configure(pcm16().buildUpon().setSampleRate(44100).build(), 0, null);
        assertEquals(1, bridge.openCount);
        assertEquals(44100, bridge.lastSampleRate);

        sink.configure(pcm16().buildUpon().setSampleRate(96000).build(), 0, null);
        assertEquals(0, bridge.closeCount);
        assertEquals(1, bridge.openCount);

        final ByteBuffer next = ByteBuffer.allocateDirect(16);
        assertFalse(sink.handleBuffer(next, 0L, 1));
        assertEquals(0, bridge.closeCount);
        assertEquals(0, next.position());

        bridge.framesRead = 100;
        assertTrue(sink.handleBuffer(next, 0L, 1));
        assertEquals(1, bridge.closeCount);
        assertEquals(2, bridge.openCount);
        assertEquals(96000, bridge.lastSampleRate);
    }

    @Test
    public void rateChangeDrainSafetyTimeoutForcesCloseAndReopen() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 16;
        bridge.framesWritten = 100;
        bridge.framesRead = 50;
        final long[] nowMs = {1000L};
        final AAudioAudioSink sink = newSink(bridge);
        sink.setClockForTest(() -> nowMs[0]);
        sink.configure(pcm16().buildUpon().setSampleRate(44100).build(), 0, null);

        sink.configure(pcm16().buildUpon().setSampleRate(96000).build(), 0, null);
        nowMs[0] = 1500L; // max(50 * 2, 500) == 500 ms safety timeout reached

        final ByteBuffer next = ByteBuffer.allocateDirect(16);
        assertTrue(sink.handleBuffer(next, 0L, 1));
        assertEquals(1, bridge.closeCount);
        assertEquals(2, bridge.openCount);
        assertEquals(96000, bridge.lastSampleRate);
    }

    @Test
    public void routePendingStillForcesReopenWhenFormatIsUnchanged() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 16;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);
        assertEquals(1, bridge.openCount);

        sink.setPreferredDeviceId(42);

        final ByteBuffer next = ByteBuffer.allocateDirect(16);
        assertTrue(sink.handleBuffer(next, 0L, 1));
        assertEquals(1, bridge.closeCount);
        assertEquals(2, bridge.openCount);
    }

    @Test
    public void closeHandleSwallowsRuntimeExceptionFromBridge() throws Exception {
        final FakeBridge bridge = new FakeBridge() {
            @Override
            public void close(long handle) {
                super.close(handle);
                throw new RuntimeException("nativeClose threw");
            }
        };
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16(), 0, null);
        sink.release();
        assertEquals(1, bridge.closeCount);
    }

    @Test
    public void routeChangeRestoreSuccessSkipsErrorAndFailureReportsOnce() throws Exception {
        final boolean[] allowDeviceZero = {true};
        final FakeBridge bridge = new FakeBridge() {
            @Override
            public long openForDevice(int sampleRate, int channelCount, int encoding,
                    boolean preferExclusive, int targetBufferMs, int deviceId) {
                if (deviceId == 99 || !allowDeviceZero[0]) {
                    return 0L;
                }
                return super.openForDevice(sampleRate, channelCount, encoding,
                        preferExclusive, targetBufferMs, deviceId);
            }
        };
        bridge.writeResult = 16;
        final AudioSink.Listener listener = org.mockito.Mockito.mock(AudioSink.Listener.class);
        final AAudioAudioSink sink = newSink(bridge);
        sink.setListener(listener);
        sink.configure(pcm16(), 0, null);

        // New device fails, restore to device 0 succeeds: no sink error reported.
        sink.setPreferredDeviceId(99);
        assertTrue(sink.handleBuffer(ByteBuffer.allocateDirect(16), 0L, 1));
        org.mockito.Mockito.verify(listener, org.mockito.Mockito.never())
                .onAudioSinkError(org.mockito.ArgumentMatchers.any());

        // New device fails AND restore fails: error reported once, not twice.
        allowDeviceZero[0] = false;
        sink.setPreferredDeviceId(99);
        assertFalse(sink.handleBuffer(ByteBuffer.allocateDirect(16), 0L, 1));
        org.mockito.Mockito.verify(listener, org.mockito.Mockito.times(1))
                .onAudioSinkError(org.mockito.ArgumentMatchers.any());
    }

    @Test
    public void playToEndOfStreamRetriesPendingEditedInputWithPendingTimestamp() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        bridge.writeResult = 4;
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm16().buildUpon().setEncoderPadding(1).build(), 0, null);

        // First buffer establishes basePositionUs = 100_000 us and stages padding.
        assertTrue(sink.handleBuffer(ByteBuffer.allocateDirect(8), 100_000L, 1));
        assertEquals(100_000L, sink.getCurrentPositionUs(false));

        // Second buffer is partially written (4 of 8 edited bytes), caching 777_000 us.
        assertFalse(sink.handleBuffer(ByteBuffer.allocateDirect(8), 777_000L, 5));

        // Mark discontinuity before EOS so playToEndOfStream retry latches its timestamp.
        sink.handleDiscontinuity();
        bridge.writeResult = 4;
        sink.playToEndOfStream();
        assertTrue(sink.isEnded());
        assertEquals(777_000L, sink.getCurrentPositionUs(false));
    }

    @Test
    public void pcm32TranscodeConsumesTrailingSubSampleBytesWithoutStalling() throws Exception {
        final FakeBridge bridge = new FakeBridge();
        final AAudioAudioSink sink = newSink(bridge);
        sink.configure(pcm32(), 0, null);

        // Direct buffer with 2 full samples (8 bytes) + 2 trailing bytes.
        bridge.writeResult = 8;
        final ByteBuffer direct = ByteBuffer.allocateDirect(10);
        assertTrue(sink.handleBuffer(direct, 0L, 1));
        assertEquals(10, direct.position());

        // Non-direct buffer with 2 full samples (8 bytes) + 1 trailing byte.
        final ByteBuffer heap = ByteBuffer.allocate(9);
        assertTrue(sink.handleBuffer(heap, 0L, 1));
        assertEquals(9, heap.position());

        // Buffer shorter than one 32-bit sample completes immediately without writing 0 bytes.
        final int writesBeforeShort = bridge.writeCount;
        final ByteBuffer shortBuf = ByteBuffer.allocateDirect(3);
        assertTrue(sink.handleBuffer(shortBuf, 0L, 1));
        assertEquals(3, shortBuf.position());
        assertEquals(writesBeforeShort, bridge.writeCount);
    }
}
