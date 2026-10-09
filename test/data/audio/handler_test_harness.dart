// test/data/audio/handler_test_harness.dart
//
// Shared host-test harness for driving the REAL [PulsrAudioHandler] and its
// `part` mixins. The handler is constructed through its `forTesting` factory
// with three real [AudioPlayer]s backed by a deterministic in-memory
// [JustAudioPlatform], so every player stream (playbackEvent, currentIndex,
// position, duration, ...) is the genuine just_audio implementation while no
// native code is touched.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockYtmService extends Mock implements YtmService {}

/// A deterministic native player that answers every platform call just_audio
/// makes and lets tests emit raw [PlaybackEventMessage]s.
class FakeNativeAudioPlayer extends AudioPlayerPlatform {
  FakeNativeAudioPlayer(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();
  final StreamController<PlayerDataMessage> _data =
      StreamController<PlayerDataMessage>.broadcast();

  Duration? duration;
  Duration position = Duration.zero;
  Duration buffered = Duration.zero;
  bool playing = false;
  int? currentIndex = 0;
  int sourceCount = 0;
  LoopModeMessage loopMode = LoopModeMessage.off;
  bool disposed = false;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  void emitPlayback({
    ProcessingStateMessage processingState = ProcessingStateMessage.ready,
    Duration? updatePosition,
    Duration? bufferedPosition,
    Duration? durationOverride,
    int? index,
    int? androidAudioSessionId,
  }) {
    if (_events.isClosed) return;
    currentIndex = index ?? currentIndex;
    position = updatePosition ?? position;
    buffered = bufferedPosition ?? buffered;
    _events.add(PlaybackEventMessage(
      processingState: processingState,
      updateTime: DateTime.now(),
      updatePosition: position,
      bufferedPosition: buffered,
      duration: durationOverride ?? duration,
      icyMetadata: null,
      currentIndex: currentIndex,
      androidAudioSessionId: androidAudioSessionId,
    ));
  }

  void emitCompleted() {
    playing = false;
    _data.add(PlayerDataMessage(playing: false));
    emitPlayback(processingState: ProcessingStateMessage.completed);
  }

  void emitPlaying(bool value) {
    playing = value;
    _data.add(PlayerDataMessage(playing: value));
    emitPlayback();
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final source = request.audioSourceMessage;
    if (source is ConcatenatingAudioSourceMessage) {
      sourceCount = source.children.length;
    } else {
      sourceCount = 1;
    }
    duration = const Duration(minutes: 3, seconds: 30);
    currentIndex = request.initialIndex ?? 0;
    position = request.initialPosition ?? Duration.zero;
    emitPlayback(processingState: ProcessingStateMessage.ready);
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playing = true;
    _data.add(PlayerDataMessage(playing: true));
    emitPlayback();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    playing = false;
    _data.add(PlayerDataMessage(playing: false));
    emitPlayback();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    loopMode = request.loopMode;
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    position = request.position ?? position;
    currentIndex = request.index ?? currentIndex;
    emitPlayback();
    return SeekResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
              SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    sourceCount += request.children.length;
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    sourceCount -= (request.endIndex - request.startIndex);
    if (sourceCount < 0) sourceCount = 0;
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
          ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    disposed = true;
    if (!_events.isClosed) await _events.close();
    if (!_data.isClosed) await _data.close();
    return DisposeResponse();
  }
}

/// Deterministic [JustAudioPlatform] handing out [FakeNativeAudioPlayer]s.
class FakeJustAudioPlatform extends JustAudioPlatform {
  final Map<String, FakeNativeAudioPlayer> players = {};

  FakeNativeAudioPlayer get mostRecent => players.values.last;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakeNativeAudioPlayer(request.id);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    final player = players.remove(request.id);
    await player?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    for (final player in players.values) {
      await player.dispose(DisposeRequest());
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

const _audioEffectsChannel = MethodChannel('com.pulsr.music/audio_effects');
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _audioSessionChannel = MethodChannel('com.ryanheise.audio_session');
const _batteryChannel = MethodChannel('com.pulsr.music/battery_optimization');

/// Installs every platform-channel stub the handler stack touches on host
/// tests, plus a mocked SharedPreferences map.
void installHandlerChannelStubs({
  Map<String, Object> prefs = const {},
}) {
  SharedPreferences.setMockInitialValues(prefs);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(_audioEffectsChannel, (call) async {
    switch (call.method) {
      case 'getCapabilities':
      case 'getProcessingCapabilities':
      case 'getSpatializerState':
        return <String, dynamic>{};
      case 'detectOemAudio':
        return <String, dynamic>{
          'hasOemAudio': false,
          'detectedEngines': <String>[],
        };
      case 'getRtfGovernorStatus':
        return <String, dynamic>{};
      case 'getPipelineLatencyFrames':
      case 'getBatteryLevel':
        return 0;
      case 'getAppliedSampleRate':
        return 48000.0;
      case 'isDvcSupported':
      case 'hasActiveEffects':
        return false;
      case 'loadLiveProgCode':
        return 'OK';
      default:
        return true;
    }
  });

  messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
    return Directory.systemTemp.path;
  });

  messenger.setMockMethodCallHandler(_audioSessionChannel, (call) async {
    return null;
  });

  messenger.setMockMethodCallHandler(_batteryChannel, (call) async => null);
}

void removeHandlerChannelStubs() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_audioEffectsChannel, null);
  messenger.setMockMethodCallHandler(_pathProviderChannel, null);
  messenger.setMockMethodCallHandler(_audioSessionChannel, null);
  messenger.setMockMethodCallHandler(_batteryChannel, null);
}

/// Builds and fully-initializes a real handler with real (fake-backed) players.
Future<PulsrAudioHandler> buildTestHandler({
  required IMusicRepository repository,
  required YtmService ytmService,
}) async {
  final handler = PulsrAudioHandler.forTesting(
    repository: repository,
    ytmService: ytmService,
    playerA: AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    ),
    playerB: AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    ),
    prefetchPlayer: AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    ),
  );
  await handler.effectsReady;
  return handler;
}

/// A local song fixture with sensible defaults.
SongsTableData localSong(
  int id, {
  String? title,
  String? artist,
  String? album,
  String path = '/music/track.mp3',
  String? genre,
  int durationMs = 200000,
  bool isFavorite = false,
  bool isDownloaded = true,
  String? codec,
}) {
  return SongsTableData(
    id: id,
    title: title ?? 'Track $id',
    artist: artist ?? 'Artist $id',
    album: album ?? 'Album $id',
    durationMs: durationMs,
    path: path,
    source: SongSource.local,
    remoteId: null,
    genre: genre,
    codec: codec,
    isFavorite: isFavorite,
    isMissing: false,
    isDownloaded: isDownloaded,
    playCount: 0,
    lastPositionMs: 0,
  );
}

/// A YouTube song fixture.
SongsTableData ytSong(
  int id, {
  required String remoteId,
  String? title,
  String? artist,
  String? album,
  int durationMs = 200000,
}) {
  return SongsTableData(
    id: id,
    title: title ?? 'YT $id',
    artist: artist ?? 'Artist $id',
    album: album ?? 'Album $id',
    durationMs: durationMs,
    path: 'ytmusic://$remoteId',
    source: SongSource.youtube,
    remoteId: remoteId,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    playCount: 0,
    lastPositionMs: 0,
  );
}

/// Registers permissive default stubs so the handler's `_init()` restore path
/// never blocks on an unstubbed repository call.
void stubDefaultRepository(MockMusicRepository repo) {
  when(() => repo.getSavedQueue())
      .thenAnswer((_) async => const Right(<QueueItemsTableData>[]));
  when(() => repo.getAllSongs(
        sortBy: any(named: 'sortBy'),
        ascending: any(named: 'ascending'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      )).thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.watchAllSongs(
        sortBy: any(named: 'sortBy'),
        ascending: any(named: 'ascending'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
        searchQuery: any(named: 'searchQuery'),
        excludedFolders: any(named: 'excludedFolders'),
      )).thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
  when(() => repo.getFavorites())
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getRecentlyPlayed(limit: any(named: 'limit')))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getSongsByIds(any()))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getAlbums())
      .thenAnswer((_) async => const Right(<AlbumsTableData>[]));
  when(() => repo.getArtists())
      .thenAnswer((_) async => const Right(<ArtistsTableData>[]));
  when(() => repo.getPlaylists())
      .thenAnswer((_) async => const Right(<PlaylistsTableData>[]));
  when(() => repo.getGenres())
      .thenAnswer((_) async => const Right(<GenreItem>[]));
  when(() => repo.getSongById(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.getSongByPath(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.getSongByUri(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.getSongByRemoteId(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.getAlbumSongs(any()))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getArtistSongs(any()))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getPlaylistSongs(any()))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.getGenreSongs(any()))
      .thenAnswer((_) async => const Right(<SongsTableData>[]));
  when(() => repo.updateLastPosition(any(), any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.updateQueuePosition(any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.saveQueue(any(), any(), any()))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.recordPlayHistory(any(), completed: any(named: 'completed')))
      .thenAnswer((_) async => const Right(null));
  when(() => repo.toggleFavorite(any()))
      .thenAnswer((_) async => const Right(true));
  when(() => repo.findMatchingLocalSong(
        remoteId: any(named: 'remoteId'),
        title: any(named: 'title'),
        artist: any(named: 'artist'),
      )).thenAnswer((_) async => const Right(null));
}

/// Stubs a deterministic stream resolution so YouTube rows never reach the
/// network (or an unstubbed mock returning null).
void stubDefaultYtm(MockYtmService ytm) {
  when(() => ytm.resolveStream(
        any(),
        quality: any(named: 'quality'),
        forceRefresh: any(named: 'forceRefresh'),
      )).thenAnswer((inv) async {
    final videoId = inv.positionalArguments.first as String;
    return YtmStream(
      videoId: videoId,
      url: 'https://googlevideo.example/stream_$videoId.m4a',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 128,
      duration: const Duration(seconds: 200),
      title: 'Stream $videoId',
      artist: 'Artist',
    );
  });
  when(() => ytm.isWifiConnected()).thenAnswer((_) async => true);
  when(() => ytm.trending(limit: any(named: 'limit')))
      .thenAnswer((_) async => const <YtmTrack>[]);
  when(() => ytm.search(any(), limit: any(named: 'limit')))
      .thenAnswer((_) async => const <YtmTrack>[]);
}
