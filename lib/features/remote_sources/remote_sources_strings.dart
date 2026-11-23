// lib/features/remote_sources/remote_sources_strings.dart
//
// Localized copy for the remote sources module, backed by ARB
// (`AppLocalizations`) with automatic English fallback in headless tests.

import 'dart:ui' show Locale;

import '../../core/utils/l10n_holder.dart';
import '../../domain/models/remote_source.dart';
import '../../l10n/generated/app_localizations.dart';

/// User-facing text for the remote sources module.
abstract final class RemoteSourcesStrings {
  static final AppLocalizations _fallback =
      lookupAppLocalizations(const Locale('en'));

  static AppLocalizations _l10n([AppLocalizations? l10n]) =>
      l10n ?? L10nHolder.current ?? _fallback;

  // Screen chrome.
  static String get title => _l10n().remoteSrcTitle;
  static String get intro => _l10n().remoteSrcIntro;
  static String get addSource => _l10n().remoteSrcAddSource;
  static String get addSourceTooltip => _l10n().remoteSrcAddSourceTooltip;
  static String get emptyTitle => _l10n().remoteSrcEmptyTitle;
  static String get emptyBody => _l10n().remoteSrcEmptyBody;
  static String get loadFailed => _l10n().remoteSrcLoadFailed;
  static String get retry => _l10n().remoteSrcRetry;
  static String get loadMore => _l10n().remoteSrcLoadMore;

  // Row actions.
  static String get actionsTooltip => _l10n().remoteSrcActionsTooltip;
  static String get editSource => _l10n().remoteSrcEditSource;
  static String get deleteSource => _l10n().remoteSrcDeleteSource;
  static String get testConnection => _l10n().remoteSrcTestConnection;
  static String get testConnectionTooltip =>
      _l10n().remoteSrcTestConnectionTooltip;
  static String get testing => _l10n().remoteSrcTesting;
  static String get browse => _l10n().remoteSrcBrowse;

  // Editor.
  static String get editorAddTitle => _l10n().remoteSrcEditorAddTitle;
  static String get editorEditTitle => _l10n().remoteSrcEditorEditTitle;
  static String get kindLabel => _l10n().remoteSrcKindLabel;
  static String get nameLabel => _l10n().remoteSrcNameLabel;
  static String get nameHint => _l10n().remoteSrcNameHint;
  static String get hostLabel => _l10n().remoteSrcHostLabel;
  static String get hostHint => _l10n().remoteSrcHostHint;
  static String get portLabel => _l10n().remoteSrcPortLabel;
  static String get tlsLabel => _l10n().remoteSrcTlsLabel;
  static String get cleartextWarning => _l10n().remoteSrcCleartextWarning;
  static String get rootLabel => _l10n().remoteSrcRootLabel;
  static String get rootHint => _l10n().remoteSrcRootHint;
  static String get rootHintShare => _l10n().remoteSrcRootHintShare;
  static String get usernameLabel => _l10n().remoteSrcUsernameLabel;
  static String get passwordLabel => _l10n().remoteSrcPasswordLabel;
  static String get passwordKeepHint => _l10n().remoteSrcPasswordKeepHint;
  static String get subsonicUrlLabel => _l10n().remoteSrcSubsonicUrlLabel;
  static String get subsonicUrlHint => _l10n().remoteSrcSubsonicUrlHint;
  static String get subsonicUrlInvalid => _l10n().remoteSrcSubsonicUrlInvalid;
  static String get cancel => _l10n().remoteSrcCancel;
  static String get save => _l10n().remoteSrcSave;
  static String get saveFailed => _l10n().remoteSrcSaveFailed;
  static String get credentialsFailed => _l10n().remoteSrcCredentialsFailed;

  // Validation.
  static String get hostRequired => _l10n().remoteSrcHostRequired;
  static String get portRange => _l10n().remoteSrcPortRange;
  static String get nameRequired => _l10n().remoteSrcNameRequired;
  static String get rootRequired => _l10n().remoteSrcRootRequired;
  static String get shareRequired => _l10n().remoteSrcShareRequired;

  // Status.
  static String get connectedIn => _l10n().remoteSrcConnectedIn;
  static String get notTested => _l10n().remoteSrcNotTested;
  static String get anonymous => _l10n().remoteSrcAnonymous;

  // Browser.
  static String get browserTitle => _l10n().remoteSrcBrowserTitle;
  static String get rootCrumb => _l10n().remoteSrcRootCrumb;
  static String get emptyFolder => _l10n().remoteSrcEmptyFolder;
  static String get folderLoadFailed => _l10n().remoteSrcFolderLoadFailed;
  static String get close => _l10n().remoteSrcClose;
  static String get fileNameUnknown => _l10n().remoteSrcFileNameUnknown;
  static String get folderLabel => _l10n().remoteSrcFolderLabel;
  static String get searchLibrary => _l10n().remoteSrcSearchLibrary;
  static String get searchHint => _l10n().remoteSrcSearchHint;
  static String get searchClear => _l10n().remoteSrcSearchClear;
  static String get noSearchResults => _l10n().remoteSrcNoSearchResults;
  static String get artistsHeader => _l10n().remoteSrcArtistsHeader;
  static String get albumsHeader => _l10n().remoteSrcAlbumsHeader;
  static String get songsHeader => _l10n().remoteSrcSongsHeader;

  // Cache.
  static String get cacheTitle => _l10n().remoteSrcCacheTitle;
  static String get cacheBody => _l10n().remoteSrcCacheBody;
  static String get clearCache => _l10n().remoteSrcClearCache;
  static String get clearCacheTooltip => _l10n().remoteSrcClearCacheTooltip;
  static String get cacheCleared => _l10n().remoteSrcCacheCleared;
  static String get calculating => _l10n().remoteSrcCalculating;

  // UPnP discovery.
  static String get upnpTitle => _l10n().remoteSrcUpnpTitle;
  static String get upnpIntro => _l10n().remoteSrcUpnpIntro;
  static String get upnpSearch => _l10n().remoteSrcUpnpSearch;
  static String get upnpSearching => _l10n().remoteSrcUpnpSearching;
  static String get upnpNone => _l10n().remoteSrcUpnpNone;
  static String get upnpUse => _l10n().remoteSrcUpnpUse;
  static String get upnpFailed => _l10n().remoteSrcUpnpFailed;

  // Delete.
  static String get deleteTitle => _l10n().remoteSrcDeleteTitle;
  static String get deleteBody => _l10n().remoteSrcDeleteBody;

  /// Label shown for a [RemoteSourceKind].
  static String kindLabelFor(RemoteSourceKind kind) {
    switch (kind) {
      case RemoteSourceKind.webdav:
        return 'WebDAV';
      case RemoteSourceKind.ftp:
        return 'FTP';
      case RemoteSourceKind.smb:
        return 'SMB';
      case RemoteSourceKind.subsonic:
        return 'Subsonic / Navidrome';
      case RemoteSourceKind.upnp:
        return 'UPnP';
    }
  }

  /// One-line hint shown under the type selector.
  static String kindDescriptionFor(
    RemoteSourceKind kind, [
    AppLocalizations? l10n,
  ]) {
    final l = _l10n(l10n);
    switch (kind) {
      case RemoteSourceKind.webdav:
        return l.remoteSrcKindWebdavDesc;
      case RemoteSourceKind.ftp:
        return l.remoteSrcKindFtpDesc;
      case RemoteSourceKind.smb:
        return l.remoteSrcKindSmbDesc;
      case RemoteSourceKind.subsonic:
        return l.remoteSrcKindSubsonicDesc;
      case RemoteSourceKind.upnp:
        return l.remoteSrcKindUpnpDesc;
    }
  }

  /// Formats [bytes] with one decimal for the cache row.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  /// `Connected in 42 ms`.
  static String connectedInLabel(int milliseconds, [AppLocalizations? l10n]) =>
      _l10n(l10n).remoteSrcConnectedInMs(milliseconds);

  /// `Delete "Living room NAS"?`.
  static String deleteConfirmTitle(String name, [AppLocalizations? l10n]) =>
      _l10n(l10n).remoteSrcDeleteConfirmTitle(name);
}
