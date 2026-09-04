// lib/domain/models/audio_output_info.dart

class AudioDeviceEntry {
  final int id;
  final String name;
  final int type;
  final String typeName;
  final bool isCurrent;
  final List<int> sampleRates;
  final int maxBitDepth;

  const AudioDeviceEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.typeName,
    required this.isCurrent,
    this.sampleRates = const [44100, 48000],
    this.maxBitDepth = 16,
  });

  factory AudioDeviceEntry.fromMap(Map<dynamic, dynamic> map) {
    final rawRates = map['sampleRates'];
    final rates = <int>[];
    if (rawRates is List) {
      for (final r in rawRates) {
        if (r is num) rates.add(r.toInt());
      }
    }
    return AudioDeviceEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: (map['name'] as String?)?.trim() ?? 'Audio Device',
      type: (map['type'] as num?)?.toInt() ?? 0,
      typeName: (map['typeName'] as String?)?.trim() ?? 'Output Device',
      isCurrent: (map['isCurrent'] as bool?) ?? false,
      sampleRates: rates.isNotEmpty ? rates : const [44100, 48000],
      maxBitDepth: (map['maxBitDepth'] as num?)?.toInt() ?? 16,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'typeName': typeName,
        'isCurrent': isCurrent,
        'sampleRates': sampleRates,
        'maxBitDepth': maxBitDepth,
      };
}

class AudioOutputInfo {
  final String deviceName;
  final bool isUsbDac;
  final int sampleRate;
  final int bitDepth;
  final bool isBitPerfectActive;
  final bool isBitPerfectSupported;
  final List<int> supportedSampleRates;
  final List<AudioDeviceEntry> availableDevices;
  final int targetSampleRate;
  final int targetBitDepth;

  final int? nativeSampleRate;
  final int? nativeFramesPerBuffer;

  const AudioOutputInfo({
    required this.deviceName,
    required this.isUsbDac,
    required this.sampleRate,
    required this.bitDepth,
    required this.isBitPerfectActive,
    this.isBitPerfectSupported = false,
    this.supportedSampleRates = const [44100, 48000],
    this.availableDevices = const [],
    this.targetSampleRate = 0,
    this.targetBitDepth = 0,
    this.nativeSampleRate,
    this.nativeFramesPerBuffer,
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
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 44100,
      bitDepth: (map['bitDepth'] as num?)?.toInt() ?? 16,
      isBitPerfectActive: (map['isBitPerfectActive'] as bool?) ?? false,
      isBitPerfectSupported: (map['isBitPerfectSupported'] as bool?) ?? false,
      supportedSampleRates: rates.isNotEmpty ? rates : const [44100, 48000],
      availableDevices: devices,
      targetSampleRate: (map['targetSampleRate'] as num?)?.toInt() ?? 0,
      targetBitDepth: (map['targetBitDepth'] as num?)?.toInt() ?? 0,
      nativeSampleRate: (map['nativeSampleRate'] as num?)?.toInt(),
      nativeFramesPerBuffer: (map['nativeFramesPerBuffer'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'isUsbDac': isUsbDac,
      'sampleRate': sampleRate,
      'bitDepth': bitDepth,
      'isBitPerfectActive': isBitPerfectActive,
      'isBitPerfectSupported': isBitPerfectSupported,
      'supportedSampleRates': supportedSampleRates,
      'availableDevices': availableDevices.map((d) => d.toMap()).toList(),
      'targetSampleRate': targetSampleRate,
      'targetBitDepth': targetBitDepth,
    };
  }

  AudioOutputInfo copyWith({
    String? deviceName,
    bool? isUsbDac,
    int? sampleRate,
    int? bitDepth,
    bool? isBitPerfectActive,
    bool? isBitPerfectSupported,
    List<int>? supportedSampleRates,
    List<AudioDeviceEntry>? availableDevices,
    int? targetSampleRate,
    int? targetBitDepth,
  }) {
    return AudioOutputInfo(
      deviceName: deviceName ?? this.deviceName,
      isUsbDac: isUsbDac ?? this.isUsbDac,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      isBitPerfectActive: isBitPerfectActive ?? this.isBitPerfectActive,
      isBitPerfectSupported:
          isBitPerfectSupported ?? this.isBitPerfectSupported,
      supportedSampleRates: supportedSampleRates ?? this.supportedSampleRates,
      availableDevices: availableDevices ?? this.availableDevices,
      targetSampleRate: targetSampleRate ?? this.targetSampleRate,
      targetBitDepth: targetBitDepth ?? this.targetBitDepth,
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
          bitDepth == other.bitDepth &&
          targetSampleRate == other.targetSampleRate &&
          targetBitDepth == other.targetBitDepth &&
          isBitPerfectActive == other.isBitPerfectActive &&
          isBitPerfectSupported == other.isBitPerfectSupported;

  @override
  int get hashCode =>
      deviceName.hashCode ^
      isUsbDac.hashCode ^
      sampleRate.hashCode ^
      bitDepth.hashCode ^
      targetSampleRate.hashCode ^
      targetBitDepth.hashCode ^
      isBitPerfectActive.hashCode ^
      isBitPerfectSupported.hashCode;

  @override
  String toString() {
    return 'AudioOutputInfo(name: $deviceName, isUsbDac: $isUsbDac, sampleRate: ${sampleRate}Hz, bitDepth: $bitDepth-bit, bitPerfect: $isBitPerfectActive)';
  }
}
