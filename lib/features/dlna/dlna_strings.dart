// lib/features/dlna/dlna_strings.dart
//
// Localized copy for the DLNA module, backed by ARB (`AppLocalizations`) with
// automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../l10n/generated/app_localizations.dart';
import 'dlna_renderer_service.dart';

/// User-facing copy for the DLNA module.
abstract final class DlnaStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  /// Screen title.
  static String get title => _l10n().dlnaTitle;

  /// One-line explanation under the title.
  static String get subtitle => _l10n().dlnaSubtitle;

  /// Label of the scan button.
  static String get scan => _l10n().dlnaScan;

  /// Label of the button that picks a local file and casts it.
  static String get castFile => _l10n().dlnaCastFile;

  /// Label of the button that casts the track playing on this device.
  static String get castCurrentTrack => _l10n().dlnaCastCurrentTrack;

  /// Semantics label for the cast-file action.
  static String get castFileSemantics => _l10n().dlnaCastFileSemantics;

  /// Semantics label for the cast-current-track action.
  static String get castCurrentSemantics => _l10n().dlnaCastCurrentSemantics;

  /// Label shown while discovery runs.
  static String get scanning => _l10n().dlnaScanning;

  /// Empty-state copy when discovery finds nothing.
  static String get noDevices => _l10n().dlnaNoDevices;

  /// Button that connects to one device.
  static String get connect => _l10n().dlnaConnect;

  /// Shown for the device currently under control.
  static String get connected => _l10n().dlnaConnected;

  /// Placeholder when nothing has been cast yet.
  static String get nothingPlaying => _l10n().dlnaNothingPlaying;

  /// Pause control label and tooltip.
  static String get pause => _l10n().dlnaPause;

  /// Previous control label and tooltip.
  static String get previous => _l10n().dlnaPrevious;

  /// Next control label and tooltip.
  static String get next => _l10n().dlnaNext;

  /// Resume control label and tooltip.
  static String get resume => _l10n().dlnaResume;

  /// Stop control label and tooltip.
  static String get stop => _l10n().dlnaStop;

  /// Label of the seek slider.
  static String get seek => _l10n().dlnaSeek;

  /// Heading of the now-playing card.
  static String get nowPlaying => _l10n().dlnaNowPlaying;

  /// Retry button in the error banner.
  static String get retry => _l10n().dlnaRetry;

  /// Title of the error banner.
  static String get errorTitle => _l10n().dlnaErrorTitle;

  /// Banner message after repeated position-poll failures.
  static String get pollLost => _l10n().dlnaPollLost;

  /// Semantics label for the scan button.
  static String get scanSemantics => _l10n().dlnaScanSemantics;

  /// Semantics label for the connect action on a named device.
  static String connectTo(String deviceName, [AppLocalizations? l10n]) =>
      _l10n(l10n).dlnaConnectTo(deviceName);

  /// Semantics label for the device row, including the model when known.
  static String deviceRow(String name, String? model) =>
      model == null || model.isEmpty ? name : '$name, $model';

  /// Transport label while the position poll is lost: the last state is
  /// displayed but must not read as live.
  static String get stateStale => _l10n().dlnaStateStale;

  /// Short label for the current transport state.
  static String stateLabel(DlnaState state, [AppLocalizations? l10n]) {
    final l = _l10n(l10n);
    switch (state) {
      case DlnaState.idle:
        return l.dlnaStateReady;
      case DlnaState.discovering:
        return l.dlnaStateScanning;
      case DlnaState.connecting:
        return l.dlnaStateConnecting;
      case DlnaState.playing:
        return l.dlnaStatePlaying;
      case DlnaState.paused:
        return l.dlnaStatePaused;
      case DlnaState.stopped:
        return l.dlnaStateStopped;
      case DlnaState.error:
        return l.dlnaStateError;
    }
  }
}
