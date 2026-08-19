// test/widget_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/domain/usecases/search_music_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = MusicRepository(db);
    final audioHandler = PulsrAudioHandler(repo);
    final scannerService = MediaScannerService(repo);

    await tester.pumpWidget(
      PulsrApp(
        database: db,
        repository: repo,
        audioHandler: audioHandler,
        scannerService: scannerService,
        getSongsUseCase: GetSongsUseCase(repo),
        getAlbumsUseCase: GetAlbumsUseCase(repo),
        getArtistsUseCase: GetArtistsUseCase(repo),
        getFavoritesUseCase: GetFavoritesUseCase(repo),
        toggleFavoriteUseCase: ToggleFavoriteUseCase(repo),
        searchMusicUseCase: SearchMusicUseCase(repo),
        playlistUseCases: PlaylistUseCases(repo),
        folderUseCases: FolderUseCases(repo),
      ),
    );

    expect(find.byType(PulsrApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
