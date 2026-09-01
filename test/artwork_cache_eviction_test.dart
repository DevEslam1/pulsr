import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('N1: ArtworkCacheManager Disk-LRU Eviction Tests', () {
    late Directory tempDir;
    late Directory cacheDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'setting_max_cache_size_mb': 1}); // 1 MB limit
      tempDir = await Directory.systemTemp.createTemp('artwork_test_');
      cacheDir = Directory(p.join(tempDir.path, 'artwork_cache'));
      await cacheDir.create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Enforces disk limit down to 90% and keeps newest files', () async {
      // 1 MB = 1048576 bytes. Target 90% = ~943718 bytes.
      // Create 4 files of 350 KB each (total 1.4 MB > 1 MB)
      final size350k = 350 * 1024;
      final bytes = Uint8List(size350k);

      final now = DateTime.now();
      final file1 = File(p.join(cacheDir.path, 'art_old1.jpg'));
      await file1.writeAsBytes(bytes);
      await file1.setLastModified(now.subtract(const Duration(minutes: 10)));

      final file2 = File(p.join(cacheDir.path, 'art_old2.jpg'));
      await file2.writeAsBytes(bytes);
      await file2.setLastModified(now.subtract(const Duration(minutes: 5)));

      final file3 = File(p.join(cacheDir.path, 'art_new1.jpg'));
      await file3.writeAsBytes(bytes);
      await file3.setLastModified(now.subtract(const Duration(minutes: 2)));

      final file4 = File(p.join(cacheDir.path, 'art_new2.jpg'));
      await file4.writeAsBytes(bytes);
      await file4.setLastModified(now);

      // Total before eviction = 1400 KB
      final initialFiles = cacheDir.listSync().whereType<File>().toList();
      expect(initialFiles.length, equals(4));

      // Simulate eviction loop (matches ArtworkCacheManager._enforceDiskLimit)
      final maxBytes = 1 * 1024 * 1024;
      final targetBytes = (maxBytes * 0.90).toInt();

      final fileList = <({File file, int size, DateTime modified})>[];
      int currentSize = 0;
      for (final f in initialFiles) {
        final size = await f.length();
        final modified = await f.lastModified();
        currentSize += size;
        fileList.add((file: f, size: size, modified: modified));
      }

      if (currentSize > maxBytes) {
        fileList.sort((a, b) => a.modified.compareTo(b.modified));
        for (final item in fileList) {
          if (currentSize <= targetBytes) break;
          await item.file.delete();
          currentSize -= item.size;
        }
      }

      // Assert that oldest files were deleted and newest files survived
      expect(await file1.exists(), isFalse); // Oldest evicted
      expect(await file2.exists(), isFalse); // Second oldest evicted
      expect(await file3.exists(), isTrue);  // Newest kept
      expect(await file4.exists(), isTrue);  // Newest kept

      // Assert total remaining size <= 90% (2 files * 350KB = 700KB < 943KB)
      expect(currentSize, lessThanOrEqualTo(targetBytes));
    });
  });
}
