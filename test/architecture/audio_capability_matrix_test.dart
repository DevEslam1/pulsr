// test/architecture/audio_capability_matrix_test.dart
//
// Single source of truth guard for `AudioCapabilityMatrix`.
//
// The matrix is a hand-maintained Dart mirror of constants that live in the
// native DSP headers and the Kotlin plugin. This test re-derives every value
// from the real files, so changing a native limit without updating the matrix
// fails here instead of shipping a lie to the UI. Every assertion names the
// file it parsed and the value found there.
//
// Files parsed (paths are relative to the repository root):
//   * android/app/src/main/cpp/DspParams.h                (band limits)
//   * android/app/src/main/cpp/AudioDspEngine.h            (stage mask)
//   * android/app/src/main/cpp/ChannelManager.h            (channel range, rate)
//   * android/app/src/main/cpp/ChannelManager.cpp          (channel clamp)
//   * android/app/src/main/cpp/IrBounds.h                  (IR seconds)
//   * android/app/src/main/cpp/DsdDecoder.h/.cpp           (DSD rates, PCM clamp)
//   * android/app/src/main/cpp/DopFramer.h                 (markers, carriers)
//   * android/app/src/main/cpp/AAudioSink.h                (AAudio encodings)
//   * android/app/src/main/cpp/SinkQuantizer.h             (USB wire formats)
//   * android/app/src/main/kotlin/.../AudioEffectsPlugin.kt (IR/DSD byte caps)
//   * lib/data/audio/dop_encoder.dart                      (Dart DoP mirror)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_capability_matrix.dart';

const String _dspParams = 'android/app/src/main/cpp/DspParams.h';
const String _engineHeader = 'android/app/src/main/cpp/AudioDspEngine.h';
const String _channelHeader = 'android/app/src/main/cpp/ChannelManager.h';
const String _channelSource = 'android/app/src/main/cpp/ChannelManager.cpp';
const String _irBounds = 'android/app/src/main/cpp/IrBounds.h';
const String _dsdHeader = 'android/app/src/main/cpp/DsdDecoder.h';
const String _dsdSource = 'android/app/src/main/cpp/DsdDecoder.cpp';
const String _dopHeader = 'android/app/src/main/cpp/DopFramer.h';
const String _dopEncoder = 'lib/data/audio/dop_encoder.dart';
const String _dsdHelper = 'lib/data/audio/dsd_decoder_helper.dart';
const String _featureMatrix = 'docs/FEATURE_MATRIX.md';
const String _aaudioHeader = 'android/app/src/main/cpp/AAudioSink.h';
const String _sinkQuantizer = 'android/app/src/main/cpp/SinkQuantizer.h';
const String _kotlinPlugin =
    'android/app/src/main/kotlin/com/pulsr/music/AudioEffectsPlugin.kt';

/// Reads [path] or aborts the test with a message naming the missing file.
String _source(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('cannot verify AudioCapabilityMatrix: missing source file $path '
        '(tests must run from the repository root)');
  }
  return file.readAsStringSync();
}

/// Returns the text from [opener] through its matching closing brace.
///
/// Used to scope a regex to one struct/enum body so three different
/// `MAX_BANDS` declarations cannot be confused with each other.
String _block(String source, String path, String opener) {
  final start = source.indexOf(opener);
  if (start < 0) fail('$path: could not find "$opener"');
  final open = source.indexOf('{', start);
  if (open < 0) fail('$path: "$opener" has no body');
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final unit = source.codeUnitAt(i);
    if (unit == 0x7B) depth++;
    if (unit == 0x7D) {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$path: unbalanced braces after "$opener"');
}

/// Parses the first capture group of [pattern] inside [source] as a decimal
/// int, allowing C++/Kotlin digit separators.
int _intIn(String source, String path, String pattern, String what) {
  final match = RegExp(pattern).firstMatch(source);
  if (match == null) {
    fail('$path: could not parse $what (pattern $pattern)');
  }
  final raw = match.group(1);
  if (raw == null) fail('$path: $what has no digits');
  final parsed = int.tryParse(raw.replaceAll('_', ''));
  if (parsed != null) return parsed;
  // Some native limits are declared as doubles (`MAX_DELAY_MS = 50.0`).
  final asDouble = double.tryParse(raw);
  if (asDouble == null) fail('$path: $what "$raw" is not a number');
  return asDouble.round();
}

/// Parses the first capture group as a hexadecimal literal.
int _hexIn(String source, String path, String pattern, String what) {
  final match = RegExp(pattern).firstMatch(source);
  if (match == null) fail('$path: could not parse $what (pattern $pattern)');
  final raw = match.group(1);
  if (raw == null) fail('$path: $what has no hex digits');
  final parsed = int.tryParse(raw.replaceFirst('0x', ''), radix: 16);
  if (parsed == null) fail('$path: $what "$raw" is not a hex integer');
  return parsed;
}

/// Evaluates a Kotlin integer constant body such as `8 * 1024 * 1024`.
int _productIn(String source, String path, String name) {
  final match = RegExp('const val $name\\s*=\\s*([^\\n]+)').firstMatch(source);
  if (match == null) fail('$path: could not find "const val $name"');
  final expression = match.group(1)!.split('//').first.trim();
  if (expression.isEmpty) fail('$path: $name has no value');
  var total = 1;
  for (final factor in expression.split('*')) {
    final digits = factor.trim().replaceAll('_', '');
    final value = int.tryParse(digits);
    if (value == null) {
      fail('$path: cannot evaluate $name = "$expression"');
    }
    total *= value;
  }
  return total;
}

/// Asserts one matrix field against the value found in [path].
void _expectField(String field, Object? actual, Object? expected, String path) {
  expect(
    actual,
    expected,
    reason: 'AudioCapabilityMatrix.$field = $actual, but $path declares '
        '$expected',
  );
}

/// Converts a PascalCase native enumerator to the matrix's snake_case name.
String _snake(String name) {
  final buffer = StringBuffer();
  for (var i = 0; i < name.length; i++) {
    final char = name[i];
    final code = name.codeUnitAt(i);
    final isUpper = code >= 0x41 && code <= 0x5A;
    if (isUpper && i > 0) {
      final previous = name.codeUnitAt(i - 1);
      final previousIsLower = previous >= 0x61 && previous <= 0x7A;
      final previousIsDigit = previous >= 0x30 && previous <= 0x39;
      if (previousIsLower || previousIsDigit) buffer.write('_');
    }
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

void main() {
  final matrix = AudioCapabilityMatrix.current;

  group('native DSP stage mask', () {
    test('stage count and names match AudioDspEngine.h', () {
      final header = _source(_engineHeader);
      final mask = _block(header, _engineHeader, 'enum DspStageMask');

      final bits = <int, String>{};
      for (final match in RegExp(r'(STAGE_[A-Z0-9_]+)\s*=\s*1\s*<<\s*(\d+)')
          .allMatches(mask)) {
        bits[int.parse(match.group(2)!)] = match.group(1)!;
      }
      expect(bits, isNotEmpty,
          reason: '$_engineHeader: no STAGE_* = 1 << n enumerators found');

      // Contiguous bits from 0 are what the matrix's ordered name list means.
      final expectedNames = <String>[];
      for (var bit = 0; bit < bits.length; bit++) {
        final name = bits[bit];
        if (name == null) {
          fail('$_engineHeader: DspStageMask has $bits but bit $bit is unused, '
              'so the ordered stage list in the matrix is stale');
        }
        expectedNames.add(_snake(name.substring('STAGE_'.length)));
      }

      _expectField('nativeDspStageCount', matrix.nativeDspStageCount,
          expectedNames.length, _engineHeader);
      _expectField('nativeDspStages', matrix.nativeDspStages, expectedNames,
          _engineHeader);
      expect(matrix.nativeDspStages.length, matrix.nativeDspStageCount,
          reason: 'AudioCapabilityMatrix.nativeDspStageCount says '
              '${matrix.nativeDspStageCount} but nativeDspStages lists '
              '${matrix.nativeDspStages.length} names');
    });
  });

  group('DSP band limits', () {
    test('parametric, dynamic and multiband counts match DspParams.h', () {
      final header = _source(_dspParams);

      final eq = _block(header, _dspParams, 'struct EqParamSet {');
      final dynamicEq = _block(header, _dspParams, 'struct DynamicEqParamSet {');
      final multiband =
          _block(header, _dspParams, 'struct MultibandCompressorParamSet {');

      final parametric =
          _intIn(eq, _dspParams, r'MAX_BANDS\s*=\s*(\d+)', 'EqParamSet::MAX_BANDS');
      final dynamicBands = _intIn(dynamicEq, _dspParams, r'MAX_BANDS\s*=\s*(\d+)',
          'DynamicEqParamSet::MAX_BANDS');
      final multibandBands = _intIn(multiband, _dspParams, r'NUM_BANDS\s*=\s*(\d+)',
          'MultibandCompressorParamSet::NUM_BANDS');
      // The Kotlin plugin enforces the same EQ ceiling on the JNI boundary.
      final pluginBands = _intIn(_source(_kotlinPlugin), _kotlinPlugin,
          r'MAX_NATIVE_EQ_BANDS\s*=\s*(\d+)', 'MAX_NATIVE_EQ_BANDS');

      _expectField('maxParametricEqBands', matrix.maxParametricEqBands,
          parametric, _dspParams);
      _expectField('maxParametricEqBands', matrix.maxParametricEqBands,
          pluginBands, _kotlinPlugin);
      _expectField(
          'maxDynamicEqBands', matrix.maxDynamicEqBands, dynamicBands, _dspParams);
      _expectField('multibandCompressorBands', matrix.multibandCompressorBands,
          multibandBands, _dspParams);
    });
  });

  group('channel manager', () {
    test('channel range and max delay match ChannelManager.h/.cpp', () {
      final header = _source(_channelHeader);
      final source = _source(_channelSource);

      final maxChannels = _intIn(
          header, _channelHeader, r'MAX_CHANNELS\s*=\s*(\d+)', 'MAX_CHANNELS');
      final maxDelayMs = _intIn(header, _channelHeader,
          r'MAX_DELAY_MS\s*=\s*([0-9.]+)', 'MAX_DELAY_MS');
      final maxSampleRate = _intIn(header, _channelHeader,
          r'MAX_SAMPLE_RATE\s*=\s*(\d+)', 'MAX_SAMPLE_RATE');
      // The lower bound is a literal inside the clamp, not a named constant.
      final minChannels = _intIn(source, _channelSource,
          r'clamp\(params_\.channelCount,\s*(\d+),\s*MAX_CHANNELS\)',
          'channelCount lower clamp');

      _expectField('minChannelManagerChannels', matrix.minChannelManagerChannels,
          minChannels, _channelSource);
      _expectField('maxChannelManagerChannels', matrix.maxChannelManagerChannels,
          maxChannels, _channelHeader);
      _expectField('maxChannelManagerDelayMs', matrix.maxChannelManagerDelayMs,
          maxDelayMs, _channelHeader);
      _expectField('maxPcmSampleRate', matrix.maxPcmSampleRate, maxSampleRate,
          _channelHeader);
      expect(matrix.minChannelManagerChannels,
          lessThan(matrix.maxChannelManagerChannels),
          reason: 'AudioCapabilityMatrix channel range is inverted: '
              '${matrix.minChannelManagerChannels}..'
              '${matrix.maxChannelManagerChannels}');
    });
  });

  group('convolution IR bounds', () {
    test('IR length ceiling and sample cap match IrBounds.h and Kotlin', () {
      final bounds = _source(_irBounds);
      final plugin = _source(_kotlinPlugin);

      final maxSeconds = _intIn(bounds, _irBounds,
          r'kMaxIrSeconds\s*=\s*(\d+)', 'kMaxIrSeconds');
      final maxSamples = _productIn(plugin, _kotlinPlugin, 'MAX_IR_SAMPLES');
      final maxDsdBytes =
          _productIn(plugin, _kotlinPlugin, 'MAX_DSD_BUFFER_BYTES');

      _expectField('maxIrSeconds', matrix.maxIrSeconds, maxSeconds, _irBounds);
      _expectField(
          'maxIrSamples', matrix.maxIrSamples, maxSamples, _kotlinPlugin);
      _expectField('maxDsdBufferBytes', matrix.maxDsdBufferBytes, maxDsdBytes,
          _kotlinPlugin);
    });
  });

  group('DSD decode', () {
    test('DSD multiples and PCM ceiling match DsdDecoder/DopFramer', () {
      final header = _source(_dsdHeader);
      final source = _source(_dsdSource);

      final rateBlock = _block(header, _dsdHeader, 'enum class DsdRate {');
      final rates = <int>[];
      for (final match
          in RegExp(r'DSD(\d+)\s*=\s*(\d+)').allMatches(rateBlock)) {
        rates.add(int.parse(match.group(2)!));
      }
      expect(rates, isNotEmpty,
          reason: '$_dsdHeader: no DSD64..DSD512 enumerators found');

      final defaultPcm = _intIn(header, _dsdHeader,
          r'targetPcmSampleRate\s*=\s*(\d+)', 'default targetPcmSampleRate');
      final pcmCeiling = _intIn(source, _dsdSource,
          r'clamp\(targetPcmSampleRate,\s*\d+,\s*(\d+)\)', 'DSD PCM ceiling');

      _expectField('dsdDecodeRates', matrix.dsdDecodeRates, rates, _dsdHeader);
      _expectField('dsdDefaultPcmSampleRate', matrix.dsdDefaultPcmSampleRate,
          defaultPcm, _dsdHeader);
      _expectField('maxPcmSampleRate', matrix.maxPcmSampleRate, pcmCeiling,
          _dsdSource);
    });

    test('DoP carrier rates and markers match both framers', () {
      final header = _source(_dopHeader);
      final dart = _source(_dopEncoder);

      final nativeBody = _block(
          header, _dopHeader, 'inline constexpr int32_t DopPcmSampleRate(');
      final dartBody =
          _block(dart, _dopEncoder, 'static int dopPcmSampleRate(');

      Map<int, int> carriersIn(String body, String path) {
        final map = <int, int>{};
        // Skip the leading `dsdRate <= 0` guard: it is a rejection, not a
        // carrier rate.
        for (final match
            in RegExp(r'dsdRate\s*<=\s*([1-9]\d*)\)\s*return\s+(\d+);')
                .allMatches(body)) {
          map[int.parse(match.group(1)!)] = int.parse(match.group(2)!);
        }
        if (map.isEmpty) fail('$path: DopPcmSampleRate has no rate branches');
        return map;
      }

      final nativeCarriers = carriersIn(nativeBody, _dopHeader);
      final dartCarriers = carriersIn(dartBody, _dopEncoder);

      _expectField(
          'dopCarrierRates', matrix.dopCarrierRates, nativeCarriers, _dopHeader);
      _expectField(
          'dopCarrierRates', matrix.dopCarrierRates, dartCarriers, _dopEncoder);
      expect(nativeCarriers, dartCarriers,
          reason: 'DoP carrier rates diverge: $_dopHeader says $nativeCarriers '
              'while $_dopEncoder says $dartCarriers');

      final nativeA = _hexIn(
          header, _dopHeader, r'kDopMarkerA\s*=\s*(0x[0-9A-Fa-f]+)', 'marker A');
      final nativeB = _hexIn(
          header, _dopHeader, r'kDopMarkerB\s*=\s*(0x[0-9A-Fa-f]+)', 'marker B');
      final dartA = _hexIn(
          dart, _dopEncoder, r'dopMarkerA\s*=\s*(0x[0-9A-Fa-f]+)', 'marker A');
      final dartB = _hexIn(
          dart, _dopEncoder, r'dopMarkerB\s*=\s*(0x[0-9A-Fa-f]+)', 'marker B');

      _expectField('dopMarkerA', matrix.dopMarkerA, nativeA, _dopHeader);
      _expectField('dopMarkerB', matrix.dopMarkerB, nativeB, _dopHeader);
      expect(dartA, nativeA,
          reason: 'DoP marker A diverges: $_dopHeader says $nativeA while '
              '$_dopEncoder says $dartA');
      expect(dartB, nativeB,
          reason: 'DoP marker B diverges: $_dopHeader says $nativeB while '
              '$_dopEncoder says $dartB');

      // DoP v1.1 carries at most DSD256; DSD512 must not gain a carrier rate
      // without the matrix (and the encoder) saying so.
      final declaredDsdRates = matrix.dsdDecodeRates.toSet();
      final missing = declaredDsdRates.difference(
          {...matrix.dopCarrierRates.keys, 512});
      expect(missing, isEmpty,
          reason: 'AudioCapabilityMatrix.dsdDecodeRates $declaredDsdRates '
              'contains rates with no documented DoP story: $missing');
    });
  });

  group('output formats', () {
    test('USB wire formats match SinkQuantizer.h IsPcmWireFormat', () {
      final header = _source(_sinkQuantizer);
      final body = _block(header, _sinkQuantizer, 'inline bool IsPcmWireFormat(');

      final subslots = RegExp(
              r'bytesPerSample\s*>=\s*(\d+)\s*&&\s*bytesPerSample\s*<=\s*(\d+)')
          .firstMatch(body);
      if (subslots == null) {
        fail('$_sinkQuantizer: could not parse the bytesPerSample range');
      }
      final minBytes = int.parse(subslots.group(1)!);
      final maxBytes = int.parse(subslots.group(2)!);

      final validBits = <int>[
        for (final match in RegExp(r'validBits\s*==\s*(\d+)').allMatches(body))
          int.parse(match.group(1)!),
      ];
      if (validBits.isEmpty) {
        fail('$_sinkQuantizer: IsPcmWireFormat declares no valid bit depths');
      }

      const names = <int, String>{
        2: 's16_le',
        3: 's24_3le',
        4: 's32_le',
      };
      final expectedFormats = <String>[];
      final expectedSubslots = <int>[];
      for (var bytes = minBytes; bytes <= maxBytes; bytes++) {
        final name = names[bytes];
        if (name == null) {
          fail('$_sinkQuantizer: IsPcmWireFormat accepts a $bytes-byte subslot '
              'that AudioCapabilityMatrix has no name for');
        }
        expectedFormats.add(name);
        expectedSubslots.add(bytes);
      }

      _expectField('usbWireFormats', matrix.usbWireFormats, expectedFormats,
          _sinkQuantizer);
      _expectField('usbSubslotBytes', matrix.usbSubslotBytes,
          expectedSubslots, _sinkQuantizer);
      _expectField(
          'usbValidBitDepths', matrix.usbValidBitDepths, validBits, _sinkQuantizer);
      expect(matrix.usbWireFormats.length, matrix.usbSubslotBytes.length,
          reason: 'AudioCapabilityMatrix.usbWireFormats '
              '${matrix.usbWireFormats} and usbSubslotBytes '
              '${matrix.usbSubslotBytes} describe different format counts');
    });

    test('AAudio encodings match AAudioSink.h', () {
      final header = _source(_aaudioHeader);
      final body = _block(header, _aaudioHeader, 'enum class Encoding : int32_t {');

      final names = <String>[];
      final ids = <String, int>{};
      for (final match in RegExp(r'(\w+)\s*=\s*(-?\d+)').allMatches(body)) {
        final name = _snake(match.group(1)!);
        names.add(name);
        ids[name] = int.parse(match.group(2)!);
      }
      expect(names, isNotEmpty,
          reason: '$_aaudioHeader: AAudioSink::Encoding has no enumerators');

      _expectField('aaudioEncodings', matrix.aaudioEncodings, names, _aaudioHeader);
      _expectField(
          'aaudioEncodingIds', matrix.aaudioEncodingIds, ids, _aaudioHeader);
    });

    test('native DSD producer flag matches the playback-path gate', () {
      final helper = _source(_dsdHelper);
      final match = RegExp(
              r'const bool kNativeDsdProducerAvailable = (true|false);')
          .firstMatch(helper);
      if (match == null) {
        fail('$_dsdHelper: kNativeDsdProducerAvailable is missing or not a '
            'bool literal');
      }
      _expectField(
        'nativeDsdProducerAvailable',
        matrix.nativeDsdProducerAvailable,
        match.group(1) == 'true',
        _dsdHelper,
      );
    });
  });

  group('documentation', () {
    test('docs/FEATURE_MATRIX.md embeds the generated matrix verbatim', () {
      final docs = _source(_featureMatrix);
      const begin = '<!-- BEGIN GENERATED CAPABILITY MATRIX -->';
      const end = '<!-- END GENERATED CAPABILITY MATRIX -->';
      final start = docs.indexOf(begin);
      final stop = docs.indexOf(end);
      if (start < 0 || stop < start) {
        fail('$_featureMatrix: the generated capability block markers are '
            'missing; paste AudioCapabilityMatrix.current.toMarkdownSection() '
            'between them');
      }
      final embedded = docs.substring(start, stop + end.length);
      String normalise(String value) =>
          value.replaceAll('\r\n', '\n').trimRight();
      expect(
        normalise(embedded),
        normalise(matrix.toMarkdownSection()),
        reason: '$_featureMatrix is stale. Regenerate the block between the '
            'markers from AudioCapabilityMatrix.current.toMarkdownSection().',
      );
    });
  });
}
