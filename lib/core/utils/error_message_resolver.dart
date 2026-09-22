import 'package:flutter/material.dart';
import 'l10n_extensions.dart';

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
    return context.l10n.libraryReadError;
  }
}

String resolveUiErrorMessage(BuildContext context, Object error) =>
    ErrorMessageResolver.resolveUserFriendly(context, error);
