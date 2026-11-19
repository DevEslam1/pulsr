// lib/features/dlna/upnp_control_point.dart
//
// UPnP AVTransport control-point for discovered renderers.
// Provides queueing, transport commands (Play, Pause, Stop, Seek, Next, Previous)
// and position / state inspection across any discovered UpnpDeviceDescription.
import 'dart:async';

import 'package:http/http.dart' as http;

import 'av_transport.dart';
import 'upnp_device.dart';

/// Control-point service that executes AVTransport actions against any
/// discovered DLNA renderer.
class UpnpControlPoint {
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  UpnpControlPoint({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout;

  /// Returns an [AvTransportClient] targeted at [device].
  AvTransportClient clientFor(UpnpDeviceDescription device) =>
      AvTransportClient(
        device.avTransportControlUrl,
        client: _client,
        timeout: _timeout,
      );

  /// Sets the active playback URI and metadata on [device].
  Future<void> setAvTransportUri(
    UpnpDeviceDescription device,
    String uri, {
    String didlMetadata = '',
  }) =>
      clientFor(device).setAvTransportUri(uri, didlMetadata);

  /// Queues the next playback URI and metadata on [device].
  Future<void> setNextAvTransportUri(
    UpnpDeviceDescription device,
    String nextUri, {
    String nextDidlMetadata = '',
  }) =>
      clientFor(device).setNextAvTransportUri(nextUri, nextDidlMetadata);

  /// Starts playback on [device].
  Future<void> play(UpnpDeviceDescription device, {String speed = '1'}) =>
      clientFor(device).play(speed: speed);

  /// Pauses playback on [device].
  Future<void> pause(UpnpDeviceDescription device) => clientFor(device).pause();

  /// Stops playback on [device].
  Future<void> stop(UpnpDeviceDescription device) => clientFor(device).stop();

  /// Seeks to [position] on [device].
  Future<void> seek(UpnpDeviceDescription device, Duration position) =>
      clientFor(device).seek(position);

  /// Reads current playback position and track info on [device].
  Future<PositionInfo> getPositionInfo(UpnpDeviceDescription device) =>
      clientFor(device).getPositionInfo();

  /// Reads current transport state on [device].
  Future<TransportInfo> getTransportInfo(UpnpDeviceDescription device) =>
      clientFor(device).getTransportInfo();

  /// Advances to next queued track on [device].
  Future<void> next(UpnpDeviceDescription device) => clientFor(device).next();

  /// Returns to previous track on [device].
  Future<void> previous(UpnpDeviceDescription device) =>
      clientFor(device).previous();

  /// Closes the underlying HTTP client if owned.
  void close() {
    if (_ownsClient) _client.close();
  }
}
