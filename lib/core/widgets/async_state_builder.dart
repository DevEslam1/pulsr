// lib/core/widgets/async_state_builder.dart
import 'package:flutter/material.dart';

import '../errors/error_message_resolver.dart';
import '../utils/l10n_extensions.dart';
import 'pulsr_empty_state.dart';
import 'shimmer_skeleton.dart';

/// {@category DesignSystem}
/// Unified renderer for [AsyncSnapshot] loading / error / empty / data states.
///
/// Replaces hand-rolled `connectionState == waiting` / `hasError` / `hasData`
/// branching so every screen presents the same skeleton, retry card and empty
/// state. Override any state with [loadingWidget], [onError] or [emptyWidget];
/// classify a successful-but-empty payload with [isEmpty].
class AsyncStateBuilder<T> extends StatelessWidget {
  const AsyncStateBuilder({
    super.key,
    required this.snapshot,
    required this.onData,
    this.loadingWidget,
    this.onError,
    this.emptyWidget,
    this.isEmpty,
    this.onRetry,
  });

  final AsyncSnapshot<T> snapshot;

  final Widget Function(T data) onData;

  final Widget? loadingWidget;

  final Widget Function(Object error)? onError;

  final Widget? emptyWidget;

  final bool Function(T data)? isEmpty;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return loadingWidget ?? const SkeletonList();
    }
    if (snapshot.hasError) {
      final error = snapshot.error!;
      return onError?.call(error) ??
          _AsyncErrorCard(error: error, onRetry: onRetry);
    }
    final data = snapshot.data;
    if (data == null || (isEmpty?.call(data) ?? false)) {
      return emptyWidget ?? const _AsyncEmptyCard();
    }
    return onData(data);
  }
}

class _AsyncErrorCard extends StatelessWidget {
  const _AsyncErrorCard({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PulsrEmptyState(
      icon: Icons.error_outline_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: l10n.somethingWentWrong,
      subtitle: resolveUiErrorMessage(context, error.toString()),
      primaryActionLabel: onRetry == null ? null : l10n.retry,
      primaryActionIcon: Icons.refresh_rounded,
      onPrimaryAction: onRetry,
    );
  }
}

class _AsyncEmptyCard extends StatelessWidget {
  const _AsyncEmptyCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PulsrEmptyState(
      icon: Icons.inbox_rounded,
      title: l10n.noResultsFound,
      subtitle: l10n.noResultsSubtitle,
    );
  }
}
