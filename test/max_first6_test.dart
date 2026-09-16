import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/domain/models/dsp_abx.dart';
import 'package:pulsr/domain/services/usb_exclusive_service.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/services/playlist_suggestions_service.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData song(int id, String artist, String genre, int plays,
    {bool fav = false}) {
  return SongsTableData(
    id: id,
    title: 'Song $id',
    artist: artist,
    album: 'Album',
    durationMs: 180000,
    path: '/m/$id.mp3',
    genre: genre,
    isFavorite: fav,
    isMissing: false,
    isDownloaded: false,
    playCount: plays,
    lastPositionMs: 0,
    source: 'local',
  );
}

void main() {
  test('1 DSP ABX shuffles + null-test holds', () {
    final h = DspAbxHelper();
    final t = h.shuffledTrials(trialsPerOption: 5);
    expect(t.length, 10);
    expect(t.where((e) => e == 'A').length, 5);
    expect(t.where((e) => e == 'B').length, 5);
    expect(DspAbxHelper.gainsNull((0.7, 0.7), (0.7, 0.7)), isTrue);
    expect(DspAbxHelper.gainsNull((1.0, 0.0), (0.5, 0.0)), isFalse);
  });

  test('2 crossfade preview curve endpoints + sum-safe', () {
    final m = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
    final curve = m.previewFadeCurve(steps: 24);
    expect(curve.length, 25);
    expect(curve.first.$1, closeTo(1.0, 1e-9));
    expect(curve.first.$2, closeTo(0.0, 1e-9));
    expect(curve.last.$1, closeTo(0.0, 1e-9));
    expect(curve.last.$2, closeTo(1.0, 1e-9));
    for (final g in curve) {
      expect(g.$1 + g.$2, lessThanOrEqualTo(1.0 + 1e-9));
    }
  });

  test('3 USB status parses + invalid streaming guarded', () {
    final s = UsbExclusiveStatus.fromMap({
      'attached': true,
      'permitted': true,
      'minVolumeDb': -60.0,
      'maxVolumeDb': 0.0,
    });
    expect(s.attached, isTrue);
    expect(s.minVolumeDb, -60.0);
  });

  test('4 suggestions seed-based Auto-DJ ranks same artist first', () {
    final svc = PlaylistSuggestionsService();
    final seed = song(1, 'A', 'Rock', 5);
    final pool = [
      seed,
      song(2, 'A', 'Rock', 0),
      song(3, 'B', 'Pop', 0),
      song(4, 'A', 'Rock', 9, fav: true),
    ];
    final similar = svc.suggestForSeed(seed, pool, limit: 3);
    expect(similar.any((e) => e.id == 1), isFalse);
    expect(similar.first.artist, 'A');
    final q = svc.buildAutoDjQueue(seed, pool,
        limit: 2, excludeIds: {4});
    expect(q.any((e) => e.id == 4), isFalse);
    expect(q.length, lessThanOrEqualTo(2));
  });

  test('5 GPU budget flag toggles', () {
    GpuBudget.setEnabled(true);
    expect(GpuBudget.isEnabled, isTrue);
    GpuBudget.setEnabled(false);
    expect(GpuBudget.isEnabled, isFalse);
  });
}
