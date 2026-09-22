import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A-06: Global keyboard shortcuts for desktop/tablet.
///
/// Bindings:
///   Space        → play/pause
///   → / ←        → seek forward / backward 10s
///   ↑ / ↓        → volume up / down 5%
///   N / P        → next / previous
///   M            → mute toggle
///   L            → toggle lyrics
///   Q            → toggle queue
///
/// Shortcuts are suppressed while a text input ([EditableText]) has focus so
/// typing in a search field never triggers playback actions.
class PlayerShortcutScope extends StatelessWidget {
  final Widget child;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;

  const PlayerShortcutScope({
    super.key,
    required this.child,
    required this.onTogglePlayPause,
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onNext,
    required this.onPrevious,
    required this.onToggleMute,
    required this.onToggleLyrics,
    required this.onToggleQueue,
  });

  /// True when the primary focus belongs to a text input, in which case
  /// single-letter/space shortcuts must not fire.
  static bool isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  VoidCallback _guard(VoidCallback action) {
    return () {
      if (isTextInputFocused()) return;
      action();
    };
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space):
            _guard(onTogglePlayPause),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            _guard(onSeekForward),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _guard(onSeekBackward),
        const SingleActivator(LogicalKeyboardKey.arrowUp): _guard(onVolumeUp),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            _guard(onVolumeDown),
        const SingleActivator(LogicalKeyboardKey.keyN): _guard(onNext),
        const SingleActivator(LogicalKeyboardKey.keyP): _guard(onPrevious),
        const SingleActivator(LogicalKeyboardKey.keyM): _guard(onToggleMute),
        const SingleActivator(LogicalKeyboardKey.keyL): _guard(onToggleLyrics),
        const SingleActivator(LogicalKeyboardKey.keyQ): _guard(onToggleQueue),
      },
      // autofocus guarantees a focused descendant exists so key events reach
      // the CallbackShortcuts Focus even when no control has focus.
      child: Focus(autofocus: true, child: child),
    );
  }
}
