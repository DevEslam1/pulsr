// lib/data/models/dummy_data.dart
class DummySong {
  final int id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final bool isFavorite;
  final String? artworkUri;

  const DummySong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.isFavorite = false,
    this.artworkUri,
  });
}

class DummyData {
  static const List<DummySong> songs = [
    DummySong(
      id: 1,
      title: 'Midnight Resonance',
      artist: 'Kavinsky & The Weeknd',
      album: 'Nightcall Odyssey',
      duration: Duration(minutes: 3, seconds: 48),
      isFavorite: true,
    ),
    DummySong(
      id: 2,
      title: 'Cyberpunk Skyline',
      artist: 'Lorn',
      album: 'Vessel of Echoes',
      duration: Duration(minutes: 4, seconds: 12),
      isFavorite: true,
    ),
    DummySong(
      id: 3,
      title: 'Neon Horizon',
      artist: 'Gunship',
      album: 'Dark All Day',
      duration: Duration(minutes: 5, seconds: 3),
      isFavorite: false,
    ),
    DummySong(
      id: 4,
      title: 'Lucid Memories',
      artist: 'Tycho',
      album: 'Epoch Horizons',
      duration: Duration(minutes: 4, seconds: 35),
      isFavorite: true,
    ),
    DummySong(
      id: 5,
      title: 'Aura Synthesis',
      artist: 'Com Truise',
      album: 'Galactic Melt',
      duration: Duration(minutes: 3, seconds: 20),
      isFavorite: false,
    ),
  ];
}
