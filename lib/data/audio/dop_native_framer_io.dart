import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

typedef _AllocNative = Pointer<Uint8> Function(Size bytes);
typedef _AllocDart = Pointer<Uint8> Function(int bytes);

typedef _FreeNative = Void Function(Pointer<Uint8> ptr);
typedef _FreeDart = void Function(Pointer<Uint8> ptr);

typedef _FramePlanarNative = Int32 Function(
  Pointer<Uint8> dsdLeft,
  Pointer<Uint8> dsdRight,
  Size channelBytes,
  Int32 containerBits,
  Int32 reverseBits,
  Uint8 firstMarker,
  Pointer<Uint8> outBuf,
  Size outCapacity,
  Pointer<Size> outBytes,
  Pointer<Uint8> nextMarker,
);
typedef _FramePlanarDart = int Function(
  Pointer<Uint8> dsdLeft,
  Pointer<Uint8> dsdRight,
  int channelBytes,
  int containerBits,
  int reverseBits,
  int firstMarker,
  Pointer<Uint8> outBuf,
  int outCapacity,
  Pointer<Size> outBytes,
  Pointer<Uint8> nextMarker,
);

class _DopNativeBindings {
  _DopNativeBindings(DynamicLibrary lib)
      : alloc = lib.lookupFunction<_AllocNative, _AllocDart>('pulsr_dop_alloc'),
        free = lib.lookupFunction<_FreeNative, _FreeDart>('pulsr_dop_free'),
        framePlanar = lib.lookupFunction<_FramePlanarNative, _FramePlanarDart>(
          'pulsr_dop_frame_planar',
        );

  final _AllocDart alloc;
  final _FreeDart free;
  final _FramePlanarDart framePlanar;
}

_DopNativeBindings? _cachedBindings;
bool _loadAttempted = false;
String? _testLibraryPath;

void setDopNativeLibraryPathForTesting(String? path) {
  _testLibraryPath = path;
  _cachedBindings = null;
  _loadAttempted = false;
}

_DopNativeBindings? _resolveBindings() {
  if (_loadAttempted) return _cachedBindings;
  _loadAttempted = true;
  final String? libPath =
      _testLibraryPath ?? (Platform.isAndroid ? 'libpulsr_dsp.so' : null);
  if (libPath == null) return null;
  try {
    _cachedBindings = _DopNativeBindings(DynamicLibrary.open(libPath));
  } catch (_) {
    _cachedBindings = null;
  }
  return _cachedBindings;
}

/// Frames planar stereo DSD bytes using the authoritative native C++
/// `DopFramer` inside `libpulsr_dsp.so`. Returns `null` when the native
/// library is unavailable so callers fall back to the identical Dart path.
Uint8List? encodeDopPlanarNative({
  required Uint8List dsdLeft,
  required Uint8List dsdRight,
  required int containerBits,
  required bool reverseBits,
  required int firstMarker,
}) {
  final bindings = _resolveBindings();
  if (bindings == null) return null;

  final int channelBytes = dsdLeft.length;
  if (channelBytes == 0) return Uint8List(0);
  if (channelBytes != dsdRight.length || channelBytes.isOdd) return null;
  if (containerBits != 24 && containerBits != 32) return null;

  final int bytesPerFrame = (containerBits == 32) ? 8 : 6;
  // Bound scratch memory to 2 MiB/ch (~12-16 MiB output scratch) while keeping
  // marker phase continuous across chunks via nextMarker.
  const int maxChunkChannelBytes = 2 * 1024 * 1024;
  final int chunkCap = math.min(channelBytes, maxChunkChannelBytes);
  final int outChunkCap = (chunkCap ~/ 2) * bytesPerFrame;

  Pointer<Uint8> leftPtr = nullptr;
  Pointer<Uint8> rightPtr = nullptr;
  Pointer<Uint8> outPtr = nullptr;
  Pointer<Uint8> outBytesRaw = nullptr;
  Pointer<Uint8> nextMarkerPtr = nullptr;

  try {
    leftPtr = bindings.alloc(chunkCap);
    rightPtr = bindings.alloc(chunkCap);
    outPtr = bindings.alloc(outChunkCap);
    outBytesRaw = bindings.alloc(sizeOf<Size>());
    nextMarkerPtr = bindings.alloc(1);

    if (leftPtr == nullptr ||
        rightPtr == nullptr ||
        outPtr == nullptr ||
        outBytesRaw == nullptr ||
        nextMarkerPtr == nullptr) {
      return null;
    }

    final Pointer<Size> outBytesPtr = outBytesRaw.cast<Size>();
    final Uint8List result = Uint8List((channelBytes ~/ 2) * bytesPerFrame);

    int offset = 0;
    int outOffset = 0;
    int marker = firstMarker;

    while (offset < channelBytes) {
      final int len = math.min(chunkCap, channelBytes - offset);
      leftPtr.asTypedList(len).setRange(0, len, dsdLeft, offset);
      rightPtr.asTypedList(len).setRange(0, len, dsdRight, offset);

      final int ok = bindings.framePlanar(
        leftPtr,
        rightPtr,
        len,
        containerBits,
        reverseBits ? 1 : 0,
        marker,
        outPtr,
        outChunkCap,
        outBytesPtr,
        nextMarkerPtr,
      );
      if (ok != 1) return null;

      final int written = outBytesPtr.value;
      result.setRange(
        outOffset,
        outOffset + written,
        outPtr.asTypedList(written),
      );
      outOffset += written;
      marker = nextMarkerPtr.value;
      offset += len;
    }

    return result;
  } finally {
    if (leftPtr != nullptr) bindings.free(leftPtr);
    if (rightPtr != nullptr) bindings.free(rightPtr);
    if (outPtr != nullptr) bindings.free(outPtr);
    if (outBytesRaw != nullptr) bindings.free(outBytesRaw);
    if (nextMarkerPtr != nullptr) bindings.free(nextMarkerPtr);
  }
}
