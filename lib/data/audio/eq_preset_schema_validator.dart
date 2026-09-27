// lib/data/audio/eq_preset_schema_validator.dart
import 'dart:convert';
import '../../core/utils/error_logger.dart';
import '../../domain/models/eq_preset.dart';

/// Result of validating and parsing an EQ preset payload.
class EqPresetValidationResult {
  final bool isValid;
  final EqPreset? preset;
  final String? errorMessage;
  final int schemaVersion;

  const EqPresetValidationResult({
    required this.isValid,
    this.preset,
    this.errorMessage,
    this.schemaVersion = 1,
  });

  factory EqPresetValidationResult.success(EqPreset preset, {int schemaVersion = 1}) {
    return EqPresetValidationResult(
      isValid: true,
      preset: preset,
      schemaVersion: schemaVersion,
    );
  }

  factory EqPresetValidationResult.failure(String message) {
    return EqPresetValidationResult(
      isValid: false,
      errorMessage: message,
    );
  }
}

/// Comprehensive schema validation and multi-format parser for Equalizer presets.
/// Supports standard Pulsr JSON schemas, AutoEQ/EqualizerAPO GraphicEQ formats,
/// and Wavelet parametric configs with boundary-safe gain sanitization.
class EqPresetSchemaValidator {
  static const double minAllowedGain = -30.0;
  static const double maxAllowedGain = 30.0;
  static const double minFrequencyHz = 10.0;
  static const double maxFrequencyHz = 48000.0;
  static const double minQFactor = 0.1;
  static const double maxQFactor = 50.0;

  /// Validates and parses raw text (JSON or GraphicEQ string) into an [EqPreset].
  static EqPresetValidationResult validateAndParse(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return EqPresetValidationResult.failure('Preset payload cannot be empty.');
    }

    // Try parsing as JSON first
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return _validateJson(trimmed);
    }

    // Check for EqualizerAPO / AutoEQ GraphicEQ format
    if (trimmed.startsWith('GraphicEQ:') || trimmed.contains(';')) {
      return _parseGraphicEq(trimmed);
    }

    return EqPresetValidationResult.failure(
      'Unrecognized preset format. Expected JSON or GraphicEQ string.',
    );
  }

  /// Validates an existing [EqPreset] in-memory model.
  static EqPresetValidationResult validatePreset(EqPreset preset) {
    if (preset.name.trim().isEmpty) {
      return EqPresetValidationResult.failure('Preset name cannot be empty.');
    }
    if (preset.gains.isEmpty) {
      return EqPresetValidationResult.failure('Preset gains list cannot be empty.');
    }
    for (int i = 0; i < preset.gains.length; i++) {
      final gain = preset.gains[i];
      if (gain.isNaN || gain.isInfinite) {
        return EqPresetValidationResult.failure('Band $i gain is not a finite number.');
      }
      if (gain < minAllowedGain || gain > maxAllowedGain) {
        return EqPresetValidationResult.failure(
          'Band $i gain $gain dB exceeds allowed range [$minAllowedGain, $maxAllowedGain].',
        );
      }
    }

    if (preset.bassBoost.isNaN || preset.bassBoost < 0.0 || preset.bassBoost > 1.0) {
      return EqPresetValidationResult.failure('bassBoost must be a value between 0.0 and 1.0.');
    }

    if (preset.customFrequencies != null) {
      final freqs = preset.customFrequencies!;
      if (freqs.isEmpty) {
        return EqPresetValidationResult.failure('customFrequencies list cannot be empty when provided.');
      }
      double lastFreq = 0.0;
      for (int i = 0; i < freqs.length; i++) {
        final f = freqs[i];
        if (f.isNaN || f.isInfinite || f < minFrequencyHz || f > maxFrequencyHz) {
          return EqPresetValidationResult.failure(
            'Frequency at band $i ($f Hz) is out of bounds [$minFrequencyHz, $maxFrequencyHz].',
          );
        }
        if (f <= lastFreq) {
          return EqPresetValidationResult.failure(
            'customFrequencies must be strictly ascending (band $i: $f Hz <= $lastFreq Hz).',
          );
        }
        lastFreq = f;
      }
    }

    if (preset.qFactors != null) {
      for (int i = 0; i < preset.qFactors!.length; i++) {
        final q = preset.qFactors![i];
        if (q.isNaN || q.isInfinite || q < minQFactor || q > maxQFactor) {
          return EqPresetValidationResult.failure(
            'Q factor at band $i ($q) is out of bounds [$minQFactor, $maxQFactor].',
          );
        }
      }
    }

    return EqPresetValidationResult.success(preset);
  }

  static EqPresetValidationResult _validateJson(String jsonString) {
    try {
      final dynamic decoded = json.decode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return EqPresetValidationResult.failure('JSON root must be an object.');
      }

      final schemaVersion = (decoded['schemaVersion'] as num?)?.toInt() ?? 1;

      final name = decoded['name'] as String? ?? 'Imported Preset';
      if (name.trim().isEmpty) {
        return EqPresetValidationResult.failure('Preset name must be a non-empty string.');
      }

      final rawGains = decoded['gains'];
      if (rawGains == null || rawGains is! List) {
        return EqPresetValidationResult.failure("Missing or invalid 'gains' array in preset JSON.");
      }
      if (rawGains.isEmpty) {
        return EqPresetValidationResult.failure("'gains' array cannot be empty.");
      }

      final gains = <double>[];
      for (int i = 0; i < rawGains.length; i++) {
        final val = rawGains[i];
        if (val is! num) {
          return EqPresetValidationResult.failure('Gain value at index $i is not numeric.');
        }
        final doubleVal = val.toDouble();
        if (doubleVal.isNaN || doubleVal.isInfinite) {
          return EqPresetValidationResult.failure('Gain at index $i is NaN or infinite.');
        }
        gains.add(doubleVal.clamp(minAllowedGain, maxAllowedGain));
      }

      final bassBoostRaw = decoded['bassBoost'];
      double bassBoost = 0.0;
      if (bassBoostRaw != null) {
        if (bassBoostRaw is! num) {
          return EqPresetValidationResult.failure("'bassBoost' must be a numeric value.");
        }
        bassBoost = bassBoostRaw.toDouble().clamp(0.0, 1.0);
      }

      List<double>? customFrequencies;
      final rawFreqs = decoded['customFrequencies'];
      if (rawFreqs != null) {
        if (rawFreqs is! List) {
          return EqPresetValidationResult.failure("'customFrequencies' must be a list of numbers.");
        }
        customFrequencies = [];
        double lastFreq = 0.0;
        for (int i = 0; i < rawFreqs.length; i++) {
          final fVal = rawFreqs[i];
          if (fVal is! num) {
            return EqPresetValidationResult.failure('Frequency at index $i is not numeric.');
          }
          final f = fVal.toDouble();
          if (f.isNaN || f.isInfinite || f < minFrequencyHz || f > maxFrequencyHz) {
            return EqPresetValidationResult.failure('Frequency $f at index $i is out of range.');
          }
          if (f <= lastFreq) {
            return EqPresetValidationResult.failure('Frequencies must be in strictly ascending order.');
          }
          customFrequencies.add(f);
          lastFreq = f;
        }
      }

      List<double>? qFactors;
      final rawQs = decoded['qFactors'];
      if (rawQs != null) {
        if (rawQs is! List) {
          return EqPresetValidationResult.failure("'qFactors' must be a list of numbers.");
        }
        qFactors = [];
        for (int i = 0; i < rawQs.length; i++) {
          final qVal = rawQs[i];
          if (qVal is! num) {
            return EqPresetValidationResult.failure('Q factor at index $i is not numeric.');
          }
          qFactors.add(qVal.toDouble().clamp(minQFactor, maxQFactor));
        }
      }

      final rawBandsMap = decoded['bandsMap'] as Map<String, dynamic>?;
      final bandsMap = <int, List<double>>{};
      if (rawBandsMap != null) {
        rawBandsMap.forEach((k, v) {
          final bandCount = int.tryParse(k);
          if (bandCount != null && v is List) {
            bandsMap[bandCount] = v
                .whereType<num>()
                .map((n) => n.toDouble().clamp(minAllowedGain, maxAllowedGain))
                .toList();
          }
        });
      }

      final preset = EqPreset(
        name: name,
        gains: gains,
        bassBoost: bassBoost,
        customFrequencies: customFrequencies,
        qFactors: qFactors,
        bandsMap: bandsMap,
      );

      return EqPresetValidationResult.success(preset, schemaVersion: schemaVersion);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to validate EQ preset JSON',
        error: e,
        stackTrace: st,
        category: 'EqPresetSchemaValidator',
      );
      return EqPresetValidationResult.failure('Malformed JSON structure: $e');
    }
  }

  static EqPresetValidationResult _parseGraphicEq(String content) {
    try {
      var body = content;
      if (body.startsWith('GraphicEQ:')) {
        body = body.substring('GraphicEQ:'.length).trim();
      }

      final segments = body.split(';');
      final parsedFreqs = <double>[];
      final parsedGains = <double>[];

      double lastFreq = 0.0;
      for (final segment in segments) {
        final pair = segment.trim().split(RegExp(r'\s+'));
        if (pair.length >= 2) {
          final freq = double.tryParse(pair[0]);
          final gain = double.tryParse(pair[1]);
          if (freq != null && gain != null) {
            // Mirror the JSON path: reject non-finite, out-of-range, or
            // non-ascending data so NaN/Infinity/mis-ordered frequencies never
            // reach the native EQ (NaN.clamp() stays NaN in Dart).
            if (!freq.isFinite ||
                freq < minFrequencyHz ||
                freq > maxFrequencyHz) {
              return EqPresetValidationResult.failure(
                'GraphicEQ frequency $freq is out of range.',
              );
            }
            if (freq <= lastFreq) {
              return EqPresetValidationResult.failure(
                'GraphicEQ frequencies must be in strictly ascending order.',
              );
            }
            if (!gain.isFinite) {
              return EqPresetValidationResult.failure(
                'GraphicEQ gain at $freq Hz is NaN or infinite.',
              );
            }
            parsedFreqs.add(freq);
            parsedGains.add(gain.clamp(minAllowedGain, maxAllowedGain));
            lastFreq = freq;
          }
        }
      }

      if (parsedGains.isEmpty) {
        return EqPresetValidationResult.failure(
          'No valid frequency-gain pairs found in GraphicEQ payload.',
        );
      }

      final preset = EqPreset(
        name: 'AutoEQ GraphicEQ',
        gains: parsedGains,
        customFrequencies: parsedFreqs,
      );

      return EqPresetValidationResult.success(preset);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to parse GraphicEQ preset',
        error: e,
        stackTrace: st,
        category: 'EqPresetSchemaValidator',
      );
      return EqPresetValidationResult.failure('Failed to parse GraphicEQ: $e');
    }
  }

  /// Encodes an [EqPreset] into a formatted, schema-compliant JSON string.
  static String exportToJson(EqPreset preset, {bool pretty = false}) {
    final map = <String, dynamic>{
      'schemaVersion': 1,
      'name': preset.name,
      'gains': preset.gains,
      'bassBoost': preset.bassBoost,
    };
    if (preset.customFrequencies != null) {
      map['customFrequencies'] = preset.customFrequencies;
    }
    if (preset.qFactors != null) {
      map['qFactors'] = preset.qFactors;
    }
    if (preset.bandsMap.isNotEmpty) {
      map['bandsMap'] = preset.bandsMap.map((k, v) => MapEntry(k.toString(), v));
    }

    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return json.encode(map);
  }
}
