// lib/data/audio/mp4_box_parser.dart
//
// ISO BMFF (MPEG-4 Part 12 / QuickTime) audio track probe.
//
// Inspects .m4a / .mp4 / .m4b / .alac containers down to the sample description
// atom (`stsd`) and the codec-specific configuration atom (e.g. `alac` magic
// cookie) instead of guessing audio properties from file extensions or
// bitrates.
//
// Traversal hierarchy:
//   ftyp (file type / brand)
//   moov (movie container)
//     trak (track)
//       mdia (media)
//         hdlr ('soun' handler verification)
//         minf (media info)
//           stbl (sample table)
//             stsd (sample description)
//               [format box, e.g. 'alac' or 'mp4a']
//                 AudioSampleEntry (channels, sampleRate, version)
//                 ['alac' atom -> ALACSpecificConfig (bitDepth, channels, sampleRate)]

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The audio codec type identified inside an ISO-BMFF / MP4 container.
enum Mp4AudioCodec {
  alac,
  aac,
  flac,
  opus,
  ac3,
  eac3,
  dts,
  other,
  none,
}

/// Result of probing an ISO BMFF / MP4 file or byte buffer for audio tracks.
class Mp4AudioProbeResult {
  const Mp4AudioProbeResult({
    required this.hasAudioTrack,
    required this.codec,
    required this.codecType,
    required this.isLossless,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.bitrateKbps,
    this.fourcc,
    this.majorBrand,
    this.compatibleBrands = const [],
  });

  /// No audio track found in the container.
  static const Mp4AudioProbeResult noAudio = Mp4AudioProbeResult(
    hasAudioTrack: false,
    codec: 'NONE',
    codecType: Mp4AudioCodec.none,
    isLossless: false,
  );

  /// Unrecognized or corrupted container.
  static const Mp4AudioProbeResult unrecognised = Mp4AudioProbeResult(
    hasAudioTrack: false,
    codec: 'UNKNOWN',
    codecType: Mp4AudioCodec.none,
    isLossless: false,
  );

  /// Whether an audio track ('soun' handler) with a sample description was found.
  final bool hasAudioTrack;

  /// Canonical human/scanner-facing codec string (e.g. 'ALAC', 'AAC', 'FLAC', 'OPUS').
  final String codec;

  /// High-level codec classification enum.
  final Mp4AudioCodec codecType;

  /// True for lossless codecs (ALAC, FLAC).
  final bool isLossless;

  /// Audio sample rate in Hz (e.g. 44100, 48000, 96000, 192000).
  final int? sampleRate;

  /// Audio bit depth (e.g. 16, 20, 24, 32). Only available for PCM/lossless like ALAC.
  final int? bitDepth;

  /// Number of audio channels (e.g. 1, 2, 6, 8).
  final int? channels;

  /// Average bitrate in kbps, if reported in the header.
  final int? bitrateKbps;

  /// The exact 4-character code from the sample entry (e.g. 'alac', 'mp4a').
  final String? fourcc;

  /// The major brand from the 'ftyp' box (e.g. 'M4A ', 'mp42', 'qt  ').
  final String? majorBrand;

  /// Compatible brands listed in the 'ftyp' box.
  final List<String> compatibleBrands;

  /// True when a valid, recognized audio track was parsed.
  bool get isRecognised => hasAudioTrack && codecType != Mp4AudioCodec.none;

  /// True when this is an Apple Lossless track.
  bool get isAlac => codecType == Mp4AudioCodec.alac;

  /// True when this is an Advanced Audio Coding track.
  bool get isAac => codecType == Mp4AudioCodec.aac;

  /// True if the track is Hi-Res (lossless and >= 24-bit or > 48 kHz).
  bool get isHiRes =>
      isLossless &&
      ((bitDepth != null && bitDepth! >= 24) ||
          (sampleRate != null && sampleRate! > 48000));

  @override
  String toString() =>
      'Mp4AudioProbeResult(codec: $codec, type: ${codecType.name}, '
      'sampleRate: $sampleRate, bitDepth: $bitDepth, channels: $channels, '
      'bitrate: ${bitrateKbps}k, isLossless: $isLossless, fourcc: $fourcc)';
}

/// Standalone ISO-BMFF / MP4 audio atom parser.
abstract final class Mp4BoxParser {
  /// Probes an MP4/M4A file at [path] asynchronously.
  ///
  /// Uses random-access seeking so even multi-gigabyte files are probed in
  /// milliseconds reading only atom headers. Never throws.
  static Future<Mp4AudioProbeResult> probePath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return Mp4AudioProbeResult.unrecognised;
    }
    return probeFile(file);
  }

  /// Probes [file] asynchronously using a [RandomAccessFile]. Never throws.
  static Future<Mp4AudioProbeResult> probeFile(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final reader = _RafByteReader(handle);
      return await _parseFromReader(reader);
    } catch (_) {
      return Mp4AudioProbeResult.unrecognised;
    } finally {
      try {
        await handle?.close();
      } catch (_) {}
    }
  }

  /// Probes [bytes] in memory synchronously. Never throws.
  static Mp4AudioProbeResult probeBytes(Uint8List bytes) {
    try {
      final reader = _MemoryByteReader(bytes);
      return _parseSyncFromReader(reader);
    } catch (_) {
      return Mp4AudioProbeResult.unrecognised;
    }
  }

  static Future<Mp4AudioProbeResult> _parseFromReader(
      _AsyncByteReader reader) async {
    final fileLength = await reader.length();
    if (fileLength < 8) return Mp4AudioProbeResult.unrecognised;

    String? majorBrand;
    final compatibleBrands = <String>[];

    int offset = 0;
    while (offset + 8 <= fileLength) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > fileLength) {
        // Corrupted box header or unexpected truncation
        break;
      }

      if (boxType == 'ftyp') {
        if (boxSize >= headerSize + 8) {
          final ftypPayload =
              await reader.readBytes(offset + headerSize, boxSize - headerSize);
          if (ftypPayload.length >= 8) {
            majorBrand = _asciiString(ftypPayload, 0, 4);
            final compCount = (ftypPayload.length - 8) ~/ 4;
            for (var i = 0; i < compCount; i++) {
              final brand = _asciiString(ftypPayload, 8 + i * 4, 4).trim();
              if (brand.isNotEmpty) compatibleBrands.add(brand);
            }
          }
        }
      } else if (boxType == 'moov') {
        // Traverse moov container
        final result = await _scanMoov(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
        if (result != null) return result;
      }

      offset += boxSize;
    }

    return Mp4AudioProbeResult.noAudio;
  }

  static Mp4AudioProbeResult _parseSyncFromReader(_SyncByteReader reader) {
    final fileLength = reader.length();
    if (fileLength < 8) return Mp4AudioProbeResult.unrecognised;

    String? majorBrand;
    final compatibleBrands = <String>[];

    int offset = 0;
    while (offset + 8 <= fileLength) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > fileLength) {
        break;
      }

      if (boxType == 'ftyp') {
        if (boxSize >= headerSize + 8) {
          final ftypPayload =
              reader.readBytes(offset + headerSize, boxSize - headerSize);
          if (ftypPayload.length >= 8) {
            majorBrand = _asciiString(ftypPayload, 0, 4);
            final compCount = (ftypPayload.length - 8) ~/ 4;
            for (var i = 0; i < compCount; i++) {
              final brand = _asciiString(ftypPayload, 8 + i * 4, 4).trim();
              if (brand.isNotEmpty) compatibleBrands.add(brand);
            }
          }
        }
      } else if (boxType == 'moov') {
        final result = _scanMoovSync(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
        if (result != null) return result;
      }

      offset += boxSize;
    }

    return Mp4AudioProbeResult.noAudio;
  }

  static Future<Mp4AudioProbeResult?> _scanMoov(
    _AsyncByteReader reader,
    int moovStart,
    int moovEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    int offset = moovStart;
    while (offset + 8 <= moovEnd) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > moovEnd) break;

      if (boxType == 'trak') {
        final probe = await _scanTrak(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
        if (probe != null && probe.hasAudioTrack) {
          return probe;
        }
      }
      offset += boxSize;
    }
    return null;
  }

  static Mp4AudioProbeResult? _scanMoovSync(
    _SyncByteReader reader,
    int moovStart,
    int moovEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    int offset = moovStart;
    while (offset + 8 <= moovEnd) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > moovEnd) break;

      if (boxType == 'trak') {
        final probe = _scanTrakSync(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
        if (probe != null && probe.hasAudioTrack) {
          return probe;
        }
      }
      offset += boxSize;
    }
    return null;
  }

  static Future<Mp4AudioProbeResult?> _scanTrak(
    _AsyncByteReader reader,
    int trakStart,
    int trakEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    int offset = trakStart;
    while (offset + 8 <= trakEnd) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > trakEnd) break;

      if (boxType == 'mdia') {
        return _scanMdia(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Mp4AudioProbeResult? _scanTrakSync(
    _SyncByteReader reader,
    int trakStart,
    int trakEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    int offset = trakStart;
    while (offset + 8 <= trakEnd) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > trakEnd) break;

      if (boxType == 'mdia') {
        return _scanMdiaSync(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Future<Mp4AudioProbeResult?> _scanMdia(
    _AsyncByteReader reader,
    int mdiaStart,
    int mdiaEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    int offset = mdiaStart;
    bool? isAudioTrack;
    int? minfStart;
    int? minfEnd;

    while (offset + 8 <= mdiaEnd) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > mdiaEnd) break;

      if (boxType == 'hdlr') {
        // FullBox: 4 bytes version+flags, 4 bytes pre_defined, 4 bytes handler_type
        if (boxSize >= headerSize + 12) {
          final hdlrData = await reader.readBytes(offset + headerSize, 12);
          final handlerType = _asciiString(hdlrData, 8, 4);
          isAudioTrack = handlerType == 'soun';
        }
      } else if (boxType == 'minf') {
        minfStart = offset + headerSize;
        minfEnd = offset + boxSize;
      }
      offset += boxSize;
    }

    if (isAudioTrack == false) {
      return null;
    }

    if (minfStart != null && minfEnd != null) {
      final res = await _scanMinf(
        reader,
        minfStart,
        minfEnd,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
      if (res != null) {
        if (isAudioTrack == true || res.hasAudioTrack) {
          return res;
        }
      }
    }
    return null;
  }

  static Mp4AudioProbeResult? _scanMdiaSync(
    _SyncByteReader reader,
    int mdiaStart,
    int mdiaEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    int offset = mdiaStart;
    bool? isAudioTrack;
    int? minfStart;
    int? minfEnd;

    while (offset + 8 <= mdiaEnd) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > mdiaEnd) break;

      if (boxType == 'hdlr') {
        if (boxSize >= headerSize + 12) {
          final hdlrData = reader.readBytes(offset + headerSize, 12);
          final handlerType = _asciiString(hdlrData, 8, 4);
          isAudioTrack = handlerType == 'soun';
        }
      } else if (boxType == 'minf') {
        minfStart = offset + headerSize;
        minfEnd = offset + boxSize;
      }
      offset += boxSize;
    }

    if (isAudioTrack == false) {
      return null;
    }

    if (minfStart != null && minfEnd != null) {
      final res = _scanMinfSync(
        reader,
        minfStart,
        minfEnd,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
      if (res != null) {
        if (isAudioTrack == true || res.hasAudioTrack) {
          return res;
        }
      }
    }
    return null;
  }

  static Future<Mp4AudioProbeResult?> _scanMinf(
    _AsyncByteReader reader,
    int minfStart,
    int minfEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    int offset = minfStart;
    while (offset + 8 <= minfEnd) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > minfEnd) break;

      if (boxType == 'stbl') {
        return _scanStbl(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Mp4AudioProbeResult? _scanMinfSync(
    _SyncByteReader reader,
    int minfStart,
    int minfEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    int offset = minfStart;
    while (offset + 8 <= minfEnd) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > minfEnd) break;

      if (boxType == 'stbl') {
        return _scanStblSync(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Future<Mp4AudioProbeResult?> _scanStbl(
    _AsyncByteReader reader,
    int stblStart,
    int stblEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    int offset = stblStart;
    while (offset + 8 <= stblEnd) {
      final (boxSize, boxType, headerSize) = await reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > stblEnd) break;

      if (boxType == 'stsd') {
        return _parseStsd(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Mp4AudioProbeResult? _scanStblSync(
    _SyncByteReader reader,
    int stblStart,
    int stblEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    int offset = stblStart;
    while (offset + 8 <= stblEnd) {
      final (boxSize, boxType, headerSize) = reader.readBoxHeader(offset);
      if (boxSize < headerSize || offset + boxSize > stblEnd) break;

      if (boxType == 'stsd') {
        return _parseStsdSync(
          reader,
          offset + headerSize,
          offset + boxSize,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      offset += boxSize;
    }
    return null;
  }

  static Future<Mp4AudioProbeResult?> _parseStsd(
    _AsyncByteReader reader,
    int stsdPayloadStart,
    int stsdEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) async {
    // stsd is a FullBox: 4 bytes version+flags, then 4 bytes entry_count
    if (stsdPayloadStart + 8 > stsdEnd) return null;
    final headerBytes = await reader.readBytes(stsdPayloadStart, 8);
    final entryCount = _readUint32(headerBytes, 4);
    if (entryCount <= 0) return null;

    int offset = stsdPayloadStart + 8;
    for (var i = 0; i < entryCount; i++) {
      if (offset + 8 > stsdEnd) break;
      final (entrySize, formatFourcc, entryHeaderSize) =
          await reader.readBoxHeader(offset);
      if (entrySize < entryHeaderSize || offset + entrySize > stsdEnd) break;

      // Sample entry contains an AudioSampleEntry header (at least 28 bytes beyond box header)
      final sampleEntryBytes = await reader.readBytes(offset, entrySize);
      final probe = _parseAudioSampleEntry(
        sampleEntryBytes,
        formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
      if (probe != null) return probe;

      offset += entrySize;
    }
    return null;
  }

  static Mp4AudioProbeResult? _parseStsdSync(
    _SyncByteReader reader,
    int stsdPayloadStart,
    int stsdEnd, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    if (stsdPayloadStart + 8 > stsdEnd) return null;
    final headerBytes = reader.readBytes(stsdPayloadStart, 8);
    final entryCount = _readUint32(headerBytes, 4);
    if (entryCount <= 0) return null;

    int offset = stsdPayloadStart + 8;
    for (var i = 0; i < entryCount; i++) {
      if (offset + 8 > stsdEnd) break;
      final (entrySize, formatFourcc, entryHeaderSize) =
          reader.readBoxHeader(offset);
      if (entrySize < entryHeaderSize || offset + entrySize > stsdEnd) break;

      final sampleEntryBytes = reader.readBytes(offset, entrySize);
      final probe = _parseAudioSampleEntry(
        sampleEntryBytes,
        formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
      if (probe != null) return probe;

      offset += entrySize;
    }
    return null;
  }

  /// Parses an AudioSampleEntry structure and its child atoms.
  static Mp4AudioProbeResult? _parseAudioSampleEntry(
    Uint8List entryBytes,
    String formatFourcc, {
    String? majorBrand,
    List<String> compatibleBrands = const [],
  }) {
    // AudioSampleEntry minimum length: 8 (box header) + 28 (audio fields) = 36 bytes
    if (entryBytes.length < 36) return null;

    final version = _readUint16(entryBytes, 16);
    final channels = _readUint16(entryBytes, 24);
    final sampleSize = _readUint16(entryBytes, 26);
    // sampleRate is 16.16 fixed-point (high 16 bits = integer sample rate)
    final sampleRateRaw = _readUint32(entryBytes, 32);
    int sampleRate = sampleRateRaw >> 16;
    if (sampleRate <= 0) {
      sampleRate = 44100;
    }

    int childOffset = 36;
    if (version == 1 && entryBytes.length >= 52) {
      childOffset = 52;
    } else if (version == 2 && entryBytes.length >= 72) {
      childOffset = 72;
    }

    final lowerFourcc = formatFourcc.toLowerCase();

    // Reject non-audio sample entries (video, subtitle, hint tracks)
    const nonAudioFourccs = {
      'avc1',
      'avc2',
      'avc3',
      'avc4',
      'hvc1',
      'hev1',
      'mp4v',
      's263',
      'vp08',
      'vp09',
      'av01',
      'jpeg',
      'png ',
      'raw ',
      'text',
      'tx3g',
      'sbtl',
      'subp',
      'rtp ',
      'hint',
      'tmcd',
    };
    if (nonAudioFourccs.contains(lowerFourcc)) {
      return null;
    }

    // Inspect child atoms (alac, esds, fLaC/dfLa, wave/enda, dOps)
    // Per §8.3: Inspect mp4a children, handle wave/enda, 64-bit child sizes,
    // and validate ALACSpecificConfig fields (bit depth 16/20/24/32, sane rate/channels).
    ({
      int bitDepth,
      int sampleRate,
      int channels,
      int? bitrateKbps
    })? alacConfig;
    String? embeddedCodec;
    bool malformedAlacSeen = false;

    int subOffset = childOffset;
    while (subOffset + 8 <= entryBytes.length) {
      int subBoxSize = _readUint32(entryBytes, subOffset);
      int subHeaderSize = 8;
      if (subBoxSize == 1) {
        if (subOffset + 16 > entryBytes.length) break;
        subBoxSize = _readUint64(entryBytes, subOffset + 8);
        subHeaderSize = 16;
      }
      if (subBoxSize < subHeaderSize ||
          subOffset + subBoxSize > entryBytes.length) {
        break;
      }
      final subBoxType = _asciiString(entryBytes, subOffset + 4, 4);

      if (subBoxType == 'alac') {
        alacConfig = _parseAlacBox(
            entryBytes, subOffset + subHeaderSize, subOffset + subBoxSize);
        if (alacConfig != null) {
          break;
        } else {
          malformedAlacSeen = true;
          break;
        }
      } else if (subBoxType == 'wave') {
        // QuickTime encapsulation: scan inside wave for alac / enda
        int waveOffset = subOffset + subHeaderSize;
        final waveEnd = subOffset + subBoxSize;
        while (waveOffset + 8 <= waveEnd) {
          int waveBoxSize = _readUint32(entryBytes, waveOffset);
          int waveHeaderSize = 8;
          if (waveBoxSize == 1) {
            if (waveOffset + 16 > waveEnd) break;
            waveBoxSize = _readUint64(entryBytes, waveOffset + 8);
            waveHeaderSize = 16;
          }
          if (waveBoxSize < waveHeaderSize ||
              waveOffset + waveBoxSize > waveEnd) {
            break;
          }
          final waveBoxType = _asciiString(entryBytes, waveOffset + 4, 4);
          if (waveBoxType == 'alac') {
            alacConfig = _parseAlacBox(entryBytes, waveOffset + waveHeaderSize,
                waveOffset + waveBoxSize);
            if (alacConfig != null) {
              break;
            } else {
              malformedAlacSeen = true;
              break;
            }
          }
          waveOffset += waveBoxSize;
        }
        if (alacConfig != null || malformedAlacSeen) break;
      } else if (subBoxType == 'fLaC' || subBoxType == 'dfLa') {
        embeddedCodec = 'FLAC';
      } else if (subBoxType == 'dOps') {
        embeddedCodec = 'OPUS';
      } else if (subBoxType == 'esds') {
        embeddedCodec = 'AAC';
      }
      subOffset += subBoxSize;
    }

    if (malformedAlacSeen) {
      return Mp4AudioProbeResult.unrecognised;
    }

    if (alacConfig != null) {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'ALAC',
        codecType: Mp4AudioCodec.alac,
        isLossless: true,
        bitDepth: alacConfig.bitDepth,
        sampleRate: alacConfig.sampleRate,
        channels: alacConfig.channels,
        bitrateKbps: alacConfig.bitrateKbps,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (embeddedCodec == 'FLAC' || lowerFourcc == 'flac') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'FLAC',
        codecType: Mp4AudioCodec.flac,
        isLossless: true,
        bitDepth: sampleSize > 0 ? sampleSize : null,
        sampleRate: sampleRate,
        channels: channels > 0 ? channels : 2,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (embeddedCodec == 'OPUS' || lowerFourcc == 'opus') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'OPUS',
        codecType: Mp4AudioCodec.opus,
        isLossless: false,
        bitDepth: null,
        sampleRate: 48000,
        channels: channels > 0 ? channels : 2,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (lowerFourcc == 'alac') {
      // Direct alac fourcc without a valid parsed child config: validate sampleSize
      if (sampleSize == 16 ||
          sampleSize == 20 ||
          sampleSize == 24 ||
          sampleSize == 32) {
        return Mp4AudioProbeResult(
          hasAudioTrack: true,
          codec: 'ALAC',
          codecType: Mp4AudioCodec.alac,
          isLossless: true,
          bitDepth: sampleSize,
          sampleRate: sampleRate,
          channels: channels > 0 ? channels : 2,
          fourcc: formatFourcc,
          majorBrand: majorBrand,
          compatibleBrands: compatibleBrands,
        );
      }
      // Corrupt/invalid ALAC config
      return Mp4AudioProbeResult.unrecognised;
    }

    if (lowerFourcc == 'mp4a' || embeddedCodec == 'AAC') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'AAC',
        codecType: Mp4AudioCodec.aac,
        isLossless: false,
        bitDepth: null, // Lossy perceptual audio
        sampleRate: sampleRate,
        channels: channels > 0 ? channels : 2,
        bitrateKbps: null,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (lowerFourcc == 'opus') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'OPUS',
        codecType: Mp4AudioCodec.opus,
        isLossless: false,
        bitDepth: null,
        sampleRate: 48000,
        channels: channels > 0 ? channels : 2,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (lowerFourcc == 'ac-3') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'AC3',
        codecType: Mp4AudioCodec.ac3,
        isLossless: false,
        sampleRate: sampleRate,
        channels: channels,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (lowerFourcc == 'ec-3') {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'EAC3',
        codecType: Mp4AudioCodec.eac3,
        isLossless: false,
        sampleRate: sampleRate,
        channels: channels,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    if (lowerFourcc.startsWith('dts')) {
      return Mp4AudioProbeResult(
        hasAudioTrack: true,
        codec: 'DTS',
        codecType: Mp4AudioCodec.dts,
        isLossless: false,
        sampleRate: sampleRate,
        channels: channels,
        fourcc: formatFourcc,
        majorBrand: majorBrand,
        compatibleBrands: compatibleBrands,
      );
    }

    return Mp4AudioProbeResult(
      hasAudioTrack: true,
      codec: formatFourcc.trim().toUpperCase(),
      codecType: Mp4AudioCodec.other,
      isLossless: false,
      sampleRate: sampleRate,
      channels: channels,
      fourcc: formatFourcc,
      majorBrand: majorBrand,
      compatibleBrands: compatibleBrands,
    );
  }

  static int _readUint32(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int _readUint16(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) return 0;
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int _readUint64(Uint8List bytes, int offset) {
    if (offset + 8 > bytes.length) return 0;
    final b = ByteData.sublistView(bytes, offset, offset + 8);
    return b.getUint64(0);
  }

  static ({int bitDepth, int sampleRate, int channels, int? bitrateKbps})?
      _parseAlacBox(
    Uint8List entryBytes,
    int boxPayloadStart,
    int boxEnd,
  ) {
    final payloadLength = boxEnd - boxPayloadStart;
    int configStart = boxPayloadStart;
    if (payloadLength >= 28) {
      configStart += 4; // skip version & flags
    }
    if (configStart + 24 > boxEnd || configStart + 24 > entryBytes.length) {
      return null;
    }

    // ALACSpecificConfig (24 bytes):
    // 0..3: frameLength (uint32)
    // 4: compatibleVersion (uint8)
    // 5: bitDepth (uint8: 16, 20, 24, 32)
    // 6: pb (uint8)
    // 7: mb (uint8)
    // 8: kb (uint8)
    // 9: numChannels (uint8)
    // 10..11: maxRun (uint16)
    // 12..15: maxFrameBytes (uint32)
    // 16..19: avgBitRate (uint32, in bps)
    // 20..23: sampleRate (uint32, in Hz)
    final bitDepth = entryBytes[configStart + 5];
    final channels = entryBytes[configStart + 9];
    final avgBitrateBps = _readUint32(entryBytes, configStart + 16);
    final rate = _readUint32(entryBytes, configStart + 20);

    // Validate per §8.3:
    // bit depth 16/20/24/32
    if (bitDepth != 16 && bitDepth != 20 && bitDepth != 24 && bitDepth != 32) {
      return null;
    }
    // sane channels: 1..8
    if (channels < 1 || channels > 8) {
      return null;
    }
    // sane sample rate: 8000..768000
    if (rate < 8000 || rate > 768000) {
      return null;
    }

    final bitrateKbps =
        avgBitrateBps > 0 ? (avgBitrateBps / 1000).round() : null;
    return (
      bitDepth: bitDepth,
      sampleRate: rate,
      channels: channels,
      bitrateKbps: bitrateKbps,
    );
  }

  static String _asciiString(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) return '';
    return ascii.decode(bytes.sublist(offset, offset + length),
        allowInvalid: true);
  }
}

// ---------------------------------------------------------------------------
// Low-level Byte Readers (RandomAccessFile vs Uint8List in-memory)
// ---------------------------------------------------------------------------

abstract interface class _AsyncByteReader {
  Future<int> length();
  Future<(int size, String type, int headerSize)> readBoxHeader(int offset);
  Future<Uint8List> readBytes(int offset, int count);
}

abstract interface class _SyncByteReader {
  int length();
  (int size, String type, int headerSize) readBoxHeader(int offset);
  Uint8List readBytes(int offset, int count);
}

final class _RafByteReader implements _AsyncByteReader {
  _RafByteReader(this._raf);
  final RandomAccessFile _raf;

  @override
  Future<int> length() => _raf.length();

  @override
  Future<(int size, String type, int headerSize)> readBoxHeader(
      int offset) async {
    await _raf.setPosition(offset);
    final header = await _raf.read(8);
    if (header.length < 8) return (0, '', 8);

    int size =
        (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
    final type = ascii.decode(header.sublist(4, 8), allowInvalid: true);
    int headerSize = 8;

    if (size == 1) {
      // 64-bit extended size
      final extHeader = await _raf.read(8);
      if (extHeader.length == 8) {
        final b = ByteData.sublistView(extHeader);
        size = b.getUint64(0);
        headerSize = 16;
      }
    } else if (size == 0) {
      final total = await _raf.length();
      size = total - offset;
    }

    return (size, type, headerSize);
  }

  @override
  Future<Uint8List> readBytes(int offset, int count) async {
    await _raf.setPosition(offset);
    return _raf.read(count);
  }
}

final class _MemoryByteReader implements _SyncByteReader {
  _MemoryByteReader(this._bytes);
  final Uint8List _bytes;

  @override
  int length() => _bytes.length;

  @override
  (int size, String type, int headerSize) readBoxHeader(int offset) {
    if (offset + 8 > _bytes.length) return (0, '', 8);

    int size = (_bytes[offset] << 24) |
        (_bytes[offset + 1] << 16) |
        (_bytes[offset + 2] << 8) |
        _bytes[offset + 3];
    final type = ascii.decode(_bytes.sublist(offset + 4, offset + 8),
        allowInvalid: true);
    int headerSize = 8;

    if (size == 1) {
      if (offset + 16 <= _bytes.length) {
        final b = ByteData.sublistView(_bytes, offset + 8, offset + 16);
        size = b.getUint64(0);
        headerSize = 16;
      }
    } else if (size == 0) {
      size = _bytes.length - offset;
    }

    return (size, type, headerSize);
  }

  @override
  Uint8List readBytes(int offset, int count) {
    final end =
        (offset + count <= _bytes.length) ? offset + count : _bytes.length;
    if (offset >= _bytes.length) return Uint8List(0);
    return _bytes.sublist(offset, end);
  }
}
