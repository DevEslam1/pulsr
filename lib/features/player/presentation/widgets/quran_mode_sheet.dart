import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/earbud_optimization_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../domain/models/quran_metadata.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../../../../domain/repositories/quran_repository.dart';
import '../../../../data/repositories/quran_repository_impl.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import 'quran_error_card.dart';
import 'quran_mushaf_view.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:flutter/services.dart';

/// Bottom sheet entry point for Quran Mode.
class QuranModeSheet extends StatelessWidget {
  const QuranModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const QuranModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const PulsrBottomSheetContainer(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuranModePanel(),
            SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// The interactive control surface. Reused by [QuranModeSheet] and the
/// full-screen `/quran-mode` route.
class QuranModePanel extends StatefulWidget {
  const QuranModePanel({super.key});

  @override
  State<QuranModePanel> createState() => _QuranModePanelState();
}

class _QuranModePanelState extends State<QuranModePanel> {
  Future<EarbudCapabilities>? _capsFuture;
  bool _isApplying = false;
  QuranMetadata? _metadata;
  QuranBookmark? _bookmark;
  bool _bookmarkBusy = false;
  String? _bookmarkError;
  String? _lastLoadedTrackUri;

  @override
  void initState() {
    super.initState();
    _capsFuture = context.read<PlayerCubit>().detectEarbudCapabilities();
  }

  void _refreshCaps() {
    if (mounted) {
      setState(() {
        _capsFuture = context.read<PlayerCubit>().detectEarbudCapabilities();
      });
    }
  }

  Future<void> _checkMetadata(String? uri) async {
    if (uri == _lastLoadedTrackUri) return;
    _lastLoadedTrackUri = uri;
    // Drop the previous track's actions before starting asynchronous reads.
    if (mounted) {
      setState(() {
        _metadata = null;
        _bookmark = null;
        _bookmarkError = null;
      });
    }
    if (uri == null || uri.isEmpty) {
      return;
    }
    try {
      final repo = getIt.isRegistered<QuranRepository>()
          ? getIt<QuranRepository>()
          : QuranRepositoryImpl();
      final meta = await repo.getMetadataForTrack(uri);
      final bm = await repo.getBookmark(uri);
      if (mounted && _lastLoadedTrackUri == uri) {
        setState(() {
          _metadata = meta;
          _bookmark = bm;
        });
      }
    } catch (_) {
      if (mounted && _lastLoadedTrackUri == uri) {
        setState(() {
          _metadata = null;
          _bookmark = null;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> _runBookmarkAction(
      String uri, Future<void> Function() action) async {
    if (_bookmarkBusy) return false;
    setState(() {
      _bookmarkBusy = true;
      _bookmarkError = null;
    });
    try {
      await action();
      return mounted && _lastLoadedTrackUri == uri;
    } catch (_) {
      if (mounted && _lastLoadedTrackUri == uri) {
        setState(() => _bookmarkError = context.l10n.quranBookmarkFailed);
      }
      return false;
    } finally {
      if (mounted) setState(() => _bookmarkBusy = false);
    }
  }

  Future<void> _runQuranAction(Future<void> action) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      await action;
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  void dispose() {
    _capsFuture = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (a, b) =>
          a.isQuranModeEnabled != b.isQuranModeEnabled ||
          a.quranReciterStyle != b.quranReciterStyle ||
          a.isReverbEnabled != b.isReverbEnabled ||
          a.reverbWetDry != b.reverbWetDry ||
          a.isSaturationEnabled != b.isSaturationEnabled ||
          a.saturationMix != b.saturationMix ||
          a.playbackSpeed != b.playbackSpeed ||
          a.errorMessage != b.errorMessage ||
          a.position != b.position ||
          a.abLoopEnabled != b.abLoopEnabled ||
          a.abPointA != b.abPointA ||
          a.abPointB != b.abPointB ||
          a.currentSong != b.currentSong,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        final enabled = state.isQuranModeEnabled && !_isApplying;
        final style = state.quranReciterStyle;
        final currentTrackUri =
            state.currentSong?.uri ?? state.currentSong?.path;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkMetadata(currentTrackUri);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s20, AppSpacing.xxs, AppSpacing.s20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.14),
                      borderRadius: AppRadii.r14All,
                    ),
                    child: Icon(Icons.menu_book_rounded,
                        color: p.accent, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.quranMode,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w800,
                            )),
                        Text(
                          context.l10n.reciterDesc,
                          style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: context.l10n.quranMode,
                    value: state.isQuranModeEnabled ? 'On' : 'Off',
                    child: PulsrSwitch(
                      value: state.isQuranModeEnabled,
                      onChanged: _isApplying
                          ? null
                          : (v) => unawaited(
                                _runQuranAction(cubit.setQuranModeEnabled(v)),
                              ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _isApplying
                      ? null
                      : () => unawaited(
                            _runQuranAction(cubit.resetQuranAutoMode()),
                          ),
                  icon: const Icon(Icons.auto_mode_rounded, size: 18),
                  label: const Text('Auto-detect recitations'),
                  style: TextButton.styleFrom(
                    foregroundColor: p.textSecondary,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s6),

            // Reciter styles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(context.l10n.reciterStyle,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.overline,
                  )),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: AppSpacing.s40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                itemCount: QuranReciterStyle.values.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final s = QuranReciterStyle.values[i];
                  final selected = s == style;
                  return Semantics(
                    label: '${context.l10n.reciterStyle}: ${s.label}',
                    selected: selected,
                    child: ChoiceChip(
                      selected: selected,
                      onSelected: _isApplying
                          ? null
                          : (_) {
                              HapticFeedback.selectionClick();
                              unawaited(_runQuranAction(
                                  cubit.setQuranReciterStyle(s)));
                            },
                      label: Text(s.label),
                      labelStyle: TextStyle(
                        color: selected ? p.onAccent : p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.label,
                      ),
                      backgroundColor: p.surfaceContainer,
                      selectedColor: p.accent,
                      side: BorderSide(color: p.hairline),
                      showCheckmark: false,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(
                '${style.tagline} • ${style.sanctuaryName.isNotEmpty ? style.sanctuaryName : style.description}',
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.label),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildQuranMetadataCard(context, p, state, cubit),
            const SizedBox(height: AppSpacing.md),

            if (_isApplying)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                child: LinearProgressIndicator(),
              ),
            if (_isApplying) const SizedBox(height: AppSpacing.sm),

            if ((state.errorMessage ?? '').contains('Quran'))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                child: QuranErrorCard(
                  message: state.errorMessage!,
                  onRetry: !_isApplying
                      ? () => unawaited(
                            _runQuranAction(cubit.reapplyQuranProfile()),
                          )
                      : null,
                ),
              ),
            if ((state.errorMessage ?? '').contains('Quran'))
              const SizedBox(height: AppSpacing.sm),

            // Tuning sliders
            _QuranSliderTile(
              icon: Icons.mosque_rounded,
              title: context.l10n.dspMosqueAmbience,
              subtitle: context.l10n.dspMosqueAmbienceDesc,
              value: state.isReverbEnabled
                  ? state.reverbWetDry.clamp(0.0, 0.6)
                  : 0.0,
              max: 0.6,
              enabled: enabled,
              valueLabel: state.isReverbEnabled
                  ? '${(state.reverbWetDry * 100).round()}%'
                  : '0%',
              onChanged: (value) => unawaited(
                _runQuranAction(cubit.setQuranAmbience(value)),
              ),
              applyOnRelease: true,
            ),
            if (state.isReverbEnabled)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.s20,
                  end: AppSpacing.s20,
                  bottom: AppSpacing.xs,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: enabled
                        ? () => unawaited(
                              _runQuranAction(cubit.setQuranAmbience(0)),
                            )
                        : null,
                    icon: const Icon(Icons.volume_off_rounded, size: 18),
                    label: Text(context.l10n.noneLabel),
                  ),
                ),
              ),
            _QuranSliderTile(
              icon: Icons.local_fire_department_rounded,
              title: context.l10n.dspVocalWarmth,
              subtitle: context.l10n.dspVocalWarmthDesc,
              value: state.isSaturationEnabled
                  ? state.saturationMix.clamp(0.0, 0.6)
                  : 0.0,
              max: 0.6,
              enabled: enabled,
              valueLabel: state.isSaturationEnabled
                  ? '${(state.saturationMix * 100).round()}%'
                  : '0%',
              onChanged: (value) => unawaited(
                _runQuranAction(cubit.setQuranWarmth(value)),
              ),
              applyOnRelease: true,
            ),

            // Learning speed
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s20, AppSpacing.s6, AppSpacing.s20, 0),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: p.textSecondary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.learningSpeed,
                            style: TextStyle(
                                color: p.textPrimary,
                                fontSize: AppFontSize.body,
                                fontWeight: FontWeight.w700)),
                        Text(context.l10n.reciterSpeedDesc,
                            style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.5, label: Text('0.5x')),
                  ButtonSegment(value: 0.75, label: Text('0.75x')),
                  ButtonSegment(value: 1.0, label: Text('1.0x')),
                ],
                selected: {
                  [0.5, 0.75, 1.0].reduce((a, b) =>
                      (a - state.playbackSpeed).abs() <
                              (b - state.playbackSpeed).abs()
                          ? a
                          : b)
                },
                onSelectionChanged: enabled
                    ? (v) => unawaited(
                          _runQuranAction(
                            cubit.setQuranPlaybackSpeed(v.first),
                          ),
                        )
                    : null,
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(p.textPrimary),
                  side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),

            // Detected output hardware
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.outputHardware,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        letterSpacing: AppTracking.overline,
                      )),
                  GestureDetector(
                    onTap: _refreshCaps,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Icon(Icons.refresh_rounded,
                          size: 14, color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: FutureBuilder<EarbudCapabilities>(
                future: _capsFuture,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _card(
                      p,
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs),
                        child: Text(
                          context.l10n.outputHardware,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return _card(
                      p,
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: SizedBox(
                            width: AppSpacing.s18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    );
                  }
                  final caps = snap.data!;
                  return _card(
                    p,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv(p, context.l10n.dspDevice, caps.deviceName),
                        _kv(p, context.l10n.dspCodec,
                            '${caps.codec.label} (${caps.codec.quality})'),
                        _kv(
                            p,
                            context.l10n.format,
                            '${caps.bitDepth}-bit • '
                            '${caps.sampleRateHz ~/ 1000} kHz'),
                        _kv(
                          p,
                          context.l10n.dspLatency,
                          caps.isBluetooth ? '~${caps.latencyMs} ms' : '—',
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        Text(
                          caps.isBluetooth
                              ? context.l10n.dspBluetoothCompensationDesc
                              : context.l10n.dspWiredCompensationDesc,
                          style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.caption),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Reset
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled
                          ? () => unawaited(
                                _runQuranAction(
                                  cubit.resetQuranProfile(),
                                ),
                              )
                          : null,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: Text(context.l10n.resetProfile),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.accent,
                        side:
                            BorderSide(color: p.accent.withValues(alpha: 0.5)),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
              child: Text(
                context.l10n.sibilanceDesc,
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.tiny),
              ),
            ),
            if (state.isQuranModeEnabled) ...[
              const SizedBox(height: AppSpacing.md),
              QuranMushafView(
                key: ValueKey(currentTrackUri),
                metadata:
                    currentTrackUri == _lastLoadedTrackUri ? _metadata : null,
                currentPosition: state.position,
                onSeek: (pos) => cubit.seek(pos),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildQuranMetadataCard(
    BuildContext context,
    PulsrPalette p,
    PlayerState state,
    PlayerCubit cubit,
  ) {
    final currentUri = state.currentSong?.uri ?? state.currentSong?.path;
    final meta = currentUri == _lastLoadedTrackUri ? _metadata : null;
    if (meta == null || !meta.isValid) {
      // Empty-state card for non-Quran tracks or tracks without Quran catalog metadata
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r14All,
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.menu_book_outlined, size: 22, color: p.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.quranNoMetadataTitle,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    context.l10n.quranNoMetadataDesc,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: p.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Valid Quran Metadata card
    final bm = _bookmark;
    final hasTimings = meta.ayahTimings.isNotEmpty;
    var repeatMode = QuranRepeatMode.off;
    if (state.abLoopEnabled && hasTimings) {
      if (meta.ayahTimings
          .any((t) => t.start == state.abPointA && t.end == state.abPointB)) {
        repeatMode = QuranRepeatMode.singleAyah;
      } else if (meta.ayahTimings.first.start == state.abPointA &&
          meta.ayahTimings.last.end == state.abPointB) {
        repeatMode = QuranRepeatMode.range;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.15),
                  borderRadius: AppRadii.r10All,
                ),
                child:
                    Icon(Icons.auto_stories_rounded, color: p.accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${meta.surahName} (${meta.surahNumber})',
                      style: TextStyle(
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      '${meta.reciter} • Ayah ${meta.ayahStart}-${meta.ayahEnd}',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: AppSpacing.s10),

          // Bookmark & Resume actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _bookmarkBusy
                    ? null
                    : () async {
                        final uri = _lastLoadedTrackUri;
                        if (uri == null) return;
                        final currentAyah = meta.ayahAt(state.position);
                        final newBookmark = QuranBookmark(
                          trackUri: uri,
                          metadata: meta,
                          currentAyah: currentAyah,
                          position: state.position,
                          timestamp: DateTime.now(),
                        );
                        final repo = getIt.isRegistered<QuranRepository>()
                            ? getIt<QuranRepository>()
                            : QuranRepositoryImpl();
                        final messenger = ScaffoldMessenger.of(context);
                        final l10n = context.l10n;
                        final saved = await _runBookmarkAction(
                            uri, () => repo.saveBookmark(newBookmark));
                        if (!saved) return;
                        if (mounted &&
                            _lastLoadedTrackUri == uri &&
                            cubit.state.currentSong == state.currentSong) {
                          setState(() => _bookmark = newBookmark);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.quranBookmarkSaved(
                                  meta.surahName, currentAyah)),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: Text(context.l10n.quranSaveBookmark,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.accent,
                  side: BorderSide(color: p.accent.withValues(alpha: 0.4)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (bm != null) ...[
                FilledButton.tonalIcon(
                  onPressed: () => cubit.seek(bm.position),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(
                    context.l10n.quranResumePrompt(meta.surahName,
                        bm.currentAyah, _formatDuration(bm.position)),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.quranClearBookmark,
                  icon: Icon(Icons.bookmark_remove_outlined,
                      color: p.error, size: 18),
                  onPressed: _bookmarkBusy
                      ? null
                      : () async {
                          final uri = _lastLoadedTrackUri;
                          if (uri == null) return;
                          final repo = getIt.isRegistered<QuranRepository>()
                              ? getIt<QuranRepository>()
                              : QuranRepositoryImpl();
                          final cleared = await _runBookmarkAction(
                              uri, () => repo.clearBookmark(uri));
                          if (!cleared) return;
                          if (mounted && _lastLoadedTrackUri == uri) {
                            setState(() => _bookmark = null);
                          }
                        },
                ),
              ],
            ],
          ),

          if (_bookmarkError != null)
            Semantics(
              liveRegion: true,
              child: Text(_bookmarkError!, style: TextStyle(color: p.error)),
            ),

          // Repeat controls (only active when accurate timings exist)
          if (hasTimings) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              context.l10n.quranRepeatMode,
              style: TextStyle(
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.wide,
                color: p.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(context.l10n.quranRepeatOff),
                  selected: repeatMode == QuranRepeatMode.off,
                  onSelected: (_) {
                    cubit.clearAbLoop();
                  },
                  labelStyle: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600,
                    color: repeatMode == QuranRepeatMode.off
                        ? p.onAccent
                        : p.textPrimary,
                  ),
                ),
                ChoiceChip(
                  label: Text(context.l10n.quranRepeatAyah),
                  selected: repeatMode == QuranRepeatMode.singleAyah,
                  onSelected: (_) {
                    final active =
                        meta.timingForAyah(meta.ayahAt(cubit.state.position));
                    if (active != null) {
                      cubit.setAbLoopRange(active.start, active.end);
                    }
                  },
                  labelStyle: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600,
                    color: repeatMode == QuranRepeatMode.singleAyah
                        ? p.onAccent
                        : p.textPrimary,
                  ),
                ),
                ChoiceChip(
                  label: Text(context.l10n.quranRepeatRange),
                  selected: repeatMode == QuranRepeatMode.range,
                  onSelected: (_) {
                    if (meta.ayahTimings.isNotEmpty) {
                      cubit.setAbLoopRange(meta.ayahTimings.first.start,
                          meta.ayahTimings.last.end);
                    }
                  },
                  labelStyle: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600,
                    color: repeatMode == QuranRepeatMode.range
                        ? p.onAccent
                        : p.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(PulsrPalette p, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r14All,
        border: Border.all(color: p.hairline),
      ),
      child: child,
    );
  }

  Widget _kv(PulsrPalette p, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(k,
                style: TextStyle(
                    color: p.textTertiary, fontSize: AppFontSize.label)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _QuranSliderTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double max;
  final bool enabled;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final bool applyOnRelease;

  const _QuranSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.max,
    required this.enabled,
    required this.valueLabel,
    required this.onChanged,
    this.applyOnRelease = false,
  });

  @override
  State<_QuranSliderTile> createState() => _QuranSliderTileState();
}

class _QuranSliderTileState extends State<_QuranSliderTile> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _QuranSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.value != oldWidget.value) {
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.s20, 0, AppSpacing.s20, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: p.textSecondary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w700)),
                    Text(widget.subtitle,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label)),
                  ],
                ),
              ),
              Text(
                  _dragValue == null
                      ? widget.valueLabel
                      : '${(_dragValue! * 100).round()}%',
                  style: TextStyle(
                      color: p.accent,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: (_dragValue ?? widget.value).clamp(0.0, widget.max),
            max: widget.max,
            onChanged: !widget.enabled
                ? null
                : (value) {
                    if (widget.applyOnRelease) {
                      setState(() => _dragValue = value);
                    } else {
                      widget.onChanged(value);
                    }
                  },
            onChangeEnd: widget.enabled && widget.applyOnRelease
                ? (value) {
                    if ((value - widget.value).abs() < 0.001) {
                      setState(() => _dragValue = null);
                    } else {
                      setState(() => _dragValue = value);
                      widget.onChanged(value);
                    }
                  }
                : null,
            activeColor: p.accent,
            inactiveColor: p.hairline,
          ),
        ],
      ),
    );
  }
}
