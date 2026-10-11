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
