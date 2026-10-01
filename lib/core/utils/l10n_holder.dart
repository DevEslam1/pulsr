import '../../l10n/generated/app_localizations.dart';

/// Holds the current [AppLocalizations] so non-widget code (cubits/services)
/// can emit localized text while still falling back to English in tests.
class L10nHolder {
  L10nHolder._();
  static AppLocalizations? current;
}
