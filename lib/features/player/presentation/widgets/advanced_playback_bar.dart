// F1/F2/F11 controls: AB loop, per-track delay, bookmark resume.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_slider.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';

/// AB-loop / bookmark labels need a placeholder for an unset point; the
/// duration itself is formatted with the shared [Formatters.formatDuration] so
/// it can never disagree with the seek bar (A-12).
String _fmt(Duration? d) {
  if (d == null) return '--:--';
  return Formatters.formatDuration(d);
}

class AdvancedPlaybackBar extends StatelessWidget {
  const AdvancedPlaybackBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                  color: context.palette.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading:
                        Icon(Icons.bookmark, color: context.palette.warning),
                    title: Text(l10n.resumeFromPrompt(
                        _fmt(state.bookmarkPosition))),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                            onPressed: cubit.seekToBookmark,
                            child: Text(l10n.resume)),
                        IconButton(
                            tooltip: l10n.close,
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
                    tooltip: l10n.setLoopPointA(_fmt(state.abPointA)),
                    color: state.abPointA != null ? context.palette.info : null,
                    onPressed: cubit.setAbPointA,
                    icon: const Text('A',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: l10n.setLoopPointB(_fmt(state.abPointB)),
                    color: state.abPointB != null ? context.palette.info : null,
                    onPressed: cubit.setAbPointB,
                    icon: const Text('B',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: state.abLoopEnabled
                        ? l10n.disableAbLoop
                        : l10n.enableAbLoop,
                    color: state.abLoopEnabled ? context.palette.success : null,
                    onPressed: (state.abPointA != null &&
                            state.abPointB != null)
                        ? cubit.toggleAbLoop
                        : null,
                    icon: const Icon(Icons.repeat_one_rounded),
                  ),
                  if (state.abPointA != null || state.abPointB != null)
                    IconButton(
                      tooltip: l10n.clearAbLoop,
                      onPressed: cubit.clearAbLoop,
                      icon: const Icon(Icons.clear, size: 18),
                    ),
                  const SizedBox(width: 8),
                  // F2: per-track delay
                  IconButton(
                    tooltip: l10n.audioDelayTooltip(state.trackDelayMs),
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
    PulsrSheetHelper.showPulsrSheet<void>(
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
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.audioDelayMsLabel(value.round()),
                style: Theme.of(context).textTheme.titleMedium),
            Text(l10n.audioDelayHelp),
            PulsrSlider(
              min: -2000,
              max: 2000,
              divisions: 80,
              value: value,
              semanticLabel: l10n.audioDelayMsLabel(value.round()),
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
                  child: Text(l10n.reset),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
