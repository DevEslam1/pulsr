// lib/data/audio/audio_effects_channel.dart
import 'dart:io';
import 'package:flutter/services.dart';
import '../../domain/models/audio_effects_config.dart';

class AudioEffectsChannel {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/audio_effects');

  static final AudioEffectsChannel _instance = AudioEffectsChannel._internal();
  factory AudioEffectsChannel() => _instance;
  AudioEffectsChannel._internal();

  bool _isVirtualizerSupported = false;
  bool _isDynamicsSupported = false;
  bool _isSpatializerSupported = false;
  bool _isVolumeBoostSupported = false;
  bool _isBassBoostSupported = false;

  bool get isVirtualizerSupported => _isVirtualizerSupported;
  bool get isDynamicsSupported => _isDynamicsSupported;
  bool get isSpatializerSupported => _isSpatializerSupported;
  bool get isVolumeBoostSupported => _isVolumeBoostSupported;
  bool get isBassBoostSupported => _isBassBoostSupported;

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      final virtSup = await _channel.invokeMethod<bool>('isVirtualizerSupported');
      _isVirtualizerSupported = virtSup ?? false;

      final dynSup = await _channel.invokeMethod<bool>('isDynamicsSupported');
      _isDynamicsSupported = dynSup ?? false;

      final vbSup = await _channel.invokeMethod<bool>('isVolumeBoostSupported');
      _isVolumeBoostSupported = vbSup ?? false;

      final bbSup = await _channel.invokeMethod<bool>('isBassBoostSupported');
      _isBassBoostSupported = bbSup ?? false;

      final spatialMap = await _channel.invokeMapMethod<String, dynamic>('getSpatializerState');
      if (spatialMap != null) {
        _isSpatializerSupported = (spatialMap['isSupported'] as bool?) ?? false;
      }
    } catch (_) {}
  }

  Future<void> setAudioSessionId(int sessionId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setAudioSessionId', {'audioSessionId': sessionId});
    } catch (_) {}
  }

  Future<void> setVolumeBoost(int milliBels) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVolumeBoost', {'milliBels': milliBels});
    } catch (_) {}
  }

  Future<void> setBassBoost(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': strength});
    } catch (_) {}
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVirtualizerEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  Future<void> setVirtualizerStrength(double strength0to1) async {
    if (!Platform.isAndroid) return;
    try {
      final intStrength = (strength0to1.clamp(0.0, 1.0) * 1000).round();
      await _channel.invokeMethod('setVirtualizerStrength', {'strength': intStrength});
    } catch (_) {}
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setDynamicsPreset', {
        'preset': preset.name,
        'enabled': enabled && preset != DynamicsPreset.off,
      });
    } catch (_) {}
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSpatializerEnabled', {'enabled': enabled});
    } catch (_) {}
  }
}
