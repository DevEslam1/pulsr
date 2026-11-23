// lib/features/announcements/announcement_screen.dart

import 'package:material_ui/material_ui.dart';
import 'dart:async';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/l10n_extensions.dart';
import '../settings/presentation/widgets/settings_section.dart';
import '../settings/presentation/widgets/settings_slider_row.dart';
import '../settings/presentation/widgets/settings_tiles.dart';
import 'announcement_composer.dart';
import 'announcement_settings.dart';
import 'announcement_strings.dart';
import 'tts_engine.dart';

/// Settings surface for spoken track announcements.
///
/// The screen reads and writes [AnnouncementSettings] directly (the object
/// notifies its own listeners) and uses [TtsEngine] only to list voices and to
/// speak a preview. It never owns either object; the caller that built them
/// disposes them.
class AnnouncementScreen extends StatefulWidget {
  /// Creates the screen.
  ///
  /// [previewTrack] is what the "speak test" button reads out; the default is a
  /// synthetic sample so the button works before anything is playing.
  const AnnouncementScreen({
    super.key,
    required this.settings,
    required this.engine,
    this.previewTrack,
  });

  /// Settings edited by this screen.
  final AnnouncementSettings settings;

  /// Engine used to list voices and speak the preview.
  final TtsEngine engine;

  /// Sample track spoken by the test button.
  final AnnouncementTrack? previewTrack;

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  late Future<List<TtsVoice>> _voicesFuture;
  ValueNotifier<bool>? _availability;
  VoidCallback? _availabilityListener;

  @override
  void initState() {
    super.initState();
    _voicesFuture = widget.engine.voices();
    // Push the persisted choice into the channel engine so a restart speaks
    // with the voice the user picked, without extra bootstrap wiring.
    final engine = widget.engine;
    if (engine is MethodChannelTtsEngine) {
      engine.voiceId = widget.settings.voiceId;
      engine.localeId = widget.settings.localeId;
      // A channel engine starts unavailable until `init` succeeds; listening to
      // its availability lets the list appear as soon as it flips, instead of
      // requiring the user to reopen the screen.
      _availability = engine.availability;
      _availabilityListener = () {
        if (!mounted) return;
        unawaited(_prepareVoices());
      };
      _availability!.addListener(_availabilityListener!);
    }
    unawaited(_prepareVoices());
  }

  @override
  void dispose() {
    final notifier = _availability;
    final listener = _availabilityListener;
    if (notifier != null && listener != null) {
      notifier.removeListener(listener);
    }
    super.dispose();
  }

  /// Initializes a channel engine when needed, then (re)lists its voices.
  ///
  /// `init` is idempotent, so this is safe both on the first frame and after a
  /// refresh tap or an availability flip.
  Future<void> _prepareVoices() async {
    final engine = widget.engine;
    if (engine is MethodChannelTtsEngine && !engine.isAvailable) {
      await engine.init();
    }
    if (!mounted) return;
    setState(() {
      _voicesFuture = widget.engine.voices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        title: Text(
          AnnouncementStrings.screenTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final settings = widget.settings;
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              if (!widget.engine.isAvailable) const _UnavailableNotice(),
              _masterSection(settings),
              _elementsSection(context, settings),
              _timingSection(context, settings),
              _skipSection(context, settings),
              _voiceSection(context, settings),
            ],
          );
        },
      ),
    );
  }

  Widget _masterSection(AnnouncementSettings settings) {
    return SettingsSection(
      icon: Icons.record_voice_over_rounded,
      title: AnnouncementStrings.sectionAnnouncements,
      children: [
        SettingsSwitchTile(
          Icons.campaign_rounded,
          AnnouncementStrings.masterTitle,
          AnnouncementStrings.masterSubtitle,
          value: settings.enabled,
          onChanged: settings.setEnabled,
        ),
      ],
    );
  }

  Widget _elementsSection(
    BuildContext context,
    AnnouncementSettings settings,
  ) {
    final palette = context.palette;
    final rows = <Widget>[];
    for (final element in AnnouncementElement.values) {
      if (rows.isNotEmpty) rows.add(settingsCardDivider(palette));
      rows.add(SettingsSwitchTile(
        _elementIcon(element),
        AnnouncementStrings.elementLabel(element),
        AnnouncementStrings.elementSubtitle(element),
        value: settings.elements.contains(element),
        onChanged: (value) => settings.setElementEnabled(element, value),
      ));
    }
    return SettingsSection(
      icon: Icons.queue_music_rounded,
      title: AnnouncementStrings.sectionElements,
      subtitle: AnnouncementStrings.elementsSubtitle,
      children: rows,
    );
  }

  Widget _timingSection(
    BuildContext context,
    AnnouncementSettings settings,
  ) {
    final palette = context.palette;
    return SettingsSection(
      icon: Icons.tune_rounded,
      title: AnnouncementStrings.sectionTiming,
      subtitle: AnnouncementStrings.sectionTimingSubtitle,
      children: [
        SettingSliderRow(
          label: AnnouncementStrings.delayLabel,
          subtitle: AnnouncementStrings.delaySubtitle,
          value: settings.delayMs.toDouble(),
          min: AnnouncementSettings.minDelayMs.toDouble(),
          max: AnnouncementSettings.maxDelayMs.toDouble(),
          divisions: 20,
          defaultValue: AnnouncementSettings.defaultDelayMs.toDouble(),
          formatValue: (value) => AnnouncementStrings.delayValue(value.round()),
          onChanged: (value) => settings.setDelayMs(value.round()),
        ),
        SettingSliderRow(
          label: AnnouncementStrings.volumeLabel,
          subtitle: AnnouncementStrings.volumeSubtitle,
          value: settings.volume,
          min: AnnouncementSettings.minVolume,
          max: AnnouncementSettings.maxVolume,
          divisions: 12,
          defaultValue: AnnouncementSettings.defaultVolume,
          formatValue: AnnouncementStrings.volumeValue,
          onChanged: settings.setVolume,
        ),
        SettingSliderRow(
          label: AnnouncementStrings.maxLengthLabel,
          subtitle: AnnouncementStrings.maxLengthSubtitle,
          value: settings.maxLength.toDouble(),
          min: AnnouncementSettings.minMaxLength.toDouble(),
          max: AnnouncementSettings.maxMaxLength.toDouble(),
          // 56 steps over the 40–600 range land on exact 10-character values.
          divisions: 56,
          defaultValue: AnnouncementSettings.defaultMaxLength.toDouble(),
          formatValue: (value) =>
              AnnouncementStrings.maxLengthValue(value.round()),
          onChanged: (value) => settings.setMaxLength(value.round()),
        ),
        settingsCardDivider(palette),
        SettingsSwitchTile(
          Icons.volume_down_rounded,
          AnnouncementStrings.duckAudioTitle,
          AnnouncementStrings.duckAudioSubtitle,
          value: settings.duckAudio,
          onChanged: settings.setDuckAudio,
        ),
      ],
    );
  }

  Widget _skipSection(BuildContext context, AnnouncementSettings settings) {
    final palette = context.palette;
    return SettingsSection(
      icon: Icons.visibility_off_rounded,
      title: AnnouncementStrings.sectionSkip,
      subtitle: AnnouncementStrings.sectionSkipSubtitle,
      children: [
        SettingsSwitchTile(
          Icons.cast_rounded,
          AnnouncementStrings.skipCastingTitle,
          AnnouncementStrings.skipCastingSubtitle,
          value: settings.skipWhenCasting,
          onChanged: settings.setSkipWhenCasting,
        ),
        settingsCardDivider(palette),
        SettingsSwitchTile(
          Icons.hd_rounded,
          AnnouncementStrings.skipBitPerfectTitle,
          AnnouncementStrings.skipBitPerfectSubtitle,
          value: settings.skipWhenBitPerfect,
          onChanged: settings.setSkipWhenBitPerfect,
        ),
      ],
    );
  }

  Widget _voiceSection(BuildContext context, AnnouncementSettings settings) {
    final palette = context.palette;
    return SettingsSection(
      icon: Icons.graphic_eq_rounded,
      title: AnnouncementStrings.sectionVoice,
      subtitle: AnnouncementStrings.sectionVoiceSubtitle,
      children: [
        FutureBuilder<List<TtsVoice>>(
          future: _voicesFuture,
          builder: (context, snapshot) {
            if (!widget.engine.isAvailable) {
              return ListTile(
                contentPadding: _rowPadding,
                leading: const SettingsIconBox(Icons.record_voice_over_rounded),
                title: Text(AnnouncementStrings.voiceLabel),
                subtitle: Text(
                  AnnouncementStrings.unavailableTitle,
                ),
                trailing: _refreshVoicesButton(),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return ListTile(
                contentPadding: _rowPadding,
                leading: const SettingsIconBox(Icons.record_voice_over_rounded),
                title: Text(AnnouncementStrings.voiceLabel),
                subtitle: Text(AnnouncementStrings.voiceLoading),
              );
            }
            return _voicePicker(
              context,
              settings,
              snapshot.data ?? const <TtsVoice>[],
            );
          },
        ),
        settingsCardDivider(palette),
        ListTile(
          contentPadding: _rowPadding,
          leading: const SettingsIconBox(Icons.play_circle_outline_rounded),
          title: Text(AnnouncementStrings.testTitle),
          subtitle: Text(AnnouncementStrings.testSubtitle),
          trailing: FilledButton(
            onPressed: widget.engine.isAvailable ? _speakPreview : null,
            child: Text(AnnouncementStrings.testButton),
          ),
        ),
      ],
    );
  }

  Widget _voicePicker(
    BuildContext context,
    AnnouncementSettings settings,
    List<TtsVoice> voices,
  ) {
    final palette = context.palette;
    if (voices.isEmpty) {
      return ListTile(
        contentPadding: _rowPadding,
        leading: const SettingsIconBox(Icons.record_voice_over_rounded),
        title: Text(AnnouncementStrings.voiceLabel),
        subtitle: Text(AnnouncementStrings.voiceNoneInstalled),
        trailing: _refreshVoicesButton(),
      );
    }
    final ids = voices.map((voice) => voice.id).toSet();
    // A stored id can disappear after a system voice update; falling back to
    // the default keeps DropdownButton's value/items assertion satisfied.
    final selected = ids.contains(settings.voiceId) ? settings.voiceId : '';
    return ListTile(
      contentPadding: _rowPadding,
      leading: const SettingsIconBox(Icons.record_voice_over_rounded),
      title: Text(AnnouncementStrings.voiceLabel),
      trailing: _refreshVoicesButton(),
      subtitle: Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            dropdownColor: palette.surfaceContainer,
            borderRadius: AppRadii.r12All,
            icon: Icon(Icons.expand_more_rounded, color: palette.textSecondary),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: AppFontSize.label,
              fontWeight: FontWeight.w600,
            ),
            items: [
              DropdownMenuItem<String>(
                value: '',
                child: Text(AnnouncementStrings.voiceSystemDefault),
              ),
              for (final voice in voices)
                DropdownMenuItem<String>(
                  value: voice.id,
                  child: Text(
                    AnnouncementStrings.voiceOption(
                      voice.name,
                      voice.localeCode,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => _selectVoice(value, voices),
          ),
        ),
      ),
    );
  }

  /// Re-lists the installed voices (and retries `init` for a channel engine).
  Widget _refreshVoicesButton() {
    return IconButton(
      tooltip: AnnouncementStrings.voiceRefresh,
      icon: const Icon(Icons.refresh_rounded),
      onPressed: () => unawaited(_prepareVoices()),
    );
  }

  void _selectVoice(String? value, List<TtsVoice> voices) {
    final settings = widget.settings;
    if (value == null || value.isEmpty) {
      settings.setVoiceId('');
      settings.setLocaleId('');
      _applyToChannelEngine('', '');
      return;
    }
    final voice = voices.firstWhere((candidate) => candidate.id == value);
    settings.setVoiceId(voice.id);
    settings.setLocaleId(voice.localeCode);
    _applyToChannelEngine(voice.id, voice.localeCode);
  }

  void _applyToChannelEngine(String voiceId, String localeId) {
    final engine = widget.engine;
    if (engine is! MethodChannelTtsEngine) return;
    engine.voiceId = voiceId;
    engine.localeId = localeId;
  }

  Future<void> _speakPreview() async {
    final settings = widget.settings;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final track = widget.previewTrack ??
        AnnouncementTrack(
          title: AnnouncementStrings.previewTrackTitle,
          artist: AnnouncementStrings.previewTrackArtist,
        );
    final l10n = context.l10n;
    final text = composeAnnouncement(
      settings.elements,
      track,
      maxLength: settings.maxLength,
      formatYear: (y) => AnnouncementStrings.yearLabel(y, l10n),
      formatTrackNumber: (n) => AnnouncementStrings.trackNumberLabel(n, l10n),
    );
    if (text.isEmpty) {
      messenger?.showSnackBar(SnackBar(
        content: Text(AnnouncementStrings.emptySelection),
      ));
      return;
    }
    try {
      await widget.engine.speak(
        text,
        volume: settings.volume,
        duckAudio: settings.duckAudio,
      );
    } on Exception catch (error, stackTrace) {
      ErrorLogger.log(
        'Test announcement could not be spoken',
        error: error,
        stackTrace: stackTrace,
        category: 'Announcements',
      );
      messenger?.showSnackBar(SnackBar(
        content: Text(AnnouncementStrings.unavailableTitle),
      ));
    }
  }

  static const EdgeInsets _rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.s2,
  );

  static IconData _elementIcon(AnnouncementElement element) =>
      switch (element) {
        AnnouncementElement.title => Icons.music_note_rounded,
        AnnouncementElement.artist => Icons.person_outline_rounded,
        AnnouncementElement.album => Icons.album_outlined,
        AnnouncementElement.year => Icons.calendar_today_outlined,
        AnnouncementElement.trackNumber => Icons.format_list_numbered_rounded,
      };
}

/// Blocking status line shown when the platform cannot speak.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: palette.warning.withValues(alpha: 0.12),
          borderRadius: AppRadii.r12All,
          border: Border.all(color: palette.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.voice_over_off_rounded,
                color: palette.warning, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AnnouncementStrings.unavailableTitle,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    AnnouncementStrings.unavailableBody,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: AppFontSize.caption,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
