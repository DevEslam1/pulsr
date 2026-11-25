import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../data/db/app_database.dart';
import '../bloc/base_cubit.dart';
import '../constants/app_colors.dart';
import '../network/network_access_guard.dart';
import '../network/remote_target_policy.dart';
import '../services/artwork_cache_manager.dart';
import '../utils/error_logger.dart';
import '../widgets/cached_artwork.dart';

class DynamicThemeState {
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final bool isDark;
  final bool hasCustomArtworkColor;
  final int? songId;

  const DynamicThemeState({
    this.primaryColor = AppColors.primary,
    this.secondaryColor = AppColors.secondary,
    this.backgroundColor = AppColors.background,
    this.surfaceColor = AppColors.surface,
    this.isDark = true,
    this.hasCustomArtworkColor = false,
    this.songId,
  });

  DynamicThemeState copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    bool? isDark,
    bool? hasCustomArtworkColor,
    int? songId,
  }) {
    return DynamicThemeState(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      isDark: isDark ?? this.isDark,
      hasCustomArtworkColor:
          hasCustomArtworkColor ?? this.hasCustomArtworkColor,
      songId: songId ?? this.songId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicThemeState &&
          runtimeType == other.runtimeType &&
          primaryColor == other.primaryColor &&
          secondaryColor == other.secondaryColor &&
          backgroundColor == other.backgroundColor &&
          surfaceColor == other.surfaceColor &&
          isDark == other.isDark &&
          hasCustomArtworkColor == other.hasCustomArtworkColor &&
          songId == other.songId;

  @override
  int get hashCode => Object.hash(
        primaryColor,
        secondaryColor,
        backgroundColor,
        surfaceColor,
        isDark,
        hasCustomArtworkColor,
        songId,
      );
}

/// Palette-only snapshot cached per song/artwork. Deliberately excludes
/// [DynamicThemeState.isDark]: replaying a whole cached state used to revert a
/// light/dark toggle made after the palette was cached.
class _CachedPalette {
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  // FIX-G3: Monotonic clock for TTL calculations and cache ordering
  static final Stopwatch _monotonicClock = Stopwatch()..start();
  final int cachedAtElapsedMs;
  // FIX-L04: Track caching timestamp for backward compatibility & debugging
  final DateTime cachedAt;

  _CachedPalette({
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    DateTime? cachedAt,
    int? cachedAtElapsedMs,
  })  : cachedAt = cachedAt ?? DateTime.now(),
        cachedAtElapsedMs =
            cachedAtElapsedMs ?? _monotonicClock.elapsedMilliseconds;

  DynamicThemeState applyTo(DynamicThemeState current, {int? songId}) =>
      current.copyWith(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        backgroundColor: backgroundColor,
        surfaceColor: surfaceColor,
        hasCustomArtworkColor: true,
        songId: songId ?? current.songId,
      );
}

class _QueuedThemeRequest {
  final int songId;
  final String? remoteArtworkUrl;
  final String cacheKey;
  final int token;
  final _CachedPalette? expiredFallback;

  const _QueuedThemeRequest({
    required this.songId,
    required this.remoteArtworkUrl,
    required this.cacheKey,
    required this.token,
    this.expiredFallback,
  });
}

@singleton
class DynamicThemeCubit extends PulsrCubit<DynamicThemeState> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  static const int _maxCacheSize = 50;
  final LinkedHashMap<String, _CachedPalette> _cachedPalettes = LinkedHashMap();
  Timer? _debounceTimer;
  int _currentRequestToken = 0;
  // FIX-C01: Guard against overlapping extractions
  bool _pendingExtraction = false;
  // H1 FIX: Single-slot queue for pending theme request so rapid track changes drain latest
  _QueuedThemeRequest? _queuedRequest;
  // FIX-H01: Ultimate fallback if palette extraction fails
  _CachedPalette? _lastEmittedPalette;

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

    // FIX-C01: Invalidate any in-flight extraction timer BEFORE incrementing token
    _debounceTimer?.cancel();
    final token = ++_currentRequestToken;

    _CachedPalette? expiredPalette;
    if (_cachedPalettes.containsKey(cacheKey)) {
      final cached = _cachedPalettes[cacheKey]!;
      // FIX-G3 / FIX-L04 / FIX-H01: Monotonic 30-minute TTL check
      final isExpired = (_CachedPalette._monotonicClock.elapsedMilliseconds -
              cached.cachedAtElapsedMs) >
          (30 * 60 * 1000);
      if (isExpired) {
        expiredPalette = cached;
        _cachedPalettes.remove(cacheKey);
      } else {
        _cachedPalettes.remove(cacheKey);
        _cachedPalettes[cacheKey] = cached; // Refresh LRU position
        _lastEmittedPalette = cached;
        // Guarded like every other emit: this path fires during teardown when
        // the player screen disposes while artwork updates are still landing.
        safeEmit(cached.applyTo(state, songId: songId));
        return;
      }
    }

    // FIX-C01: Check token inside callback before calling extraction
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 500), () {
      if (token != _currentRequestToken || isClosed) return;
      _extractPalette(
          songId: songId,
          remoteArtworkUrl: remoteArtworkUrl,
          cacheKey: cacheKey,
          token: token,
          expiredFallback: expiredPalette);
    }));
  }

  Future<void> _extractPalette(
      {required int songId,
      String? remoteArtworkUrl,
      required String cacheKey,
      required int token,
      _CachedPalette? expiredFallback}) async {
    if (isClosed) return;
    // FIX-C01 / H1 FIX: Queue pending request if an extraction is already in flight
    if (_pendingExtraction) {
      _queuedRequest = _QueuedThemeRequest(
        songId: songId,
        remoteArtworkUrl: remoteArtworkUrl,
        cacheKey: cacheKey,
        token: token,
        expiredFallback: expiredFallback,
      );
      return;
    }
    _pendingExtraction = true;

    try {
      ImageProvider? imageProvider;

      // 1. If online remote artwork URL exists (YouTube Music streaming / online song)
      if (remoteArtworkUrl != null && remoteArtworkUrl.isNotEmpty) {
        final isHttp = remoteArtworkUrl.startsWith('http://') ||
            remoteArtworkUrl.startsWith('https://');
        if (remoteArtworkUrl.startsWith('assets/')) {
          imageProvider = AssetImage(remoteArtworkUrl);
        } else if (remoteArtworkUrl.startsWith('file://')) {
          final localFile = File(Uri.parse(remoteArtworkUrl).toFilePath());
          if (await localFile.exists()) {
            imageProvider = FileImage(localFile);
          }
        } else if (!isHttp) {
          final localFile = File(remoteArtworkUrl);
          if (await localFile.exists()) {
            imageProvider = FileImage(localFile);
          }
        } else {
          final highResUrl =
              CachedArtwork.upgradeToHighResArtwork(remoteArtworkUrl);
          final cachedBytes = ArtworkLruCache().get(highResUrl) ??
              ArtworkLruCache().get(remoteArtworkUrl);
          if (cachedBytes != null && cachedBytes.isNotEmpty) {
            imageProvider =
                ResizeImage(MemoryImage(cachedBytes), width: 64, height: 64);
          } else {
            // Palette sampling only needs a 64x64 swatch, so fetching the ~1200px
            // high-res artwork here wastes bandwidth and memory. Feed the low-res
            // thumbnail URL to the extractor instead of the high-res upgrade.
            final lowResUrl = ArtworkCacheManager.toLowQualityArtworkUrl(
                remoteArtworkUrl,
                width: 220,
                height: 220);
            final blocked =
                await NetworkAccessGuard.isBlocked(category: 'DynamicTheme');
            if (!blocked && RemoteTargetPolicy.isAllowed(lowResUrl)) {
              imageProvider =
                  ResizeImage(NetworkImage(lowResUrl), width: 128, height: 128);
            }
          }
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
              size: 64,
              quality: 50,
            );
          } catch (_) {
            rawArt = null;
          }
        }
        if (rawArt != null && rawArt.isNotEmpty) {
          imageProvider =
              ResizeImage(MemoryImage(rawArt), width: 64, height: 64);
        }
      }

      if (token != _currentRequestToken || isClosed) return;

      if (imageProvider != null) {
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          size: const Size(64, 64),
          maximumColorCount: 16,
        ).timeout(const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Palette timeout'));

        if (token != _currentRequestToken || isClosed) return;

        // Prioritize rich chromatic swatches from the artwork and perceptually
        // normalize them so Dynamic Aura avoids neon eye-strain, muddy browns,
        // or dead monochrome greys across Dark, Light, and AMOLED themes.
        Color? rawPrimary;
        final candidates = [
          palette.vibrantColor?.color,
          palette.lightVibrantColor?.color,
          palette.darkVibrantColor?.color,
          palette.dominantColor?.color,
          palette.mutedColor?.color,
          palette.lightMutedColor?.color,
        ].whereType<Color>().toList();

        for (final c in candidates) {
          final hsl = HSLColor.fromColor(c);
          if (hsl.saturation >= 0.24 &&
              hsl.lightness >= 0.18 &&
              hsl.lightness <= 0.82) {
            rawPrimary = c;
            break;
          }
        }
        rawPrimary ??= candidates.cast<Color?>().firstWhere(
              (c) => c != null && HSLColor.fromColor(c).saturation >= 0.14,
              orElse: () => null,
            );

        final primary = rawPrimary != null
            ? _refineArtworkAccent(rawPrimary)
            : AppColors.primary;

        final rawSecondary = palette.mutedColor?.color ??
            palette.lightMutedColor?.color ??
            palette.darkVibrantColor?.color;
        final secondary = rawSecondary != null
            ? _refineArtworkSecondary(rawSecondary, fallback: primary)
            : AppColors.secondary;

        final darkVibrant = palette.darkVibrantColor?.color ??
            palette.darkMutedColor?.color ??
            primary;
        final bg = Color.alphaBlend(
          AppColors.scrimAt(0.78),
          _refineBackdropSeed(darkVibrant),
        );

        final newPalette = _CachedPalette(
          primaryColor: primary,
          secondaryColor: secondary,
          backgroundColor: bg,
          surfaceColor: Color.alphaBlend(
              primary.withValues(alpha: 0.08), AppColors.surface),
        );

        if (_cachedPalettes.containsKey(cacheKey)) {
          _cachedPalettes.remove(cacheKey);
        } else if (_cachedPalettes.length >= _maxCacheSize) {
          _cachedPalettes.remove(_cachedPalettes.keys.first);
        }
        _cachedPalettes[cacheKey] = newPalette;
        _lastEmittedPalette = newPalette;
        if (!isClosed && token == _currentRequestToken) {
          safeEmit(newPalette.applyTo(state, songId: songId));
        }
        return;
      }
    } catch (e, st) {
      // FIX-H01: If re-extraction fails, emit expired palette as fallback instead of leaving state stale
      if (expiredFallback != null &&
          !isClosed &&
          token == _currentRequestToken) {
        _lastEmittedPalette = expiredFallback;
        safeEmit(expiredFallback.applyTo(state, songId: songId));
        return;
      }
      if (_lastEmittedPalette != null &&
          !isClosed &&
          token == _currentRequestToken) {
        safeEmit(_lastEmittedPalette!.applyTo(state, songId: songId));
        return;
      }
      // Do not reset to default on single artwork 404/timeout — keep existing palette
      if (e is TimeoutException ||
          e.toString().contains('404') ||
          e.toString().contains('Failed host lookup')) {
        ErrorLogger.log(
            'Palette fetch transient failure for $cacheKey (keeping existing): $e',
            category: 'DynamicTheme');
        return;
      }
      ErrorLogger.log('Failed to generate dynamic theme palette for $cacheKey',
          error: e, stackTrace: st, category: 'DynamicTheme');
      return;
    } finally {
      _pendingExtraction = false;
      final next = _queuedRequest;
      _queuedRequest = null;
      if (next != null && !isClosed && next.token == _currentRequestToken) {
        unawaited(_extractPalette(
          songId: next.songId,
          remoteArtworkUrl: next.remoteArtworkUrl,
          cacheKey: next.cacheKey,
          token: next.token,
          expiredFallback: next.expiredFallback,
        ));
      }
    }

    if (token == _currentRequestToken && !isClosed) {
      safeEmit(DynamicThemeState(isDark: state.isDark, songId: songId));
    }
  }

  /// Normalizes raw artwork accents into a balanced studio band so Dynamic Aura
  /// never ships harsh neon oversaturation or muddy near-grey browns.
  static Color _refineArtworkAccent(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    if (hsl.saturation < 0.14) {
      return AppColors.primary;
    }
    // Warm yellows/olives (40°–75°) turn muddy easily when dark or low-sat;
    // keep them slightly brighter and cleaner.
    final isWarmYellowBand = hsl.hue >= 40.0 && hsl.hue <= 75.0;
    final refinedSat =
        hsl.saturation.clamp(0.36, isWarmYellowBand ? 0.78 : 0.82);
    final refinedLight =
        hsl.lightness.clamp(isWarmYellowBand ? 0.44 : 0.40, 0.62);
    return hsl.withSaturation(refinedSat).withLightness(refinedLight).toColor();
  }

  static Color _refineArtworkSecondary(Color raw, {required Color fallback}) {
    final hsl = HSLColor.fromColor(raw);
    if (hsl.saturation < 0.14) {
      return Color.lerp(fallback, AppColors.secondary, 0.35) ?? fallback;
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.28, 0.72))
        .withLightness(hsl.lightness.clamp(0.36, 0.60))
        .toColor();
  }

  static Color _refineBackdropSeed(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.65))
        .withLightness(hsl.lightness.clamp(0.16, 0.36))
        .toColor();
  }

  void resetToDefault() {
    if (isClosed) return;
    _debounceTimer?.cancel();
    _currentRequestToken++;
    _queuedRequest = null;
    // Preserve the current light/dark selection; a bare DynamicThemeState()
    // hard-codes isDark: true and silently reverted the user's mode.
    safeEmit(DynamicThemeState(isDark: state.isDark));
  }

  @override
  Future<void> close() {
    _pendingExtraction = false;
    _queuedRequest = null;
    // H-02: Cancel explicitly. autoTimer normally covers this, but if close()
    // runs before the first updateFromDetails the timer was never registered.
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cachedPalettes.clear();
    return super.close();
  }
}
