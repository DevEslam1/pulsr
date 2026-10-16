/// Personal adjustments to a reciter style. These are intentionally separate
/// from normal playback preferences: Quran learning speed must never leak into
/// music playback or per-track playback memory.
class QuranStyleTuning {
  final double? ambience;
  final double? warmth;
  final double? playbackSpeed;

  const QuranStyleTuning({this.ambience, this.warmth, this.playbackSpeed});

  bool get isEmpty =>
      ambience == null && warmth == null && playbackSpeed == null;

  QuranStyleTuning copyWith({
    double? ambience,
    double? warmth,
    double? playbackSpeed,
  }) =>
      QuranStyleTuning(
        ambience: ambience ?? this.ambience,
        warmth: warmth ?? this.warmth,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      );

  Map<String, double> toJson() => {
        if (ambience != null) 'ambience': ambience!,
        if (warmth != null) 'warmth': warmth!,
        if (playbackSpeed != null) 'playbackSpeed': playbackSpeed!,
      };

  factory QuranStyleTuning.fromJson(Map<String, dynamic> json) {
    double? read(String key, double min, double max) {
      final value = (json[key] as num?)?.toDouble();
      return value != null && value.isFinite
          ? value.clamp(min, max).toDouble()
          : null;
    }

    return QuranStyleTuning(
      ambience: read('ambience', 0, 0.6),
      warmth: read('warmth', 0, 0.6),
      playbackSpeed: read('playbackSpeed', 0.5, 2.0),
    );
  }
}
