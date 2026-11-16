// lib/features/remote_sources/remote_provider_factory.dart
//
// P0-1 "remote sources": one place that maps a source kind to a provider.
//
// Screens and the main agent's playback wiring take a
// [RemoteProviderFactory] instead of constructing providers themselves, which
// keeps the SMB/WebDAV/FTP switch in a single spot and lets tests inject a fake.
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'ftp_fs_provider.dart';
import 'remote_credentials_store.dart';
import 'smb_fs_provider.dart';
import 'webdav_fs_provider.dart';

/// Builds a provider for [source] using [credentials] (may be `null`).
typedef RemoteProviderFactory = RemoteFsProvider Function(
  RemoteSource source,
  RemoteCredentials? credentials,
);

/// Production factory: picks the implementation matching `source.kind`.
///
/// SMB requires the Android plugin; on any other platform [SmbFsProvider]
/// raises a [RemoteUnavailableError] the first time it is used instead of
/// pretending the share is empty.
RemoteFsProvider createRemoteProvider(
  RemoteSource source,
  RemoteCredentials? credentials,
) {
  switch (source.kind) {
    case RemoteSourceKind.webdav:
      return WebDavFsProvider(
        source,
        username: credentials?.username,
        password: credentials?.password,
      );
    case RemoteSourceKind.ftp:
      return FtpFsProvider(
        source,
        username: credentials?.username,
        password: credentials?.password,
      );
    case RemoteSourceKind.smb:
      return SmbFsProvider(
        source,
        username: credentials?.username,
        password: credentials?.password,
      );
  }
}
