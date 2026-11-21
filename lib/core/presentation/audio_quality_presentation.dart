// lib/core/presentation/audio_quality_presentation.dart
// Presentation-layer extensions mapping domain AudioQualityInfo into Flutter UI
// colors and icons. Decouples the domain AudioQualityInfo model from Flutter/Material.

import 'package:material_ui/material_ui.dart';
import '../../domain/models/audio_quality_info.dart';
import '../constants/app_colors.dart';

extension AudioQualityPresentation on AudioQualityInfo {
  Color get badgeColor {
    if (format == 'MQA') return AppColors.qualityBadgeAmber;
    if (format == 'RADIO') return AppColors.qualityBadgeSky;
    if (codecName.startsWith('YouTube Music Stream')) {
      return AppColors.qualityBadgeRose;
    }
    if (format == 'DSD') return AppColors.amberDeep;
    if (tier == AudioQualityTier.hiResLossless) return AppColors.amberDeep;
    if (tier == AudioQualityTier.lossless) return AppColors.qualityBadgeCyan;
    if (format == 'AAC') return AppColors.qualityBadgeSky;
    if (format == 'OPUS' || format == 'OGG') {
      return AppColors.qualityBadgeIndigo;
    }
    if (tierLabel == 'Decoder Required') return AppColors.slate;
    return switch (tier) {
      AudioQualityTier.highQuality => AppColors.qualityBadgeBlue,
      AudioQualityTier.standardQuality =>
        format == 'AUDIO' ? AppColors.slate : AppColors.qualityBadgeSlate,
      AudioQualityTier.compact => AppColors.slate,
      _ => AppColors.slate,
    };
  }

  IconData get icon {
    if (format == 'MQA') return Icons.verified_rounded;
    if (format == 'RADIO') return Icons.radio_rounded;
    if (codecName.startsWith('YouTube Music Stream')) {
      return Icons.wifi_tethering_rounded;
    }
    if (format == 'DSD') return Icons.stars_rounded;
    if (tier == AudioQualityTier.hiResLossless) {
      return Icons.workspace_premium_rounded;
    }
    if (tier == AudioQualityTier.lossless) return Icons.diamond_rounded;
    if (format == 'AAC') return Icons.high_quality_rounded;
    if (format == 'OPUS' || format == 'OGG') return Icons.graphic_eq_rounded;
    if (tierLabel == 'Decoder Required') return Icons.extension_off_rounded;
    return switch (tier) {
      AudioQualityTier.highQuality => Icons.high_quality_rounded,
      AudioQualityTier.standardQuality => Icons.graphic_eq_rounded,
      AudioQualityTier.compact => Icons.audiotrack_rounded,
      _ => Icons.graphic_eq_rounded,
    };
  }
}
