// lib/features/smart_playlist_builder/smart_playlist_builder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/di/injection.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/cached_artwork.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/smart_playlist_criteria.dart';
import 'smart_playlist_builder_cubit.dart';
import 'smart_playlist_builder_state.dart';

class SmartPlaylistBuilderScreen extends StatelessWidget {
  final PlaylistsTableData? initialPlaylist;

  const SmartPlaylistBuilderScreen({super.key, this.initialPlaylist});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SmartPlaylistBuilderCubit>(
      create: (_) {
        final cubit = getIt<SmartPlaylistBuilderCubit>();
        if (initialPlaylist != null) {
          cubit.initWithPlaylist(initialPlaylist!);
        }
        return cubit;
      },
      child: const _SmartPlaylistBuilderView(),
    );
  }
}

class _SmartPlaylistBuilderView extends StatefulWidget {
  const _SmartPlaylistBuilderView();

  @override
  State<_SmartPlaylistBuilderView> createState() => _SmartPlaylistBuilderViewState();
}

class _SmartPlaylistBuilderViewState extends State<_SmartPlaylistBuilderView> {
  late final TextEditingController _nameController;
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    final state = context.read<SmartPlaylistBuilderCubit>().state;
    _nameController = TextEditingController(text: state.name);
    _limitController = TextEditingController(text: state.criteria.limit?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BlocConsumer<SmartPlaylistBuilderCubit, SmartPlaylistBuilderState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: p.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<SmartPlaylistBuilderCubit>();

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: p.accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  state.isEditing ? context.l10n.editPlaylist : context.l10n.createSmartPlaylist,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: state.isSubmitting
                    ? null
                    : () async {
                        final success = await cubit.savePlaylist();
                        if (success && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                icon: state.isSubmitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
                      )
                    : Icon(Icons.check_rounded, color: p.accent),
                label: Text(
                  context.l10n.save,
                  style: TextStyle(color: p.accent, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(context.pagePadding, 12, context.pagePadding, 160),
                children: [
              // Playlist Name Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PLAYLIST NAME', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      onChanged: cubit.updateName,
                      decoration: InputDecoration(
                        hintText: 'e.g. 80s Rock Hits, Heavy Rotation...',
                        filled: true,
                        fillColor: p.surfaceContainerHigh,
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Match Logic Toggle
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MATCH LOGIC', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Match ALL Rules (AND)')),
                            selected: state.criteria.matchAll,
                            selectedColor: p.accent.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: state.criteria.matchAll ? p.accent : p.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) => cubit.toggleMatchAll(true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Match ANY Rule (OR)')),
                            selected: !state.criteria.matchAll,
                            selectedColor: p.accent.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: !state.criteria.matchAll ? p.accent : p.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) => cubit.toggleMatchAll(false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Rules Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('RULES', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  TextButton.icon(
                    onPressed: () {
                      cubit.addRule(const SmartRule(
                        field: SmartRuleField.genre,
                        operator: SmartOperator.contains,
                        value: '',
                      ));
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Rule'),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              ...List.generate(state.criteria.rules.length, (index) {
                final rule = state.criteria.rules[index];
                return _RuleCard(
                  rule: rule,
                  onChanged: (updated) => cubit.updateRule(index, updated),
                  onDelete: () => cubit.removeRule(index),
                );
              }),

              const SizedBox(height: 16),

              // Options Card (Limit & Sorting)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.surfaceContainer,
                  borderRadius: AppRadii.cardRadius,
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SORTING & LIMIT', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Sort Field', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: state.criteria.sortBy ?? 'title',
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: p.surface,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'title', child: Text('Title')),
                                  DropdownMenuItem(value: 'dateAdded', child: Text('Date Added')),
                                  DropdownMenuItem(value: 'playCount', child: Text('Play Count')),
                                  DropdownMenuItem(value: 'lastPlayed', child: Text('Last Played')),
                                  DropdownMenuItem(value: 'durationMs', child: Text('Duration')),
                                  DropdownMenuItem(value: 'year', child: Text('Year')),
                                ],
                                onChanged: (val) => cubit.setSortBy(val),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Track Limit', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _limitController,
                                keyboardType: TextInputType.number,
                                onChanged: (val) {
                                  final num = int.tryParse(val.trim());
                                  cubit.setLimit(num);
                                },
                                decoration: InputDecoration(
                                  hintText: 'Unlimited',
                                  filled: true,
                                  fillColor: p.surface,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Live Match Preview Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MATCHING TRACKS PREVIEW', style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${state.previewSongs.length} tracks',
                      style: TextStyle(color: p.accent, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (state.previewSongs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer.withValues(alpha: 0.5),
                    borderRadius: AppRadii.cardRadius,
                    border: Border.all(color: p.hairline.withValues(alpha: 0.5)),
                  ),
                  child: Center(
                    child: Text(
                      'No tracks match the selected rules.',
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                Material(
                  color: p.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.cardRadius,
                    side: BorderSide(color: p.hairline),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: state.previewSongs.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: p.hairline),
                      itemBuilder: (context, index) {
                        final song = state.previewSongs[index];
                        return ListTile(
                          dense: true,
                          leading: CachedArtwork(
                            id: song.id,
                            remoteUrl: song.remoteArtworkUrl,
                            type: ArtworkType.AUDIO,
                            size: 36,
                            borderRadius: 8,
                          ),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: p.textPrimary)),
                          subtitle: Text(
                            '${song.artist} • ${Formatters.formatDuration(Duration(milliseconds: song.durationMs))}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.textSecondary, fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  },
);
  }
}

class _RuleCard extends StatefulWidget {
  final SmartRule rule;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.rule,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends State<_RuleCard> {
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.rule.value);
  }

  @override
  void didUpdateWidget(covariant _RuleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule.value != widget.rule.value && _valueController.text != widget.rule.value) {
      _valueController.text = widget.rule.value;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.cardRadius,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Field Dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<SmartRuleField>(
                  initialValue: widget.rule.field,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: p.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                  ),
                  items: SmartRuleField.values.where((f) => f != SmartRuleField.bpm).map((f) {
                    return DropdownMenuItem(
                      value: f,
                      child: Text(f.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (f) {
                    if (f != null) {
                      widget.onChanged(widget.rule.copyWith(field: f));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Operator Dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<SmartOperator>(
                  initialValue: widget.rule.operator,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: p.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                  ),
                  items: SmartOperator.values.map((o) {
                    return DropdownMenuItem(
                      value: o,
                      child: Text(o.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (o) {
                    if (o != null) {
                      widget.onChanged(widget.rule.copyWith(operator: o));
                    }
                  },
                ),
              ),

              IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: p.error),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Value Input
          if (widget.rule.field == SmartRuleField.isFavorite || widget.rule.field == SmartRuleField.isLossless)
            DropdownButtonFormField<String>(
              initialValue: widget.rule.value.toLowerCase() == 'true' || widget.rule.value == '1' ? 'true' : 'false',
              decoration: InputDecoration(
                filled: true,
                fillColor: p.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
              ),
              items: const [
                DropdownMenuItem(value: 'true', child: Text('Yes (True)')),
                DropdownMenuItem(value: 'false', child: Text('No (False)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  widget.onChanged(widget.rule.copyWith(value: val));
                }
              },
            )
          else
            TextField(
              controller: _valueController,
              onChanged: (val) {
                widget.onChanged(widget.rule.copyWith(value: val));
              },
              keyboardType: (widget.rule.field == SmartRuleField.playCount ||
                      widget.rule.field == SmartRuleField.year ||
                      widget.rule.field == SmartRuleField.decade ||
                      widget.rule.field == SmartRuleField.durationMs ||
                      widget.rule.operator == SmartOperator.withinDays)
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                hintText: _getHintForField(widget.rule.field, widget.rule.operator),
                filled: true,
                fillColor: p.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
              ),
            ),
        ],
      ),
    );
  }

  String _getHintForField(SmartRuleField field, SmartOperator op) {
    if (op == SmartOperator.withinDays) return 'e.g. 30 (days)';
    if (op == SmartOperator.between) return 'e.g. 5, 20 or 5..20';
    switch (field) {
      case SmartRuleField.playCount:
        return 'e.g. 5';
      case SmartRuleField.artist:
        return 'e.g. Queen, Daft Punk...';
      case SmartRuleField.album:
        return 'e.g. Discovery, Rumours...';
      case SmartRuleField.title:
        return 'e.g. Bohemian, Love...';
      case SmartRuleField.genre:
        return 'e.g. Rock, Pop, Jazz...';
      case SmartRuleField.year:
        return 'e.g. 2024';
      case SmartRuleField.decade:
        return 'e.g. 1980, 1990, 2000, 2020...';
      case SmartRuleField.isLossless:
        return 'FLAC, WAV, ALAC';
      case SmartRuleField.dateAdded:
        return 'e.g. 30';
      case SmartRuleField.durationMs:
        return 'e.g. 300000 (ms = 5 mins)';
      case SmartRuleField.lastPlayed:
        return 'e.g. 7';
      default:
        return 'Value...';
    }
  }
}
