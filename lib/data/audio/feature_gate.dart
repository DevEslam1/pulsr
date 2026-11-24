// lib/data/audio/feature_gate.dart
//
// Centralized FeatureGate and Conflict/Precedence Matrix (Sections 5.2 & 9).
// Computes allowed/blocked decisions, refusal reasons, and localized explanations
// across UI sheets, audio handler, and backend seams.

import 'playback_backend.dart';

enum AudioFeature {
  dsp,
  bitPerfect,
  nativeDsd,
  dop,
  lowPower,
  hrtf,
  crossfeed,
  multichannel,
  softwareVolume,
  crossfade,
  replayGain,
}

enum FeatureBlockReason {
  none,
  remoteBackend,
  dsdDomain,
  bitPerfectExclusivity,
  lowPowerInterlock,
  hrtfCrossfeedExclusivity,
  unsupportedRoute,
  capabilityMissing,
}

class FeatureGateDecision {
  final bool isAllowed;
  final FeatureBlockReason reason;
  final String userMessage;

  const FeatureGateDecision.allowed()
      : isAllowed = true,
        reason = FeatureBlockReason.none,
        userMessage = '';

  const FeatureGateDecision.blocked({
    required this.reason,
    required this.userMessage,
  }) : isAllowed = false;

  bool get isBlocked => !isAllowed;
}

class FeatureGate {
  const FeatureGate();

  FeatureGateDecision evaluate(
    AudioFeature feature, {
    required BackendCapabilities backend,
    bool bitPerfectActive = false,
    bool dspActive = false,
    bool isDsdMode = false,
    bool lowPowerActive = false,
    bool hrtfActive = false,
    bool crossfeedActive = false,
    bool isBluetooth = false,
    int channels = 2,
    bool isAAudio = false,
  }) {
    // 1. Remote backend gating (Cast / UPnP): local DSP does not apply to original stream
    if (backend.isRemote) {
      if (feature == AudioFeature.dsp ||
          feature == AudioFeature.hrtf ||
          feature == AudioFeature.crossfeed) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.remoteBackend,
          userMessage: 'DSP is not applied to remote streaming devices.',
        );
      }
      if (feature == AudioFeature.softwareVolume && !backend.canSoftwareVolume) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.remoteBackend,
          userMessage: 'Software volume is controlled directly on the remote receiver.',
        );
      }
    }

    // 2. Native DSD / DoP bitstream domain: no PCM-domain DSP or software volume
    if ((feature == AudioFeature.nativeDsd || feature == AudioFeature.dop) &&
        dspActive) {
      return const FeatureGateDecision.blocked(
        reason: FeatureBlockReason.dsdDomain,
        userMessage:
            'Disable active DSP stages to stream native DSD or DoP bitstreams.',
      );
    }
    if (isDsdMode) {
      if (feature == AudioFeature.dsp ||
          feature == AudioFeature.hrtf ||
          feature == AudioFeature.crossfeed ||
          feature == AudioFeature.multichannel ||
          feature == AudioFeature.crossfade ||
          feature == AudioFeature.replayGain) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.dsdDomain,
          userMessage:
              'DSP, multichannel, crossfade, and ReplayGain cannot be processed in the 1-bit DSD domain.',
        );
      }
      if (feature == AudioFeature.softwareVolume &&
          !backend.canSoftwareVolume) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.dsdDomain,
          userMessage:
              'Direct DSD requires hardware DAC volume or fixed-volume mode.',
        );
      }
    }

    // 3. Bit-perfect exclusivity
    if (bitPerfectActive) {
      if (feature == AudioFeature.dsp ||
          feature == AudioFeature.hrtf ||
          feature == AudioFeature.crossfeed ||
          feature == AudioFeature.replayGain ||
          feature == AudioFeature.crossfade ||
          feature == AudioFeature.softwareVolume) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.bitPerfectExclusivity,
          userMessage:
              'Bit-perfect output requires an unaltered audio stream without DSP or software volume.',
        );
      }
    }

    // 4. Low-power interlock: mutually exclusive with active DSP stages
    if (feature == AudioFeature.lowPower && dspActive) {
      return const FeatureGateDecision.blocked(
        reason: FeatureBlockReason.lowPowerInterlock,
        userMessage:
            'Disable active DSP stages to engage hardware low-power bypass.',
      );
    }
    if (lowPowerActive &&
        (feature == AudioFeature.dsp ||
            feature == AudioFeature.hrtf ||
            feature == AudioFeature.crossfeed)) {
      return const FeatureGateDecision.blocked(
        reason: FeatureBlockReason.lowPowerInterlock,
        userMessage:
            'Enabling DSP stages automatically exits low-power mode.',
      );
    }

    // 6. HRTF and Crossfeed mutual exclusivity
    if (feature == AudioFeature.hrtf && crossfeedActive) {
      return const FeatureGateDecision.blocked(
        reason: FeatureBlockReason.hrtfCrossfeedExclusivity,
        userMessage: 'HRTF binaural rendering and crossfeed are mutually exclusive.',
      );
    }
    if (feature == AudioFeature.crossfeed && hrtfActive) {
      return const FeatureGateDecision.blocked(
        reason: FeatureBlockReason.hrtfCrossfeedExclusivity,
        userMessage: 'Crossfeed cannot be enabled while HRTF binaural rendering is active.',
      );
    }

    // 7. Multichannel constraints
    if (feature == AudioFeature.multichannel) {
      if (channels > 2 && isAAudio) {
        return const FeatureGateDecision.blocked(
          reason: FeatureBlockReason.unsupportedRoute,
          userMessage: 'Multichannel audio (>2 channels) requires AudioTrack float mode.',
        );
      }
    }

    // 8. Backend capability check
    switch (feature) {
      case AudioFeature.crossfade:
        if (!backend.canCrossfade) {
          return const FeatureGateDecision.blocked(
            reason: FeatureBlockReason.capabilityMissing,
            userMessage: 'Active playback backend does not support crossfade.',
          );
        }
        break;
      case AudioFeature.replayGain:
        if (!backend.canReplayGain) {
          return const FeatureGateDecision.blocked(
            reason: FeatureBlockReason.capabilityMissing,
            userMessage: 'Active playback backend does not support ReplayGain.',
          );
        }
        break;
      default:
        break;
    }

    return const FeatureGateDecision.allowed();
  }
}
