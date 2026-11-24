// lib/core/widgets/pulsr_modal_tracker.dart
import 'package:material_ui/material_ui.dart';
import '../router/safe_navigation.dart';
import '../services/system_ui_controller.dart';
import 'pulsr_dock_tracker.dart';

/// {@category DesignSystem}
/// Global tracker for modal routes (dialogs / bottom sheets).
///
/// The app shell (mini player dock, tablet player bar) listens to
/// [isModalOpen] and hides itself while any modal is on screen, so the
/// mini player never renders on top of dialogs.
///
/// Modals must be registered either automatically via the root
/// [PulsrModalObserver] or manually with [push]/[pop] (used by
/// `PulsrDialog` helpers for non-root navigators).
class PulsrModalTracker {
  static final ValueNotifier<bool> isModalOpen = ValueNotifier<bool>(false);
  static int _activeModals = 0;

  static void push() {
    _activeModals++;
    if (_activeModals == 1) isModalOpen.value = true;
  }

  static void pop() {
    _activeModals = (_activeModals - 1).clamp(0, 1 << 30);
    if (_activeModals == 0) isModalOpen.value = false;
  }
}

/// Root navigator observer that auto-registers dialogs, bottom sheets, and full-screen player routes.
class PulsrModalObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (_isModal(route)) PulsrModalTracker.push();
    if (_isNowPlaying(route)) PulsrDockTracker.setNowPlayingOpen(true);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (_isModal(route)) {
      PulsrModalTracker.pop();
    } else {
      PulsrSafePush.clearDebounce();
    }
    SystemUiController.instance.releaseForRoute(route);
    if (_isNowPlaying(route)) {
      PulsrDockTracker.setNowPlayingOpen(false);
      SystemUiController.instance.releaseImmersive('now_playing');
      SystemUiController.instance.releaseImmersive('karaoke');
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (_isModal(route)) PulsrModalTracker.pop();
    SystemUiController.instance.releaseForRoute(route);
    if (_isNowPlaying(route)) {
      PulsrDockTracker.setNowPlayingOpen(false);
      SystemUiController.instance.releaseImmersive('now_playing');
      SystemUiController.instance.releaseImmersive('karaoke');
    }
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (oldRoute != null && _isModal(oldRoute)) PulsrModalTracker.pop();
    if (newRoute != null && _isModal(newRoute)) PulsrModalTracker.push();
    if (oldRoute != null) {
      SystemUiController.instance.releaseForRoute(oldRoute);
    }
    if (oldRoute != null && _isNowPlaying(oldRoute)) {
      PulsrDockTracker.setNowPlayingOpen(false);
      SystemUiController.instance.releaseImmersive('now_playing');
      SystemUiController.instance.releaseImmersive('karaoke');
    }
    if (newRoute != null && _isNowPlaying(newRoute)) {
      PulsrDockTracker.setNowPlayingOpen(true);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  // Detect modals by ROUTE TYPE rather than a brittle name-substring heuristic.
  // This reliably catches bottom sheets and dialogs regardless of their route
  // name. (DialogRoute/RawDialogRoute/ModalBottomSheetRoute all extend
  // PopupRoute, but they are listed explicitly for clarity.)
  bool _isModal(Route route) =>
      route is ModalBottomSheetRoute ||
      route is DialogRoute ||
      route is RawDialogRoute ||
      route is PopupRoute;

  bool _isNowPlaying(Route route) =>
      route.settings.name == 'now-playing' ||
      route.settings.name == '/now-playing';
}

/// Ensures system Back closes the topmost modal sheet/dialog on the root
/// navigator BEFORE `GoRouter` pops an underlying pushed `StatefulShellBranch`
/// route (such as `context.push('/settings')`).
///
/// Uses a `ChildBackButtonDispatcher` with `takePriority()` so it outranks
/// `StatefulShellRoute`'s branch `ChildBackButtonDispatcher` (plain
/// `BackButtonListener` only adds a callback on the parent dispatcher, which
/// runs *after* prioritized child dispatchers).
class PulsrModalBackGuard extends StatefulWidget {
  final Widget child;

  const PulsrModalBackGuard({super.key, required this.child});

  @override
  State<PulsrModalBackGuard> createState() => _PulsrModalBackGuardState();
}

class _PulsrModalBackGuardState extends State<PulsrModalBackGuard> {
  ChildBackButtonDispatcher? _dispatcher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = Router.maybeOf(context)?.backButtonDispatcher;
    if (parent != null && _dispatcher == null) {
      _dispatcher = parent.createChildBackButtonDispatcher()
        ..addCallback(_handleBack)
        ..takePriority();
    }
  }

  Future<bool> _handleBack() async {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    await Navigator.of(context).maybePop();
    return true;
  }

  @override
  void dispose() {
    final dispatcher = _dispatcher;
    if (dispatcher != null) {
      dispatcher.removeCallback(_handleBack);
      dispatcher.parent.forget(dispatcher);
    }
    _dispatcher = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
