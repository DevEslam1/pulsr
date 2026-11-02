// lib/features/library/presentation/library_quality_utils.dart
import '../../../data/db/app_database.dart';

/// Codecs that always carry lossless PCM (or DSD) audio, mirroring the
/// smart-playlist engine's lossless rule.
const Set<String> _losslessCodecs = {
  'FLAC',
  'ALAC',
  'WAV',
  'AIFF',
  'PCM',
  'DSF',
  'DFF',
};

const List<String> _losslessExtensions = [
  '.flac',
  '.wav',
  '.alac',
  '.aiff',
  '.dsf',
  '.dff',
];

/// Single source of truth for "is this track lossless?" inside the Library
/// feature. Codec is checked case-insensitively; a missing codec falls back to
/// the path extension, and >= 24-bit depth counts even when metadata is thin.
bool isLosslessSong(SongsTableData song) {
  final codec = song.codec?.trim().toUpperCase();
  if (codec != null && codec.isNotEmpty && _losslessCodecs.contains(codec)) {
    return true;
  }
  final bitDepth = song.bitDepth;
  if (bitDepth != null && bitDepth >= 24) return true;
  final path = song.path.toLowerCase();
  for (final ext in _losslessExtensions) {
    if (path.endsWith(ext)) return true;
  }
  return false;
}

/// Returns true when the track meets Hi-Res audio criteria (>= 24-bit or > 48kHz).
bool isHiResSong(SongsTableData song) {
  if (!isLosslessSong(song)) return false;
  final bitDepth = song.bitDepth ?? 0;
  final sampleRate = song.sampleRate ?? 0;
  return bitDepth >= 24 || sampleRate > 48000;
}

/// Short badge label for track quality comparisons (e.g. "HI-RES", "LOSSLESS", "320K").
String? songQualityBadge(SongsTableData song) {
  if (isHiResSong(song)) return 'HI-RES';
  if (isLosslessSong(song)) return 'LOSSLESS';
  final bitrate = song.bitrateKbps;
  if (bitrate != null && bitrate > 0) return '${bitrate}K';
  return null;
}

/// Compact technical summary for duplicate comparison and stats rows.
String formatSongTechSpecs(SongsTableData song) {
  final parts = <String>[];

  final rawCodec = song.codec?.trim().toUpperCase();
  if (rawCodec != null && rawCodec.isNotEmpty) {
    parts.add(rawCodec);
  } else {
    final dotIdx = song.path.lastIndexOf('.');
    if (dotIdx != -1 && dotIdx < song.path.length - 1) {
      parts.add(song.path.substring(dotIdx + 1).toUpperCase());
    }
  }

  if (song.sampleRate != null && song.sampleRate! > 0) {
    final khz = (song.sampleRate! / 1000).toStringAsFixed(
      song.sampleRate! % 1000 == 0 ? 0 : 1,
    );
    final depth =
        song.bitDepth != null && song.bitDepth! > 0 ? '${song.bitDepth}-bit/' : '';
    parts.add('$depth${khz}kHz');
  } else if (song.bitrateKbps != null && song.bitrateKbps! > 0) {
    parts.add('${song.bitrateKbps} kbps');
  }

  if (song.fileSize != null && song.fileSize! > 0) {
    final mb = (song.fileSize! / (1024 * 1024)).toStringAsFixed(1);
    parts.add('$mb MB');
  }

  return parts.join(' • ');
}