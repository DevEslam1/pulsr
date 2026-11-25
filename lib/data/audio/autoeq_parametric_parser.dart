// lib/data/audio/autoeq_parametric_parser.dart
//
// AutoEQ ships two profile shapes per headphone: a five-band GraphicEQ curve
// (already imported by HeadphoneProfilesRepository) and a full parametric
// "ParametricEQ.txt" — ten filters in the common case, sometimes more —
// carrying real filter types, Q values and a preamp. The parametric file
// reproduces the measured correction far more closely than a five-band
// approximation, so it is parsed here into a typed model and mapped onto the
// app's existing preset models.
//
// Grammar handled (the EqualizerAPO subset AutoEQ emits; case-insensitive):
//
//   Preamp: -6.2 dB
//   Filter 1: ON PK  Fc 105 Hz  Gain 5.5 dB Q 0.70
//   Filter 2: ON LSC Fc 105 Hz  Gain 5.5 dB Q 0.70
//   Filter 3: ON HP  Fc 20 Hz   Q 0.707
//   Filter 4: OFF PK Fc 1000 Hz Gain 0.0 dB Q 1.0
//   Filter 5: ON BP  Fc 1.2 kHz BW Oct 1.0
//
// Behaviour contract:
//  * Malformed, unknown or unsupported lines are skipped with a warning;
//    parsing never aborts on an individual bad line.
//  * [AutoEqParametricParser.parse] returns null when the input carries no
//    payload at all (empty / blank / comment-only). It throws
//    [AutoEqParametricParseFailure] when the input has content but nothing
//    recognisable. An import UI can catch that failure and show its message.
//  * Values are clamped to [DspParamRanges] (the native contract) and every
//    clamp is reported as a warning instead of silently changing the curve.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../core/errors/failures.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/headphone_profile.dart';
import 'dsp_param_ranges.dart';

/// Filter shapes an AutoEQ parametric profile can request, mapped onto the
/// native `FilterType` ordinals declared in
/// `android/app/src/main/cpp/DspParams.h`.
enum EqFilterKind {
  peaking(0, 'PK', 'peaking'),
  lowShelf(1, 'LSC', 'low shelf'),
  highShelf(2, 'HSC', 'high shelf'),
  lowPass(3, 'LP', 'low pass'),
  highPass(4, 'HP', 'high pass'),
  notch(5, 'NO', 'notch'),
  bandPass(6, 'BP', 'band pass'),
  allPass(7, 'AP', 'all pass');

  const EqFilterKind(this.nativeIndex, this.typeCode, this.label);

  /// Ordinal accepted by `EqFilterType` / the native `FilterType` enum.
  final int nativeIndex;

  /// AutoEQ / EqualizerAPO type token used in the file and in warnings.
  final String typeCode;

  /// Human-readable name for warning messages.
  final String label;

  /// Whether the shape is a gain curve (peaking or shelf). Pass, notch and
  /// all-pass filters shape magnitude without carrying a gain, so a
  /// gain-per-band preset cannot express them.
  bool get isGainBearing =>
      this == EqFilterKind.peaking ||
      this == EqFilterKind.lowShelf ||
      this == EqFilterKind.highShelf;
}

/// One parsed `Filter N:` line, in file order.
class AutoEqBand {
  const AutoEqBand({
    required this.filterIndex,
    required this.enabled,
    required this.kind,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
  });

  /// The `N` from `Filter N:`, as written in the file (1-based in AutoEQ).
  final int filterIndex;
  final bool enabled;
  final EqFilterKind kind;
  final double frequencyHz;
  final double gainDb;
  final double q;

  /// Convenience for building an [EqFilter] on the native path.
  int get filterType => kind.nativeIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoEqBand &&
          filterIndex == other.filterIndex &&
          enabled == other.enabled &&
          kind == other.kind &&
          frequencyHz == other.frequencyHz &&
          gainDb == other.gainDb &&
          q == other.q;

  @override
  int get hashCode =>
      Object.hash(filterIndex, enabled, kind, frequencyHz, gainDb, q);

  @override
  String toString() => 'AutoEqBand(Filter $filterIndex, '
      '${enabled ? 'ON' : 'OFF'} ${kind.typeCode}, '
      '${frequencyHz.toStringAsFixed(2)} Hz, '
      '${gainDb.toStringAsFixed(2)} dB, Q ${q.toStringAsFixed(3)})';
}

/// A parsed AutoEQ `ParametricEQ.txt` profile.
///
/// [warnings] collects every parse clamp, skipped line and mapping limitation.
/// [AutoEqParametricParser.toPreset] appends its own mapping warnings to the
/// same list (deduplicated) because its required signature returns only the
/// preset; read [warnings] after mapping to surface them together.
class AutoEqParametricProfile {
  AutoEqParametricProfile({
    required this.name,
    required this.preampDb,
    required this.bands,
    List<String> warnings = const <String>[],
  }) : _warnings = List<String>.of(warnings);

  final String name;

  /// `Preamp:` value in dB, clamped to [DspParamRanges.preampDb].
  final double preampDb;

  /// Every `Filter N:` line, in file order (disabled filters included).
  final List<AutoEqBand> bands;

  final List<String> _warnings;

  /// Unmodifiable view of the warnings raised while parsing and mapping.
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  /// Bands that are enabled, in file order.
  List<AutoEqBand> get enabledBands => [
        for (final band in bands)
          if (band.enabled) band
      ];

  void _addWarning(String warning) {
    if (!_warnings.contains(warning)) _warnings.add(warning);
  }

  /// Value equality over [name], [preampDb] and [bands] (order-sensitive).
  /// [warnings] are diagnostics, not identity, and are excluded.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AutoEqParametricProfile ||
        name != other.name ||
        preampDb != other.preampDb ||
        bands.length != other.bands.length) {
      return false;
    }
    for (var i = 0; i < bands.length; i++) {
      if (bands[i] != other.bands[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, preampDb, Object.hashAll(bands));

  @override
  String toString() =>
      'AutoEqParametricProfile($name, preamp ${preampDb.toStringAsFixed(2)} dB, '
      '${bands.length} bands, ${_warnings.length} warnings)';
}

/// Thrown when input carries content but no recognisable AutoEQ data.
///
/// Typed in the project's [AppFailure] style so import callers can branch on
/// it like any other domain failure instead of string-matching an exception.
class AutoEqParametricParseFailure extends AppFailure {
  const AutoEqParametricParseFailure(String message, [Object? cause])
      : super(message, 'AUTOEQ_PARAMETRIC_PARSE_FAILURE', cause);
}

/// Parser and mapper for AutoEQ `ParametricEQ.txt` files.
abstract final class AutoEqParametricParser {
  /// Native `EqParamSet::MAX_BANDS` / `ParametricEQ::MAX_BANDS`
  /// (`android/app/src/main/cpp/DspParams.h`). The native EQ drops anything
  /// past this, so mapping caps here and says so.
  static const int maxBands = 64;

  /// Fallback name when [parse] is called without one.
  static const String defaultProfileName = 'AutoEQ Parametric';

  /// Butterworth Q used when a line omits both `Q` and `BW`
  /// (matches [DspParamRanges.eqFilterQ.defaultValue]).
  static const double _defaultQ = 1.414;

  static final RegExp _preampPattern = RegExp(
    r'^preamp\s*:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)'
    r'\s*(?:db)?$',
    caseSensitive: false,
  );

  static final RegExp _filterPattern = RegExp(
    r'^filter\s+(\d+)\s*:\s*(?:(on|off)\s+)?([a-z]+)(.*)$',
    caseSensitive: false,
  );

  /// `Fc 105 Hz`, `Gain -6.2 dB`, `Q 0.7`, `BW Oct 1.0`, `BW 0.5 Oct`.
  static final RegExp _parameterPattern = RegExp(
    r'\b(fc|gain|q|bw)\s+(oct\s+)?'
    r'([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*'
    r'(khz|hz|db|oct)?',
    caseSensitive: false,
  );

  /// The optional slope token of the `LS 6dB` / `HS 12dB` shelf forms.
  static final RegExp _shelfSlopePattern =
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*db\b', caseSensitive: false);

  static final RegExp _lineBreakPattern = RegExp(r'\r\n|\r|\n');

  /// Parses [text] into a profile.
  ///
  /// Returns null when [text] holds no payload (empty, blank, or comment-only
  /// lines). Throws [AutoEqParametricParseFailure] when it holds content but
  /// no recognisable `Preamp:` / `Filter N:` line. Individual malformed lines
  /// are skipped with a warning and never abort the parse.
  static AutoEqParametricProfile? parse(
    String text, {
    String name = defaultProfileName,
  }) {
    final source = text.startsWith('\uFEFF') ? text.substring(1) : text;
    final rawLines = source.split(_lineBreakPattern);

    var hasContent = false;
    for (final raw in rawLines) {
      if (_stripComment(raw).trim().isNotEmpty) {
        hasContent = true;
        break;
      }
    }
    if (!hasContent) return null;

    final warnings = <String>[];
    final bands = <AutoEqBand>[];
    final seenIndexes = <int>{};
    double? preamp;
    var recognised = 0;

    for (var i = 0; i < rawLines.length; i++) {
      final lineNumber = i + 1;
      final line = _stripComment(rawLines[i]).trim();
      if (line.isEmpty) continue;

      final preampMatch = _preampPattern.firstMatch(line);
      if (preampMatch != null) {
        final raw = double.tryParse(preampMatch.group(1)!);
        if (raw == null || !raw.isFinite) {
          warnings.add('Line $lineNumber: unreadable "Preamp:" value — '
              'assuming ${_number(preamp ?? 0)} dB.');
          continue;
        }
        if (preamp != null) {
          warnings.add('Line $lineNumber: duplicate "Preamp:" line — '
              'the last value wins.');
        }
        final clampedPreamp = DspParamRanges.preampDb.clamp(raw);
        if (clampedPreamp != raw) {
          warnings.add('Line $lineNumber: preamp ${_number(raw)} dB is outside '
              'the native range ${_number(DspParamRanges.preampDb.min)}..'
              '${_number(DspParamRanges.preampDb.max)} dB — clamped to '
              '${_number(clampedPreamp)} dB.');
        }
        preamp = clampedPreamp;
        recognised++;
        continue;
      }

      final filterMatch = _filterPattern.firstMatch(line);
      if (filterMatch == null) {
        warnings.add('Line $lineNumber: unrecognised line "${_preview(line)}" '
            '— skipped.');
        continue;
      }

      final index = int.tryParse(filterMatch.group(1)!);
      final stateToken = filterMatch.group(2)?.toLowerCase();
      final typeToken = filterMatch.group(3)!.toLowerCase();
      final kind = _kindForCode(typeToken);
      if (index == null) {
        warnings.add('Line $lineNumber: unreadable filter index — skipped.');
        continue;
      }
      if (kind == null) {
        warnings.add('Line $lineNumber: unsupported filter type "$typeToken" '
            '— filter skipped.');
        continue;
      }

      final enabled = stateToken != 'off';
      if (stateToken == null) {
        warnings.add('Line $lineNumber: filter state is missing — treating the '
            'filter as ON.');
      }

      final tail = filterMatch.group(4) ?? '';
      var parameterTail = tail;
      if (kind == EqFilterKind.lowShelf || kind == EqFilterKind.highShelf) {
        final slope = _shelfSlopePattern.firstMatch(parameterTail);
        if (slope != null) {
          warnings.add('Line $lineNumber: shelf slope '
              '"${slope.group(1)} dB" is not modelled; the Q value is used to '
              'approximate the shelf.');
          parameterTail = parameterTail.substring(slope.end);
        }
      }

      final parameters = <String, _ParsedParameter>{};
      for (final match in _parameterPattern.allMatches(parameterTail)) {
        final value = double.tryParse(match.group(3)!);
        if (value == null) continue;
        final unit = (match.group(2) ?? match.group(4))?.trim().toLowerCase();
        parameters[match.group(1)!.toLowerCase()] =
            _ParsedParameter(value, unit);
      }

      final fc = parameters['fc'];
      if (fc == null) {
        warnings.add('Line $lineNumber: filter has no "Fc" frequency — '
            'skipped.');
        continue;
      }
      if (fc.unit != null && fc.unit != 'hz' && fc.unit != 'khz') {
        warnings.add('Line $lineNumber: "Fc" unit "${fc.unit}" is not a '
            'frequency — the value is interpreted as Hz.');
      }
      final frequency = fc.unit == 'khz' ? fc.value * 1000.0 : fc.value;

      final gain = parameters['gain']?.value ?? 0.0;
      final q = _resolveQ(parameters, lineNumber, warnings);

      final clampedFrequency =
          DspParamRanges.eqFilterFrequencyHz.clamp(frequency);
      if (clampedFrequency != frequency) {
        warnings.add('Line $lineNumber: frequency ${_number(frequency)} Hz is '
            'outside the native EQ range '
            '${_number(DspParamRanges.eqFilterFrequencyHz.min)}..'
            '${_number(DspParamRanges.eqFilterFrequencyHz.max)} Hz — clamped to '
            '${_number(clampedFrequency)} Hz.');
      }
      final clampedGain = DspParamRanges.eqFilterGainDb.clamp(gain);
      if (clampedGain != gain) {
        warnings.add('Line $lineNumber: gain ${_number(gain)} dB is outside '
            'the native filter range — clamped to ${_number(clampedGain)} dB.');
      }
      final clampedQ = DspParamRanges.eqFilterQ.clamp(q);
      if (clampedQ != q) {
        warnings.add('Line $lineNumber: Q ${_number(q)} is outside the native '
            'filter range — clamped to ${_number(clampedQ)}.');
      }

      if (!seenIndexes.add(index)) {
        warnings.add('Line $lineNumber: duplicate filter index $index — both '
            'filters are kept in file order.');
      }

      bands.add(AutoEqBand(
        filterIndex: index,
        enabled: enabled,
        kind: kind,
        frequencyHz: clampedFrequency,
        gainDb: clampedGain,
        q: clampedQ,
      ));
      recognised++;
    }

    if (recognised == 0) {
      throw AutoEqParametricParseFailure(
        'No AutoEQ parametric data found: the input has '
        '${rawLines.length} line(s) but none matched "Preamp: <x> dB" or '
        '"Filter <n>: ON|OFF <type> ...".',
      );
    }
    if (bands.isEmpty) {
      warnings.add('No "Filter <n>:" line found — the profile has no EQ '
          'bands.');
    }
    if (preamp == null) {
      warnings.add('No "Preamp:" line found — assuming 0 dB.');
    }

    return AutoEqParametricProfile(
      name: name,
      preampDb: preamp ?? 0.0,
      bands: bands,
      warnings: warnings,
    );
  }

  /// Reads [file] as UTF-8 (tolerating a byte-order mark, CRLF line endings
  /// and `#` / `//` comment lines) and parses it.
  ///
  /// The profile name defaults to the file stem with the `ParametricEQ`
  /// suffix removed (e.g. "Sennheiser HD 600 ParametricEQ.txt" becomes
  /// "Sennheiser HD 600"). File-system errors propagate unchanged; only
  /// unparseable *content* raises [AutoEqParametricParseFailure].
  static Future<AutoEqParametricProfile?> parseFile(
    File file, {
    String? name,
  }) async {
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return parse(text, name: name ?? profileNameFromPath(file.path));
  }

  /// Derives a display name from a profile path.
  static String profileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    var base = normalized.split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final stripped = base
        .replaceFirst(
            RegExp(r'[\s_\-]*parametric\s*eq\s*$', caseSensitive: false), '')
        .trim();
    final cleaned = stripped.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
    if (cleaned.isNotEmpty) return cleaned;
    return base.trim().isEmpty ? defaultProfileName : base.trim();
  }

  /// Maps a profile onto [EqPreset] for the graphic-EQ path.
  ///
  /// Enabled filters are projected in file order, capped at [maxBands], and
  /// each gain keeps its own centre frequency and Q in
  /// [EqPreset.customFrequencies] / [EqPreset.qFactors]. [EqPreset] has no
  /// per-band filter *type*, so:
  ///  * pass, notch and all-pass filters are dropped (a gain band would read
  ///    as a no-op) with an explicit warning;
  ///  * peaking and shelves are projected as their gain at their centre.
  /// Use [toHeadphoneProfile] when the exact shapes matter.
  ///
  /// [EqPreset] also has no preamp slot — apply [AutoEqParametricProfile
  /// .preampDb] through `EqualizerManager.setPreamp`.
  static EqPreset toPreset(AutoEqParametricProfile profile) {
    final gains = <double>[];
    final frequencies = <double>[];
    final qFactors = <double>[];
    var overCap = 0;

    for (final band in profile.bands) {
      if (!band.enabled) continue;
      if (!_isUsable(band)) {
        profile._addWarning('Filter ${band.filterIndex} has non-finite or '
            'non-positive values — dropped from the preset.');
        continue;
      }
      if (!band.kind.isGainBearing) {
        profile._addWarning('Filter ${band.filterIndex} is a '
            '${band.kind.label} filter — EqPreset carries gain bands only, so '
            'it was dropped. Use toHeadphoneProfile() to keep every filter.');
        continue;
      }
      if (gains.length >= maxBands) {
        overCap++;
        continue;
      }
      gains.add(band.gainDb);
      frequencies.add(band.frequencyHz);
      qFactors.add(band.q);
    }

    if (overCap > 0) {
      profile._addWarning('Profile "${profile.name}" has '
          '${gains.length + overCap} usable bands; the native EQ accepts '
          '$maxBands. The last $overCap band(s) were dropped.');
    }
    if (gains.isEmpty) {
      profile._addWarning('Profile "${profile.name}" produced no usable '
          'EqPreset bands (${profile.bands.length} filter(s) parsed).');
    } else {
      for (var i = 1; i < frequencies.length; i++) {
        if (frequencies[i] <= frequencies[i - 1]) {
          profile._addWarning('Filter frequencies are not strictly ascending '
              'in "${profile.name}"; graphic-EQ interpolation assumes '
              'ascending centres. Use toHeadphoneProfile() for an exact '
              'curve.');
          break;
        }
      }
    }

    return EqPreset(
      name: profile.name,
      gains: gains,
      customFrequencies: frequencies.isEmpty ? null : frequencies,
      qFactors: qFactors.isEmpty ? null : qFactors,
    );
  }

  /// Maps every enabled filter onto a [HeadphoneProfile]'s parametric filter
  /// list — the exact path `EqualizerManager` already drives the native
  /// 64-band PEQ with. Unlike [toPreset], no filter type is lost; only the
  /// [maxBands] cap applies.
  ///
  /// [HeadphoneProfile.gains] is intentionally empty: the filters are the
  /// authoritative correction. The id carries the `custom_` prefix
  /// [HeadphoneProfilesRepository] requires before it will persist a profile,
  /// so an imported file survives the next app launch.
  static HeadphoneProfile toHeadphoneProfile(
    AutoEqParametricProfile profile,
  ) {
    final usable = <AutoEqBand>[];
    var overCap = 0;
    for (final band in profile.bands) {
      if (!band.enabled) continue;
      if (!_isUsable(band)) {
        profile._addWarning('Filter ${band.filterIndex} has non-finite or '
            'non-positive values — dropped from the parametric profile.');
        continue;
      }
      if (usable.length >= maxBands) {
        overCap++;
        continue;
      }
      usable.add(band);
    }
    if (overCap > 0) {
      profile._addWarning('Profile "${profile.name}" has '
          '${usable.length + overCap} usable filters; the native parametric '
          'EQ accepts $maxBands. The last $overCap were dropped.');
    }

    return HeadphoneProfile(
      id: 'custom_autoeq_${_slug(profile.name)}',
      name: profile.name,
      brand: '',
      model: '',
      category: 'AutoEq',
      gains: const <double>[],
      preampGain: profile.preampDb,
      filters: [
        for (final band in usable)
          EqFilter(
            frequency: band.frequencyHz,
            gain: band.gainDb,
            q: band.q,
            filterType: band.kind.nativeIndex,
          ),
      ],
      source: 'AutoEQ ParametricEQ',
    );
  }

  /// Converts an EqualizerAPO bandwidth (octaves) to the equivalent Q:
  /// Q = sqrt(2^bw) / (2^bw - 1), so 1.0 octave yields 1.414 and 0.5 octave
  /// yields 2.871. Non-positive or non-finite input returns the default Q.
  static double qFromBandwidthOctaves(double bandwidthOctaves) {
    if (!bandwidthOctaves.isFinite || bandwidthOctaves <= 0) return _defaultQ;
    final n = math.pow(2.0, bandwidthOctaves).toDouble();
    if (!n.isFinite || n <= 1.0) return _defaultQ;
    return math.sqrt(n) / (n - 1.0);
  }

  static bool _isUsable(AutoEqBand band) =>
      band.frequencyHz.isFinite &&
      band.frequencyHz > 0 &&
      band.gainDb.isFinite &&
      band.q.isFinite &&
      band.q > 0;

  static double _resolveQ(
    Map<String, _ParsedParameter> parameters,
    int lineNumber,
    List<String> warnings,
  ) {
    final qParameter = parameters['q'];
    if (qParameter != null &&
        qParameter.value.isFinite &&
        qParameter.value > 0) {
      return qParameter.value;
    }
    final bwParameter = parameters['bw'];
    if (bwParameter != null &&
        bwParameter.value.isFinite &&
        bwParameter.value > 0) {
      return qFromBandwidthOctaves(bwParameter.value);
    }
    if (qParameter != null) {
      warnings.add('Line $lineNumber: Q ${_number(qParameter.value)} is not a '
          'positive number — using Q ${_number(_defaultQ)}.');
    } else if (bwParameter != null) {
      warnings.add('Line $lineNumber: BW ${_number(bwParameter.value)} Oct is '
          'not a positive number — using Q ${_number(_defaultQ)}.');
    } else {
      warnings.add('Line $lineNumber: no Q or BW given — using '
          'Q ${_number(_defaultQ)}.');
    }
    return _defaultQ;
  }

  static EqFilterKind? _kindForCode(String code) {
    switch (code) {
      case 'pk':
      case 'peak':
        return EqFilterKind.peaking;
      case 'ls':
      case 'lsc':
        return EqFilterKind.lowShelf;
      case 'hs':
      case 'hsc':
        return EqFilterKind.highShelf;
      case 'lp':
        return EqFilterKind.lowPass;
      case 'hp':
        return EqFilterKind.highPass;
      case 'bp':
        return EqFilterKind.bandPass;
      case 'no':
        return EqFilterKind.notch;
      case 'ap':
        return EqFilterKind.allPass;
      default:
        return null;
    }
  }

  static String _stripComment(String line) {
    var cleaned = line;
    final hash = cleaned.indexOf('#');
    if (hash >= 0) cleaned = cleaned.substring(0, hash);
    final slashes = cleaned.indexOf('//');
    if (slashes >= 0) cleaned = cleaned.substring(0, slashes);
    return cleaned;
  }

  static String _preview(String line) =>
      line.length <= 60 ? line : '${line.substring(0, 60)}…';

  static String _number(double value) {
    if (!value.isFinite) return value.toString();
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 1e-9) return rounded.toInt().toString();
    return value.toStringAsFixed(2);
  }

  static String _slug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'profile' : slug;
  }
}

/// One `key value [unit]` triple from a filter line.
class _ParsedParameter {
  const _ParsedParameter(this.value, this.unit);

  final double value;
  final String? unit;
}
