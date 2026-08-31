import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../bloc/base_cubit.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../data/db/app_database.dart';
import '../constants/app_colors.dart';
import '../utils/error_logger.dart';
import '../widgets/cached_artwork.dart';

class DynamicThemeState {
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final bool isDark;
  final bool hasCustomArtworkColor;

  const DynamicThemeState({
    this.primaryColor = AppColors.primary,
    this.secondaryColor = AppColors.secondary,
    this.backgroundColor = AppColors.background,
    this.surfaceColor = AppColors.surface,
    this.isDark = true,
    this.hasCustomArtworkColor = false,
  });

  DynamicThemeState copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    bool? isDark,
    bool? hasCustomArtworkColor,
  }) {
    return DynamicThemeState(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      isDark: isDark ?? this.isDark,
      hasCustomArtworkColor:
          hasCustomArtworkColor ?? this.hasCustomArtworkColor,
    );
  }
}

@singleton
class DynamicThemeCubit extends PulsrCubit<DynamicThemeState> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  static const int _maxCacheSize = 50;
  final LinkedHashMap<String, DynamicThemeState> _cachedPalettes =
      LinkedHashMap();
  Timer? _debounceTimer;
  int _currentRequestToken = 0;

  DynamicThemeCubit() : super(const DynamicThemeState());

  /// Extracts dynamic color scheme from a [SongsTableData] object, supporting
  /// both local MediaStore songs and online streaming tracks (YouTube Music).
  Future<void> updateFromSong(SongsTableData? song) async {
    if (song == null) {
      resetToDefault();
      return;
    }
    await updateFromDetails(
        songId: song.id, remoteArtworkUrl: song.remoteArtworkUrl);
  }

  Future<void> updateFromSongId(int songId, {String? remoteArtworkUrl}) async {
    await updateFromDetails(songId: songId, remoteArtworkUrl: remoteArtworkUrl);
  }

  Future<void> updateFromDetails(
      {required int songId, String? remoteArtworkUrl}) async {
    final cacheKey = (remoteArtworkUrl != null && remoteArtworkUrl.isNotEmpty)
        ? remoteArtworkUrl
        : 'AUDIO_$songId';

    if (_cachedPalettes.containsKey(cacheKey)) {
      _debounceTimer?.cancel();
      final cached = _cachedPalettes.remove(cacheKey)!;
      _cachedPalettes[cacheKey] = cached; // Refresh LRU position
      emit(cached);
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 500), () {
      _extractPalette(
          songId: songId,
          remoteArtworkUrl: remoteArtworkUrl,
          cacheKey: cacheKey);
    }));
  }

  Future<void> _extractPalette(
      {required int songId,
      String? remoteArtworkUrl,
      required String cacheKey}) async {
    final token = ++_currentRequestToken;

    try {
      ImageProvider? imageProvider;

      // 1. If online remote artwork URL exists (YouTube Music streaming / online song)
      if (remoteArtworkUrl != null && remoteArtworkUrl.isNotEmpty) {
        final highResUrl =
            CachedArtwork.upgradeToHighResArtwork(remoteArtworkUrl);
        final cachedBytes = ArtworkLruCache().get(highResUrl) ??
            ArtworkLruCache().get(remoteArtworkUrl);
        if (cachedBytes != null && cachedBytes.isNotEmpty) {
          imageProvider = MemoryImage(cachedBytes);
        } else {
          imageProvider =
              ResizeImage(NetworkImage(highResUrl), width: 128, height: 128);
        }
      } else {
        // 2. Local audio file from MediaStore
        Uint8List? rawArt = ArtworkLruCache().get('AUDIO_$songId');
        if (rawArt == null || rawArt.isEmpty) {
          try {
            rawArt = await _audioQuery.queryArtwork(
              songId,
              ArtworkType.AUDIO,
              format: ArtworkFormat.JPEG,
              size: 150,
              quality: 75,
            );
          } catch (_) {
            rawArt = null;
          }
        }
        if (rawArt != null && rawArt.isNotEmpty) {
          imageProvider = MemoryImage(rawArt);
        }
      }

      if (token != _currentRequestToken || isClosed) return;

      if (imageProvider != null) {
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          size: const Size(64, 64),
          maximumColorCount: 16,
        ).timeout(const Duration(seconds: 5), onTimeout: () => throw TimeoutException('Palette timeout'));

        if (token != _currentRequestToken || isClosed) return;

        // Prioritize saturated/vibrant colors from the artwork
        Color? primary;
        final candidates = [
          palette.vibrantColor?.color,
          palette.lightVibrantColor?.color,
          palette.darkVibrantColor?.color,
          palette.dominantColor?.color,
          palette.mutedColor?.color,
        ].whereType<Color>().toList();

        final darkVibrant =
            palette.darkVibrantColor?.color ?? palette.darkMutedColor?.color;
        final bg = darkVibrant != null
            ? Color.alphaBlend(
                Colors.black.withValues(alpha: 0.75), darkVibrant)
            : const Color(0xFF14172B);

        for (final c in candidates) {
          final hsl = HSLColor.fromColor(c);
          final clampedLightness = hsl.lightness.clamp(0.0, 1.0);
          final clampedSaturation = hsl.saturation.clamp(0.0, 1.0);
          if (clampedSaturation > 0.20 &&
              clampedLightness > 0.15 &&
              clampedLightness < 0.85 &&
              _contrastRatio(c, bg) >= 3.0) {
            primary = c;
            break;
          }
        }
        primary ??= (palette.vibrantColor?.color != null &&
                _contrastRatio(palette.vibrantColor!.color, bg) >= 3.0)
            ? palette.vibrantColor!.color
            : AppColors.primary;

        final newState = state.copyWith(
          primaryColor: primary,
          secondaryColor: palette.mutedColor?.color ?? AppColors.secondary,
          backgroundColor: bg,
          surfaceColor: Color.alphaBlend(
              primary.withValues(alpha: 0.08), AppColors.surface),
          hasCustomArtworkColor: true,
        );

        if (_cachedPalettes.length >= _maxCacheSize) {
          _cachedPalettes.remove(_cachedPalettes.keys.first);
        }
        _cachedPalettes[cacheKey] = newState;
        if (!isClosed && token == _currentRequestToken) {
          emit(newState);
        }
        return;
      }
    } catch (e, st) {
      // Do not reset to default on single artwork 404/timeout — keep existing palette
      if (e is TimeoutException || e.toString().contains('404') || e.toString().contains('Failed host lookup')) {
        ErrorLogger.log('Palette fetch transient failure for $cacheKey (keeping existing)',
            error: e, stackTrace: st, category: 'DynamicTheme');
        return;
      }
      ErrorLogger.log('Failed to generate dynamic theme palette for $cacheKey',
          error: e, stackTrace: st, category: 'DynamicTheme');
      return;
    }

    if (token == _currentRequestToken &&
        !isClosed &&
        !state.hasCustomArtworkColor) {
      emit(const DynamicThemeState());
    }
  }

  void resetToDefault() {
    _debounceTimer?.cancel();
    _currentRequestToken++;
    emit(const DynamicThemeState());
  }

  static double _luminance(Color c) {
    double r = c.r;
    double g = c.g;
    double b = c.b;
    r = r <= 0.03928 ? r / 12.92 : math.pow((r + 0.055) / 1.055, 2.4).toDouble();
    g = g <= 0.03928 ? g / 12.92 : math.pow((g + 0.055) / 1.055, 2.4).toDouble();
    b = b <= 0.03928 ? b / 12.92 : math.pow((b + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double _contrastRatio(Color c1, Color c2) {
    final l1 = _luminance(c1);
    final l2 = _luminance(c2);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  Future<void> close() {
    // Debounce timer is registered with PulsrCubit; cancelled automatically.
    _cachedPalettes.clear();
    return super.close();
  }
}
