// lib/domain/services/headphone_device_matcher.dart
//
// Pure, side-effect-free matcher that maps a connected output device's name
// (Android `AudioDeviceInfo.productName`, e.g. "WH-1000XM5" or
// "Sony WH-1000XM5") to a bundled AutoEQ [HeadphoneProfile].
//
// Design goals:
//   * Never guess when the result is ambiguous — two profiles with a near-equal
//     score (e.g. WH-1000XM5 vs WF-1000XM5 for the friendly name "Sony XM5")
//     return null so we do not apply the wrong correction.
//   * Be resilient to how Android reports the same headset ("WH-1000XM5",
//     "LE_WH-1000XM5", "Sony WH-1000XM5", "WH-1000XM5 (Bluetooth)").
//
// No I/O, no platform calls: the caller owns loading profiles and persisting
// the chosen link.
import '../models/headphone_profile.dart';

/// The winning device -> profile association.
class HeadphoneDeviceMatch {
  final HeadphoneProfile profile;

  /// 0.0–1.0 confidence. Exact model containment scores 1.0.
  final double score;

  /// Machine-readable reason (safe to log/persist).
  final String reason;

  const HeadphoneDeviceMatch({
    required this.profile,
    required this.score,
    required this.reason,
  });

  @override
  String toString() =>
      'HeadphoneDeviceMatch(${profile.id}, ${score.toStringAsFixed(2)}, $reason)';
}

class HeadphoneDeviceMatcher {
  /// Minimum confidence before a single candidate is accepted.
  static const double defaultMinScore = 0.62;

  /// If the top two candidates are within this margin (and the winner is not
  /// near-certain), the match is treated as ambiguous and rejected.
  static const double _ambiguityMargin = 0.06;

  /// Scores at/above this are considered certain enough to ignore ambiguity.
  static const double _certainScore = 0.96;

  /// Transport / generic words that carry no model identity and must not count
  /// toward a match.
  static const Set<String> _genericTokens = {
    'bluetooth', 'wireless', 'headphone', 'headphones', 'headset', 'earbud',
    'earbuds', 'earphone', 'earphones', 'audio', 'stereo', 'hands', 'free',
    'handsfree', 'tws', 'in', 'on', 'over', 'ear', 'buds', 'bud', 'le',
    'leaudio', 'a2dp', 'aac', 'sbc', 'ldac', 'aptx', 'device', 'output',
    'dac', 'usb', 'hifi', 'hires', 'hi', 'res', 'the', 'for', 'and', 'by',
    'with', 'phone', 'mobile', 'default', 'built', 'builtin', 'speaker',
    'mono', 'sound', 'card', 'target', 'curve',
  };

  /// Returns the best AutoEQ profile for [deviceName], or null when nothing
  /// crosses [minScore] or the result is ambiguous.
  static HeadphoneDeviceMatch? match({
    required String deviceName,
    required List<HeadphoneProfile> profiles,
    double minScore = defaultMinScore,
  }) {
    final deviceNorm = _normalize(deviceName);
    if (deviceNorm.isEmpty || profiles.isEmpty) return null;
    final deviceTokens = _significantTokens(deviceNorm);
    if (deviceTokens.isEmpty) return null;

    final scored = <HeadphoneDeviceMatch>[];
    for (final profile in profiles) {
      final result = _score(deviceNorm, deviceTokens, profile);
      if (result != null) scored.add(result);
    }
    if (scored.isEmpty) return null;

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.profile.id.compareTo(b.profile.id);
    });

    final best = scored.first;
    if (best.score < minScore) return null;
    if (scored.length > 1 &&
        best.score < _certainScore &&
        (best.score - scored[1].score) < _ambiguityMargin) {
      return null; // e.g. "Sony XM5" is as close to WH- as to WF-1000XM5.
    }
    return best;
  }

  static HeadphoneDeviceMatch? _score(
    String deviceNorm,
    List<String> deviceTokens,
    HeadphoneProfile profile,
  ) {
    final brandNorm = _normalize(profile.brand);
    final modelNorm = _normalize(profile.model);
    final nameNorm = _normalize(profile.name);

    final brandTokens = _significantTokens(brandNorm);
    final modelTokens = _significantTokens(modelNorm);
    var profileTokens = <String>{...brandTokens, ...modelTokens};
    if (profileTokens.isEmpty) {
      // Fall back to the display name for profiles whose model is a
      // descriptive string (e.g. "Target Curve (In-Ear)").
      profileTokens = _significantTokens(nameNorm).toSet();
    }
    if (profileTokens.isEmpty) return null;

    // Decisive: the device name literally contains the profile's model.
    if (modelNorm.isNotEmpty) {
      final modelCompact = modelNorm.replaceAll(' ', '');
      final deviceCompact = deviceNorm.replaceAll(' ', '');
      if (modelCompact.length >= 3 && deviceCompact.contains(modelCompact)) {
        return HeadphoneDeviceMatch(
          profile: profile,
          score: 1.0,
          reason: 'exact-model',
        );
      }
    }

    var matchedModelTokens = 0;
    for (final mt in modelTokens) {
      if (deviceTokens.any((d) => _tokenMatch(d, mt))) matchedModelTokens++;
    }
    var matchedDeviceTokens = 0;
    for (final dt in deviceTokens) {
      if (profileTokens.any((pt) => _tokenMatch(dt, pt))) matchedDeviceTokens++;
    }
    if (matchedDeviceTokens == 0) return null;

    final modelRatio =
        modelTokens.isEmpty ? 0.0 : matchedModelTokens / modelTokens.length;
    final deviceRatio = matchedDeviceTokens / deviceTokens.length;
    final brandHit =
        brandTokens.any((bt) => deviceTokens.any((d) => _tokenMatch(d, bt)));

    var score = 0.7 * modelRatio + 0.3 * deviceRatio;
    if (brandHit) score += 0.15;

    // Require at least one substantive token (>= 3 chars) to avoid matches
    // driven purely by two-letter noise like "wh".
    final hasSubstantive = deviceTokens.any((d) =>
        d.length >= 3 &&
        profileTokens.any((pt) => _tokenMatch(d, pt)));
    if (!hasSubstantive) return null;

    final clamped = score.clamp(0.0, 1.0).toDouble();
    if (clamped < 0.35) return null;
    return HeadphoneDeviceMatch(
      profile: profile,
      score: clamped,
      reason: 'token-overlap',
    );
  }

  static bool _tokenMatch(String a, String b) {
    if (a == b) return true;
    final shortest = a.length < b.length ? a.length : b.length;
    if (shortest < 3) return false;
    return a.contains(b) || b.contains(a);
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _significantTokens(String normalized) {
    if (normalized.isEmpty) return const [];
    return normalized
        .split(' ')
        .where((t) => t.isNotEmpty && !_genericTokens.contains(t))
        .toList(growable: false);
  }
}
