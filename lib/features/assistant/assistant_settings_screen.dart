// lib/features/assistant/assistant_settings_screen.dart
//
// Small opt-in surface for the assistant search-suggestion cache. It edits
// [AssistantSettings] directly (the object notifies listeners) and clears the
// native cache when the user turns the toggle off.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/di/injection.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/pulsr_adaptive_sheet.dart';
import '../../domain/repositories/music_repository_interface.dart';
import 'assistant_search_channel.dart';
import 'assistant_settings.dart';
import 'assistant_strings.dart';
import 'assistant_suggestion_sync.dart';

AssistantSuggestionSync? _resolveSuggestionSync(
  AssistantSettings settings,
  AssistantSuggestionSync? provided,
) {
  if (provided != null) return provided;
  if (getIt.isRegistered<AssistantSuggestionSync>()) {
    return getIt<AssistantSuggestionSync>();
  }
  if (getIt.isRegistered<IMusicRepository>()) {
    return AssistantSuggestionSync(
      repository: getIt<IMusicRepository>(),
      settings: settings,
    );
  }
  return null;
}

/// Screen with the assistant suggestion toggle.
class AssistantSettingsScreen extends StatelessWidget {
  const AssistantSettingsScreen({
    super.key,
    required this.settings,
    this.suggestionSync,
  });

  /// Persisted toggle this screen edits.
  final AssistantSettings settings;

  /// Optional sync used to clear cached rows when the toggle turns off.
  final AssistantSuggestionSync? suggestionSync;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final effectiveSync = _resolveSuggestionSync(settings, suggestionSync);
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        title: Text(
          AssistantStrings.settingsTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            children: <Widget>[
              Text(
                AssistantStrings.suggestionsSection,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: palette.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SwitchListTile.adaptive(
                value: settings.suggestionsEnabled,
                title: Text(AssistantStrings.suggestionsTitle),
                subtitle: Text(AssistantStrings.suggestionsSubtitle),
                onChanged: (value) {
                  settings.setSuggestionsEnabled(value);
                  if (value) {
                    unawaited(effectiveSync?.pushRecent());
                  } else {
                    _clearSuggestionCache(effectiveSync);
                  }
                },
              ),
              if (!settings.suggestionsEnabled) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AssistantStrings.suggestionsOffNotice,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Clears cached rows without requiring the repository (the toggle may be used
/// before a sync object exists).
void _clearSuggestionCache(AssistantSuggestionSync? sync) {
  unawaited(() async {
    try {
      if (sync != null) {
        await sync.clear();
      } else {
        await AssistantSearchChannel().clear();
      }
    } catch (error, stackTrace) {
      // Both paths are already failure-tolerant; this is a last-resort guard.
      ErrorLogger.log(
        'Assistant suggestion cache could not be cleared',
        error: error,
        stackTrace: stackTrace,
        category: 'Assistant',
      );
    }
  }());
}

/// Shows the same toggle in an adaptive modal sheet.
Future<void> showAssistantSettingsSheet(
  BuildContext context, {
  required AssistantSettings settings,
  AssistantSuggestionSync? suggestionSync,
}) {
  final effectiveSync = _resolveSuggestionSync(settings, suggestionSync);
  return PulsrAdaptiveSheet.show<void>(
    context: context,
    title: Text(AssistantStrings.settingsTitle),
    builder: (context) => SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: SwitchListTile.adaptive(
            value: settings.suggestionsEnabled,
            title: Text(AssistantStrings.suggestionsTitle),
            subtitle: Text(AssistantStrings.suggestionsSubtitle),
            onChanged: (value) {
              settings.setSuggestionsEnabled(value);
              if (value) {
                unawaited(effectiveSync?.pushRecent());
              } else {
                _clearSuggestionCache(effectiveSync);
              }
            },
          ),
        ),
      ),
    ),
  );
}
