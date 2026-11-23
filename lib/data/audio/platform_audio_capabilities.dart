/// Tri-state support classification for platform audio and DSP capabilities.
///
/// Replaces ambiguous `bool` stubs on non-Android hosts so UI and services can
/// distinguish between full native support, platform unavailability, and
/// missing runtime permissions (such as USB host permission).
enum CapabilitySupport {
  /// Supported and usable on the current platform without additional prompts.
  supported,

  /// Unsupported on the current platform or hardware path.
  unsupported,

  /// Platform supports the feature once the user grants runtime permission.
  requiresPermission,
}

/// Typed capability matrix reported by [AudioEffectsChannel].
class PlatformAudioCapabilities {
  const PlatformAudioCapabilities({
    required this.nativeDsp,
    required this.eqBands,
    required this.warmupBuffer,
    required this.floatOutput,
    required this.hardwareOffload,
    required this.usbExclusiveDac,
    required this.aaudio,
    required this.spatializer,
    required this.bluetoothHiRes,
  });

  /// Full capability matrix for Android, factoring probed output/USB state.
  factory PlatformAudioCapabilities.detect({
    required bool isAndroid,
    bool floatOutputSupported = false,
    bool hardwareOffloadSupported = false,
    bool usbAttached = false,
    bool usbPermissionGranted = false,
    bool bluetoothHiResSupported = false,
    bool aaudioSupported = true,
    bool spatializerSupported = true,
  }) {
    if (!isAndroid) {
      return const PlatformAudioCapabilities(
        nativeDsp: CapabilitySupport.unsupported,
        eqBands: CapabilitySupport.unsupported,
        warmupBuffer: CapabilitySupport.unsupported,
        floatOutput: CapabilitySupport.unsupported,
        hardwareOffload: CapabilitySupport.unsupported,
        usbExclusiveDac: CapabilitySupport.unsupported,
        aaudio: CapabilitySupport.unsupported,
        spatializer: CapabilitySupport.unsupported,
        bluetoothHiRes: CapabilitySupport.unsupported,
      );
    }
    return PlatformAudioCapabilities(
      nativeDsp: CapabilitySupport.supported,
      eqBands: CapabilitySupport.supported,
      warmupBuffer: CapabilitySupport.supported,
      floatOutput: floatOutputSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
      hardwareOffload: hardwareOffloadSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
      usbExclusiveDac: !usbAttached || usbPermissionGranted
          ? CapabilitySupport.supported
          : CapabilitySupport.requiresPermission,
      aaudio: aaudioSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
      spatializer: spatializerSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
      bluetoothHiRes: bluetoothHiResSupported
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported,
    );
  }

  /// Native C++ DSP engine and JNI bridge availability.
  final CapabilitySupport nativeDsp;

  /// Hardware/native multi-band equalizer control updates.
  final CapabilitySupport eqBands;

  /// Warmup silence buffer submission prior to DSP transitions.
  final CapabilitySupport warmupBuffer;

  /// 32-bit float PCM output path support.
  final CapabilitySupport floatOutput;

  /// Direct / hardware audio offload support.
  final CapabilitySupport hardwareOffload;

  /// Direct USB-DAC exclusive transport claim capability.
  final CapabilitySupport usbExclusiveDac;

  /// Android AAudio low-latency/MMAP output path.
  final CapabilitySupport aaudio;

  /// Platform spatializer stage.
  final CapabilitySupport spatializer;

  /// High-resolution Bluetooth codec support (LDAC/aptX HD/etc.).
  final CapabilitySupport bluetoothHiRes;

  /// Convenience summary map for telemetry and diagnostics serialization.
  Map<String, String> toJson() => <String, String>{
        'nativeDsp': nativeDsp.name,
        'eqBands': eqBands.name,
        'warmupBuffer': warmupBuffer.name,
        'floatOutput': floatOutput.name,
        'hardwareOffload': hardwareOffload.name,
        'usbExclusiveDac': usbExclusiveDac.name,
        'aaudio': aaudio.name,
        'spatializer': spatializer.name,
        'bluetoothHiRes': bluetoothHiRes.name,
      };
}
