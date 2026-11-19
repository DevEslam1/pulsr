// P1-8: the discovery panel must show what answered and hand the chosen
// server back to the settings screen, which is what persists it.
//
// The HTTP round trip is completed inside `runAsync`: a widget test runs in a
// fake-async zone, and `http`'s stream plumbing only drains in the real one.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/dlna/ssdp_client.dart';
import 'package:pulsr/features/dlna/upnp_device.dart';
import 'package:pulsr/features/remote_sources/remote_sources_strings.dart';
import 'package:pulsr/features/remote_sources/upnp_discovery.dart';
import 'package:pulsr/features/remote_sources/upnp_server_picker_sheet.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.body);

  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        200,
        headers: const {'content-type': 'text/xml'},
      );
}

const String _description = '<?xml version="1.0"?>'
    '<root><device>'
    '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
    '<friendlyName>Living room NAS</friendlyName>'
    '<modelName>DS220+</modelName>'
    '<UDN>uuid:nas-1</UDN>'
    '<serviceList><service>'
    '<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>'
    '<controlURL>/ctl/ContentDir</controlURL>'
    '</service></serviceList>'
    '</device></root>';

UpnpDiscovery _discovery() => UpnpDiscovery(
      search: (_) async => <SsdpResponse>[
        const SsdpResponse(
          location: 'http://192.168.1.5:8200/nas.xml',
          searchTarget: 'ssdp:all',
          usn: 'uuid:nas-1',
          server: 'Linux UPnP/1.0',
          sourceAddress: '192.168.1.5',
        ),
      ],
      client: _FakeHttpClient(_description),
    );

/// Lets the discovery round trip finish outside the fake-async zone.
Future<void> _settleDiscovery(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  testWidgets('lists a discovered server with its model and address',
      (tester) async {
    final discovery = _discovery();
    addTearDown(discovery.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(body: UpnpServerPickerSheet(discovery: discovery)),
      ),
    );
    await _settleDiscovery(tester);

    expect(find.text(RemoteSourcesStrings.upnpTitle), findsOneWidget);
    expect(find.text('Living room NAS'), findsOneWidget);
    expect(find.text(RemoteSourcesStrings.upnpUse), findsOneWidget);
    expect(find.text(RemoteSourcesStrings.upnpSearching), findsNothing);
  });

  testWidgets('a modal sheet returns the chosen server', (tester) async {
    final discovery = _discovery();
    addTearDown(discovery.close);
    UpnpServerDescription? picked;

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<UpnpServerDescription>(
                    context: context,
                    builder: (_) => UpnpServerPickerSheet(discovery: discovery),
                  );
                },
                child: const Text('search'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _settleDiscovery(tester);

    expect(find.text('Living room NAS'), findsOneWidget);

    await tester.tap(find.text(RemoteSourcesStrings.upnpUse));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(picked?.friendlyName, 'Living room NAS');
    expect(
      picked?.contentDirectoryControlUrl,
      Uri.parse('http://192.168.1.5:8200/ctl/ContentDir'),
    );
  });

  testWidgets('shows the empty state when nothing answers', (tester) async {
    final discovery = UpnpDiscovery(
      search: (_) async => const <SsdpResponse>[],
      client: _FakeHttpClient(''),
    );
    addTearDown(discovery.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(body: UpnpServerPickerSheet(discovery: discovery)),
      ),
    );
    await tester.pump();

    expect(find.text(RemoteSourcesStrings.upnpNone), findsOneWidget);
  });
}
