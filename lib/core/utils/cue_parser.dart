// lib/core/utils/cue_parser.dart
import 'dart:convert';
import 'dart:io';
import '../../domain/models/chapter_info.dart';
import 'error_logger.dart';

class CueParser {
  /// Parses standard CUE sheet text content into a sorted list of ChapterInfo,
  /// supporting both single-file album sheets and multi-file split-track sheets.
  static List<ChapterInfo> parse(String cueContent) {
    final lines = cueContent.split(RegExp(r'\r?\n'));
    final List<ChapterInfo> chapters = [];

    int currentTrackIndex = 0;
    String currentTitle = '';
    String? currentFileName;
    Duration? currentStart;

    final fileRegex =
        RegExp(r'^\s*FILE\s+"?([^"]+?)"?\s+([A-Z0-9]+)', caseSensitive: false);
    final trackRegex =
        RegExp(r'^\s*TRACK\s+(\d+)\s+AUDIO', caseSensitive: false);
    final titleRegex = RegExp(r'^\s*TITLE\s+"?([^"]+)"?', caseSensitive: false);
    final indexRegex = RegExp(r'^\s*INDEX\s+01\s+(\d{2}):(\d{2}):(\d{2})',
        caseSensitive: false);

    void savePrevious() {
      if (currentTrackIndex > 0 && currentStart != null) {
        final title = currentTitle.isNotEmpty
            ? currentTitle
            : 'Chapter $currentTrackIndex';
        chapters.add(ChapterInfo(
          index: currentTrackIndex,
          title: title,
          start: currentStart,
          fileName: currentFileName,
        ));
      }
    }

    for (final line in lines) {
      final fileMatch = fileRegex.firstMatch(line);
      if (fileMatch != null) {
        savePrevious();
        currentTrackIndex = 0;
        currentTitle = '';
        currentStart = null;
        currentFileName = fileMatch.group(1)?.trim();
        continue;
      }

      final trackMatch = trackRegex.firstMatch(line);
      if (trackMatch != null) {
        savePrevious();
        currentTrackIndex =
            int.tryParse(trackMatch.group(1) ?? '1') ?? (chapters.length + 1);
        currentTitle = '';
        currentStart = null;
        continue;
      }

      final titleMatch = titleRegex.firstMatch(line);
      if (titleMatch != null && currentTrackIndex > 0) {
        currentTitle = titleMatch.group(1)?.trim() ?? '';
        continue;
      }

      final indexMatch = indexRegex.firstMatch(line);
      if (indexMatch != null && currentTrackIndex > 0) {
        final minutes = int.tryParse(indexMatch.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(indexMatch.group(2) ?? '0') ?? 0;
        final frames = int.tryParse(indexMatch.group(3) ?? '0') ?? 0;
        final ms = ((frames / 75.0) * 1000.0).round();
        currentStart =
            Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
      }
    }

    savePrevious();

    // Calculate end durations
    final List<ChapterInfo> resolved = [];
    for (int i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      // Only set end duration if next track is in the same source file
      final Duration? end =
          (i + 1 < chapters.length && chapters[i + 1].fileName == c.fileName)
              ? chapters[i + 1].start
              : null;
      resolved.add(ChapterInfo(
        index: c.index,
        title: c.title,
        start: c.start,
        end: end,
        fileName: c.fileName,
      ));
    }

    return resolved;
  }

  /// Searches for and parses sibling .cue file matching audioFilePath.
  /// Falls back to embedded CUE sheet if no sibling .cue file exists.
  static Future<List<ChapterInfo>> findAndParseCue(String audioFilePath) async {
    try {
      final lastDot = audioFilePath.lastIndexOf('.');
      if (lastDot != -1) {
        final cuePath = '${audioFilePath.substring(0, lastDot)}.cue';
        final file = File(cuePath);
        if (await file.exists()) {
          final content = await file.readAsString();
          return parse(content);
        }
      }

      // Check for embedded CUE sheet if no external file exists
      final embeddedContent = await extractEmbeddedCueSheet(audioFilePath);
      if (embeddedContent != null && embeddedContent.isNotEmpty) {
        return parse(embeddedContent);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read external/embedded cue for $audioFilePath',
          error: e, stackTrace: st, category: 'CueParser');
    }
    return const [];
  }

  /// Extracts embedded CUE sheet from audio file metadata (FLAC Vorbis comment / cuesheet block, or WAV chunks).
  static Future<String?> extractEmbeddedCueSheet(String audioFilePath) async {
    try {
      final file = File(audioFilePath);
      if (!await file.exists()) return null;
      final ext = audioFilePath.split('.').last.toLowerCase();
      if (ext == 'flac') {
        return await _extractFlacEmbeddedCue(file);
      } else if (ext == 'wav') {
        return await _extractWavEmbeddedCue(file);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to extract embedded cue sheet for $audioFilePath',
          error: e, stackTrace: st, category: 'CueParser');
    }
    return null;
  }

  static Future<String?> _extractFlacEmbeddedCue(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(4);
      if (header.length < 4 ||
          header[0] != 0x66 ||
          header[1] != 0x4C ||
          header[2] != 0x61 ||
          header[3] != 0x43) {
        return null;
      }

      bool isLast = false;
      while (!isLast) {
        final blockHeader = await raf.read(4);
        if (blockHeader.length < 4) break;
        isLast = (blockHeader[0] & 0x80) != 0;
        final blockType = blockHeader[0] & 0x7F;
        final length =
            (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];

        if (blockType == 4) {
          // VORBIS_COMMENT block
          final blockData = await raf.read(length);
          if (blockData.length == length) {
            final cue = _findCueInVorbisComment(blockData);
            if (cue != null) return cue;
          }
        } else if (blockType == 5) {
          // CUESHEET block
          final blockData = await raf.read(length);
          if (blockData.length == length) {
            final cue = _parseFlacCuesheetBlock(blockData);
            if (cue != null) return cue;
          }
        } else {
          final pos = await raf.position();
          await raf.setPosition(pos + length);
        }
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  static String? _findCueInVorbisComment(List<int> bytes) {
    try {
      if (bytes.length < 8) return null;
      var offset = 0;
      final vendorLength = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4 + vendorLength;
      if (offset + 4 > bytes.length) return null;

      final userCommentListLength = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4;

      for (int i = 0; i < userCommentListLength; i++) {
        if (offset + 4 > bytes.length) break;
        final length = bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24);
        offset += 4;
        if (offset + length > bytes.length) break;

        final commentStr = utf8.decode(bytes.sublist(offset, offset + length),
            allowMalformed: true);
        offset += length;

        final eqIdx = commentStr.indexOf('=');
        if (eqIdx != -1) {
          final key = commentStr.substring(0, eqIdx).toUpperCase();
          if (key == 'CUESHEET' || key == 'CUE_SHEET') {
            return commentStr.substring(eqIdx + 1);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _parseFlacCuesheetBlock(List<int> bytes) {
    try {
      if (bytes.length < 396) return null;
      final numTracks = bytes[395];
      var offset = 396;
      final sb = StringBuffer();

      for (int t = 0; t < numTracks; t++) {
        if (offset + 36 > bytes.length) break;
        var trackOffsetSamples = 0;
        for (int i = 0; i < 8; i++) {
          trackOffsetSamples = (trackOffsetSamples << 8) | bytes[offset + i];
        }
        final trackNum = bytes[offset + 8];
        final numIndexPoints = bytes[offset + 35];
        offset += 36;

        // Skip lead-out track (170 or 0xAA)
        if (trackNum == 170 || trackNum == 0xAA) {
          offset += numIndexPoints * 12;
          continue;
        }

        sb.writeln('  TRACK ${trackNum.toString().padLeft(2, '0')} AUDIO');
        for (int p = 0; p < numIndexPoints; p++) {
          if (offset + 12 > bytes.length) break;
          var pointOffsetSamples = 0;
          for (int i = 0; i < 8; i++) {
            pointOffsetSamples = (pointOffsetSamples << 8) | bytes[offset + i];
          }
          final pointNum = bytes[offset + 8];
          offset += 12;

          final totalSamples = trackOffsetSamples + pointOffsetSamples;
          final totalFrames = (totalSamples / 588.0).round();
          final minutes = totalFrames ~/ (75 * 60);
          final seconds = (totalFrames % (75 * 60)) ~/ 75;
          final frames = totalFrames % 75;

          final mStr = minutes.toString().padLeft(2, '0');
          final sStr = seconds.toString().padLeft(2, '0');
          final fStr = frames.toString().padLeft(2, '0');
          sb.writeln(
              '    INDEX ${pointNum.toString().padLeft(2, '0')} $mStr:$sStr:$fStr');
        }
      }
      return sb.isNotEmpty ? sb.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _extractWavEmbeddedCue(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final riffHeader = await raf.read(12);
      if (riffHeader.length < 12) return null;
      final magic = ascii.decode(riffHeader.sublist(0, 4), allowInvalid: true);
      final wave = ascii.decode(riffHeader.sublist(8, 12), allowInvalid: true);
      if (magic != 'RIFF' || wave != 'WAVE') return null;

      final fileLength = await file.length();
      int sampleRate = 44100;

      while ((await raf.position()) + 8 <= fileLength) {
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) break;
        final chunkId =
            ascii.decode(chunkHeader.sublist(0, 4), allowInvalid: true);
        final chunkSize = chunkHeader[4] |
            (chunkHeader[5] << 8) |
            (chunkHeader[6] << 16) |
            (chunkHeader[7] << 24);

        if (chunkId == 'fmt ' && chunkSize >= 16) {
          final fmtData = await raf.read(16);
          if (fmtData.length >= 8) {
            sampleRate = fmtData[4] |
                (fmtData[5] << 8) |
                (fmtData[6] << 16) |
                (fmtData[7] << 24);
          }
          if (chunkSize > 16) {
            final cur = await raf.position();
            await raf.setPosition(cur + (chunkSize - 16));
          }
        } else if (chunkId == 'cue ' && chunkSize >= 4) {
          final cueData = await raf.read(chunkSize);
          if (cueData.length == chunkSize) {
            final cue = _parseWavCueChunk(cueData, sampleRate);
            if (cue != null) return cue;
          }
        } else {
          final cur = await raf.position();
          await raf.setPosition(cur + chunkSize);
        }
        if (chunkSize.isOdd) {
          await raf.read(1);
        }
      }
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
    return null;
  }

  static String? _parseWavCueChunk(List<int> bytes, int sampleRate) {
    try {
      if (bytes.length < 4) return null;
      final numPoints =
          bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
      if (numPoints <= 0) return null;
      var offset = 4;
      final sb = StringBuffer();

      for (int i = 0; i < numPoints; i++) {
        if (offset + 24 > bytes.length) break;
        // sample offset is at offset + 20
        final sampleOffset = bytes[offset + 20] |
            (bytes[offset + 21] << 8) |
            (bytes[offset + 22] << 16) |
            (bytes[offset + 23] << 24);
        offset += 24;

        final trackNum = i + 1;
        final totalFrames = ((sampleOffset / sampleRate) * 75.0).round();
        final minutes = totalFrames ~/ (75 * 60);
        final seconds = (totalFrames % (75 * 60)) ~/ 75;
        final frames = totalFrames % 75;

        final mStr = minutes.toString().padLeft(2, '0');
        final sStr = seconds.toString().padLeft(2, '0');
        final fStr = frames.toString().padLeft(2, '0');

        sb.writeln('  TRACK ${trackNum.toString().padLeft(2, '0')} AUDIO');
        sb.writeln('    INDEX 01 $mStr:$sStr:$fStr');
      }
      return sb.isNotEmpty ? sb.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
