// lib/core/services/scrobbler_service.dart
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import '../utils/error_logger.dart';

@singleton
class ScrobblerService {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/scrobbler');

  Future<void> notifyPlaybackState({
    required int id,
    required String artist,
    required String track,
    required String album,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
  }) async {
    try {
      await _channel.invokeMethod('broadcastPlaybackState', {
        'id': id,
        'artist': artist,
        'track': track,
        'album': album,
        'duration': durationMs,
        'position': positionMs,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      ErrorLogger.log('Failed to broadcast scrobble intent: $e', category: 'Scrobbler');
    }
  }
}
