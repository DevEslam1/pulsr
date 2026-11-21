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
  const PartySheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrAdaptiveSheet.show<void>(
      context: context,
      builder: (_) => const PartySheet(),
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
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
      setState(() => _serverUrlError = 'Server URL cannot be empty');
      return false;
    }
    final uri = Uri.tryParse(text);
    final scheme = uri?.scheme.toLowerCase();
    final validScheme = scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'ws' ||
        scheme == 'wss';
    if (uri == null || !validScheme || uri.host.isEmpty) {
      setState(() => _serverUrlError = 'Enter a valid URL (http, https, ws, or wss)');
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
              onPressed: () {
                _serverController.text = ListenTogetherService.defaultServerUrl;
                _partyService.setCustomServerUrl(null);
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
                await _partyService.setCustomServerUrl(trimmed);
                if (mounted) {
                  setState(() {
                    _showSettings = false;
                    _serverUrlError = null;
                  });
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
                maxLength: 6,
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
                    ),
                ],
              ),
            ),
          );
        }),

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
}
