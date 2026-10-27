import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_switch.dart';
import '../../../../services/discord/discord_rpc_service.dart';

/// Bottom sheet for managing Discord Rich Presence settings and user token.
class DiscordRpcSheet extends StatefulWidget {
  const DiscordRpcSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (_) => const DiscordRpcSheet(),
    );
  }

  @override
  State<DiscordRpcSheet> createState() => _DiscordRpcSheetState();
}

class _DiscordRpcSheetState extends State<DiscordRpcSheet> {
  final DiscordRpcService _rpcService = DiscordRpcService.instance;
  late final TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _isSaving = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: _rpcService.token);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _statusError = 'Token cannot be empty');
      return;
    }

    setState(() {
      _isSaving = true;
      _statusError = null;
    });

    await _rpcService.setToken(token);
    final user = await _rpcService.fetchUserInfo();

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (user == null) {
          _statusError = 'Could not verify token. Please check and try again.';
        }
      });
      if (user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Connected as ${user.globalName} (@${user.username})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    await _rpcService.clearAccount();
    if (mounted) {
      setState(() {
        _tokenController.clear();
        _statusError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.discordAccountDisconnected),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final user = _rpcService.currentUser;
    final hasToken = _rpcService.token.isNotEmpty;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s20,
              AppSpacing.s14,
              AppSpacing.s20,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textSecondary.withValues(alpha: 0.3),
                      borderRadius: AppRadii.r12All,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.discordBlurple.withValues(alpha: 0.15),
                        borderRadius: AppRadii.r12All,
                      ),
                      child: const Icon(
                        Icons.discord_rounded,
                        color: AppColors.discordBlurple,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discord Rich Presence',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.title,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Display currently playing song on your profile',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Enable/Disable Switch Card
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.r16All,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rich Presence Status',
                              style: TextStyle(
                                color: p.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: AppFontSize.body,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              _rpcService.isEnabled
                                  ? 'Active (streaming to Discord)'
                                  : 'Disabled',
                              style: TextStyle(
                                color: _rpcService.isEnabled
                                    ? p.success
                                    : p.textSecondary,
                                fontSize: AppFontSize.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PulsrSwitch(
                        value: _rpcService.isEnabled,
                        onChanged: (val) async {
                          if (val && _rpcService.token.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter your Discord User Token first',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          await _rpcService.setEnabled(val);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // User Profile Card if logged in
                if (hasToken && user != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: p.surfaceContainer,
                      borderRadius: AppRadii.r16All,
                      border: Border.all(
                        color: AppColors.discordBlurple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.discordBlurple,
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  user.username.isNotEmpty
                                      ? user.username[0].toUpperCase()
                                      : 'D',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.globalName,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.body,
                                ),
                              ),
                              Text(
                                '@${user.username}',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontSize: AppFontSize.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.logout_rounded, color: p.error),
                          tooltip: 'Disconnect',
                          onPressed: _disconnect,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Token input field
                Text(
                  hasToken ? 'Discord User Token' : 'Enter Discord Token',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.body,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Your Discord account user token (Authorization header). Stored locally in your app preferences.',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.bodySmall,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    hintText: 'Paste token here...',
                    hintStyle: TextStyle(color: p.textTertiary),
                    filled: true,
                    fillColor: p.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r12All,
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: p.textSecondary,
                          ),
                          tooltip: _obscureToken
                              ? context.l10n.showPassword
                              : context.l10n.hidePassword,
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_statusError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _statusError!,
                    style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.md),

                Row(
                  children: [
                    if (hasToken) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _disconnect,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.error,
                            side: BorderSide(
                                color: p.error.withValues(alpha: 0.5)),
                          ),
                          child: Text(context.l10n.disconnect),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.discordBlurple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isSaving ? null : _saveToken,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                hasToken ? 'Update Token' : 'Connect Account'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
