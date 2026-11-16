// lib/features/remote_sources/remote_sources_strings.dart
//
// P0-1 "remote sources": every English string this module renders.
//
// One file so the strings can be handed to a translator (or moved into the
// generated ARB catalogue) without touching the widgets.
import '../../domain/models/remote_source.dart';

/// User-facing text for the remote sources module.
abstract final class RemoteSourcesStrings {
  // Screen chrome.
  static const String title = 'Remote sources';
  static const String intro =
      'Play music stored on a NAS, a WebDAV server or an FTP host.';
  static const String addSource = 'Add source';
  static const String addSourceTooltip = 'Add a remote source';
  static const String emptyTitle = 'No remote sources yet';
  static const String emptyBody =
      'Add a WebDAV, FTP or SMB library to browse it from here.';
  static const String loadFailed =
      'The saved sources could not be read. They were kept on disk.';
  static const String retry = 'Retry';

  // Row actions.
  static const String actionsTooltip = 'Source actions';
  static const String editSource = 'Edit';
  static const String deleteSource = 'Delete';
  static const String testConnection = 'Test connection';
  static const String testConnectionTooltip = 'Test this connection';
  static const String testing = 'Testing…';
  static const String browse = 'Browse';

  // Editor.
  static const String editorAddTitle = 'Add a remote source';
  static const String editorEditTitle = 'Edit remote source';
  static const String kindLabel = 'Type';
  static const String nameLabel = 'Name';
  static const String nameHint = 'Living room NAS';
  static const String hostLabel = 'Host';
  static const String hostHint = '192.168.1.10 or nas.local';
  static const String portLabel = 'Port';
  static const String tlsLabel = 'Use HTTPS';
  static const String rootLabel = 'Root folder';
  static const String rootHint = '/Music';
  static const String rootHintShare = '/Share/Folder';
  static const String usernameLabel = 'Username';
  static const String passwordLabel = 'Password';
  static const String passwordKeepHint = 'Leave empty to keep the saved one';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String saveFailed = 'The source could not be saved.';
  static const String credentialsFailed =
      'The source was saved, but the password could not be stored securely.';

  // Validation.
  static const String hostRequired = 'Host is required.';
  static const String portRange = 'Port must be between 1 and 65535.';
  static const String nameRequired = 'Name is required.';
  static const String rootRequired = 'Set a root, for example /Music.';
  static const String shareRequired =
      'SMB needs a share in the root, for example /Music.';

  // Status.
  static const String connectedIn = 'Connected in';
  static const String notTested = 'Not tested yet';
  static const String anonymous = 'Anonymous';

  // Browser.
  static const String browserTitle = 'Browse';
  static const String rootCrumb = 'Root';
  static const String emptyFolder = 'This folder is empty.';
  static const String folderLoadFailed = 'This folder could not be read.';
  static const String close = 'Close';
  static const String fileNameUnknown = 'File';
  static const String folderLabel = 'Folder';

  // Cache.
  static const String cacheTitle = 'Cached audio';
  static const String cacheBody = 'Files you played are kept for fast seeking.';
  static const String clearCache = 'Clear cache';
  static const String clearCacheTooltip = 'Delete cached audio';
  static const String cacheCleared = 'Cached audio deleted.';
  static const String calculating = 'Calculating…';

  // Delete.
  static const String deleteTitle = 'Delete this source?';
  static const String deleteBody =
      'Its saved password and cached audio are removed too.';

  /// Label shown for a [RemoteSourceKind].
  static String kindLabelFor(RemoteSourceKind kind) {
    switch (kind) {
      case RemoteSourceKind.webdav:
        return 'WebDAV';
      case RemoteSourceKind.ftp:
        return 'FTP';
      case RemoteSourceKind.smb:
        return 'SMB';
    }
  }

  /// One-line hint shown under the type selector.
  static String kindDescriptionFor(RemoteSourceKind kind) {
    switch (kind) {
      case RemoteSourceKind.webdav:
        return 'Nextcloud, ownCloud, Apache mod_dav';
      case RemoteSourceKind.ftp:
        return 'Plain FTP servers and routers';
      case RemoteSourceKind.smb:
        return 'Windows shares and Samba (Android only)';
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
  static String connectedInLabel(int milliseconds) =>
      '$connectedIn $milliseconds ms';

  /// `Delete "Living room NAS"?`.
  static String deleteConfirmTitle(String name) => 'Delete "$name"?';
}
