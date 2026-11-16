part of 'radio_screen.dart';

class _StationArtwork extends StatelessWidget {
  const _StationArtwork({required this.station, required this.isPlaying});

  final RadioStation station;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final artworkUrl =
        (station.artworkUrl != null && station.artworkUrl!.isNotEmpty)
            ? station.artworkUrl
            : RadioStationStore.resolveArtworkForStation(
                id: station.id,
                name: station.name,
                url: station.url,
              );
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isPlaying
              ? p.accent.withValues(alpha: 0.2)
              : p.accentContainer.withValues(alpha: 0.35),
          borderRadius: AppRadii.r12All,
          border: isPlaying ? Border.all(color: p.accent, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          isPlaying ? Icons.graphic_eq_rounded : Icons.radio_rounded,
          color: p.accent,
          size: 22,
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CachedArtwork(
          id: 0,
          remoteUrl: artworkUrl,
          size: 44,
          borderRadius: AppRadii.r12,
          fallbackIcon: Icons.radio_rounded,
        ),
        if (isPlaying)
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
                border: Border.all(color: p.bg, width: 1.5),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                color: p.onAccent,
                size: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class _AddStationDialog extends StatefulWidget {
  const _AddStationDialog({this.initial});

  /// When non-null the dialog edits an existing station instead of adding one.
  final RadioStation? initial;

  @override
  State<_AddStationDialog> createState() => _AddStationDialogState();
}

class _AddStationDialogState extends State<_AddStationDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _genreController;
  String? _urlError;
  String? _artworkUrl;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _urlController = TextEditingController(text: widget.initial?.url ?? '');
    _genreController = TextEditingController(text: widget.initial?.genre ?? '');
    _artworkUrl = widget.initial?.artworkUrl ??
        RadioStationStore.resolveArtworkForStation(
          id: widget.initial?.id,
          name: widget.initial?.name,
          url: widget.initial?.url,
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _artworkUrl = picked.path);
      }
    } catch (_) {}
  }

  String? _validateUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return context.l10n.radioErrorEnterUrl;
    final scheme = url.toLowerCase();
    if (!scheme.startsWith('http://') && !scheme.startsWith('https://')) {
      return context.l10n.radioErrorUrlScheme;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return context.l10n.radioErrorInvalidUrl;
    }
    if (!RadioStation.isHttpUrl(url)) {
      return context.l10n.radioErrorInvalidUrl;
    }
    return null;
  }

  void _submit() {
    final url = _urlController.text.trim();
    final error = _validateUrl(url);
    if (error != null) {
      setState(() => _urlError = error);
      return;
    }
    final name = _nameController.text.trim();
    final genre = _genreController.text.trim();
    final effectiveArt = _artworkUrl ??
        RadioStationStore.resolveArtworkForStation(
          name: name,
          url: url,
        );
    Navigator.of(context, rootNavigator: true).pop(
      RadioStation.create(
        name: name,
        url: url,
        genre: genre.isNotEmpty ? genre : null,
        artworkUrl: effectiveArt,
        lastPlayed: widget.initial?.lastPlayed,
      ),
    );
  }

  Widget _buildPresetChip(String label, String assetPath) {
    final isSelected = _artworkUrl == assetPath;
    final p = context.palette;
    return ChoiceChip(
      avatar: ClipOval(
        child: Image.asset(
          assetPath,
          width: 18,
          height: 18,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 14),
        ),
      ),
      label: Text(label, style: const TextStyle(fontSize: AppFontSize.caption)),
      selected: isSelected,
      onSelected: (val) {
        setState(() => _artworkUrl = val ? assetPath : null);
      },
      selectedColor: p.accent.withValues(alpha: 0.25),
    );
  }

  Widget _buildArtworkAndPresets(PulsrPalette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.r16All,
                    color: p.surfaceContainerHigh,
                    border: Border.all(color: p.hairline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _artworkUrl != null && _artworkUrl!.isNotEmpty
                      ? CachedArtwork(
                          id: 0,
                          remoteUrl: _artworkUrl,
                          size: 68,
                          borderRadius: 16,
                          fallbackIcon: Icons.radio_rounded,
                        )
                      : Icon(Icons.radio_rounded, color: p.accent, size: 36),
                ),
              ),
              PositionedDirectional(
                end: -4,
                bottom: -4,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: p.onAccent,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          alignment: WrapAlignment.center,
          children: [
            _buildPresetChip(
                'القرآن - القاهرة', RadioStationStore.quranCairoArtwork),
            _buildPresetChip('الحصري', RadioStationStore.hussaryArtwork),
            _buildPresetChip('المنشاوي', RadioStationStore.minshawiArtwork),
            _buildPresetChip('عبد الباسط', RadioStationStore.abdulBasitArtwork),
            _buildPresetChip(
                'مصطفى إسماعيل', RadioStationStore.mustafaIsmailArtwork),
            _buildPresetChip('تراتيل', RadioStationStore.tarteelArtwork),
            if (_artworkUrl != null)
              ActionChip(
                avatar: const Icon(Icons.clear_rounded, size: 14),
                label: Text(context.l10n.radioCancelImageAction,
                    style: const TextStyle(fontSize: AppFontSize.caption)),
                onPressed: () => setState(() => _artworkUrl = null),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNameField(PulsrPalette p) {
    return TextField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      onChanged: (text) {
        if (_artworkUrl == null ||
            _artworkUrl!.startsWith('assets/Pictures/')) {
          final detected = RadioStationStore.resolveArtworkForStation(
            name: text,
            url: _urlController.text,
          );
          if (detected != _artworkUrl) {
            setState(() => _artworkUrl = detected);
          }
        }
      },
      style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
      decoration: InputDecoration(
        labelText: context.l10n.radioStationName,
        labelStyle: TextStyle(color: p.textSecondary),
        hintText: context.l10n.browseRadioNameHint,
        hintStyle: TextStyle(color: p.textTertiary),
        filled: true,
        fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildGenreField(PulsrPalette p) {
    return TextField(
      controller: _genreController,
      textInputAction: TextInputAction.next,
      style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
      decoration: InputDecoration(
        labelText: context.l10n.radioGenreLabel,
        labelStyle: TextStyle(color: p.textSecondary),
        hintText: context.l10n.radioGenreHint,
        hintStyle: TextStyle(color: p.textTertiary),
        filled: true,
        fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildUrlField(PulsrPalette p) {
    return TextField(
      controller: _urlController,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style: TextStyle(color: p.textPrimary, fontSize: AppFontSize.body),
      decoration: InputDecoration(
        labelText: context.l10n.radioStationUrl,
        labelStyle: TextStyle(color: p.textSecondary),
        hintText: 'https://...',
        hintStyle: TextStyle(color: p.textTertiary),
        errorText: _urlError,
        filled: true,
        fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.r12All,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      onChanged: (_) {
        if (_urlError != null) {
          setState(() => _urlError = null);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    final useTwoColumnLayout =
        (size.width >= 580 && size.height < 640) || size.width >= 700;

    return PulsrDialog(
      icon: Icon(Icons.radio_rounded, color: p.accent, size: 28),
      title: Text(
        _isEditing
            ? context.l10n.radioEditStation
            : context.l10n.radioAddStation,
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: useTwoColumnLayout ? 620 : 420,
        ),
        child: SingleChildScrollView(
          child: useTwoColumnLayout
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 210,
                      child: _buildArtworkAndPresets(p),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(flex: 3, child: _buildNameField(p)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(flex: 2, child: _buildGenreField(p)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s14),
                          _buildUrlField(p),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildArtworkAndPresets(p),
                    const SizedBox(height: AppSpacing.s14),
                    _buildNameField(p),
                    const SizedBox(height: AppSpacing.s14),
                    _buildGenreField(p),
                    const SizedBox(height: AppSpacing.s14),
                    _buildUrlField(p),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(context.l10n.radioCancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            _isEditing ? context.l10n.radioSave : context.l10n.radioAdd,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ImportStationsDialog extends StatefulWidget {
  const _ImportStationsDialog();

  @override
  State<_ImportStationsDialog> createState() => _ImportStationsDialogState();
}

class _ImportStationsDialogState extends State<_ImportStationsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    final isCompactLandscape = size.width > size.height && size.height < 520;

    return PulsrDialog(
      icon: Icon(Icons.download_rounded, color: p.accent, size: 28),
      title: Text(context.l10n.radioImportTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: TextField(
            controller: _controller,
            maxLines: isCompactLandscape ? 3 : 6,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: AppFontSize.bodySmall,
            ),
            decoration: InputDecoration(
              hintText: context.l10n.radioImportHint,
              hintStyle: TextStyle(
                color: p.textTertiary,
                fontSize: AppFontSize.bodySmall,
              ),
              filled: true,
              fillColor: p.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: AppRadii.r12All,
                borderSide: BorderSide(color: p.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.r12All,
                borderSide: BorderSide(color: p.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.r12All,
                borderSide: BorderSide(color: p.accent, width: 1.5),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: p.textSecondary,
          ),
          child: Text(context.l10n.radioCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20,
              vertical: AppSpacing.sm,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
            ),
          ),
          child: Text(
            context.l10n.radioImport,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
