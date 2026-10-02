// lib/domain/interfaces/lyrics_provider_interface.dart
// FIX-A2: Dependency inversion interface for lyrics providers
import '../models/lyrics_line.dart';

/// Contract for fetching synchronized or plain lyrics from remote sources.
///
/// Failure semantics:
/// - `null` means "not found" — the provider had no match. It is a normal,
///   non-exceptional outcome and callers should fall through to another
///   provider without surfacing an error.
/// - Implementations must not throw for a network timeout or a malformed
///   response either; those should be logged and mapped to `null` so one bad
///   provider cannot abort a multi-source lookup. A caller that needs to
///   distinguish transport failure from genuine absence should wrap the call
///   with its own timeout/health tracking.
abstract class ILyricsProvider {
  /// Fetches lyrics matching [trackName], [artistName], and optional metadata.
  ///
  /// Returns `null` when no lyrics are found.
  Future<LyricsResult?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  });
}
