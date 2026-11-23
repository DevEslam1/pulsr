import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';
import 'update_dialog.dart';

/// Parsed SemVer representation.
class ParsedVersion {
  final List<int> parts;
  final bool isPreRelease;

  const ParsedVersion(this.parts, this.isPreRelease);

  static ParsedVersion parse(String raw) {
    final clean =
        raw.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final dash = clean.indexOf('-');
    final base = dash >= 0 ? clean.substring(0, dash) : clean;
    final isPre = dash >= 0;
    final parts = base.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    return ParsedVersion(parts, isPre);
  }

  static bool isNewer(String latest, String current) {
    final l = parse(latest);
    final c = parse(current);
    final maxLen =
        l.parts.length > c.parts.length ? l.parts.length : c.parts.length;
    for (int i = 0; i < maxLen; i++) {
      final a = i < l.parts.length ? l.parts[i] : 0;
      final b = i < c.parts.length ? c.parts[i] : 0;
      if (a != b) return a > b;
    }
    // A stable release outranks a pre-release of the same numbers (e.g. 1.0.0 vs 1.0.0-beta)
    return c.isPreRelease && !l.isPreRelease;
  }
}

/// Information about an available app release.
class UpdateInfo {
  final String version;
  final String tagName;
  final String releaseUrl;
  final String? apkUrl;
  final String? sha256;
  final String? notes;
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseUrl,
    this.apkUrl,
    this.sha256,
    this.notes,
    this.publishedAt,
  });

  static String? _normalizeSha256(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim().toLowerCase();
    if (cleaned.startsWith('sha256:')) {
      cleaned = cleaned.substring(7).trim();
    }
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(cleaned) ? cleaned : null;
  }

  factory UpdateInfo.fromGitHubJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final version =
        tagName.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final releaseUrl = json['html_url'] as String? ?? '';
    final notes = json['body'] as String?;

    String? apkUrl;
    String? sha256;
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = asset['name'] as String? ?? '';
          final state = asset['state'] as String? ?? '';
          if (name.toLowerCase().endsWith('.apk') && state == 'uploaded') {
            apkUrl = asset['browser_download_url'] as String?;
            sha256 = _normalizeSha256(
              (asset['digest'] as String?) ?? (asset['sha256'] as String?),
            );
            break;
          }
        }
      }
    }

    if (sha256 == null && notes != null && notes.isNotEmpty) {
      final match = RegExp(
        r'sha-?256[:\s]+([a-fA-F0-9]{64})',
        caseSensitive: false,
      ).firstMatch(notes);
      if (match != null) {
        sha256 = match.group(1)?.toLowerCase();
      }
    }

    DateTime? published;
    final pubStr = json['published_at'] as String?;
    if (pubStr != null) {
      published = DateTime.tryParse(pubStr);
    }

    return UpdateInfo(
      version: version,
      tagName: tagName,
      releaseUrl: releaseUrl,
      apkUrl: apkUrl,
      sha256: sha256,
      notes: notes,
      publishedAt: published,
    );
  }
}

/// Service that queries GitHub releases, downloads APK updates with progress,
/// and launches the platform package installer.
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();

  AppUpdateService._internal({http.Client? client})
      : _client = client ?? http.Client();

  factory AppUpdateService({http.Client? client}) {
    if (client != null) {
      return AppUpdateService._internal(client: client);
    }
    return instance;
  }

  static const String defaultRepo = 'pulsr-audio/pulsr';
  static const MethodChannel _updaterChannel =
      MethodChannel(PulsrChannels.updater);
  static const Set<String> allowedApkHostSuffixes = {
    'github.com',
    'githubusercontent.com',
  };
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration streamChunkTimeout = Duration(seconds: 30);

  final http.Client _client;
  String _repo = defaultRepo;
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _cancelDownload = false;
  Future<File?>? _activeDownloadFuture;

  String get repo => _repo;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;

  /// Enforces HTTPS and an allowlist of official GitHub release hosts.
  static bool isAllowedApkUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return allowedApkHostSuffixes.any(
      (suffix) => host == suffix || host.endsWith('.$suffix'),
    );
  }

  /// Sanitizes a version string before interpolating it into an APK filename.
  static String sanitizeVersionForFilename(String rawVersion) {
    final sanitized = rawVersion
        .trim()
        .replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '_');
    final cleaned = sanitized.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  void configureRepo(String repo) {
    if (repo.trim().isNotEmpty) {
      _repo = repo.trim();
    }
  }

  /// Checks GitHub releases API for newer app version.
  Future<UpdateInfo?> check({String? currentVersionOverride}) async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final currentVersion = currentVersionOverride ?? AppConfig.appVersion;
      final uri =
          Uri.parse('https://api.github.com/repos/$_repo/releases/latest');
      final res = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'PulsrMusic/$currentVersion',
        },
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final info = UpdateInfo.fromGitHubJson(json);
        if (ParsedVersion.isNewer(info.version, currentVersion)) {
          return info;
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'AppUpdateService.check failed',
        error: e,
        stackTrace: st,
        category: 'Updater',
      );
    } finally {
      _isChecking = false;
    }
    return null;
  }

  /// Cancels any in-flight download.
  void cancelDownload() {
    _cancelDownload = true;
  }

  /// Downloads the release APK into the app cache directory, tracking progress from 0.0 to 1.0.
  Future<File?> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    Directory? cacheDirectoryOverride,
    Duration? chunkTimeoutOverride,
  }) {
    if (_isDownloading && _activeDownloadFuture != null) {
      return _activeDownloadFuture!;
    }
    final future = _performDownloadApk(
      info,
      onProgress: onProgress,
      cacheDirectoryOverride: cacheDirectoryOverride,
      chunkTimeoutOverride: chunkTimeoutOverride,
    );
    _activeDownloadFuture = future;
    return future;
  }

  Future<File?> _performDownloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    Directory? cacheDirectoryOverride,
    Duration? chunkTimeoutOverride,
  }) async {
    final apkUrl = info.apkUrl?.trim();
    if (apkUrl == null || apkUrl.isEmpty) {
      throw StateError(
          'No APK download URL available for release ${info.version}');
    }
    if (!isAllowedApkUrl(apkUrl)) {
      throw ArgumentError.value(
        apkUrl,
        'apkUrl',
        'APK download URL must use HTTPS and an allowed GitHub release host.',
      );
    }
    final expectedSha256 = UpdateInfo._normalizeSha256(info.sha256);
    if (info.sha256 != null &&
        info.sha256!.trim().isNotEmpty &&
        expectedSha256 == null) {
      throw ArgumentError.value(
        info.sha256,
        'sha256',
        'Invalid SHA-256 digest format.',
      );
    }

    _isDownloading = true;
    _cancelDownload = false;
    IOSink? sink;
    File? targetFile;
    var completedSuccessfully = false;

    try {
      final cacheDir =
          cacheDirectoryOverride ?? await getApplicationCacheDirectory();
      final updatesDir = Directory('${cacheDir.path}/updates');
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      } else {
        // Clear old downloads
        try {
          final list = updatesDir.listSync();
          for (final f in list) {
            if (f is File) f.deleteSync();
          }
        } catch (e) {
          ErrorLogger.logSwallowed('AppUpdateService.clearUpdatesDir', e);
        }
      }

      final safeVersion = sanitizeVersionForFilename(info.version);
      targetFile = File('${updatesDir.path}/pulsr-$safeVersion.apk');

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await _client.send(request).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw HttpException(
            'HTTP download failed with code ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      sink = targetFile.openWrite();
      final chunkTimeout = chunkTimeoutOverride ?? streamChunkTimeout;

      await for (final chunk in response.stream.timeout(chunkTimeout)) {
        if (_cancelDownload) {
          return null;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          final ratio = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(ratio);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (_cancelDownload) {
        return null;
      }

      if (expectedSha256 != null) {
        final bytes = await targetFile.readAsBytes();
        final actualSha256 = sha256.convert(bytes).toString().toLowerCase();
        if (actualSha256 != expectedSha256) {
          throw StateError(
            'APK SHA-256 checksum mismatch (expected $expectedSha256, got $actualSha256)',
          );
        }
      }

      completedSuccessfully = true;
      return targetFile;
    } catch (e, st) {
      ErrorLogger.log(
        'AppUpdateService.downloadApk failed',
        error: e,
        stackTrace: st,
        category: 'Updater',
      );
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (e) {
        ErrorLogger.logSwallowed('AppUpdateService.closeSink', e);
      }
      if (!completedSuccessfully && targetFile != null) {
        try {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
        } catch (e) {
          ErrorLogger.logSwallowed('AppUpdateService.deletePartialApk', e);
        }
      }
      _isDownloading = false;
      _activeDownloadFuture = null;
    }
  }

  /// Triggers package installation via platform intent or channel.
  Future<bool> installApk(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('APK file does not exist', file.path);
    }

    if (Platform.isAndroid) {
      try {
        final result = await _updaterChannel.invokeMethod<String>(
          'installApk',
          {'filePath': file.path},
        );
        return result == 'INSTALLING' || result == 'REQUESTED_PERMISSION';
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to trigger Android installer via MethodChannel',
          error: e,
          stackTrace: st,
          category: 'Updater',
        );
      }
    }
    return false;
  }

  /// Checks for updates with interactive user feedback.
  Future<void> checkForUpdates(
    BuildContext context, {
    bool userInitiated = false,
  }) async {
    if (!context.mounted) return;

    if (userInitiated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.updateChecking),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final update = await check();
    if (!context.mounted) return;

    if (update != null) {
      UpdateDialog.show(context, update);
    } else if (userInitiated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10n.updateUpToDate('v${AppConfig.appVersion}')),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void dispose() {
    cancelDownload();
    _client.close();
  }
}
