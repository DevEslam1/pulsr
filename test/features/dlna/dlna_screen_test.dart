// Screen smoke tests: discovery wiring, 48 dp targets, semantics labels, the
// error banner retry, and the now-playing transport controls. A stub service
// keeps the widget layer free of sockets and timers.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/features/dlna/dlna_renderer_service.dart';
import 'package:pulsr/features/dlna/dlna_screen.dart';
import 'package:pulsr/features/dlna/dlna_strings.dart';
import 'package:pulsr/features/dlna/upnp_device.dart';

final UpnpDeviceDescription _device = UpnpDeviceDescription(
  friendlyName: 'Mock Renderer',
  modelName: 'Pulsr Test',
  udn: 'uuid:mock-renderer',
  deviceType: 'urn:schemas-upnp-org:device:MediaRenderer:1',
  location: Uri.parse('http://192.168.1.5:5555/description.xml'),
  avTransportControlUrl: Uri.parse('http://192.168.1.5:5555/control/avt'),
);

class _StubRendererService extends DlnaRendererService {
  _StubRendererService({this.error}) : super();

  AppError? error;

  DlnaState _current = DlnaState.idle;
  List<UpnpDeviceDescription> _deviceList = const <UpnpDeviceDescription>[];
  UpnpDeviceDescription? _selected;
  String? _title;
  Duration _position = Duration.zero;

  @override
  DlnaState get state => _current;

  @override
  List<UpnpDeviceDescription> get devices => _deviceList;

  @override
  UpnpDeviceDescription? get selectedDevice => _selected;

  @override
  String? get nowPlayingTitle => _title;

  @override
  Duration get position => _position;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  AppError? get lastError => error;

  @override
  Future<void> discover() async {
    error = null;
    _deviceList = <UpnpDeviceDescription>[_device];
    _current = DlnaState.idle;
    notifyListeners();
  }

  @override
  Future<void> select(UpnpDeviceDescription device) async {
    _selected = device;
    _current = DlnaState.stopped;
    notifyListeners();
  }

  @override
  Future<void> playFile(
    String path, {
    String? title,
    String? artist,
    String? album,
  }) async {
    _title = title ?? 'Stub Song';
    _current = DlnaState.playing;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _current = DlnaState.paused;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    _current = DlnaState.playing;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _current = DlnaState.stopped;
    _title = null;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration target) async {
    _position = target;
    notifyListeners();
  }
}

void main() {
  testWidgets('scans, lists a device, and connects with a 48dp scan target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final service = _StubRendererService();
    addTearDown(service.dispose);

    await tester.pumpWidget(MaterialApp(home: DlnaScreen(service: service)));

    expect(find.bySemanticsLabel(DlnaStrings.scanSemantics), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48.0),
    );

    await tester.tap(find.text(DlnaStrings.scan));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mock Renderer'), findsOneWidget);
    expect(find.text('Pulsr Test'), findsOneWidget);

    await tester.tap(find.text(DlnaStrings.connect));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(DlnaStrings.connected), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows the error banner and retries discovery', (tester) async {
    final service = _StubRendererService(
      error: GenericAppError(
        code: 'DLNA_NO_DEVICE',
        userMessage: 'Select a DLNA renderer first.',
      ),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(MaterialApp(home: DlnaScreen(service: service)));

    expect(find.text(DlnaStrings.errorTitle), findsOneWidget);
    expect(find.text('Select a DLNA renderer first.'), findsOneWidget);

    await tester.tap(find.text(DlnaStrings.retry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mock Renderer'), findsOneWidget);
  });

  testWidgets('now-playing card exposes 48dp pause and stop controls',
      (tester) async {
    final service = _StubRendererService();
    addTearDown(service.dispose);
    await service.discover();
    await service.select(_device);
    await service.playFile('/tmp/song.mp3', title: 'Widget Song');

    await tester.pumpWidget(MaterialApp(home: DlnaScreen(service: service)));

    expect(find.text('Widget Song'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    final pause = find.byTooltip(DlnaStrings.pause);
    final stop = find.byTooltip(DlnaStrings.stop);
    expect(pause, findsOneWidget);
    expect(stop, findsOneWidget);
    expect(tester.getSize(pause).height, greaterThanOrEqualTo(48.0));
    expect(tester.getSize(stop).height, greaterThanOrEqualTo(48.0));

    await tester.tap(pause);
    await tester.pump();
    expect(find.byTooltip(DlnaStrings.resume), findsOneWidget);
    expect(
      find.text(DlnaStrings.stateLabel(DlnaState.paused)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(DlnaStrings.resume));
    await tester.pump();
    expect(find.byTooltip(DlnaStrings.pause), findsOneWidget);
  });
}
