import '../../domain/models/ytm_track.dart';

/// YouTube caps a playlist at 5,000 items. Callers that need the complete list
/// (e.g. "download all") pass this as `maxTracks`.
const int kYtmMaxPlaylistTracks = 5000;

class YtmAccountPlaylist {
  final String playlistId;
  final String title;
  final String subtitle;
  final String? artworkUrl;

  const YtmAccountPlaylist({
    required this.playlistId,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
  });

  String get cleanPlaylistId =>
      playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;

  String get shareUrl =>
      'https://music.youtube.com/playlist?list=$cleanPlaylistId';

  Map<String, dynamic> toJson() => {
        'playlistId': playlistId,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
      };

  factory YtmAccountPlaylist.fromJson(Map<String, dynamic> json) =>
      YtmAccountPlaylist(
        playlistId: json['playlistId'] as String? ?? '',
        title: json['title'] as String? ?? 'Playlist',
        subtitle: json['subtitle'] as String? ?? 'YouTube Music',
        artworkUrl: json['artworkUrl'] as String?,
      );
}

class YtmPlaylistDetails {
  final String id;
  final String title;
  final String author;
  final String? artworkUrl;
  final List<YtmTrack> tracks;

  const YtmPlaylistDetails({
    required this.id,
    required this.title,
    required this.author,
    this.artworkUrl,
    required this.tracks,
  });
}
