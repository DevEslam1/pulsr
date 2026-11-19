// lib/data/audio/audio_capability_matrix.dart
//
// Dart mirror of the hard limits compiled into the native audio stack. Every
// value below is copied from a real source constant; the guard test in
// `test/architecture/audio_capability_matrix_test.dart` re-parses those files
// and fails when this table and the native/Dart truth disagree.
//
// The single source of truth is the native header (or the Kotlin plugin for the
// few limits that only exist there). This class is hand-maintained on purpose:
// it is data, not behaviour, and must stay dependency-free and const so it can
// be read from a background isolate, a golden test or a diagnostic dump without
// touching the engine.

/// Immutable description of what this build's audio stack can actually do.
///
/// Consumers must treat this as a *maximum capability* report, not a promise:
/// a device may support less (for example a DAC that only accepts 24-bit
/// subslots), but never more than what is declared here.
class AudioCapabilityMatrix {
  /// Creates a matrix snapshot. All fields are required so a new capability
  /// cannot be added without stating its value.
  const AudioCapabilityMatrix({
    required this.nativeDspStageCount,
    required this.nativeDspStages,
    required this.maxParametricEqBands,
    required this.maxDynamicEqBands,
    required this.multibandCompressorBands,
    required this.minChannelManagerChannels,
    required this.maxChannelManagerChannels,
    required this.maxChannelManagerDelayMs,
    required this.maxIrSamples,
    required this.maxIrSeconds,
    required this.dsdDecodeRates,
    required this.dsdDefaultPcmSampleRate,
    required this.maxPcmSampleRate,
    required this.dopCarrierRates,
    required this.dopMarkerA,
    required this.dopMarkerB,
    required this.usbWireFormats,
    required this.usbSubslotBytes,
    required this.usbValidBitDepths,
    required this.aaudioEncodings,
    required this.aaudioEncodingIds,
    required this.maxDsdBufferBytes,
    required this.nativeDsdProducerAvailable,
  });

  /// Number of independently gated stages in the native DSP graph.
  ///
  /// Mirrors the `DspStageMask` bits in `AudioDspEngine.h`; always equal to
  /// [nativeDspStages].length.
  final int nativeDspStageCount;

  /// Canonical stage names, ordered by their `DspStageMask` bit index.
  ///
  /// Derived from the `STAGE_*` enumerator names in `AudioDspEngine.h` with the
  /// prefix removed and lower-cased (`STAGE_MULTIBAND_COMPRESSOR` becomes
  /// `multiband_compressor`).
  final List<String> nativeDspStages;

  /// Maximum parametric EQ bands (`EqParamSet::MAX_BANDS`).
  final int maxParametricEqBands;

  /// Maximum dynamic EQ bands (`DynamicEqParamSet::MAX_BANDS`).
  final int maxDynamicEqBands;

  /// Fixed band count of the multiband compressor
  /// (`MultibandCompressorParamSet::NUM_BANDS`).
  final int multibandCompressorBands;

  /// Lowest channel count the channel manager accepts, inclusive.
  final int minChannelManagerChannels;

  /// Highest channel count the channel manager accepts, inclusive
  /// (`ChannelManager::MAX_CHANNELS`).
  final int maxChannelManagerChannels;

  /// Longest per-channel delay the channel manager can apply, in milliseconds
  /// (`ChannelManager::MAX_DELAY_MS`).
  final int maxChannelManagerDelayMs;

  /// Hard ceiling on a user-supplied convolution impulse response, in samples
  /// across all channels (`AudioEffectsPlugin.MAX_IR_SAMPLES`).
  final int maxIrSamples;

  /// Length ceiling for a convolution impulse response, in seconds
  /// (`pulsr::kMaxIrSeconds` in `IrBounds.h`).
  final int maxIrSeconds;

  /// DSD multiples the native decoder accepts (`DsdDecoder::DsdRate`):
  /// 64, 128, 256 and 512, i.e. DSD64 through DSD512.
  final List<int> dsdDecodeRates;

  /// PCM rate the decoder targets when the caller does not ask for one
  /// (`DsdDecoder::configure` default parameter).
  final int dsdDefaultPcmSampleRate;

  /// Highest PCM sample rate anywhere in the pipeline, in hertz
  /// (`ChannelManager::MAX_SAMPLE_RATE`, also the DSD decode clamp).
  final int maxPcmSampleRate;

  /// DoP carrier rate per DSD multiple (`pulsr::DopPcmSampleRate`). DSD512 is
  /// deliberately absent: DoP v1.1 cannot carry it, so it decodes to PCM or
  /// goes out as native DSD instead.
  final Map<int, int> dopCarrierRates;

  /// First DoP marker byte (`pulsr::kDopMarkerA`).
  final int dopMarkerA;

  /// Second (alternating) DoP marker byte (`pulsr::kDopMarkerB`).
  final int dopMarkerB;

  /// USB Audio Class wire formats this build can pack, in subslot order.
  final List<String> usbWireFormats;

  /// Subslot width in bytes for each entry of [usbWireFormats]
  /// (2, 3, 4 -> S16_LE, S24_3LE, S32_LE).
  final List<int> usbSubslotBytes;

  /// Valid bit depths accepted inside a USB subslot.
  final List<int> usbValidBitDepths;

  /// AAudio sample encodings, in the order declared by `AAudioSink::Encoding`.
  final List<String> aaudioEncodings;

  /// Numeric `AAudioSink::Encoding` values, keyed by the names in
  /// [aaudioEncodings].
  final Map<String, int> aaudioEncodingIds;

  /// Largest DSD buffer the JNI bridge will accept, in bytes
  /// (`AudioEffectsPlugin.MAX_DSD_BUFFER_BYTES`).
  final int maxDsdBufferBytes;

  /// Whether this build can actually send raw DSD to a DAC.
  ///
  /// Decoding DSD to PCM and DoP framing are separate capabilities and stay
  /// available either way. This flag is about the producer that opens a
  /// DSD_U32 alternate setting and writes 1-bit frames to the USB sink: the
  /// sink side exists and is unit-tested, but nothing pumps frames into it yet,
  /// so advertising native output would be a claim the app cannot honour.
  /// Mirrors `kNativeDsdProducerAvailable` in `dsd_decoder_helper.dart`.
  final bool nativeDsdProducerAvailable;

  /// The matrix for this build. Verified field by field against the native and
  /// Kotlin sources by the architecture guard test.
  static const AudioCapabilityMatrix current = AudioCapabilityMatrix(
    nativeDspStageCount: 20,
    nativeDspStages: <String>[
      'eq',
      'crossfeed',
      'reverb',
      'panner',
      'limiter',
      'resampler',
      'saturation',
      'width',
      'loudness',
      'crossover',
      'dyneq',
      'dither',
      'multiband_compressor',
      'dynamic_bass',
      'viper_ddc',
      'arbitrary_eq',
      'live_prog',
      'headphone_safety',
      'channel_manager',
      'dac_voicing',
    ],
    maxParametricEqBands: 64,
    maxDynamicEqBands: 8,
    multibandCompressorBands: 4,
    minChannelManagerChannels: 2,
    maxChannelManagerChannels: 8,
    maxChannelManagerDelayMs: 50,
    maxIrSamples: 2000000,
    maxIrSeconds: 10,
    dsdDecodeRates: <int>[64, 128, 256, 512],
    dsdDefaultPcmSampleRate: 176400,
    maxPcmSampleRate: 768000,
    dopCarrierRates: <int, int>{64: 176400, 128: 352800, 256: 705600},
    dopMarkerA: 0x05,
    dopMarkerB: 0xFA,
    usbWireFormats: <String>['s16_le', 's24_3le', 's32_le'],
    usbSubslotBytes: <int>[2, 3, 4],
    usbValidBitDepths: <int>[16, 24, 32],
    aaudioEncodings: <String>['int16', 'float', 'i24_packed', 'int32'],
    aaudioEncodingIds: <String, int>{
      'int16': 1,
      'float': 2,
      'i24_packed': 3,
      'int32': 4,
    },
    maxDsdBufferBytes: 8388608,
    nativeDsdProducerAvailable: true,
  );

  /// Markdown block embedded in `docs/FEATURE_MATRIX.md`.
  ///
  /// The docs guard regenerates this text from [current] and fails when the
  /// file disagrees, so a capability cannot be documented as present (or
  /// absent) without changing the matrix and the test that defends it.
  String toMarkdownSection() {
    final dsd = dsdDecodeRates.isEmpty
        ? 'none'
        : 'DSD${dsdDecodeRates.first}–DSD${dsdDecodeRates.last}';
    final dop = dopCarrierRates.values.join(' / ');
    final buffer = StringBuffer()
      ..writeln('<!-- BEGIN GENERATED CAPABILITY MATRIX -->')
      ..writeln('| Capability | This build |')
      ..writeln('| :--- | :--- |')
      ..writeln('| Native DSP stages | $nativeDspStageCount |')
      ..writeln('| Parametric EQ bands | $maxParametricEqBands |')
      ..writeln('| Dynamic EQ bands | $maxDynamicEqBands |')
      ..writeln('| Multiband compressor bands | $multibandCompressorBands |')
      ..writeln('| Channel manager | $minChannelManagerChannels–'
          '$maxChannelManagerChannels channels, $maxChannelManagerDelayMs ms '
          'max delay |')
      ..writeln('| Convolution IR | $maxIrSamples samples / $maxIrSeconds s |')
      ..writeln('| DSD decode | $dsd |')
      ..writeln('| DoP carriers | $dop Hz |')
      ..writeln('| Highest PCM rate | $maxPcmSampleRate Hz |')
      ..writeln('| USB wire formats | ${usbWireFormats.join(" / ")} |')
      ..writeln('| AAudio encodings | ${aaudioEncodings.join(" / ")} |')
      ..writeln('| Native DSD producer | '
          '${nativeDsdProducerAvailable ? "available" : "not available"} |')
      ..writeln('<!-- END GENERATED CAPABILITY MATRIX -->');
    return buffer.toString();
  }
}
