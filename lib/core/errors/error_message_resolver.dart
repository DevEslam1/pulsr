// lib/core/errors/error_message_resolver.dart
import 'package:flutter/widgets.dart';
import '../utils/l10n_extensions.dart';

/// Localizes English-only error strings emitted by cubits and services (which
/// have no `BuildContext`) at the display site. Covers player, YouTube Music,
/// auth, downloads, and library errors.
///
/// Unknown or changed literals pass through untouched, so the UI never breaks
/// when a new message appears before a key exists for it.
String resolveUiErrorMessage(BuildContext context, String message) {
  final l10n = context.l10n;

  switch (message) {
    case 'Failed to save queue':
      return l10n.errSaveQueue;
    case 'Failed to clear queue':
      return l10n.errClearQueue;
    case 'Failed to reorder queue':
      return l10n.errReorderQueue;
    case 'Failed to remove track':
      return l10n.errRemoveTrack;
    case 'Queue slot is empty':
      return l10n.errQueueSlotEmpty;
    case 'Failed to switch queue slot':
      return l10n.errSwitchQueueSlot;
    case 'Invalid stream URL':
      return l10n.errInvalidStreamUrl;
    case 'Pitch change failed':
      return l10n.errPitchFailed;
    case 'Playback action failed':
      return l10n.errPlaybackActionFailed;
    case 'Speed change failed':
      return l10n.errSpeedFailed;
    case 'Volume change failed':
      return l10n.errVolumeFailed;
    case 'Shuffle failed':
      return l10n.errShuffleFailed;
    case 'Repeat failed':
      return l10n.errRepeatFailed;
    case 'Skip failed':
      return l10n.errSkipFailed;
    case 'Seek failed, position restored':
      return l10n.errSeekFailed;
    case 'Impulse response rejected by the audio engine':
      return l10n.errIrRejected;
    case 'Local match unavailable, streaming online':
      return l10n.errLocalMatchStreaming;
  }

  // Song titles are data, not UI text: only the template is translated.
  // The no-colon guard keeps DSP messages ('Failed to add dynamic EQ band:
  // ...') out of the song-title branch.
  if (message.startsWith('Failed to play ') && !message.contains(': ')) {
    return l10n.errPlayFailed(message.substring('Failed to play '.length));
  }
  if (message.startsWith('Failed to add ') && !message.contains(': ')) {
    return l10n.errAddFailed(message.substring('Failed to add '.length));
  }

  final queueFull =
      RegExp(r'^Queue full \((\d+)\) - cannot add more$').firstMatch(message);
  if (queueFull != null) {
    return l10n.errQueueFull(queueFull.group(1)!);
  }

  // YouTube Music / network / account errors. Matched by stem so '.' and
  // '…' variants both resolve. Checked before the generic DSP prefix loop.
  if (message.startsWith('No connection. Check your network')) {
    return l10n.errYtmNoConnection;
  }
  if (message.startsWith('Playback failed. Please try again')) {
    return l10n.errYtmPlaybackFailed;
  }
  if (message.startsWith('Something went wrong with YouTube Music')) {
    return l10n.errYtmGeneric;
  }
  if (message.startsWith('This track is restricted in your region')) {
    return l10n.errYtmRegionRestricted;
  }
  if (message.startsWith('This track is unavailable')) {
    return l10n.errYtmUnavailable;
  }
  if (message.startsWith('YouTube session expired. Tap to reconnect')) {
    return l10n.errYtmSessionExpired;
  }
  if (message.startsWith('YouTube Music is not available in this build')) {
    return l10n.errYtmNotInBuild;
  }
  if (message.startsWith('Backend proxy authentication failed')) {
    return l10n.errYtmProxyAuth;
  }
  if (message.startsWith('Signature deciphering unavailable for this format')) {
    return l10n.errYtmSigFail;
  }
  if (message.startsWith('YouTube is busy. Cooling down')) {
    return l10n.errYtmBusy;
  }
  if (message.startsWith('YouTube is having trouble. Retrying')) {
    return l10n.errYtmTrouble;
  }
  if (message.startsWith('Stream extraction failed. Switching route')) {
    return l10n.errYtmExtractFail;
  }
  if (message.startsWith('YouTube needs verification. Trying alternate route')) {
    return l10n.errYtmVerify;
  }
  if (message.startsWith('Sign in failed. Please try again')) {
    return l10n.errSignInFailed;
  }
  if (message.startsWith('Sign up failed. Please try again')) {
    return l10n.errSignUpFailed;
  }
  if (message.startsWith('Failed to load downloads')) {
    return l10n.errLoadDownloads;
  }
  if (message.startsWith('Could not retry failed downloads')) {
    return l10n.errRetryDownloads;
  }
  if (message.startsWith('Not signed in to YouTube Music')) {
    return l10n.errYtmNotSignedIn;
  }
  if (message.startsWith('Failed to sync YouTube Music likes')) {
    return l10n.errYtmSyncLikes;
  }
  if (message.startsWith('Search failed')) {
    return l10n.errSearchFailed;
  }
  if (message.startsWith('Please enter a playlist name')) {
    return l10n.errPlaylistNameRequired;
  }

  // Download failures. The repository stores the raw service message; match by
  // stem so both the '…' and '.' variants and interpolated details resolve.
  if (message.startsWith('Wi-Fi Only Mode is active')) {
    return l10n.downloadWifiOnly;
  }
  if (message.startsWith('Offline Only Mode is active')) {
    return l10n.downloadOfflineOnly;
  }
  if (message.startsWith('Insufficient storage') ||
      message.startsWith('Storage full') ||
      message.startsWith('MediaStore did not return') ||
      message.startsWith('Downloaded file was not found')) {
    return l10n.downloadErrorStorage;
  }
  if (message.startsWith('Downloaded audio file is corrupt') ||
      message.startsWith('Downloaded file was corrupted') ||
      message.startsWith('Downloaded file was not created') ||
      message.startsWith('Download incomplete') ||
      message.startsWith('Parallel download byte mismatch') ||
      message.startsWith('Merged file size mismatch') ||
      message.startsWith('Chunk ')) {
    return l10n.downloadErrorCorrupt;
  }
  if (message.startsWith('No connection while downloading') ||
      message.startsWith('Download network timeout')) {
    return l10n.downloadErrorNetwork;
  }
  if (message.startsWith('YouTube is busy') ||
      message.startsWith('HTTP 429') ||
      message.contains('Rate limited')) {
    return l10n.downloadErrorRateLimited;
  }
  if (message.startsWith('Download timed out')) {
    return l10n.downloadErrorTimeout;
  }
  if (message.startsWith('YouTube verification triggered') ||
      message.startsWith('HTTP 403') ||
      message.startsWith('HTTP 401')) {
    return l10n.downloadErrorBotChallenge;
  }
  if (message.startsWith('This track is unavailable')) {
    return l10n.downloadErrorUnavailable;
  }
  if (message.startsWith('Download canceled') ||
      message.startsWith('Download cancelled')) {
    return l10n.downloadErrorInterrupted;
  }

  // Technical DSP/file failures: translate the template, keep the raw detail
  // (exception text / parameter) verbatim.
  for (final prefix in [
    'Failed to set ',
    'Failed to apply ',
    'Failed to update ',
    'Failed to load ',
    'Failed to add ',
    'Failed to remove ',
  ]) {
    if (message.startsWith(prefix)) {
      final sep = message.indexOf(': ');
      final detail =
          sep >= 0 ? message.substring(sep + 2) : message.substring(prefix.length);
      return l10n.errAudioSettingFailed(detail);
    }
  }

  return message;
}

/// Humanizes raw error messages and system exceptions into user-friendly copy.
class ErrorMessageResolver {
  const ErrorMessageResolver._();

  static String resolveUserFriendly(BuildContext context, Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('network') ||
        raw.contains('connection refused') ||
        raw.contains('timed out') ||
        raw.contains('clientexception')) {
      return 'Network connection error. Please check your internet connection and retry.';
    }
    if (raw.contains('permissiondenied') ||
        raw.contains('permission_denied') ||
        raw.contains('denied')) {
      return 'Storage permission was denied. Please grant permission in system settings.';
    }
    if (raw.contains('filenotfound') || raw.contains('no such file')) {
      return 'The requested audio file was not found on your storage.';
    }
    if (raw.contains('formatexception') || raw.contains('invalid json')) {
      return 'Encountered unexpected or corrupt data format.';
    }
    if (raw.contains('quota') || raw.contains('429')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (raw.contains('unsupported') || raw.contains('notsupported')) {
      return 'This feature or audio format is not supported on this device.';
    }
    try {
      return context.l10n.libraryReadError;
    } catch (_) {
      return 'An error occurred while accessing the library.';
    }
  }
}

