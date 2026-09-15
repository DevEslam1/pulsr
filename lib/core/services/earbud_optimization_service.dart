// lib/core/services/earbud_optimization_service.dart
import 'package:injectable/injectable.dart';

import '../../domain/models/audio_output_info.dart';
import '../../domain/models/eq_preset.dart';
import 'bluetooth_latency_calibrator.dart';

/// Codec families Pulsr knows how to reason about.
///
/// This is derived from the platform-reported A2DP codec name — it is *not* a
/// driver-type guess. Driver topology (dynamic / BA / planar / hybrid) is not
/// exposed by Android and cannot be inferred from the codec or sample rate, so
/// it is intentionally absent.
enum EarbudCodec {
  sbc('SBC', 'Basic', false),
  aac('AAC', 'Good', false),
  aptx('aptX', 'Good', false),
  aptxHd('aptX HD', 'High', false),
  aptxAdaptive('aptX Adaptive', 'Adaptive', false),
  ldac('LDAC', 'Ultra', false),
  lhdc('LHDC', 'Ultra', false),
  lc3('LC3 / LE Audio', 'Low latency', false),
  opus('Opus', 'Good', false),
  wired('Wired', 'Lossless', true),
  usbDac('USB DAC', 'Lossless', true),
  unknown('Unknown', '—', true);

  const EarbudCodec(this.label, this.quality, this.isLossless);

  final String label;
  final String quality;
  final bool isLossless;

  /// True when the codec is an ultra-high-bitrate A2DP codec where extra DSP
  /// compensation would do more harm than good.
  bool get isUltraHighQuality =>
      this == EarbudCodec.ldac ||
      this == EarbudCodec.lhdc ||
      this == EarbudCodec.aptxHd ||
      this == EarbudCodec.aptxAdaptive;
}

/// A snapshot of what the current output route actually reports. Everything
/// here comes from [AudioOutputInfo]; no values are fabricated.
class EarbudCapabilities {
  final String deviceName;
  final EarbudCodec codec;
  final bool isBluetooth;
  final bool isLeAudio;
  final bool isUsbDac;
  final int sampleRateHz;
  final int bitDepth;
  final int latencyMs;

  const EarbudCapabilities({
    required this.deviceName,
    required this.codec,
    required this.isBluetooth,
    required this.isLeAudio,
    required this.isUsbDac,
    required this.sampleRateHz,
    required this.bitDepth,
    required this.latencyMs,
  });

  bool get isLossyBluetooth => isBluetooth && !codec.isLossless;

  /// Bluetooth codecs that already smear transients benefit from a shorter,
  /// drier reverb tail rather than a longer one.
  double get reverbScale =>
      isLossyBluetooth ? (latencyMs >= 200 ? 0.65 : 0.8) : 1.0;

  bool get hasHighLatency => latencyMs > 200;
}

/// Detects the output route's real capabilities and derives a *conservative*
/// EQ compensation for lossy Bluetooth codecs.
@singleton
class EarbudOptimizationService {
  EarbudOptimizationService();

  EarbudCapabilities detect(AudioOutputInfo? info) {
    if (info == null) {
      return const EarbudCapabilities(
        deviceName: 'Default output',
        codec: EarbudCodec.unknown,
        isBluetooth: false,
        isLeAudio: false,
        isUsbDac: false,
        sampleRateHz: 44100,
        bitDepth: 16,
        latencyMs: 0,
      );
    }

    final codec = _detectCodec(info);
    return EarbudCapabilities(
      deviceName: info.deviceName,
      codec: codec,
      isBluetooth: info.isBluetooth,
      isLeAudio: info.isLeAudio,
      isUsbDac: info.isUsbDac,
      sampleRateHz: info.btSampleRateHz ?? info.sampleRate,
      bitDepth: info.btBitDepth ?? info.bitDepth,
      latencyMs: info.isBluetooth
          ? estimateBtLatencyForCodec(info.btCodecName)
          : 0,
    );
  }

  /// A gentle, codec-aware EQ trim. Only lossy Bluetooth gets a small
  /// high-frequency presence lift to counter the codec's top-end rolloff;
  /// lossless and high-quality routes are left untouched.
  List<double> eqCompensation(EarbudCapabilities caps) {
    final gains = List<double>.filled(EqPreset.centerFrequencies.length, 0.0);
    if (!caps.isBluetooth || caps.codec.isLossless) return gains;

    switch (caps.codec) {
      case EarbudCodec.sbc:
        // SBC rolls off the most — a touch of 4–8 kHz presence.
        gains[7] += 0.5; // 4 kHz
        gains[8] += 0.5; // 8 kHz
        break;
      case EarbudCodec.aac:
      case EarbudCodec.opus:
        gains[7] += 0.3;
        break;
      default:
        break;
    }
    return gains;
  }

  /// Merges a base curve with hardware compensation and clamps to ±15 dB.
  List<double> mergeCompensation(
    List<double> base,
    EarbudCapabilities caps,
  ) {
    final comp = eqCompensation(caps);
    final out = List<double>.generate(base.length, (i) {
      final c = i < comp.length ? comp[i] : 0.0;
      return (base[i] + c).clamp(-15.0, 15.0).toDouble();
    });
    return out;
  }

  /// True when codec info could not be read because the runtime
  /// BLUETOOTH_CONNECT permission is missing (Android 12+).
  static bool needsBluetoothPermission(AudioOutputInfo? info) {
    if (info == null || !info.isBluetooth) return false;
    return !info.btCodecConnected &&
        (info.btReason == 'permission_required' ||
            (info.btCodecName?.isEmpty ?? true));
  }

  String describe(EarbudCapabilities caps, [AudioOutputInfo? info]) {
    if (!caps.isBluetooth) {
      return '${caps.deviceName} • wired/USB • ${caps.sampleRateHz ~/ 1000} kHz';
    }
    if (caps.codec == EarbudCodec.unknown) {
      final hint = info != null && needsBluetoothPermission(info)
          ? ' • grant Nearby-devices permission for codec details'
          : ' • codec unavailable';
      return '${caps.deviceName} • Bluetooth$hint • ~${caps.latencyMs} ms';
    }
    final rate = caps.sampleRateHz ~/ 1000;
    return '${caps.deviceName} • ${caps.codec.label} • '
        '${caps.bitDepth}-bit • $rate kHz • ~${caps.latencyMs} ms';
  }

  EarbudCodec _detectCodec(AudioOutputInfo info) {
    if (!info.isBluetooth) {
      return info.isUsbDac ? EarbudCodec.usbDac : EarbudCodec.wired;
    }
    final name = (info.btCodecName ?? '').toLowerCase();
    if (name.contains('ldac')) return EarbudCodec.ldac;
    if (name.contains('lhdc')) return EarbudCodec.lhdc;
    if (name.contains('adaptive')) return EarbudCodec.aptxAdaptive;
    if (name.contains('aptx') && name.contains('hd')) return EarbudCodec.aptxHd;
    if (name.contains('aptx')) return EarbudCodec.aptx;
    if (name.contains('lc3')) return EarbudCodec.lc3;
    if (name.contains('sbc')) return EarbudCodec.sbc;
    if (name.contains('aac')) return EarbudCodec.aac;
    if (name.contains('opus')) return EarbudCodec.opus;
    return EarbudCodec.unknown;
  }
}
