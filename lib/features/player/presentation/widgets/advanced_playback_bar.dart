// F1/F2/F11 controls: AB loop, per-track delay, bookmark resume.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

String _fmt(Duration? d) {
  if (d == null) return '--:--';
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class AdvancedPlaybackBar extends StatelessWidget {
  const AdvancedPlaybackBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (p, c) =>
          p.abLoopEnabled != c.abLoopEnabled ||
          p.abPointA != c.abPointA ||
          p.abPointB != c.abPointB ||
          p.trackDelayMs != c.trackDelayMs ||
          p.bookmarkPosition != c.bookmarkPosition ||
          p.currentSong?.id != c.currentSong?.id,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.bookmarkPosition != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Material(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark, color: Colors.amber),
                    title: Text(
                        'Resume from ${_fmt(state.bookmarkPosition)}?'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                            onPressed: cubit.seekToBookmark,
                            child: const Text('Resume')),
                        IconButton(
                            onPressed: cubit.dismissBookmark,
                            icon: const Icon(Icons.close, size: 18)),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // F1: AB loop
                  IconButton(
                    tooltip: 'Set loop point A (${_fmt(state.abPointA)})',
                    color: state.abPointA != null ? Colors.blue : null,
                    onPressed: cubit.setAbPointA,
                    icon: const Text('A',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'Set loop point B (${_fmt(state.abPointB)})',
                    color: state.abPointB != null ? Colors.blue : null,
                    onPressed: cubit.setAbPointB,
                    icon: const Text('B',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: state.abLoopEnabled
                        ? 'Disable AB loop'
                        : 'Enable AB loop',
                    color: state.abLoopEnabled ? Colors.green : null,
                    onPressed: (state.abPointA != null &&
                            state.abPointB != null)
                        ? cubit.toggleAbLoop
                        : null,
                    icon: const Icon(Icons.repeat_one_rounded),
                  ),
                  if (state.abPointA != null || state.abPointB != null)
                    IconButton(
                      tooltip: 'Clear AB loop',
                      onPressed: cubit.clearAbLoop,
                      icon: const Icon(Icons.clear, size: 18),
                    ),
                  const SizedBox(width: 8),
                  // F2: per-track delay
                  IconButton(
                    tooltip:
                        'Audio delay (${state.trackDelayMs} ms)',
                    onPressed: () =>
                        _showDelaySheet(context, cubit, state.trackDelayMs),
                    icon: const Icon(Icons.av_timer_outlined, size: 20),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDelaySheet(BuildContext context, PlayerCubit cubit, int current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _DelaySheet(initial: current, cubit: cubit),
    );
  }
}

class _DelaySheet extends StatefulWidget {
  final int initial;
  final PlayerCubit cubit;
  const _DelaySheet({required this.initial, required this.cubit});

  @override
  State<_DelaySheet> createState() => _DelaySheetState();
}

class _DelaySheetState extends State<_DelaySheet> {
  late double value;
  @override
  void initState() {
    super.initState();
    value = widget.initial.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audio delay: ${value.round()} ms',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('Positive delays audio (e.g. slow Bluetooth/video).'),
            Slider(
              min: -2000,
              max: 2000,
              divisions: 80,
              value: value,
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) => widget.cubit.setTrackDelayMs(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.cubit.setTrackDelayMs(0);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
