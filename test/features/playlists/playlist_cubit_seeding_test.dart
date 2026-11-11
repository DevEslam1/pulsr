import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPlaylistUseCases extends Mock implements PlaylistUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPlaylistUseCases mockPlaylistUseCases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockPlaylistUseCases = MockPlaylistUseCases();
    when(() => mockPlaylistUseCases.watchPlaylists())
        .thenAnswer((_) => Stream.value(const Right(<PlaylistsTableData>[])));
  });

  test('0.10 _checkSeeding failure leaves seeded flag false and retries next launch', () async {
    final prefs = await SharedPreferences.getInstance();

    // 1. First launch: seedDefaultSmartPlaylists fails / throws
    var attemptCount = 0;
    when(() => mockPlaylistUseCases.seedDefaultSmartPlaylists()).thenAnswer((_) async {
      attemptCount++;
      throw Exception('Database locked / seeding failure');
    });

    final cubit1 = PlaylistCubit(playlistUseCases: mockPlaylistUseCases);
    await Future.delayed(const Duration(milliseconds: 100));

    expect(attemptCount, 1);
    // Flag must remain false because seeding failed!
    expect(prefs.getBool('smart_playlists_seeded') ?? false, isFalse);
    await cubit1.close();

    // 2. Next launch: retry seeding, this time it succeeds
    when(() => mockPlaylistUseCases.seedDefaultSmartPlaylists()).thenAnswer((_) async {
      attemptCount++;
    });

    final cubit2 = PlaylistCubit(playlistUseCases: mockPlaylistUseCases);
    await Future.delayed(const Duration(milliseconds: 100));

    expect(attemptCount, 2);
    // Flag must now be persisted as true after success!
    expect(prefs.getBool('smart_playlists_seeded'), isTrue);
    await cubit2.close();

    // 3. Third launch: seeded flag is true, should not call seedDefaultSmartPlaylists again
    final cubit3 = PlaylistCubit(playlistUseCases: mockPlaylistUseCases);
    await Future.delayed(const Duration(milliseconds: 100));

    expect(attemptCount, 2); // No new seeding attempt
    await cubit3.close();
  });
}
