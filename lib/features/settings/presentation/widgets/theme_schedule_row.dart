// lib/features/settings/presentation/widgets/theme_schedule_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/settings_cubit.dart';

/// Lets the user pick the start/end hour of the automatic dark theme window.
///
/// Values live in SharedPreferences (read by SettingsCubit on cold start) and
/// are pushed into the [ThemeSchedulerService] singleton via
/// [SettingsCubit.setThemeScheduleHours]. Only shown while
/// `state.autoThemeByTime` is on.
class ThemeScheduleRow extends StatefulWidget {
  const ThemeScheduleRow({super.key});

  @override
  State<ThemeScheduleRow> createState() => _ThemeScheduleRowState();
}

class _ThemeScheduleRowState extends State<ThemeScheduleRow> {
  static const String _startKey = 'setting_theme_schedule_start';
  static const String _endKey = 'setting_theme_schedule_end';
  int _start = 19;
  int _end = 6;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final start = prefs.getInt(_startKey) ?? 19;
      final end = prefs.getInt(_endKey) ?? 6;
      if (!mounted) return;
      setState(() {
        _start = start;
        _end = end;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _apply(int start, int end) {
    setState(() {
      _start = start;
      _end = end;
    });
    context
        .read<SettingsCubit>()
        .setThemeScheduleHours(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: p.accent),
              const SizedBox(width: 12),
              Text(
                context.l10n.themeScheduleTitle,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HourDropdown(
                  label: context.l10n.themeScheduleStartLabel,
                  value: _start,
                  onChanged: (v) => _apply(v, _end),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HourDropdown(
                  label: context.l10n.themeScheduleEndLabel,
                  value: _end,
                  onChanged: (v) => _apply(_start, v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HourDropdown extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _HourDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: p.textSecondary, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        DropdownButton<int>(
          isExpanded: true,
          underline: const SizedBox.shrink(),
          value: value,
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem<int>(
                value: h,
                child: Text(context.l10n.themeScheduleHour(h)),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
