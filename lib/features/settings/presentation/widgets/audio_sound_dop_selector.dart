part of 'audio_sound_section.dart';

/// DoP PCM container width selector (24-bit standard packing vs zero-padded
/// 32-bit frames for DACs that require 32-bit USB frames). Persisted directly
/// to [PrefsKeys.dopContainerBits] so no settings-state codegen is required;
/// the playback router reads the same key when framing DoP. Shown only while
/// DoP output is selected on a capable DAC.
class _DopContainerSelector extends StatefulWidget {
  const _DopContainerSelector();

  @override
  State<_DopContainerSelector> createState() => _DopContainerSelectorState();
}

class _DopContainerSelectorState extends State<_DopContainerSelector> {
  int _bits = 24;
  bool _loaded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed || !mounted) return;
      setState(() {
        final stored = prefs.getInt(PrefsKeys.dopContainerBits) ?? 24;
        _bits = stored == 32 ? 32 : 24;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _select(int bits) async {
    if (_disposed || !mounted) return;
    setState(() => _bits = bits);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.dopContainerBits, bits);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!_loaded) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.dopContainer,
            style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
          ),
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding:
                WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
          ),
          segments: const [
            ButtonSegment(
              value: 24,
              label: Text("24-bit",
                  style:
                      TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
            ),
            ButtonSegment(
              value: 32,
              label: Text("32-bit",
                  style:
                      TextStyle(fontSize: AppFontSize.caption, fontWeight: FontWeight.w700)),
            ),
          ],
          selected: {_bits},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) _select(selected.first);
          },
        ),
      ],
    );
  }
}
