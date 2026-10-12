// lib/data/party/party_models.dart

/// A song as shared within a listen-together party.
class PartyTrack {
  final String videoId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int? durationMs;
  final bool fromAutoplay;

  const PartyTrack({
    required this.videoId,
    this.title = '',
    this.artist = '',
    this.thumbnailUrl,
    this.durationMs,
    this.fromAutoplay = false,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (durationMs != null) 'durationMs': durationMs,
        'fromAutoplay': fromAutoplay,
      };

  factory PartyTrack.fromJson(Map<String, dynamic> json) {
    return PartyTrack(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      fromAutoplay: json['fromAutoplay'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartyTrack &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId &&
          title == other.title &&
          artist == other.artist;

  @override
  int get hashCode => videoId.hashCode ^ title.hashCode ^ artist.hashCode;
}

/// One participant in the party.
class PartyMember {
  final String memberId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isHost;
  final bool connected;
  final int joinedAtMs;
  final int lastSeenMs;

  const PartyMember({
    required this.memberId,
    this.userId = '',
    this.displayName = '',
    this.avatarUrl,
    this.isHost = false,
    this.connected = false,
    this.joinedAtMs = 0,
    this.lastSeenMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'memberId': memberId,
        'userId': userId,
        'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'isHost': isHost,
        'connected': connected,
        'joinedAtMs': joinedAtMs,
        'lastSeenMs': lastSeenMs,
      };

  factory PartyMember.fromJson(Map<String, dynamic> json) {
    return PartyMember(
      memberId: json['memberId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      isHost: json['isHost'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      joinedAtMs: (json['joinedAtMs'] as num?)?.toInt() ?? 0,
      lastSeenMs: (json['lastSeenMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Playback status of the party.
class PartyPlayback {
  final int seq;
  final PartyTrack? track;
  final int queueSeq;
  final int queueLength;
  final int queueIndex;
  final bool isPlaying;
  final int positionMs;
  final int anchorMs;
  final int effectivePositionMs;
  final String? updatedBy;
  final String? startedBy;
  final String? startedByName;
  final bool autoplayEnabled;
  final int updatedAtMs;

  const PartyPlayback({
    this.seq = 0,
    this.track,
    this.queueSeq = 0,
    this.queueLength = 0,
    this.queueIndex = -1,
    this.isPlaying = false,
    this.positionMs = 0,
    this.anchorMs = 0,
    this.effectivePositionMs = 0,
    this.updatedBy,
    this.startedBy,
    this.startedByName,
    this.autoplayEnabled = false,
    this.updatedAtMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        if (track != null) 'track': track!.toJson(),
        'queueSeq': queueSeq,
        'queueLength': queueLength,
        'queueIndex': queueIndex,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'anchorMs': anchorMs,
        'effectivePositionMs': effectivePositionMs,
        if (updatedBy != null) 'updatedBy': updatedBy,
        if (startedBy != null) 'startedBy': startedBy,
        if (startedByName != null) 'startedByName': startedByName,
        'autoplayEnabled': autoplayEnabled,
        'updatedAtMs': updatedAtMs,
      };

  factory PartyPlayback.fromJson(Map<String, dynamic> json) {
    final trackJson = json['track'];
    return PartyPlayback(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      track: trackJson is Map<String, dynamic>
          ? PartyTrack.fromJson(trackJson)
          : null,
      queueSeq: (json['queueSeq'] as num?)?.toInt() ?? 0,
      queueLength: (json['queueLength'] as num?)?.toInt() ?? 0,
      queueIndex: (json['queueIndex'] as num?)?.toInt() ?? -1,
      isPlaying: json['isPlaying'] as bool? ?? false,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      anchorMs: (json['anchorMs'] as num?)?.toInt() ?? 0,
      effectivePositionMs:
          (json['effectivePositionMs'] as num?)?.toInt() ?? 0,
      updatedBy: json['updatedBy'] as String?,
      startedBy: json['startedBy'] as String?,
      startedByName: json['startedByName'] as String?,
      autoplayEnabled: json['autoplayEnabled'] as bool? ?? false,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The playlist running order shared across party members.
class PartyQueue {
  final int seq;
  final int index;
  final List<PartyTrack> items;

  const PartyQueue({
    this.seq = 0,
    this.index = -1,
    this.items = const [],
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'index': index,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory PartyQueue.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PartyQueue(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      index: (json['index'] as num?)?.toInt() ?? -1,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map((e) => PartyTrack.fromJson(e))
          .toList(),
    );
  }
}

/// Full snapshot sent on joining or welcome.
class PartySnapshot {
  final String code;
  final int createdAtMs;
  final int maxMembers;
  final bool hostOnlyControl;
  final List<PartyMember> members;
  final PartyPlayback playback;
  final PartyQueue queue;
  final int serverMs;

  const PartySnapshot({
    this.code = '',
    this.createdAtMs = 0,
    this.maxMembers = 5,
    this.hostOnlyControl = false,
    this.members = const [],
    this.playback = const PartyPlayback(),
    this.queue = const PartyQueue(),
    this.serverMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'createdAtMs': createdAtMs,
        'maxMembers': maxMembers,
        'hostOnlyControl': hostOnlyControl,
        'members': members.map((e) => e.toJson()).toList(),
        'playback': playback.toJson(),
        'queue': queue.toJson(),
        'serverMs': serverMs,
      };

  factory PartySnapshot.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? [];
    final playbackJson = json['playback'] as Map<String, dynamic>? ?? {};
    final queueJson = json['queue'] as Map<String, dynamic>? ?? {};

    return PartySnapshot(
      code: json['code'] as String? ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 5,
      hostOnlyControl: json['hostOnlyControl'] as bool? ?? false,
      members: rawMembers
          .whereType<Map<String, dynamic>>()
          .map((e) => PartyMember.fromJson(e))
          .toList(),
      playback: PartyPlayback.fromJson(playbackJson),
      queue: PartyQueue.fromJson(queueJson),
      serverMs: (json['serverMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Returned by POST /api/parties and POST /api/parties/{code}/join
class PartyMembership {
  final String code;
  final String token;
  final PartyMember you;
  final PartySnapshot party;
  final int serverMs;

  const PartyMembership({
    required this.code,
    required this.token,
    required this.you,
    required this.party,
    this.serverMs = 0,
  });

  factory PartyMembership.fromJson(Map<String, dynamic> json) {
    return PartyMembership(
      code: json['code'] as String? ?? '',
      token: json['token'] as String? ?? '',
      you: PartyMember.fromJson(json['you'] as Map<String, dynamic>? ?? {}),
      party:
          PartySnapshot.fromJson(json['party'] as Map<String, dynamic>? ?? {}),
      serverMs: (json['serverMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Request body for party creation and join endpoints.
class JoinPartyRequest {
  final String userId;
  final String deviceId;
  final String displayName;
  final String? avatarUrl;
  final int? maxMembers;
  final bool? autoplayEnabled;

  const JoinPartyRequest({
    required this.userId,
    required this.deviceId,
    required this.displayName,
    this.avatarUrl,
    this.maxMembers,
    this.autoplayEnabled,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'deviceId': deviceId,
        'displayName': displayName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (maxMembers != null) 'maxMembers': maxMembers,
        if (autoplayEnabled != null) 'autoplayEnabled': autoplayEnabled,
      };
}
