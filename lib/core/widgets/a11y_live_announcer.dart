// lib/core/widgets/a11y_live_announcer.dart
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import '../utils/l10n_extensions.dart';

/// Accessibility live region coordinator for TalkBack / VoiceOver.
///
/// Announces:
/// 1. Track change ("Now playing: {title} by {artist}")
/// 2. Play/Pause transitions ("Playing" / "Paused")
/// 3. Queue mutations (song added, song removed, queue reordered, queue cleared)
///
/// Dispatches announcements both via [SemanticsService.sendAnnouncement] for immediate
/// speech synthesis and via an active [liveRegion] semantics node in the widget
/// tree for screen readers listening to tree mutations.
class A11yLiveAnnouncer extends StatefulWidget {
  final Widget child;

  const A11yLiveAnnouncer({super.key, required this.child});

  @override
  State<A11yLiveAnnouncer> createState() => A11yLiveAnnouncerState();
}

class A11yLiveAnnouncerState extends State<A11yLiveAnnouncer> {
  String _announcement = '';
  PlayerState? _prevState;

  @visibleForTesting
  String get currentAnnouncement => _announcement;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prevState ??= context.read<PlayerCubit>().state;
  }

  void announce(String message) {
    if (message.isEmpty || !mounted) return;
    setState(() {
      _announcement = message;
    });
    try {
      final view = View.maybeOf(context);
      final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
      if (view != null) {
        SemanticsService.sendAnnouncement(
          view,
          message,
          direction,
          assertiveness: Assertiveness.polite,
        );
      }
    } catch (_) {
      // Swallowed in test environments where platform messaging channel is absent
    }
  }

  void _handlePlayerStateChange(
    BuildContext context,
    PlayerState prev,
    PlayerState curr,
  ) {
    final l10n = context.l10n;

    // 1. Track change
    final prevSong = prev.currentSong;
    final currSong = curr.currentSong;
    if (currSong != null && (prevSong == null || prevSong.id != currSong.id)) {
      announce(l10n.nowPlayingSemantics(currSong.title, currSong.artist));
      return;
    }

    // 2. Play / Pause transition
    if (currSong != null && prev.isPlaying != curr.isPlaying) {
      final msg = curr.isPlaying
          ? l10n.playbackPlayingAnnouncement
          : l10n.playbackPausedAnnouncement;
      announce(msg);
      return;
    }

    // 3. Queue mutations
    final prevQ = prev.queue;
    final currQ = curr.queue;
    if (prevQ.isEmpty && currQ.isEmpty) return;

    if (currQ.length > prevQ.length) {
      final added = currQ.firstWhere(
        (s) => !prevQ.any((p) => p.id == s.id),
        orElse: () => currQ.last,
      );
      announce(l10n.songAddedToQueue(added.title));
      return;
    }

    if (currQ.length < prevQ.length) {
      if (currQ.isEmpty) {
        announce(l10n.queueCleared);
        return;
      }
      final removed = prevQ.firstWhere(
        (s) => !currQ.any((c) => c.id == s.id),
        orElse: () => prevQ.first,
      );
      announce(l10n.queueSongRemoved(removed.title));
      return;
    }

    if (currQ.length == prevQ.length && currQ.isNotEmpty) {
      bool orderChanged = false;
      for (int i = 0; i < currQ.length; i++) {
        if (currQ[i].id != prevQ[i].id) {
          orderChanged = true;
          break;
        }
      }
      if (orderChanged) {
        announce(l10n.queueReordered);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PlayerCubit, PlayerState>(
      listenWhen: (prev, curr) {
        final songChanged = prev.currentSong?.id != curr.currentSong?.id;
        final playChanged = prev.isPlaying != curr.isPlaying;
        final queueChanged = prev.queue.length != curr.queue.length ||
            !listEquals(
              prev.queue.map((s) => s.id).toList(growable: false),
              curr.queue.map((s) => s.id).toList(growable: false),
            );
        return songChanged || playChanged || queueChanged;
      },
      listener: (context, state) {
        if (_prevState != null) {
          _handlePlayerStateChange(context, _prevState!, state);
        }
        _prevState = state;
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          PositionedDirectional(
            start: 0,
            top: 0,
            width: 0,
            height: 0,
            child: Semantics(
              container: true,
              liveRegion: true,
              label: _announcement,
              child: const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
