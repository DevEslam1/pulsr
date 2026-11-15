// lib/core/widgets/source_scope_switcher.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_segmented_control.dart';

/// Canonical scope options across Home, Search, Favorites, and Playlists.
enum SourceScope { all, local, online }

/// Unified Local / Online (and optional All) switcher with consistent labels,
/// icon order, and [SharedPreferences] persistence across features.
class SourceScopeSwitcher extends StatefulWidget {
  /// Surface identifier appended to [PrefsKeys.sourceScopePrefix] (e.g.
  /// `'home'`, `'search'`, `'favorites'`, `'playlists'`).
  final String persistKey;

  /// Currently active scope.
  final SourceScope selectedScope;

  /// Called when the user selects a scope or when a persisted scope is
  /// restored from disk.
  final ValueChanged<SourceScope> onChanged;

  /// Whether to prepend the `All` segment (used on Search).
  final bool includeAll;

  /// Optional badge counts rendered next to each segment label.
  final int? allCount;
  final int? localCount;
  final int? onlineCount;

  /// Outer margin forwarded to [PulsrSegmentedControl].
  final EdgeInsetsGeometry margin;

  const SourceScopeSwitcher({
    super.key,
    required this.persistKey,
    required this.selectedScope,
    required this.onChanged,
    this.includeAll = false,
    this.allCount,
    this.localCount,
    this.onlineCount,
    this.margin = EdgeInsets.zero,
  });

  /// Canonical storage key for a surface's saved scope.
  static String storageKey(String persistKey) =>
      '${PrefsKeys.sourceScopePrefix}$persistKey';

  @override
  State<SourceScopeSwitcher> createState() => _SourceScopeSwitcherState();
}

class _SourceScopeSwitcherState extends State<SourceScopeSwitcher> {
  @override
  void initState() {
    super.initState();
    unawaited(_restoreSavedScope());
  }

  Future<void> _restoreSavedScope() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final raw = prefs.getString(SourceScopeSwitcher.storageKey(widget.persistKey));
      if (raw == null) return;
      final parsed = SourceScope.values.where((s) => s.name == raw).firstOrNull;
      if (parsed == null) return;
      if (!widget.includeAll && parsed == SourceScope.all) return;
      if (parsed != widget.selectedScope) {
        widget.onChanged(parsed);
      }
    } catch (_) {
      // Safe fallback when SharedPreferences channel isn't mounted in isolated unit tests.
    }
  }

  Future<void> _persistScope(SourceScope scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SourceScopeSwitcher.storageKey(widget.persistKey),
        scope.name,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scopes = <SourceScope>[
      if (widget.includeAll) SourceScope.all,
      SourceScope.local,
      SourceScope.online,
    ];

    final currentIndex = scopes.indexOf(widget.selectedScope);
    final safeIndex = currentIndex >= 0 ? currentIndex : 0;

    final segments = <PulsrSegment>[
      for (final scope in scopes)
        switch (scope) {
          SourceScope.all => PulsrSegment(
              label: context.l10n.all,
              icon: Icons.dashboard_rounded,
              count: widget.allCount,
            ),
          SourceScope.local => PulsrSegment(
              label: context.l10n.local,
              icon: Icons.folder_rounded,
              count: widget.localCount,
            ),
          SourceScope.online => PulsrSegment(
              label: context.l10n.online,
              icon: Icons.cloud_rounded,
              count: widget.onlineCount,
            ),
        },
    ];

    return PulsrSegmentedControl(
      margin: widget.margin,
      selectedIndex: safeIndex,
      onChanged: (index) {
        if (index < 0 || index >= scopes.length) return;
        final next = scopes[index];
        unawaited(_persistScope(next));
        if (next != widget.selectedScope) {
          widget.onChanged(next);
        }
      },
      segments: segments,
    );
  }
}
