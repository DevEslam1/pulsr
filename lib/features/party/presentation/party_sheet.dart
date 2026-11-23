import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../../core/widgets/pulsr_adaptive_sheet.dart';
import '../../../core/widgets/pulsr_badge.dart';
import '../../../core/widgets/pulsr_button.dart';
import '../../../core/widgets/pulsr_toast.dart';
import '../../../data/party/listen_together_service.dart';
import '../../../data/party/party_models.dart';

import '../../../core/utils/pulsr_haptics.dart';
class PartySheet extends StatefulWidget {
  final String? initialCode;
  final String? initialServerUrl;

  const PartySheet({
    super.key,
    this.initialCode,
    this.initialServerUrl,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialCode,
    String? initialServerUrl,
  }) {
    return PulsrAdaptiveSheet.show<void>(
      context: context,
      builder: (_) => PartySheet(
        initialCode: initialCode,
        initialServerUrl: initialServerUrl,
      ),
    );
  }

  @override
  State<PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends State<PartySheet> {
  final ListenTogetherService _partyService = getIt<ListenTogetherService>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();

  bool _isCreating = false;
  bool _isJoining = false;
  bool _showSettings = false;
  String? _errorMessage;
  String? _serverUrlError;

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialCode?.trim();
    if (initialCode != null && initialCode.isNotEmpty) {
      final cleaned =
          initialCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      _codeController.text =
          cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
    }
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final initialServer = widget.initialServerUrl?.trim();
    if (initialServer != null && initialServer.isNotEmpty) {
      try {
        await _partyService.setCustomServerUrl(initialServer);
      } on ArgumentError {
        // Ignore disallowed deep-link server override and fall back to saved/default.
      }
    }
    final server = await _partyService.getServerUrl();
    if (mounted) {
      _serverController.text = server;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nicknameController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final nick = _nicknameController.text.trim();
      await _partyService.createParty(
        nickname: nick.isNotEmpty ? nick : null,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = resolveUiErrorMessage(
              context, e.toString().replaceAll('Exception: ', ''));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });

    try {
      final nick = _nicknameController.text.trim();
      await _partyService.joinParty(
        code,
        nickname: nick.isNotEmpty ? nick : null,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = resolveUiErrorMessage(
              context, e.toString().replaceAll('Exception: ', ''));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _handleLeave() async {
    await _partyService.leaveParty();
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/');
      }
    }
  }

  Future<void> _copyInvite(String code) async {
    PulsrHaptics.lightImpact();
    final base = await _partyService.getServerUrl();
    final link = '$base/invite/$code';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    PulsrToast.show(context, message: link, isSuccess: true);
  }

  Future<void> _shareInvite(String code) async {
    PulsrHaptics.lightImpact();
    final loc = context.l10n;
    final base = await _partyService.getServerUrl();
    final link = '$base/invite/$code';
    await SharePlus.instance.share(ShareParams(
      text: loc.partyShareText(link),
      subject: loc.partyShareSubject(code),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _partyService.connectionState,
        _partyService.partySnapshot,
        _partyService.currentMember,
        _partyService.lastError,
        _partyService.clockSynced,
        _partyService.roundTripMs,
      ]),
      builder: (context, _) {
        final snap = _partyService.partySnapshot.value;
        final inParty = _partyService.inParty && snap != null;

        return SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.group_rounded,
                      color: inParty ? p.accent : p.textPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        context.l10n.partyListenTogether,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.title,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  MergeSemantics(
                    child: Semantics(
                      toggled: _showSettings,
                      child: IconButton(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        icon: Icon(
                          _showSettings
                              ? Icons.close_rounded
                              : Icons.settings_rounded,
                          color: p.textSecondary,
                          size: 20,
                        ),
                        tooltip: context.l10n.partyServerSettings,
                        onPressed: () {
                          setState(() => _showSettings = !_showSettings);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_partyService.connectionState.value ==
                  PartyConnectionState.connecting)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Semantics(
                    liveRegion: true,
                    label: context.l10n.partySynchronizingClock,
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              if (_partyService.connectionState.value ==
                      PartyConnectionState.offline &&
                  _partyService.lastError.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      resolveUiErrorMessage(
                          context, _partyService.lastError.value!),
                      style: TextStyle(
                        color: p.error,
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),

              if (_showSettings) ...[
                _buildSettingsView(p),
              ] else if (inParty) ...[
                _buildInPartyView(p, snap),
              ] else ...[
                _buildLobbyView(p),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _validateServerUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _serverUrlError = context.l10n.partyServerUrlEmpty);
      return false;
    }
    if (!ListenTogetherService.isValidServerUrl(text)) {
      setState(() => _serverUrlError = context.l10n.partyServerUrlInvalid);
      return false;
    }
    setState(() => _serverUrlError = null);
    return true;
  }

  Widget _buildSettingsView(PulsrPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            context.l10n.partyServerConfiguration,
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _serverController,
          onChanged: (_) {
            if (_serverUrlError != null) {
              setState(() => _serverUrlError = null);
            }
          },
          decoration: InputDecoration(
            hintText: 'https://party.pulsr.app',
            labelText: context.l10n.partyServerUrl,
            errorText: _serverUrlError,
            border: OutlineInputBorder(borderRadius: AppRadii.r12All),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () async {
                await _partyService.setCustomServerUrl(null);
                if (!mounted) return;
                _serverController.text = ListenTogetherService.defaultServerUrl;
                setState(() {
                  _showSettings = false;
                  _serverUrlError = null;
                });
              },
              child: Text(context.l10n.partyResetDefault),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: () async {
                final trimmed = _serverController.text.trim();
                if (!_validateServerUrl(trimmed)) return;
                try {
                  await _partyService.setCustomServerUrl(trimmed);
                  final saved = await _partyService.getServerUrl();
                  if (mounted) {
                    _serverController.text = saved;
                    setState(() {
                      _showSettings = false;
                      _serverUrlError = null;
                    });
                  }
                } on ArgumentError {
                  if (mounted) {
                    setState(() {
                      _serverUrlError = context.l10n.partyServerUrlInvalid;
                    });
                  }
                }
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLobbyView(PulsrPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.partySyncDescription,
          style: TextStyle(
            fontSize: AppFontSize.bodySmall,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Optional Nickname
        TextField(
          controller: _nicknameController,
          decoration: InputDecoration(
            hintText: context.l10n.partyDisplayNameHint,
            prefixIcon: const Icon(Icons.person_outline_rounded),
            border: OutlineInputBorder(borderRadius: AppRadii.r12All),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Create Room Button
        FilledButton.icon(
          icon: _isCreating
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: p.onAccent),
                )
              : const Icon(Icons.add_rounded),
          label: Text(context.l10n.partyCreateNew),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            minimumSize: const Size(
              AppSpacing.minTouchTarget,
              AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.r14All),
          ),
          onPressed: _isCreating || _isJoining ? null : _handleCreate,
        ),
        const SizedBox(height: AppSpacing.md),

        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: p.hairline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                context.l10n.partyOrJoinByCode,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            Expanded(child: Divider(color: p.hairline)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Enter 6-digit code
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: const <TextInputFormatter>[
                  _PartyCodeInputFormatter(),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: context.l10n.partyCodeHint,
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                  border: OutlineInputBorder(borderRadius: AppRadii.r12All),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PulsrButton(
              label: context.l10n.partyJoin,
              size: PulsrButtonSize.md,
              variant: PulsrButtonVariant.primary,
              loading: _isJoining,
              onPressed: _isCreating || _isJoining ? null : _handleJoin,
            ),
          ],
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              _errorMessage!,
              style: TextStyle(
                  color: p.error, fontSize: AppFontSize.bodySmall),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInPartyView(PulsrPalette p, PartySnapshot snap) {
    final isHost = _partyService.isHost;
    final rtt = _partyService.roundTripMs.value;
    final isSynced = _partyService.clockSynced.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Room Code Banner
        Semantics(
          container: true,
          customSemanticsActions: {
            CustomSemanticsAction(label: context.l10n.partyCopyInvite): () =>
                _copyInvite(snap.code),
            CustomSemanticsAction(label: context.l10n.partyShareInvite): () =>
                _shareInvite(snap.code),
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: AppRadii.r16All,
              border: Border.all(color: p.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Semantics(
                        label:
                            '${context.l10n.partyRoomCode}: ${snap.code.split('').join(' ')}',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.partyRoomCode,
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                color: p.textSecondary,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                snap.code,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: AppFontSize.display,
                                  fontWeight: FontWeight.w900,
                                  color: p.accent,
                                  letterSpacing: 4.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget,
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          tooltip: context.l10n.partyCopyInvite,
                          onPressed: () => _copyInvite(snap.code),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        IconButton.filledTonal(
                          constraints: const BoxConstraints(
                            minWidth: AppSpacing.minTouchTarget,
                            minHeight: AppSpacing.minTouchTarget,
                          ),
                          icon: const Icon(Icons.share_rounded, size: 20),
                          tooltip: context.l10n.partyShareInvite,
                          onPressed: () => _shareInvite(snap.code),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: PulsrBadge(
                          dot: true,
                          color: isSynced
                              ? PulsrBadgeColor.success
                              : PulsrBadgeColor.warning,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isSynced
                              ? context.l10n.partySyncedRtt(rtt)
                              : context.l10n.partySynchronizingClock,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                      if (isHost)
                        PulsrBadge(
                          label: context.l10n.partyHost,
                          color: PulsrBadgeColor.accent,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Member list header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              header: true,
              child: Text(
                context.l10n.partyMembers(snap.members.length, snap.maxMembers),
                style: TextStyle(
                  fontSize: AppFontSize.body,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        // Member list
        ...snap.members.map((member) {
          final isMe =
              member.memberId == _partyService.currentMember.value?.memberId;
          return MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: p.surfaceContainerHigh,
                      backgroundImage: member.avatarUrl != null
                          ? NetworkImage(member.avatarUrl!)
                          : null,
                      child: member.avatarUrl == null
                          ? Text(
                              member.displayName.isNotEmpty
                                  ? member.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                member.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.body,
                                  fontWeight:
                                      isMe ? FontWeight.w800 : FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Text(
                                context.l10n.partyYouLabel,
                                style: TextStyle(
                                    fontSize: AppFontSize.caption,
                                    color: p.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (member.isHost)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.2),
                        borderRadius: AppRadii.r6All,
                      ),
                      child: Text(
                        context.l10n.partyHostMember,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                          color: p.accent,
                        ),
                      ),
                    )
                  else if (isHost && !isMe)
                    IconButton(
                      key: ValueKey<String>('party_kick_${member.memberId}'),
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      icon: Icon(
                        Icons.person_remove_rounded,
                        size: 18,
                        color: p.error,
                      ),
                      tooltip: context.l10n.remove,
                      onPressed: () {
                        PulsrHaptics.lightImpact();
                        _partyService.sendKick(member.memberId);
                      },
                    ),
                ],
              ),
            ),
          );
        }),

        // Host-only control lock toggle (host) or lock indicator (guest)
        if (isHost) ...[
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: p.surfaceContainer.withValues(alpha: 0.65),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.r12All,
              side: BorderSide(color: p.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              key: const ValueKey<String>('party_host_only_switch'),
              contentPadding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.sm,
              ),
              secondary: Icon(
                snap.hostOnlyControl
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                size: 20,
                color: snap.hostOnlyControl ? p.accent : p.textSecondary,
              ),
              title: Text(
                '${context.l10n.partyHostMember} • ${context.l10n.playback} / ${context.l10n.queue}',
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              value: snap.hostOnlyControl,
              onChanged: (enabled) {
                PulsrHaptics.selectionClick();
                _partyService.sendSetHostOnlyControl(enabled);
              },
            ),
          ),
        ] else if (snap.hostOnlyControl) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 16, color: p.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${context.l10n.partyHostMember} • ${context.l10n.playback} / ${context.l10n.queue}',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        ],

        // Shared Queue (Up Next)
        const SizedBox(height: AppSpacing.md),
        _buildSharedQueueSection(p, snap, isHost: isHost),

        const SizedBox(height: AppSpacing.lg),

        // Leave Party Button
        OutlinedButton.icon(
          icon: Icon(Icons.exit_to_app_rounded, color: p.error),
          label: Text(context.l10n.partyLeave,
              style: TextStyle(color: p.error)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: p.error),
            minimumSize: const Size(
              AppSpacing.minTouchTarget,
              AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: AppRadii.r14All),
          ),
          onPressed: _handleLeave,
        ),
      ],
    );
  }

  Widget _buildSharedQueueSection(
    PulsrPalette p,
    PartySnapshot snap, {
    required bool isHost,
  }) {
    final startIdx = snap.queue.index >= 0 ? snap.queue.index + 1 : 0;
    final upcoming = startIdx < snap.queue.items.length
        ? snap.queue.items.sublist(startIdx)
        : const <PartyTrack>[];
    final canControlQueue = isHost || !snap.hostOnlyControl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            context.l10n.queue,
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (upcoming.isEmpty)
          Text(
            context.l10n.queueEmpty,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: p.textSecondary,
            ),
          )
        else
          ...upcoming.map((track) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppFontSize.bodySmall,
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        if (track.artist.isNotEmpty)
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: p.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (canControlQueue)
                    IconButton(
                      key: ValueKey<String>(
                        'party_queue_remove_${track.videoId}',
                      ),
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: p.textSecondary,
                      ),
                      tooltip: context.l10n.remove,
                      onPressed: () {
                        PulsrHaptics.lightImpact();
                        _partyService.sendQueueRemove(track.videoId);
                      },
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Strips hyphens, spaces, and non-alphanumeric characters before uppercasing
/// and capping room codes at 6 characters so pasted codes like `ABC-123` are
/// never truncated to 5 characters.
class _PartyCodeInputFormatter extends TextInputFormatter {
  const _PartyCodeInputFormatter();

  static final RegExp _nonAlphanumeric = RegExp(r'[^A-Z0-9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned =
        newValue.text.toUpperCase().replaceAll(_nonAlphanumeric, '');
    final capped = cleaned.length > 6 ? cleaned.substring(0, 6) : cleaned;
    return TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }
}
