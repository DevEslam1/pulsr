// lib/core/theme/dynamic_theme_cubit.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import '../constants/app_colors.dart';

class DynamicThemeState {
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final bool isDark;

  const DynamicThemeState({
    this.primaryColor = AppColors.primary,
    this.secondaryColor = AppColors.secondary,
    this.backgroundColor = AppColors.background,
    this.surfaceColor = AppColors.surface,
    this.isDark = true,
  });

  DynamicThemeState copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    bool? isDark,
  }) {
    return DynamicThemeState(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      isDark: isDark ?? this.isDark,
    );
  }
}

class DynamicThemeCubit extends Cubit<DynamicThemeState> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Map<int, DynamicThemeState> _cachedPalettes = {};

  DynamicThemeCubit() : super(const DynamicThemeState());

  Future<void> updateFromSongId(int songId) async {
    if (_cachedPalettes.containsKey(songId)) {
      emit(_cachedPalettes[songId]!);
      return;
    }

    try {
      final Uint8List? rawArt = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 200,
        quality: 80,
      );

      if (rawArt != null && rawArt.isNotEmpty) {
        final imageProvider = MemoryImage(rawArt);
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          maximumColorCount: 16,
        );

        final dominant = palette.dominantColor?.color;
        final vibrant = palette.vibrantColor?.color ?? palette.lightVibrantColor?.color ?? dominant;
        final darkVibrant = palette.darkVibrantColor?.color ?? palette.darkMutedColor?.color;

        final primary = vibrant ?? dominant ?? AppColors.primary;
        final bg = darkVibrant != null
            ? Color.alphaBlend(Colors.black.withValues(alpha: 0.75), darkVibrant)
            : const Color(0xFF14172B);

        final newState = state.copyWith(
          primaryColor: primary,
          secondaryColor: palette.mutedColor?.color ?? AppColors.secondary,
          backgroundColor: bg,
          surfaceColor: Color.alphaBlend(primary.withValues(alpha: 0.08), AppColors.surface),
        );

        _cachedPalettes[songId] = newState;
        emit(newState);
        return;
      }
    } catch (_) {}

    // Fallback to default
    emit(const DynamicThemeState());
  }

  void resetToDefault() {
    emit(const DynamicThemeState());
  }
}
