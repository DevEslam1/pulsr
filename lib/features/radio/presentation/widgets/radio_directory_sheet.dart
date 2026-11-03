// lib/features/radio/presentation/widgets/radio_directory_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/radio_browser_service.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/pulsr_search_field.dart';
import '../../../../core/widgets/pulsr_toast.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../domain/models/radio_station.dart';

/// Search-and-add sheet for the live radio-browser.info directory.
class RadioDirectorySheet extends StatefulWidget {
  const RadioDirectorySheet({
    super.key,
    required this.service,
    required this.store,
  });

  final RadioBrowserService service;
  final RadioStationStore store;

  static Future<void> show(
    BuildContext context, {
    RadioBrowserService? service,
    RadioStationStore? store,
  }) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 820),
      builder: (_) => FractionallySizedBox(
        heightFactor: isLandscape ? 0.94 : 0.88,
        child: RadioDirectorySheet(
          service: service ?? RadioBrowserService(),
          store: store ?? RadioStationStore(),
        ),
      ),
    );
  }

  @override
  State<RadioDirectorySheet> createState() => _RadioDirectorySheetState();
}

class _RadioDirectorySheetState extends State<RadioDirectorySheet> {
  final TextEditingController _controller = TextEditingController();
  final Set<String> _addedIds = <String>{};
  final Set<String> _checkingIds = <String>{};

  List<RadioStation> _results = const [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    for (final existing in widget.store.list) {
      _addedIds.add(existing.id);
    }
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isStationAlreadySaved(RadioStation station) {
    return _addedIds.contains(station.id) ||
        widget.store.hasUrlCollision(station.url);
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final results = await widget.service.search(query: query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _add(RadioStation station) async {
    if (_isStationAlreadySaved(station) || _checkingIds.contains(station.id)) {
      return;
    }
    setState(() => _checkingIds.add(station.id));
    final reachable = await widget.service.isReachable(station.url);
    if (!mounted) return;
    setState(() => _checkingIds.remove(station.id));
    if (!reachable) {
      PulsrToast.show(
        context,
        message: context.l10n.radioDirectoryUnreachable,
        isError: true,
      );
      return;
    }
    try {
      await widget.store.add(station);
      if (!mounted) return;
      setState(() => _addedIds.add(station.id));
      PulsrToast.show(
        context,
        message: context.l10n.radioDirectoryAdded,
        icon: Icons.check_rounded,
      );
    } catch (_) {
      if (!mounted) return;
      PulsrToast.show(
        context,
        message: context.l10n.somethingWentWrong,
        isError: true,
      );
    }
  }

  Widget _buildStationResultTile(
    BuildContext context,
    RadioStation station, {
    required bool isCompact,
  }) {
    final p = context.palette;
    final added = _isStationAlreadySaved(station);
    final checking = _checkingIds.contains(station.id);

    return Material(
      color: p.surfaceContainer,
      borderRadius: AppRadii.r14All,
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: ListTile(
          dense: isCompact,
          contentPadding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.sm,
            isCompact ? 0 : AppSpacing.xxs,
            AppSpacing.xs,
            isCompact ? 0 : AppSpacing.xxs,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.r12All,
            ),
            clipBehavior: Clip.antiAlias,
            child: station.artworkUrl != null
                ? Image.network(
                    station.artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.radio_rounded, color: p.textTertiary),
                  )
                : Icon(Icons.radio_rounded, color: p.textTertiary),
          ),
          title: MarqueeText(
            text: station.name,
            textAlign: TextAlign.start,
            allowUserPause: false,
            velocity: 28.0,
            blankSpace: 36.0,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.bodySmall,
            ),
          ),
          subtitle: station.genre == null
              ? null
              : Text(
                  station.genre!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                  ),
                ),
          trailing: TextButton.icon(
            onPressed: added || checking ? null : () => _add(station),
            icon: checking
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.accent,
                    ),
                  )
                : Icon(
                    added ? Icons.check_rounded : Icons.add_rounded,
                    size: 18,
                  ),
            label: Text(
              added ? context.l10n.radioDirectoryAdded : context.l10n.radioAdd,
            ),
            style: TextButton.styleFrom(
              foregroundColor: added ? p.textTertiary : p.accent,
              minimumSize: const Size(64, AppSpacing.minTouchTarget),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mq = MediaQuery.of(context);
    final isCompactLandscape =
        mq.size.width > mq.size.height && mq.size.height < 520;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Material(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: isCompactLandscape ? AppSpacing.xs : AppSpacing.sm,
              ),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.hairline,
                  borderRadius: AppRadii.r2All,
                ),
              ),
              if (isCompactLandscape)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          context.l10n.radioDirectoryBrowse,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.body,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 3,
                        child: PulsrSearchField(
                          controller: _controller,
                          hintText: context.l10n.radioDirectoryHint,
                          debounceDuration: const Duration(milliseconds: 350),
                          onChanged: _search,
                          onClear: () => _search(''),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        tooltip: context.l10n.cancel,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close_rounded, color: p.textSecondary),
                      ),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.s20,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.radioDirectoryBrowse,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        tooltip: context.l10n.cancel,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close_rounded, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                  child: PulsrSearchField(
                    controller: _controller,
                    hintText: context.l10n.radioDirectoryHint,
                    debounceDuration: const Duration(milliseconds: 350),
                    onChanged: _search,
                    onClear: () => _search(''),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: _buildBody(
                  context,
                  isCompactLandscape: isCompactLandscape,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isCompactLandscape,
  }) {
    final p = context.palette;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: p.accent),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_failed) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: PulsrEmptyState(
                  icon: Icons.cloud_off_rounded,
                  iconColor: p.error,
                  title: context.l10n.radioDirectoryError,
                  subtitle: context.l10n.downloadErrorNetwork,
                  primaryActionLabel: context.l10n.retry,
                  primaryActionIcon: Icons.refresh_rounded,
                  onPrimaryAction: () => _search(_controller.text),
                ),
              ),
            ),
          );
        }

        if (_results.isEmpty) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: PulsrEmptyState(
                  icon: Icons.radio_rounded,
                  title: context.l10n.radioDirectoryEmpty,
                  subtitle: context.l10n.radioDirectoryHint,
                ),
              ),
            ),
          );
        }

        final useGrid = constraints.maxWidth >= 560;

        if (!useGrid) {
          return ListView.separated(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s20,
              0,
              AppSpacing.s20,
              AppSpacing.lg,
            ),
            itemCount: _results.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) => _buildStationResultTile(
              context,
              _results[index],
              isCompact: isCompactLandscape,
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s20,
            AppSpacing.xxs,
            AppSpacing.s20,
            AppSpacing.lg,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: isCompactLandscape ? 64 : 72,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemCount: _results.length,
          itemBuilder: (context, index) => _buildStationResultTile(
            context,
            _results[index],
            isCompact: isCompactLandscape,
          ),
        );
      },
    );
  }
}
