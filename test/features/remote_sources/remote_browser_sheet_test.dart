// P1-8: the browser is the one place both new providers plug into. These
// tests pin the two things that changed there: a tap reports the entry (so a
// track's real title reaches the player) and the breadcrumb shows names rather
// than the opaque ids Subsonic and UPnP paths are built from.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/remote_browser_sheet.dart';
import 'package:pulsr/features/remote_sources/remote_sources_strings.dart';
import 'package:pulsr/features/remote_sources/subsonic_fs_provider.dart';
import 'package:pulsr/data/remote/subsonic_client.dart';

class _FakeProvider implements RemoteFsProvider {
  _FakeProvider(this.source, this.tree);

  @override
  final RemoteSource source;

  final Map<String, List<RemoteEntry>> tree;

  @override
  Future<List<RemoteEntry>> list(String path) async =>
      tree[path] ?? const <RemoteEntry>[];

  @override
  Future<RemoteEntry?> stat(String path) async => null;

  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) =>
      const Stream<List<int>>.empty();

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> close() async {}
}

final RemoteSource _source = RemoteSource(
  id: 'upnp-1',
  kind: RemoteSourceKind.upnp,
  displayName: 'Living room NAS',
  host: '192.168.1.5',
  port: 8200,
  rootPath: '/control/cds',
  createdAt: DateTime.utc(2026),
);

Future<void> _pumpSheet(WidgetTester tester, RemoteBrowserSheet sheet) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AuraTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: sheet),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('breadcrumbs show entry names instead of opaque path ids',
      (tester) async {
    final provider = _FakeProvider(_source, <String, List<RemoteEntry>>{
      '': const <RemoteEntry>[
        RemoteEntry(path: 'c/ar-1', name: 'Björk', isDirectory: true),
      ],
      'c/ar-1': const <RemoteEntry>[
        RemoteEntry(
            path: 'c/ar-1/i/al-9', name: 'Homogenic', isDirectory: true),
      ],
    });
    await _pumpSheet(
      tester,
      RemoteBrowserSheet(source: _source, provider: provider),
    );

    expect(find.text('Björk'), findsOneWidget);
    await tester.tap(find.text('Björk'));
    await tester.pumpAndSettle();

    expect(find.text('Homogenic'), findsOneWidget);
    // The path this provider uses is an id, so a path-derived breadcrumb would
    // have shown "c/ar-1"; the sheet must show the entry name instead.
    expect(find.text('c/ar-1'), findsNothing);
    expect(find.text('Björk'), findsOneWidget);

    await tester.tap(find.text(RemoteSourcesStrings.rootCrumb));
    await tester.pumpAndSettle();
    expect(find.text('Björk'), findsOneWidget);
  });

  testWidgets('a file tap reports the entry, not just its path',
      (tester) async {
    final played = <RemoteEntry>[];
    const entry = RemoteEntry(
      path: 'i/so-2',
      name: 'Jóga',
      isDirectory: false,
      sizeBytes: 42,
    );
    final provider = _FakeProvider(_source, <String, List<RemoteEntry>>{
      '': const <RemoteEntry>[entry],
    });
    await _pumpSheet(
      tester,
      RemoteBrowserSheet(
        source: _source,
        provider: provider,
        onPlay: (source, entry) async => played.add(entry),
      ),
    );

    await tester.tap(find.text('Jóga'));
    await tester.pumpAndSettle();

    expect(played, hasLength(1));
    expect(played.single.path, 'i/so-2');
    expect(played.single.name, 'Jóga');
    expect(played.single.sizeBytes, 42);
  });

  testWidgets('Subsonic search button is visible and search results render',
      (tester) async {
    final subsonicSource = RemoteSource(
      id: 'subsonic-1',
      kind: RemoteSourceKind.subsonic,
      displayName: 'Navidrome',
      host: 'music.example.com',
      port: 443,
      rootPath: '/',
      createdAt: DateTime.utc(2026),
    );

    final fakeSubsonic = _FakeSubsonicProvider(
      subsonicSource,
      searchResults: const SubsonicSearchResult(
        artists: [SubsonicArtist(id: 'art-1', name: 'Radiohead')],
        albums: [
          SubsonicAlbum(id: 'alb-1', name: 'Kid A', artist: 'Radiohead')
        ],
        songs: [
          SubsonicSong(
            id: 's-1',
            title: 'Idioteque',
            artist: 'Radiohead',
            album: 'Kid A',
            albumId: 'alb-1',
          ),
        ],
      ),
    );

    final played = <RemoteEntry>[];
    await _pumpSheet(
      tester,
      RemoteBrowserSheet(
        source: subsonicSource,
        provider: fakeSubsonic,
        onPlay: (source, entry) async => played.add(entry),
      ),
    );

    expect(find.byTooltip(RemoteSourcesStrings.searchLibrary), findsOneWidget);
    await tester.tap(find.byTooltip(RemoteSourcesStrings.searchLibrary));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'radiohead');
    // Advance past the 300ms search debounce timer
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Radiohead'), findsOneWidget);
    expect(find.text('Kid A • Radiohead'), findsOneWidget);
    expect(find.text('Idioteque • Radiohead'), findsOneWidget);

    await tester.tap(find.text('Idioteque • Radiohead'));
    await tester.pumpAndSettle();

    expect(played, hasLength(1));
    expect(played.single.name, 'Idioteque • Radiohead');
  });

  testWidgets('Subsonic search debounces typing and discards rapid keystrokes',
      (tester) async {
    final subsonicSource = RemoteSource(
      id: 'subsonic-1',
      kind: RemoteSourceKind.subsonic,
      displayName: 'Navidrome',
      host: 'music.example.com',
      port: 443,
      rootPath: '/',
      createdAt: DateTime.utc(2026),
    );

    final fakeSubsonic = _FakeSubsonicProvider(subsonicSource);
    await _pumpSheet(
      tester,
      RemoteBrowserSheet(
        source: subsonicSource,
        provider: fakeSubsonic,
      ),
    );

    await tester.tap(find.byTooltip(RemoteSourcesStrings.searchLibrary));
    await tester.pumpAndSettle();

    // Type partial queries rapidly
    await tester.enterText(find.byType(TextField), 'r');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'rad');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'radio');
    await tester.pump(const Duration(milliseconds: 100));

    // Debounce window (300ms) has not elapsed since 'radio'
    expect(fakeSubsonic.searchCalls, isEmpty);

    // Now advance past 300ms
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(fakeSubsonic.searchCalls, ['radio']);
  });
}

class _FakeSubsonicProvider implements SubsonicFsProvider {
  _FakeSubsonicProvider(this.source, {this.searchResults});

  @override
  final RemoteSource source;

  final SubsonicSearchResult? searchResults;
  final List<String> searchCalls = [];

  @override
  Future<List<RemoteEntry>> list(String path) async => const [];

  @override
  Future<RemoteEntry?> stat(String path) async => null;

  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) =>
      const Stream<List<int>>.empty();

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> close() async {}

  @override
  Future<SubsonicSearchResult> search(
    String query, {
    int artistCount = 20,
    int artistOffset = 0,
    int albumCount = 20,
    int albumOffset = 0,
    int songCount = 50,
    int songOffset = 0,
  }) async {
    searchCalls.add(query);
    return searchResults ?? const SubsonicSearchResult();
  }

  @override
  Uri? getCoverArtUrl(String? coverArtId, {int? size}) =>
      coverArtId != null ? Uri.parse('http://127.0.0.1/art/$coverArtId') : null;

  @override
  String? getCoverArtCacheKey(String? coverArtId, {int? size}) =>
      coverArtId != null
          ? 'subsonic://music.example.com/art/$coverArtId'
          : null;
}
