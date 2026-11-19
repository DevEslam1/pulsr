// lib/data/audio/decoder_capability_registry.dart
//
// What this build can *actually* decode, stated per format instead of implied
// by a scanner allow-list. The distinction matters: `AudioFormats` answers
// "should this file enter the library?", this registry answers "can we decode
// it once the user presses play?".
//
// Ground truth for this build:
//   * FLAC is bundled (vendored libFLAC in `third_party/media3-flac-decoder`).
//   * DSD (dsf/dff) is bundled through the native C++ decoder.
//   * SACD ISO is bundled through the extractor that turns a disc image into
//     DSF tracks.
//   * WAV/AIFF/MP3/AAC/Opus/Vorbis/WebM/Matroska are platform (Media3)
//     decoders, which exist on the device but must be probed for the concrete
//     codec before playback can be promised.
//   * ALAC is probe-required: Media3 ships no ALAC decoder, so an .m4a holding
//     ALAC only plays when the platform happens to expose one.
//   * APE/WavPack/TTA/TAK/WMA/MPC/MOD/IT/XM/S3M have no decoder in this build.
//
// This file is pure data and lookup logic: no I/O, no plugin calls, no globals
// that change at runtime.

/// How a format reaches decoded audio in this build.
enum DecoderSupport {
  /// The decoder ships with the app, so playback does not depend on the device.
  bundled,

  /// A platform (Media3) decoder may exist, but only for some codecs; the
  /// concrete codec inside the container must be probed before promising
  /// playback.
  platformProbeRequired,

  /// Recognized as audio, but no decoder ships in this build. The file must
  /// never be handed to a player.
  notBundled,
}

/// The decode contract for one format.
class DecoderCapability {
  /// Creates a capability entry. Every field is required so a new format
  /// cannot be added with an unstated support level.
  const DecoderCapability({
    required this.extension,
    required this.displayName,
    required this.support,
    required this.reasonCode,
  });

  /// Canonical lower-case extension without the leading dot.
  final String extension;

  /// Human-readable format name for diagnostics and settings surfaces.
  final String displayName;

  /// Whether this build can decode the format.
  final DecoderSupport support;

  /// Stable machine-readable justification, e.g. `decoder_not_bundled`.
  final String reasonCode;

  /// Whether playback can be attempted at all.
  ///
  /// True for [DecoderSupport.bundled] and
  /// [DecoderSupport.platformProbeRequired]: the latter may still fail after
  /// the codec probe, but refusing it up front would be wrong. False only for
  /// [DecoderSupport.notBundled].
  bool get isPlayable => support != DecoderSupport.notBundled;
}

/// Lookup table of [DecoderCapability] entries, keyed by extension or MIME type.
abstract final class DecoderCapabilityRegistry {
  /// Reason code: FLAC is decoded by the vendored libFLAC module.
  static const String reasonBundledFlac = 'bundled_libflac';

  /// Reason code: DSD is decoded by the native C++ DSD decoder.
  static const String reasonBundledNativeDsd = 'bundled_native_dsd_decoder';

  /// Reason code: a SACD ISO is unpacked by the bundled extractor first.
  static const String reasonBundledSacdExtractor = 'bundled_sacd_extractor';

  /// Reason code: a platform (Media3) decoder is expected to exist.
  static const String reasonPlatformDecoder = 'media3_platform_decoder';

  /// Reason code: the container's codec must be probed before playback.
  static const String reasonPlatformProbe = 'media3_codec_probe_required';

  /// Reason code: Media3 ships no ALAC decoder, so the platform must provide one.
  static const String reasonNoAlacDecoder = 'media3_no_alac_decoder';

  /// Reason code: recognized audio format with no decoder in this build.
  static const String reasonNotBundled = 'decoder_not_bundled';

  /// Reason code: not an audio format this build recognizes at all.
  static const String reasonUnknownExtension = 'unknown_extension';

  /// Every format this build recognizes, including the ones it cannot decode.
  ///
  /// Ordered bundled-first so a diagnostic dump reads as a capability list.
  static const List<DecoderCapability> capabilities = <DecoderCapability>[
    // Bundled decoders.
    DecoderCapability(
      extension: 'flac',
      displayName: 'FLAC',
      support: DecoderSupport.bundled,
      reasonCode: reasonBundledFlac,
    ),
    DecoderCapability(
      extension: 'dsf',
      displayName: 'DSF (DSD)',
      support: DecoderSupport.bundled,
      reasonCode: reasonBundledNativeDsd,
    ),
    DecoderCapability(
      extension: 'dff',
      displayName: 'DFF (DSD)',
      support: DecoderSupport.bundled,
      reasonCode: reasonBundledNativeDsd,
    ),
    DecoderCapability(
      extension: 'iso',
      displayName: 'SACD ISO',
      support: DecoderSupport.bundled,
      reasonCode: reasonBundledSacdExtractor,
    ),
    // Platform / Media3 decoders.
    DecoderCapability(
      extension: 'wav',
      displayName: 'WAV',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'aiff',
      displayName: 'AIFF',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'aif',
      displayName: 'AIFF',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'mp3',
      displayName: 'MP3',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'aac',
      displayName: 'AAC',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'm4a',
      displayName: 'M4A',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformProbe,
    ),
    DecoderCapability(
      extension: 'alac',
      displayName: 'ALAC',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonNoAlacDecoder,
    ),
    DecoderCapability(
      extension: 'ogg',
      displayName: 'Ogg Vorbis',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'oga',
      displayName: 'Ogg Audio',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'opus',
      displayName: 'Opus',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformDecoder,
    ),
    DecoderCapability(
      extension: 'webm',
      displayName: 'WebM Audio',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformProbe,
    ),
    DecoderCapability(
      extension: 'mka',
      displayName: 'Matroska Audio',
      support: DecoderSupport.platformProbeRequired,
      reasonCode: reasonPlatformProbe,
    ),
    // Recognized, no decoder bundled.
    DecoderCapability(
      extension: 'ape',
      displayName: "Monkey's Audio (APE)",
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'wv',
      displayName: 'WavPack',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'tta',
      displayName: 'TTA',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'tak',
      displayName: 'TAK',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'wma',
      displayName: 'WMA',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'mpc',
      displayName: 'Musepack',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'mod',
      displayName: 'MOD',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'it',
      displayName: 'Impulse Tracker',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 'xm',
      displayName: 'FastTracker II (XM)',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
    DecoderCapability(
      extension: 's3m',
      displayName: 'Scream Tracker 3',
      support: DecoderSupport.notBundled,
      reasonCode: reasonNotBundled,
    ),
  ];

  /// MIME types mapped onto the canonical extension. Container MIME types with
  /// a codec parameter (`audio/mp4; codecs=alac`) resolve through their base
  /// type after the parameter is stripped.
  static const Map<String, String> _mimeAliases = <String, String>{
    'audio/flac': 'flac',
    'audio/x-flac': 'flac',
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/mp4': 'm4a',
    'audio/m4a': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'audio/aacp': 'aac',
    'audio/wav': 'wav',
    'audio/wave': 'wav',
    'audio/x-wav': 'wav',
    'audio/aiff': 'aiff',
    'audio/x-aiff': 'aiff',
    'audio/ogg': 'ogg',
    'application/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/webm': 'webm',
    'audio/x-matroska': 'mka',
    'audio/matroska': 'mka',
    'audio/dsd': 'dsf',
    'audio/x-dsf': 'dsf',
    'audio/x-dff': 'dff',
    'audio/alac': 'alac',
    'audio/x-alac': 'alac',
    'audio/x-ape': 'ape',
    'audio/wavpack': 'wv',
    'audio/x-wavpack': 'wv',
    'audio/x-tta': 'tta',
    'audio/x-tak': 'tak',
    'audio/x-ms-wma': 'wma',
    'audio/x-musepack': 'mpc',
    'audio/x-mod': 'mod',
    'audio/x-it': 'it',
    'audio/x-xm': 'xm',
    'audio/x-s3m': 's3m',
  };

  static final Map<String, DecoderCapability> _byExtension = () {
    final map = <String, DecoderCapability>{};
    for (final capability in capabilities) {
      map[capability.extension] = capability;
    }
    return map;
  }();

  /// Normalizes a path, bare extension, dotted extension or MIME type to the
  /// canonical lower-case extension used as the registry key.
  ///
  /// Returns an empty string when nothing usable remains.
  static String normalize(String extensionOrMime) {
    var value = extensionOrMime.trim().toLowerCase();
    if (value.isEmpty) return '';
    final parameters = value.indexOf(';');
    if (parameters >= 0) value = value.substring(0, parameters).trim();
    final alias = _mimeAliases[value];
    if (alias != null) return alias;

    final lastForward = value.lastIndexOf('/');
    final lastBackward = value.lastIndexOf(r'\');
    final lastSeparator = lastForward > lastBackward ? lastForward : lastBackward;
    final name = lastSeparator >= 0 ? value.substring(lastSeparator + 1) : value;
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) return name.substring(dot + 1);
    return name;
  }

  /// Returns the entry for [extensionOrMime], or null when the format is not
  /// in the registry at all.
  ///
  /// Use this when the caller must distinguish "recognized but undecodable"
  /// from "not an audio format we know". [capabilityFor] never returns null.
  static DecoderCapability? lookup(String extensionOrMime) {
    return _byExtension[normalize(extensionOrMime)];
  }

  /// Returns the entry for [extensionOrMime], falling back to a
  /// [DecoderSupport.notBundled] entry for anything unrecognized.
  ///
  /// The fallback is deliberate: an unknown extension must fail closed, never
  /// be treated as playable by omission.
  static DecoderCapability capabilityFor(String extensionOrMime) {
    final key = normalize(extensionOrMime);
    final known = _byExtension[key];
    if (known != null) return known;
    return DecoderCapability(
      extension: key,
      displayName: key.isEmpty ? 'Unknown' : 'Unknown ($key)',
      support: DecoderSupport.notBundled,
      reasonCode: reasonUnknownExtension,
    );
  }

  /// Support level for [extensionOrMime]; never null.
  static DecoderSupport supportFor(String extensionOrMime) =>
      capabilityFor(extensionOrMime).support;

  /// Whether playback may be attempted for [extensionOrMime].
  ///
  /// Agrees with `supportFor(...) != DecoderSupport.notBundled` by
  /// construction.
  static bool isPlayable(String extensionOrMime) =>
      capabilityFor(extensionOrMime).isPlayable;

  /// Stable reason code for [extensionOrMime], or null when the format is
  /// bundled and therefore needs no justification.
  static String? reasonCodeFor(String extensionOrMime) {
    final capability = capabilityFor(extensionOrMime);
    if (capability.support == DecoderSupport.bundled) return null;
    return capability.reasonCode;
  }
}
