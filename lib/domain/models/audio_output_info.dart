// lib/domain/models/audio_output_info.dart

/// Value equality for lists whose elements implement `==`.
///
/// Importing `package:flutter/foundation.dart` here would drag Flutter into the
/// pure domain layer, so this model keeps a local, dependency-free helper.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Per-format direct-playback capability (from Android's
/// isDirectPlaybackSupported probe).
class AudioDirectFormat {
  final String encoding; // 'float' | '24' | '32'
  final int sampleRate;
  final bool supported;

  const AudioDirectFormat({
    required this.encoding,
    required this.sampleRate,
    required this.supported,
  });

  factory AudioDirectFormat.fromMap(Map<dynamic, dynamic> map) =>
      AudioDirectFormat(
        encoding: map['encoding'] as String? ?? '',
        sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 0,
        supported: (map['supported'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'encoding': encoding,
        'sampleRate': sampleRate,
        'supported': supported,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDirectFormat &&
          runtimeType == other.runtimeType &&
          encoding == other.encoding &&
          sampleRate == other.sampleRate &&
          supported == other.supported;

  @override
  int get hashCode => Object.hash(encoding, sampleRate, supported);
}

class AudioDeviceEntry {
  final int id;
  final String name;
  final int type;
  final String typeName;
  final bool isCurrent;

  /// The platform accepted an explicit routing request for this device. Distinct
  /// from [isCurrent]: on retail builds routing requests are refused, and the UI
  /// must not highlight a device the audio never moved to.
  final bool isPreferred;
  final List<int> sampleRates;
  final int maxBitDepth;
  final List<String> supportedEncodings;
  final List<int> channelCounts;
  final List<int> channelMasks;

  const AudioDeviceEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.typeName,
    required this.isCurrent,
    this.isPreferred = false,
    this.sampleRates = const <int>[],
    this.maxBitDepth = 0,
    this.supportedEncodings = const <String>[],
    this.channelCounts = const <int>[],
    this.channelMasks = const <int>[],
  });

  factory AudioDeviceEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawRates = map['sampleRates'];
    final rates = <int>[];
    if (rawRates is List) {
      for (final r in rawRates) {
        if (r is num) rates.add(r.toInt());
      }
    }
    final rawEncs = map['supportedEncodings'];
    final encs = <String>[];
    if (rawEncs is List) {
      for (final e in rawEncs) {
        if (e is String && e.isNotEmpty) encs.add(e);
      }
    }
    final rawChCounts = map['channelCounts'];
    final chCounts = <int>[];
    if (rawChCounts is List) {
      for (final c in rawChCounts) {
        if (c is num) chCounts.add(c.toInt());
      }
    }
    final rawChMasks = map['channelMasks'];
    final chMasks = <int>[];
    if (rawChMasks is List) {
      for (final m in rawChMasks) {
        if (m is num) chMasks.add(m.toInt());
      }
    }
    return AudioDeviceEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: (map['name'] as String?)?.trim() ?? 'Audio Device',
      type: (map['type'] as num?)?.toInt() ?? 0,
      typeName: (map['typeName'] as String?)?.trim() ?? 'Output Device',
      isCurrent: (map['isCurrent'] as bool?) ?? false,
      isPreferred: (map['isPreferred'] as bool?) ?? false,
      sampleRates: rates.isNotEmpty ? rates : const <int>[],
      maxBitDepth: (map['maxBitDepth'] as num?)?.toInt() ?? 0,
      supportedEncodings: encs.isNotEmpty ? encs : const <String>[],
      channelCounts: chCounts.isNotEmpty ? chCounts : const <int>[],
      channelMasks: chMasks.isNotEmpty ? chMasks : const <int>[],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'typeName': typeName,
        'isCurrent': isCurrent,
        'isPreferred': isPreferred,
        'sampleRates': sampleRates,
        'maxBitDepth': maxBitDepth,
        'supportedEncodings': supportedEncodings,
        'channelCounts': channelCounts,
        'channelMasks': channelMasks,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDeviceEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          typeName == other.typeName &&
          isCurrent == other.isCurrent &&
          isPreferred == other.isPreferred &&
          _listEquals(sampleRates, other.sampleRates) &&
          maxBitDepth == other.maxBitDepth &&
          _listEquals(supportedEncodings, other.supportedEncodings) &&
          _listEquals(channelCounts, other.channelCounts) &&
          _listEquals(channelMasks, other.channelMasks);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        type,
        typeName,
        isCurrent,
        isPreferred,
        Object.hashAll(sampleRates),
        maxBitDepth,
        Object.hashAll(supportedEncodings),
        Object.hashAll(channelCounts),
        Object.hashAll(channelMasks),
      );
}

class AudioOutputInfo {
  final String deviceName;
  final bool isUsbDac;
  final int sampleRate;
  final int pcmEncoding;
  final int bitDepth;
  final bool isBitPerfectActive;
  final bool isBitPerfectSupported;

  /// Native routed media to USB without claiming exclusive mixer attributes.
  final bool isDirectRouteFallback;
  final List<int> supportedSampleRates;
  final List<AudioDeviceEntry> availableDevices;
  final int targetSampleRate;
  final int targetBitDepth;

  final int? nativeSampleRate;
  final int? nativeFramesPerBuffer;

  // Extended for exclusive-for-all
  final bool isDirectSupported;
  final bool isOffloadSupported;
  final String? bitPerfectFailureReason;
  final String
      activeDeviceType; // usb/wired/ble/bluetooth/hearing_aid/hdmi/builtin
  final bool isBluetooth;

  /// Active route is an LE Audio sink. LC3 negotiation is owned by the platform,
  /// so none of the A2DP codec controls apply.
  final bool isLeAudio;
  final bool bleAudioPresent;

  /// What the decoder actually produced, not what the scanner tagged.
  /// A 24-bit ALAC in an .m4a container is routinely tagged 16-bit; the
  /// chain must judge the decoded depth or it would call a 16-bit output a
  /// verified match.
  final int decodedBitDepth;
  final int decodedSampleRate;
  final int decodedPcmEncoding;
  final int decodedChannelCount;

  /// The rate the sink actually opened (not the file tag, not the target).
  /// 0 means the platform did not report it, which can never be a verified
  /// format match.
  final int sinkSampleRate;

  /// The sink's true container depth, before any display collapsing.
  /// [bitDepth] stays the collapsed, user-facing value.
  final int sinkBitDepth;

  /// `AudioFormat.ENCODING_PCM_*` constant the sink opened, 0 if unprobed.
  final int sinkPcmEncoding;

  /// The decoder carries the source in float32 although the file is integer
  /// PCM, so the integer samples were re-quantised upstream of the sink.
  final bool floatCarrierDecodesSource;

  /// The native engine reported an integer bit-perfect bypass engaged on this
  /// route: the decoded integer samples reached the sink unmodified. This is an
  /// observation, never an inference from [sinkPcmEncoding] - an integer sink
  /// encoding says nothing about a float carrier or a gain stage ahead of it.
  final bool integerBypassActive;

  /// The user asked for Bit-Perfect. This is a request, not evidence: only the
  /// observed route can say whether the samples survived.
  final bool bitPerfectRequested;

  /// Number of active HAL/system (AudioEffect) stages on this route. Non-zero
  /// means the samples are altered after the app hands them over.
  final int halStagesActive;

  /// The vendor/OEM effect chain could not prove itself bypassed while a
  /// bypass was requested. [halStagesActive] only counts stages the app owns
  /// and can switch off; this flag covers the system chain it cannot, so an
  /// app-side toggle must never clear it.
  final bool systemEffectsCompromised;

  // Phase 4: output-path capability diagnostics
  final List<AudioDirectFormat> directFormats;
  final int usbAudioClass; // 0 = none/unknown, 1 = UAC1, 2 = UAC2, 3 = UAC3
  final String? usbDacLabel;

  // Bluetooth codec control (populated when isBluetooth == true)
  final String?
      btCodecName; // 'SBC' | 'AAC' | 'aptX' | 'aptX HD' | 'LDAC' | 'LC3'
  final int? btSampleRateHz; // 44100 / 48000 / 88200 / 96000
  final int? btBitDepth; // 16 / 24 / 32
  final int?
      btLdacQualityMode; // 0=Best Effort, 1=Mobile, 2=Standard, 3=Maximum (990kbps)
  /// Nominal (not measured) bitrate of the negotiated codec, null if unknown.
  final int? btEstimatedBitrateKbps;
  final bool canConfigureBluetooth;
  final bool btCodecConnected; // true when codec status was read successfully
  final bool
      btA2dpPresent; // true when A2DP device detected in audio routing (even without permission)
  final String?
      btReason; // 'permission_required' | 'proxy_initializing' | 'no_device_connected'
  final List<String> btSelectableCodecs;
  final List<String> btSupportedCodecs;
  final List<int> btSelectableSampleRates;
  final List<int> btSelectableBitDepths;
  final List<String> supportedEncodings;
  final List<int> supportedChannelCounts;
  final List<int> supportedChannelMasks;

  const AudioOutputInfo({
    required this.deviceName,
    required this.isUsbDac,
    required this.sampleRate,
    this.pcmEncoding = 0,
    required this.bitDepth,
    required this.isBitPerfectActive,
    this.isBitPerfectSupported = false,
    this.isDirectRouteFallback = false,
    this.supportedSampleRates = const <int>[],
    this.availableDevices = const [],
    this.targetSampleRate = 0,
    this.targetBitDepth = 0,
    this.nativeSampleRate,
    this.nativeFramesPerBuffer,
    this.isDirectSupported = false,
    this.isOffloadSupported = false,
    this.bitPerfectFailureReason,
    this.activeDeviceType = 'builtin',
    this.isBluetooth = false,
    this.isLeAudio = false,
    this.bleAudioPresent = false,
    this.decodedBitDepth = 0,
    this.decodedSampleRate = 0,
    this.decodedPcmEncoding = 0,
    this.decodedChannelCount = 2,
    this.sinkSampleRate = 0,
    this.sinkBitDepth = 0,
    this.sinkPcmEncoding = 0,
    this.floatCarrierDecodesSource = false,
    this.integerBypassActive = false,
    this.bitPerfectRequested = false,
    this.halStagesActive = 0,
    this.systemEffectsCompromised = false,
    this.directFormats = const [],
    this.usbAudioClass = 0,
    this.usbDacLabel,
    // BT codec
    this.btCodecName,
    this.btSampleRateHz,
    this.btBitDepth,
    this.btLdacQualityMode,
    this.btEstimatedBitrateKbps,
    this.canConfigureBluetooth = false,
    this.btCodecConnected = false,
    this.btA2dpPresent = false,
    this.btReason,
    this.btSelectableCodecs = const [],
    this.btSupportedCodecs = const [],
    this.btSelectableSampleRates = const [],
    this.btSelectableBitDepths = const [],
    this.supportedEncodings = const <String>[],
    this.supportedChannelCounts = const <int>[],
    this.supportedChannelMasks = const <int>[],
  });

  factory AudioOutputInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawRates = map['supportedSampleRates'];
    final rates = <int>[];
    if (rawRates is List) {
      for (final r in rawRates) {
        if (r is num) rates.add(r.toInt());
      }
    }

    final rawDevices = map['availableDevices'];
    final devices = <AudioDeviceEntry>[];
    if (rawDevices is List) {
      for (final d in rawDevices) {
        if (d is Map) devices.add(AudioDeviceEntry.fromMap(d));
      }
    }

    return AudioOutputInfo(
      deviceName:
          (map['deviceName'] as String?)?.trim() ?? 'Default Audio Output',
      isUsbDac: (map['isUsbDac'] as bool?) ?? false,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 0,
      pcmEncoding: (map['pcmEncoding'] as num?)?.toInt() ?? 0,
      bitDepth: (map['bitDepth'] as num?)?.toInt() ?? 0,
      isBitPerfectActive: (map['isBitPerfectActive'] as bool?) ?? false,
      isBitPerfectSupported: (map['isBitPerfectSupported'] as bool?) ?? false,
      isDirectRouteFallback: (map['isDirectRouteFallback'] as bool?) ?? false,
      supportedSampleRates: rates.isNotEmpty ? rates : const <int>[],
      availableDevices: devices,
      targetSampleRate: (map['targetSampleRate'] as num?)?.toInt() ?? 0,
      targetBitDepth: (map['targetBitDepth'] as num?)?.toInt() ?? 0,
      nativeSampleRate: (map['nativeSampleRate'] as num?)?.toInt(),
      nativeFramesPerBuffer: (map['nativeFramesPerBuffer'] as num?)?.toInt(),
      isDirectSupported: (map['isDirectSupported'] as bool?) ?? false,
      isOffloadSupported: (map['isOffloadSupported'] as bool?) ?? false,
      bitPerfectFailureReason: map['bitPerfectFailureReason'] as String?,
      activeDeviceType: (map['activeDeviceType'] as String?) ?? 'builtin',
      isBluetooth: (map['isBluetooth'] as bool?) ?? false,
      isLeAudio: (map['isLeAudio'] as bool?) ?? false,
      bleAudioPresent: (map['bleAudioPresent'] as bool?) ?? false,
      decodedBitDepth: (map['decodedBitDepth'] as num?)?.toInt() ?? 0,
      decodedSampleRate: (map['decodedSampleRate'] as num?)?.toInt() ?? 0,
      decodedPcmEncoding: (map['decodedPcmEncoding'] as num?)?.toInt() ?? 0,
      decodedChannelCount: (map['decodedChannelCount'] as num?)?.toInt() ?? 2,
      sinkSampleRate: (map['sinkSampleRate'] as num?)?.toInt() ?? 0,
      sinkBitDepth: (map['sinkBitDepth'] as num?)?.toInt() ?? 0,
      sinkPcmEncoding: (map['sinkPcmEncoding'] as num?)?.toInt() ?? 0,
      floatCarrierDecodesSource:
          (map['floatCarrierDecodesSource'] as bool?) ?? false,
      integerBypassActive: (map['integerBypassActive'] as bool?) ?? false,
      bitPerfectRequested: (map['bitPerfectRequested'] as bool?) ?? false,
      halStagesActive: (map['halStagesActive'] as num?)?.toInt() ?? 0,
      systemEffectsCompromised:
          (map['systemEffectsCompromised'] as bool?) ?? false,
      directFormats: () {
        final raw = map['directFormats'];
        final out = <AudioDirectFormat>[];
        if (raw is List) {
          for (final d in raw) {
            if (d is Map) out.add(AudioDirectFormat.fromMap(d));
          }
        }
        return out;
      }(),
      usbAudioClass: (map['usbAudioClass'] as num?)?.toInt() ?? 0,
      usbDacLabel: map['usbDacLabel'] as String?,
      // BT codec fields
      btCodecName: map['btCodecName'] as String?,
      btSampleRateHz: (map['btSampleRateHz'] as num?)?.toInt(),
      btBitDepth: (map['btBitDepth'] as num?)?.toInt(),
      btLdacQualityMode: (map['btLdacQualityMode'] as num?)?.toInt(),
      btEstimatedBitrateKbps: (map['btEstimatedBitrateKbps'] as num?)?.toInt(),
      canConfigureBluetooth: map['canConfigureBluetooth'] == true,
      btCodecConnected: (map['btCodecConnected'] as bool?) ?? false,
      btA2dpPresent: (map['btA2dpPresent'] as bool?) ?? false,
      btReason: map['btReason'] as String?,
      btSelectableCodecs: () {
        final raw = map['btSelectableCodecs'];
        return (raw is List)
            ? raw.whereType<String>().toList()
            : const <String>[];
      }(),
      btSupportedCodecs: () {
        final raw = map['btSupportedCodecs'];
        return (raw is List)
            ? raw.whereType<String>().toList()
            : const <String>[];
      }(),
      btSelectableSampleRates: () {
        final raw = map['btSelectableSampleRates'];
        return (raw is List)
            ? raw.whereType<num>().map((n) => n.toInt()).toList()
            : const <int>[];
      }(),
      btSelectableBitDepths: () {
        final raw = map['btSelectableBitDepths'];
        return (raw is List)
            ? raw.whereType<num>().map((n) => n.toInt()).toList()
            : const <int>[];
      }(),
      supportedEncodings: () {
        final raw = map['supportedEncodings'];
        return (raw is List)
            ? raw.whereType<String>().toList()
            : const <String>[];
      }(),
      supportedChannelCounts: () {
        final raw = map['supportedChannelCounts'];
        return (raw is List)
            ? raw.whereType<num>().map((n) => n.toInt()).toList()
            : const <int>[];
      }(),
      supportedChannelMasks: () {
        final raw = map['supportedChannelMasks'];
        return (raw is List)
            ? raw.whereType<num>().map((n) => n.toInt()).toList()
            : const <int>[];
      }(),
    );
  }

  bool get isUsb => isUsbDac || activeDeviceType == 'usb';

  bool get isBt =>
      isBluetooth ||
      isLeAudio ||
      bleAudioPresent ||
      activeDeviceType == 'bluetooth' ||
      activeDeviceType == 'ble' ||
      activeDeviceType == 'hearing_aid';

  bool get isHeadphones =>
      activeDeviceType == 'wired' ||
      activeDeviceType == 'wired_headset' ||
      activeDeviceType == 'headphones';

  bool get isSpeaker =>
      activeDeviceType == 'builtin' ||
      activeDeviceType == 'speaker' ||
      activeDeviceType == 'builtin_speaker';

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'isUsbDac': isUsbDac,
      'sampleRate': sampleRate,
      'pcmEncoding': pcmEncoding,
      'bitDepth': bitDepth,
      'isBitPerfectActive': isBitPerfectActive,
      'isBitPerfectSupported': isBitPerfectSupported,
      'isDirectRouteFallback': isDirectRouteFallback,
      'supportedSampleRates': supportedSampleRates,
      'availableDevices': availableDevices.map((d) => d.toMap()).toList(),
      'targetSampleRate': targetSampleRate,
      'targetBitDepth': targetBitDepth,
      'nativeSampleRate': nativeSampleRate,
      'nativeFramesPerBuffer': nativeFramesPerBuffer,
      'isDirectSupported': isDirectSupported,
      'isOffloadSupported': isOffloadSupported,
      'bitPerfectFailureReason': bitPerfectFailureReason,
      'activeDeviceType': activeDeviceType,
      'isBluetooth': isBluetooth,
      'isLeAudio': isLeAudio,
      'bleAudioPresent': bleAudioPresent,
      'decodedBitDepth': decodedBitDepth,
      'decodedSampleRate': decodedSampleRate,
      'decodedPcmEncoding': decodedPcmEncoding,
      'decodedChannelCount': decodedChannelCount,
      'sinkSampleRate': sinkSampleRate,
      'sinkBitDepth': sinkBitDepth,
      'sinkPcmEncoding': sinkPcmEncoding,
      'floatCarrierDecodesSource': floatCarrierDecodesSource,
      'integerBypassActive': integerBypassActive,
      'bitPerfectRequested': bitPerfectRequested,
      'halStagesActive': halStagesActive,
      'systemEffectsCompromised': systemEffectsCompromised,
      'directFormats': directFormats.map((d) => d.toMap()).toList(),
      'usbAudioClass': usbAudioClass,
      'usbDacLabel': usbDacLabel,
      'btCodecName': btCodecName,
      'btSampleRateHz': btSampleRateHz,
      'btBitDepth': btBitDepth,
      'btLdacQualityMode': btLdacQualityMode,
      'btEstimatedBitrateKbps': btEstimatedBitrateKbps,
      'canConfigureBluetooth': canConfigureBluetooth,
      'btCodecConnected': btCodecConnected,
      'btA2dpPresent': btA2dpPresent,
      'btReason': btReason,
      'btSelectableCodecs': btSelectableCodecs,
      'btSupportedCodecs': btSupportedCodecs,
      'btSelectableSampleRates': btSelectableSampleRates,
      'btSelectableBitDepths': btSelectableBitDepths,
      'supportedEncodings': supportedEncodings,
      'supportedChannelCounts': supportedChannelCounts,
      'supportedChannelMasks': supportedChannelMasks,
    };
  }

  AudioOutputInfo copyWith({
    String? deviceName,
    bool? isUsbDac,
    int? sampleRate,
    int? pcmEncoding,
    int? bitDepth,
    bool? isBitPerfectActive,
    bool? isBitPerfectSupported,
    bool? isDirectRouteFallback,
    List<int>? supportedSampleRates,
    List<AudioDeviceEntry>? availableDevices,
    int? targetSampleRate,
    int? targetBitDepth,
    int? nativeSampleRate,
    int? nativeFramesPerBuffer,
    bool? isDirectSupported,
    bool? isOffloadSupported,
    String? bitPerfectFailureReason,
    String? activeDeviceType,
    bool? isBluetooth,
    bool? isLeAudio,
    bool? bleAudioPresent,
    int? decodedBitDepth,
    int? decodedSampleRate,
    int? decodedPcmEncoding,
    int? decodedChannelCount,
    int? sinkSampleRate,
    int? sinkBitDepth,
    int? sinkPcmEncoding,
    bool? floatCarrierDecodesSource,
    bool? integerBypassActive,
    bool? bitPerfectRequested,
    int? halStagesActive,
    bool? systemEffectsCompromised,
    List<AudioDirectFormat>? directFormats,
    int? usbAudioClass,
    String? usbDacLabel,
    String? btCodecName,
    int? btSampleRateHz,
    int? btBitDepth,
    int? btLdacQualityMode,
    int? btEstimatedBitrateKbps,
    bool? canConfigureBluetooth,
    bool? btCodecConnected,
    bool? btA2dpPresent,
    String? btReason,
    List<String>? btSelectableCodecs,
    List<String>? btSupportedCodecs,
    List<int>? btSelectableSampleRates,
    List<int>? btSelectableBitDepths,
    List<String>? supportedEncodings,
    List<int>? supportedChannelCounts,
    List<int>? supportedChannelMasks,
  }) {
    return AudioOutputInfo(
      deviceName: deviceName ?? this.deviceName,
      isUsbDac: isUsbDac ?? this.isUsbDac,
      sampleRate: sampleRate ?? this.sampleRate,
      pcmEncoding: pcmEncoding ?? this.pcmEncoding,
      bitDepth: bitDepth ?? this.bitDepth,
      isBitPerfectActive: isBitPerfectActive ?? this.isBitPerfectActive,
      isBitPerfectSupported:
          isBitPerfectSupported ?? this.isBitPerfectSupported,
      isDirectRouteFallback:
          isDirectRouteFallback ?? this.isDirectRouteFallback,
      supportedSampleRates: supportedSampleRates ?? this.supportedSampleRates,
      availableDevices: availableDevices ?? this.availableDevices,
      targetSampleRate: targetSampleRate ?? this.targetSampleRate,
      targetBitDepth: targetBitDepth ?? this.targetBitDepth,
      nativeSampleRate: nativeSampleRate ?? this.nativeSampleRate,
      nativeFramesPerBuffer:
          nativeFramesPerBuffer ?? this.nativeFramesPerBuffer,
      isDirectSupported: isDirectSupported ?? this.isDirectSupported,
      isOffloadSupported: isOffloadSupported ?? this.isOffloadSupported,
      bitPerfectFailureReason:
          bitPerfectFailureReason ?? this.bitPerfectFailureReason,
      activeDeviceType: activeDeviceType ?? this.activeDeviceType,
      isBluetooth: isBluetooth ?? this.isBluetooth,
      isLeAudio: isLeAudio ?? this.isLeAudio,
      bleAudioPresent: bleAudioPresent ?? this.bleAudioPresent,
      decodedBitDepth: decodedBitDepth ?? this.decodedBitDepth,
      decodedSampleRate: decodedSampleRate ?? this.decodedSampleRate,
      decodedPcmEncoding: decodedPcmEncoding ?? this.decodedPcmEncoding,
      decodedChannelCount: decodedChannelCount ?? this.decodedChannelCount,
      sinkSampleRate: sinkSampleRate ?? this.sinkSampleRate,
      sinkBitDepth: sinkBitDepth ?? this.sinkBitDepth,
      sinkPcmEncoding: sinkPcmEncoding ?? this.sinkPcmEncoding,
      floatCarrierDecodesSource:
          floatCarrierDecodesSource ?? this.floatCarrierDecodesSource,
      integerBypassActive: integerBypassActive ?? this.integerBypassActive,
      bitPerfectRequested: bitPerfectRequested ?? this.bitPerfectRequested,
      halStagesActive: halStagesActive ?? this.halStagesActive,
      systemEffectsCompromised:
          systemEffectsCompromised ?? this.systemEffectsCompromised,
      directFormats: directFormats ?? this.directFormats,
      usbAudioClass: usbAudioClass ?? this.usbAudioClass,
      usbDacLabel: usbDacLabel ?? this.usbDacLabel,
      btCodecName: btCodecName ?? this.btCodecName,
      btSampleRateHz: btSampleRateHz ?? this.btSampleRateHz,
      btBitDepth: btBitDepth ?? this.btBitDepth,
      btLdacQualityMode: btLdacQualityMode ?? this.btLdacQualityMode,
      btEstimatedBitrateKbps:
          btEstimatedBitrateKbps ?? this.btEstimatedBitrateKbps,
      canConfigureBluetooth:
          canConfigureBluetooth ?? this.canConfigureBluetooth,
      btCodecConnected: btCodecConnected ?? this.btCodecConnected,
      btA2dpPresent: btA2dpPresent ?? this.btA2dpPresent,
      btReason: btReason ?? this.btReason,
      btSelectableCodecs: btSelectableCodecs ?? this.btSelectableCodecs,
      btSupportedCodecs: btSupportedCodecs ?? this.btSupportedCodecs,
      btSelectableSampleRates:
          btSelectableSampleRates ?? this.btSelectableSampleRates,
      btSelectableBitDepths:
          btSelectableBitDepths ?? this.btSelectableBitDepths,
      supportedEncodings: supportedEncodings ?? this.supportedEncodings,
      supportedChannelCounts:
          supportedChannelCounts ?? this.supportedChannelCounts,
      supportedChannelMasks:
          supportedChannelMasks ?? this.supportedChannelMasks,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioOutputInfo &&
          runtimeType == other.runtimeType &&
          deviceName == other.deviceName &&
          isUsbDac == other.isUsbDac &&
          sampleRate == other.sampleRate &&
          pcmEncoding == other.pcmEncoding &&
          bitDepth == other.bitDepth &&
          isBitPerfectActive == other.isBitPerfectActive &&
          isBitPerfectSupported == other.isBitPerfectSupported &&
          isDirectRouteFallback == other.isDirectRouteFallback &&
          _listEquals(supportedSampleRates, other.supportedSampleRates) &&
          _listEquals(availableDevices, other.availableDevices) &&
          targetSampleRate == other.targetSampleRate &&
          targetBitDepth == other.targetBitDepth &&
          nativeSampleRate == other.nativeSampleRate &&
          nativeFramesPerBuffer == other.nativeFramesPerBuffer &&
          isDirectSupported == other.isDirectSupported &&
          isOffloadSupported == other.isOffloadSupported &&
          bitPerfectFailureReason == other.bitPerfectFailureReason &&
          activeDeviceType == other.activeDeviceType &&
          isBluetooth == other.isBluetooth &&
          isLeAudio == other.isLeAudio &&
          bleAudioPresent == other.bleAudioPresent &&
          decodedBitDepth == other.decodedBitDepth &&
          decodedSampleRate == other.decodedSampleRate &&
          decodedPcmEncoding == other.decodedPcmEncoding &&
          sinkSampleRate == other.sinkSampleRate &&
          sinkBitDepth == other.sinkBitDepth &&
          sinkPcmEncoding == other.sinkPcmEncoding &&
          floatCarrierDecodesSource == other.floatCarrierDecodesSource &&
          integerBypassActive == other.integerBypassActive &&
          bitPerfectRequested == other.bitPerfectRequested &&
          halStagesActive == other.halStagesActive &&
          systemEffectsCompromised == other.systemEffectsCompromised &&
          _listEquals(directFormats, other.directFormats) &&
          usbAudioClass == other.usbAudioClass &&
          usbDacLabel == other.usbDacLabel &&
          btCodecName == other.btCodecName &&
          btSampleRateHz == other.btSampleRateHz &&
          btBitDepth == other.btBitDepth &&
          btLdacQualityMode == other.btLdacQualityMode &&
          btEstimatedBitrateKbps == other.btEstimatedBitrateKbps &&
          canConfigureBluetooth == other.canConfigureBluetooth &&
          btCodecConnected == other.btCodecConnected &&
          btA2dpPresent == other.btA2dpPresent &&
          btReason == other.btReason &&
          _listEquals(btSelectableCodecs, other.btSelectableCodecs) &&
          _listEquals(btSupportedCodecs, other.btSupportedCodecs) &&
          _listEquals(btSelectableSampleRates, other.btSelectableSampleRates) &&
          _listEquals(btSelectableBitDepths, other.btSelectableBitDepths) &&
          _listEquals(supportedEncodings, other.supportedEncodings) &&
          _listEquals(supportedChannelCounts, other.supportedChannelCounts) &&
          _listEquals(supportedChannelMasks, other.supportedChannelMasks);

  @override
  int get hashCode => Object.hashAll([
        deviceName,
        isUsbDac,
        sampleRate,
        pcmEncoding,
        bitDepth,
        isBitPerfectActive,
        isBitPerfectSupported,
        isDirectRouteFallback,
        Object.hashAll(supportedSampleRates),
        Object.hashAll(availableDevices),
        targetSampleRate,
        targetBitDepth,
        nativeSampleRate,
        nativeFramesPerBuffer,
        isDirectSupported,
        isOffloadSupported,
        bitPerfectFailureReason,
        activeDeviceType,
        isBluetooth,
        isLeAudio,
        bleAudioPresent,
        decodedBitDepth,
        decodedSampleRate,
        decodedPcmEncoding,
        sinkSampleRate,
        sinkBitDepth,
        sinkPcmEncoding,
        floatCarrierDecodesSource,
        integerBypassActive,
        bitPerfectRequested,
        halStagesActive,
        systemEffectsCompromised,
        Object.hashAll(directFormats),
        usbAudioClass,
        usbDacLabel,
        btCodecName,
        btSampleRateHz,
        btBitDepth,
        btLdacQualityMode,
        btEstimatedBitrateKbps,
        canConfigureBluetooth,
        btCodecConnected,
        btA2dpPresent,
        btReason,
        Object.hashAll(btSelectableCodecs),
        Object.hashAll(btSupportedCodecs),
        Object.hashAll(btSelectableSampleRates),
        Object.hashAll(btSelectableBitDepths),
        Object.hashAll(supportedEncodings),
        Object.hashAll(supportedChannelCounts),
        Object.hashAll(supportedChannelMasks),
      ]);

  /// True when the current device or the stream decoding pipeline supports > 2 channels.
  bool get hasMultichannelOutput =>
      supportedChannelCounts.any((c) => c > 2) ||
      decodedChannelCount > 2 ||
      availableDevices.any((d) => d.isCurrent && d.channelCounts.any((c) => c > 2));

  @override
  String toString() {
    return 'AudioOutputInfo(name: $deviceName, isUsbDac: $isUsbDac, '
        'sampleRate: ${sampleRate}Hz, bitDepth: $bitDepth-bit, '
        'sink: ${sinkSampleRate}Hz/$sinkBitDepth-bit '
        '(enc $sinkPcmEncoding), '
        'decoder: ${decodedSampleRate}Hz/$decodedBitDepth-bit '
        '(enc $decodedPcmEncoding), '
        'bitPerfectRequested: $bitPerfectRequested, '
        'bitPerfectActive: $isBitPerfectActive, '
        'integerBypass: $integerBypassActive, '
        'halStagesActive: $halStagesActive, '
        'systemEffectsCompromised: $systemEffectsCompromised)';
  }
}
