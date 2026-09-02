// lib/features/player/presentation/widgets/autoeq_search_sheet.dart
import 'package:flutter/material.dart';
import '../../../../domain/services/autoeq_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../data/audio/equalizer_manager.dart';

class AutoEqSearchSheet extends StatefulWidget {
  final EqualizerManager equalizerManager;

  const AutoEqSearchSheet({super.key, required this.equalizerManager});

  @override
  State<AutoEqSearchSheet> createState() => _AutoEqSearchSheetState();
}

class _AutoEqSearchSheetState extends State<AutoEqSearchSheet> {
  final AutoEqService _autoEqService = AutoEqService();
  final TextEditingController _searchController = TextEditingController();
  List<AutoEqResult> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _performSearch('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    final results = await _autoEqService.search(query);
    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AutoEQ 2.0 Database',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: p.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _performSearch,
            style: TextStyle(color: p.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search headphones (Sony, Sennheiser, Apple...)',
              hintStyle:
                  TextStyle(color: p.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.search, color: p.primary),
              filled: true,
              fillColor: p.surfaceCard,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: p.primary))
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No matching headphone profiles found',
                          style: TextStyle(color: p.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final isSelected = widget.equalizerManager
                                  .selectedHeadphoneProfile?.name ==
                              item.name;

                          return InkWell(
                            onTap: () async {
                              final profile = item.toHeadphoneProfile();
                              await widget.equalizerManager
                                  .setHeadphoneProfile(profile);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Applied ${item.name} profile'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? p.primary.withValues(alpha: 0.15)
                                    : p.surfaceCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? p.primary : p.surfaceCard,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: p.primary.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.headphones_rounded,
                                        color: p.primary, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: TextStyle(
                                            color: p.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Target: ${item.target} • AutoEQ Verified',
                                          style: TextStyle(
                                            color: p.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded,
                                        color: p.primary, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
