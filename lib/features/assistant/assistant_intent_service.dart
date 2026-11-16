// lib/features/assistant/assistant_intent_service.dart
//
// Bridge between the Android assistant / search surface and the player.
// The native side (MainActivity) forwards MEDIA_PLAY_FROM_SEARCH extras and
// launcher shortcuts over 'com.pulsr.music/assistant'; this service parses
// them, resolves a plan through [AssistantResolver] and hands the plan to an
// injected player port, so the module never imports PlayerCubit.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../core/utils/error_logger.dart';
import 'assistant_query.dart';
import 'assistant_resolver.dart';

/// Receives assistant requests and plays the resolved plan.
///
/// Inbound methods:
///  * `onSearchQuery` - a `Map` of search-intent extras (QUERY, PLAYLIST, ...).
///  * `onShortcut`    - a launcher shortcut id (`shortcut_play`, ...).
///
/// Identical requests inside [AssistantIntentService.dedupeWindow] are
/// dropped, because Android delivers the same intent twice on cold start
/// (pending intent plus channel call) and users double-tap shortcut bubbles.
class AssistantIntentService {
  /// Creates the service and starts listening on the platform channel.
  ///
  /// [playPlan] is the player port the main agent wires to PlayerCubit.
  /// [clock] is injectable so the dedupe window is testable without waiting.
  AssistantIntentService({
    required AssistantResolver resolver,
    required Future<void> Function(AssistantPlayPlan plan) playPlan,
    this.dedupeWindow = const Duration(seconds: 1),
    DateTime Function()? clock,
    MethodChannel? channel,
  })  : _resolver = resolver,
        _playPlan = playPlan,
        _clock = clock ?? DateTime.now,
        _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      await handleMethodCall(call);
      return null;
    });
  }

  /// Platforms channel shared with the native assistant bridge.
  static const String channelName = 'com.pulsr.music/assistant';

  /// How long an identical request is ignored after being handled.
  final Duration dedupeWindow;

  final AssistantResolver _resolver;
  final Future<void> Function(AssistantPlayPlan plan) _playPlan;
  final DateTime Function() _clock;
  final MethodChannel _channel;

  String? _lastSignature;
  DateTime? _lastRequestAt;
  bool _disposed = false;

  /// Handles search-intent extras. Invalid requests are logged and dropped;
  /// this method never throws.
  Future<void> handle(Map<String, String?> extras) async {
    if (_disposed) return;
    final AssistantPlayRequest request;
    try {
      request = parseSearchExtras(extras);
    } on AssistantQueryError catch (e) {
      ErrorLogger.log(
        'Assistant request ignored: ${e.reason}',
        category: 'Assistant',
      );
      return;
    }
    await _dispatch(
      'search:${request.field.name}:${request.term}',
      () => _resolver.resolveSearchExtras(request),
    );
  }

  /// Handles a launcher shortcut id. Unknown ids and the search shortcut (which
  /// belongs to the search UI, not to playback) are logged and ignored.
  Future<void> handleShortcut(String shortcutId) async {
    if (_disposed) return;
    switch (shortcutId) {
      case 'shortcut_play':
        await _dispatch('shortcut:play', _resolver.resolveLastAlbum);
      case 'shortcut_shuffle':
        await _dispatch(
          'shortcut:shuffle',
          () => _resolver.resolveFavorites(shuffle: true),
        );
      case 'shortcut_favorites':
        await _dispatch('shortcut:favorites', _resolver.resolveFavorites);
      case 'shortcut_search':
        ErrorLogger.log(
          'Search shortcut opens the search UI, not the assistant player',
          category: 'Assistant',
        );
      default:
        ErrorLogger.log(
          'Unknown assistant shortcut: $shortcutId',
          category: 'Assistant',
        );
    }
  }

  /// Stops listening on the channel and ignores further requests.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }

  /// Handles one inbound platform call (`onSearchQuery`, `onShortcut`).
  ///
  /// Public so tests can drive the channel contract without a binary
  /// messenger; production code only reaches it through the channel handler.
  @visibleForTesting
  Future<void> handleMethodCall(MethodCall call) async {
    if (_disposed) return;
    try {
      switch (call.method) {
        case 'onSearchQuery':
          await handle(_readExtras(call.arguments));
        case 'onShortcut':
          final arguments = call.arguments;
          if (arguments is String) {
            await handleShortcut(arguments);
          } else {
            ErrorLogger.log(
              'Assistant shortcut call carried no id',
              category: 'Assistant',
            );
          }
        case 'isReady':
          // Native readiness probe before it routes warm search intents here.
          // The handler existing is the whole answer.
          break;
        default:
          ErrorLogger.log(
            'Unhandled assistant channel method: ${call.method}',
            category: 'Assistant',
          );
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Assistant channel call failed: ${call.method}',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
    }
  }

  /// Applies dedupe, then resolves and plays. Never rethrows.
  Future<void> _dispatch(
    String signature,
    Future<AssistantResolution> Function() resolve,
  ) async {
    final now = _clock();
    final previousAt = _lastRequestAt;
    if (_lastSignature == signature &&
        previousAt != null &&
        now.difference(previousAt) < dedupeWindow) {
      return;
    }
    _lastSignature = signature;
    _lastRequestAt = now;

    final AssistantResolution resolution;
    try {
      resolution = await resolve();
    } catch (e, st) {
      ErrorLogger.log(
        'Assistant resolver threw for $signature',
        error: e,
        stackTrace: st,
        category: 'Assistant',
      );
      return;
    }

    switch (resolution) {
      case final AssistantResolutionFailure failure:
        ErrorLogger.log(
          'Assistant could not resolve $signature: ${failure.message}',
          category: 'Assistant',
        );
      case final AssistantPlayPlan plan:
        try {
          await _playPlan(plan);
        } catch (e, st) {
          ErrorLogger.log(
            'Assistant could not start playback for $signature',
            error: e,
            stackTrace: st,
            category: 'Assistant',
          );
        }
    }
  }

  /// Reads the channel payload as a string map without trusting its shape.
  Map<String, String?> _readExtras(Object? arguments) {
    if (arguments is! Map) return const <String, String?>{};
    final extras = <String, String?>{};
    for (final entry in arguments.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final value = entry.value;
      extras[key] = value?.toString();
    }
    return extras;
  }
}
