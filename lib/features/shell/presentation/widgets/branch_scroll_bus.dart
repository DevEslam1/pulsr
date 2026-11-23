import 'package:material_ui/material_ui.dart';

/// Callback signature invoked when the active navigation branch tab is
/// re-tapped while already selected.
typedef BranchReselectCallback = void Function({required bool reduceMotion});

/// Coordinates scroll-to-top actions when a user re-taps the already active
/// shell navigation branch.
///
/// Branches inside `StatefulNavigationShell` typically manage their own
/// `CustomScrollView` / `ListView` controllers rather than sharing `MaterialApp`'s
/// root `PrimaryScrollController`. Screens may register a controller or custom
/// listener here; when none is registered, [scrollActiveBranchToTop] locates the
/// visible vertical `ScrollableState` inside the active branch subtree.
class BranchScrollBus {
  BranchScrollBus._();

  /// Shared singleton bus used by [AppShell].
  static final BranchScrollBus instance = BranchScrollBus._();

  /// Creates an isolated instance for unit tests.
  @visibleForTesting
  BranchScrollBus.forTesting();

  final Map<int, List<ScrollController>> _controllers =
      <int, List<ScrollController>>{};
  final Map<int, List<BranchReselectCallback>> _listeners =
      <int, List<BranchReselectCallback>>{};

  /// Registers [controller] for [branchIndex] and returns an unregister hook.
  VoidCallback registerController(
    int branchIndex,
    ScrollController controller,
  ) {
    final list =
        _controllers.putIfAbsent(branchIndex, () => <ScrollController>[]);
    if (!list.contains(controller)) {
      list.add(controller);
    }
    return () {
      final entries = _controllers[branchIndex];
      if (entries == null) return;
      entries.remove(controller);
      if (entries.isEmpty) {
        _controllers.remove(branchIndex);
      }
    };
  }

  /// Registers a custom re-tap listener for [branchIndex] and returns an
  /// unregister hook.
  VoidCallback addListener(
    int branchIndex,
    BranchReselectCallback listener,
  ) {
    final list =
        _listeners.putIfAbsent(branchIndex, () => <BranchReselectCallback>[]);
    if (!list.contains(listener)) {
      list.add(listener);
    }
    return () {
      final entries = _listeners[branchIndex];
      if (entries == null) return;
      entries.remove(listener);
      if (entries.isEmpty) {
        _listeners.remove(branchIndex);
      }
    };
  }

  /// Clears all registered controllers and listeners (for test teardown).
  @visibleForTesting
  void clear() {
    _controllers.clear();
    _listeners.clear();
  }

  /// Notifies listeners and scrolls the active branch to the top.
  Future<bool> scrollActiveBranchToTop({
    required int branchIndex,
    BuildContext? branchContext,
    ScrollController? primaryFallback,
    required bool reduceMotion,
    Duration duration = const Duration(milliseconds: 260),
    Curve curve = Curves.easeOutCubic,
  }) async {
    final listeners = List<BranchReselectCallback>.from(
      _listeners[branchIndex] ?? const <BranchReselectCallback>[],
    );
    for (final listener in listeners) {
      listener(reduceMotion: reduceMotion);
    }

    final controllers = List<ScrollController>.from(
      _controllers[branchIndex] ?? const <ScrollController>[],
    );
    var scrolled = false;
    for (final controller in controllers) {
      if (!controller.hasClients) continue;
      await _scrollPositionToStart(
        controller.position,
        reduceMotion: reduceMotion,
        duration: duration,
        curve: curve,
      );
      scrolled = true;
    }
    if (scrolled) return true;

    if (branchContext != null && branchContext.mounted) {
      final position = _findVisibleVerticalScrollPosition(branchContext);
      if (position != null) {
        await _scrollPositionToStart(
          position,
          reduceMotion: reduceMotion,
          duration: duration,
          curve: curve,
        );
        return true;
      }
    }

    if (primaryFallback != null && primaryFallback.hasClients) {
      await _scrollPositionToStart(
        primaryFallback.position,
        reduceMotion: reduceMotion,
        duration: duration,
        curve: curve,
      );
      return true;
    }

    return listeners.isNotEmpty;
  }

  Future<void> _scrollPositionToStart(
    ScrollPosition position, {
    required bool reduceMotion,
    required Duration duration,
    required Curve curve,
  }) async {
    final target = position.hasPixels ? position.minScrollExtent : 0.0;
    if (reduceMotion || duration <= Duration.zero) {
      position.jumpTo(target);
      return;
    }
    await position.animateTo(
      target,
      duration: duration,
      curve: curve,
    );
  }

  ScrollPosition? _findVisibleVerticalScrollPosition(BuildContext root) {
    ScrollPosition? fallbackAttached;

    bool visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) {
        return false;
      }
      if (widget is TickerMode && !widget.enabled) {
        return false;
      }
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        final axis = axisDirectionToAxis(scrollable.axisDirection);
        if (axis == Axis.vertical && scrollable.position.hasPixels) {
          final pos = scrollable.position;
          fallbackAttached ??= pos;
          if (pos.pixels > pos.minScrollExtent) {
            fallbackAttached = pos;
            return true;
          }
        }
      }
      var found = false;
      element.visitChildren((child) {
        if (!found) {
          found = visit(child);
        }
      });
      return found;
    }

    if (root is Element) {
      visit(root);
    }
    return fallbackAttached;
  }
}
