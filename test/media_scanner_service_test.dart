import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicRepository mockRepository;
  late MediaScannerService scannerService;

  setUp(() {
    mockRepository = MockMusicRepository();
    scannerService = MediaScannerService(mockRepository);
  });

  group('MediaScannerService Unit Tests', () {
    test('isSystemIgnoredPath detects WhatsApp, Telegram, call recordings and dot folders', () {
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/1.opus'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Android/media/com.whatsapp/audio.mp3'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Telegram/Telegram Audio/voice.ogg'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Recordings/call_123.m4a'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Music/.thumbnails/art.jpg'), isTrue);
      expect(MediaScannerService.isSystemIgnoredPath('/storage/emulated/0/Music/Albums/Track01.flac'), isFalse);
    });

    test('scanProgress stream provides stream of scan progression', () async {
      expect(scannerService.scanProgress, isA<Stream<double>>());
    });
  });
}
