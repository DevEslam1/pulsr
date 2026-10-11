// test/core/services/yt_download_quality_policy_test.dart
//
// The per-download picker override and the quality precedence rule, exercised
// directly against the collaborator extracted from YtDownloadService.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_quality_policy.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';

void main() {
  group('resolve', () {
    test('override wins, then download setting, then streaming, then high', () {
      expect(
        YtDownloadQualityPolicy.resolve(
          override: YtmAudioQuality.low,
          downloadQuality: 'high',
          streamingQuality: 'medium',
        ),
        'low',
      );
      expect(
        YtDownloadQualityPolicy.resolve(
          downloadQuality: 'medium',
          streamingQuality: 'low',
        ),
        'medium',
      );
      expect(
        YtDownloadQualityPolicy.resolve(streamingQuality: 'low'),
        'low',
      );
      expect(YtDownloadQualityPolicy.resolve(), 'high');
    });

    test('blank or whitespace settings fall through to high', () {
      expect(
        YtDownloadQualityPolicy.resolve(
          downloadQuality: '  ',
          streamingQuality: '',
        ),
        'high',
      );
      expect(
        YtDownloadQualityPolicy.resolve(streamingQuality: '  '),
        'high',
      );
    });

    test('settings are trimmed before use', () {
      expect(
        YtDownloadQualityPolicy.resolve(downloadQuality: ' medium '),
        'medium',
      );
    });
  });

  group('pending overrides', () {
    test('set then take returns the quality exactly once', () {
      final policy = YtDownloadQualityPolicy();
      policy.setPending('vid1', YtmAudioQuality.low);
      expect(policy.takePending('vid1'), YtmAudioQuality.low);
      expect(policy.takePending('vid1'), isNull);
    });

    test('discard drops the override without returning it', () {
      final policy = YtDownloadQualityPolicy();
      policy.setPending('vid1', YtmAudioQuality.medium);
      policy.discardPending('vid1');
      expect(policy.takePending('vid1'), isNull);
    });

    test('empty video ids are ignored', () {
      final policy = YtDownloadQualityPolicy();
      policy.setPending('', YtmAudioQuality.high);
      expect(policy.takePending(''), isNull);
    });

    test('a newer pick for the same id replaces the older one', () {
      final policy = YtDownloadQualityPolicy();
      policy.setPending('vid1', YtmAudioQuality.low);
      policy.setPending('vid1', YtmAudioQuality.high);
      expect(policy.takePending('vid1'), YtmAudioQuality.high);
    });

    test('the map stays bounded and evicts the oldest id', () {
      final policy = YtDownloadQualityPolicy();
      for (var i = 0; i < YtDownloadQualityPolicy.maxPendingOverrides; i++) {
        policy.setPending('vid$i', YtmAudioQuality.medium);
      }

      policy.setPending('overflow', YtmAudioQuality.high);

      expect(policy.takePending('vid0'), isNull,
          reason: 'the oldest override is evicted first');
      expect(policy.takePending('overflow'), YtmAudioQuality.high);
    });

    test('refreshing an id already in the map does not evict others', () {
      final policy = YtDownloadQualityPolicy();
      for (var i = 0; i < YtDownloadQualityPolicy.maxPendingOverrides; i++) {
        policy.setPending('vid$i', YtmAudioQuality.medium);
      }

      policy.setPending('vid0', YtmAudioQuality.high);

      expect(policy.takePending('vid0'), YtmAudioQuality.high);
      expect(policy.takePending('vid1'), YtmAudioQuality.medium);
    });
  });
}
