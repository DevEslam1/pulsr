// test/core/services/stream_url_verifier_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/stream_url_verifier.dart';

const _cdnUrl =
    'https://rr1---sn-x.googlevideo.com/videoplayback?itag=140&sig=abc';
const _otherUrl = 'https://media.example.com/audio/track.m4a';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    StreamUrlVerifier.debugProbeOverride = null;
  });

  group('StreamUrlVerifier — host policy', () {
    test('only YouTube media CDN hosts are probeable', () {
      expect(StreamUrlVerifier.isProbeable(_cdnUrl), isTrue);
      expect(
          StreamUrlVerifier.isProbeable(
              'https://redirector.googlevideo.com/videoplayback?x=1'),
          isTrue);
      expect(
          StreamUrlVerifier.isProbeable(
              'https://r1---sn-x.c.youtube.com/videoplayback?x=1'),
          isTrue,
          reason: 'the legacy c.youtube.com edges serve the same bytes');
      expect(
          StreamUrlVerifier.isProbeable(
              'https://backend.example.net/videoplayback/abc'),
          isTrue,
          reason: 'a self-hosted proxy path is still a videoplayback body');
      expect(StreamUrlVerifier.isProbeable(_otherUrl), isFalse);
      expect(StreamUrlVerifier.isProbeable('not a url'), isFalse);
      expect(
          StreamUrlVerifier.isProbeable('https://googlevideo.com.evil.example/x'),
          isFalse,
          reason: 'the check is a host suffix, not a substring');
    });

    test('a non-CDN URL answers ok without asking the seam', () async {
      var calls = 0;
      StreamUrlVerifier.debugProbeOverride =
          (url, {userAgent, referer, cookie}) async {
        calls++;
        return const StreamUrlProbe.rejected(403);
      };

      final probe = await StreamUrlVerifier().probe(_otherUrl);

      expect(probe.isOk, isTrue);
      expect(calls, 0,
          reason: 'a failure from a self-hosted proxy says nothing about a '
              'googlevideo signature');
    });
  });

  group('StreamUrlVerifier — status mapping', () {
    test('2xx answers ok', () {
      expect(StreamUrlVerifier.verdictForStatus(200).isOk, isTrue);
      expect(StreamUrlVerifier.verdictForStatus(206).isOk, isTrue,
          reason: 'a honoured Range request answers 206');
    });

    test('401/403/404/410 are rejected, with the status preserved', () {
      for (final status in const [401, 403, 404, 410]) {
        final verdict = StreamUrlVerifier.verdictForStatus(status);
        expect(verdict.isRejected, isTrue, reason: '$status is a dead URL');
        expect(verdict.statusCode, status);
      }
    });

    test('everything else is unknown, never rejected', () {
      for (final status in const [300, 408, 429, 500, 502, 503]) {
        final verdict = StreamUrlVerifier.verdictForStatus(status);
        expect(verdict.isUnknown, isTrue,
            reason: '$status says nothing about the URL signature');
        expect(verdict.isRejected, isFalse);
      }
    });
  });

  group('StreamUrlVerifier — probe', () {
    test('concurrent probes for one URL share a single round trip', () async {
      final gate = Completer<StreamUrlProbe>();
      var calls = 0;
      StreamUrlVerifier.debugProbeOverride =
          (url, {userAgent, referer, cookie}) {
        calls++;
        return gate.future;
      };

      final first = StreamUrlVerifier().probe(_cdnUrl);
      final second = StreamUrlVerifier().probe(_cdnUrl);
      gate.complete(const StreamUrlProbe.ok());

      expect((await first).isOk, isTrue);
      expect((await second).isOk, isTrue);
      expect(calls, 1, reason: 'one URL, one probe');
    });

    test('a settled probe is not reused by a later call', () async {
      var calls = 0;
      StreamUrlVerifier.debugProbeOverride =
          (url, {userAgent, referer, cookie}) async {
        calls++;
        return const StreamUrlProbe.ok();
      };

      final verifier = StreamUrlVerifier();
      await verifier.probe(_cdnUrl);
      await verifier.probe(_cdnUrl);

      expect(calls, 2,
          reason: 'single-flight coalesces concurrent probes, not sequential '
              'ones — the cache max-age owns that decision');
    });

    test('the playback headers reach the probe unchanged', () async {
      String? seenUa;
      String? seenReferer;
      String? seenCookie;
      StreamUrlVerifier.debugProbeOverride =
          (url, {userAgent, referer, cookie}) async {
        seenUa = userAgent;
        seenReferer = referer;
        seenCookie = cookie;
        return const StreamUrlProbe.ok();
      };

      await StreamUrlVerifier().probe(
        _cdnUrl,
        userAgent: 'UA',
        referer: 'https://music.youtube.com/',
        cookie: 'SID=1',
      );

      expect(seenUa, 'UA');
      expect(seenReferer, 'https://music.youtube.com/');
      expect(seenCookie, 'SID=1');
    });

    test('never throws, even when the probe itself fails', () async {
      StreamUrlVerifier.debugProbeOverride =
          (url, {userAgent, referer, cookie}) async =>
              throw StateError('probe exploded');

      final probe = await StreamUrlVerifier().probe(_cdnUrl);

      expect(probe.isUnknown, isTrue,
          reason: 'an unknown verdict keeps the cached URL, so a broken probe '
              'can never cost a re-resolve');
    });
  });
}
