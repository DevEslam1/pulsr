// lib/features/auth/presentation/auth_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/error_message_resolver.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/theme/aura_theme.dart';
import '../../../core/utils/adaptive.dart';
import '../../../core/utils/l10n_extensions.dart';
import '../../settings/presentation/widgets/ytm_account_disconnect_dialog.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';
import 'ytm_web_login_sheet.dart';
import 'ytm_oauth_login_sheet.dart';

import '../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});

  static Future<void> show(BuildContext context) {
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      wrapWithContainer: false,
      builder: (ctx) => const AuthSheet(),
    );
  }

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isSendingReset = false;

  Future<void> _handlePasswordReset(AuthCubit cubit) async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.enterEmailFirst)),
      );
      return;
    }
    if (_isSendingReset) return;
    setState(() => _isSendingReset = true);
    try {
      final ok = await cubit.sendPasswordReset(email);
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok
              ? '${context.l10n.browsePasswordResetSent} $email'
              : cubit.state.errorMessage ??
                  'Failed to send reset link. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.authenticated) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                      '${context.l10n.signedInAs} ${state.user?.email ?? state.user?.displayName ?? context.l10n.browseUser}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else if (state.status == AuthStatus.error &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                    resolveUiErrorMessage(context, state.errorMessage!)),
                backgroundColor: p.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
      },
      builder: (context, state) {
        final isLoading = state.status == AuthStatus.authenticating;

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Adaptive.sheetConstraints(context).maxWidth),
            child: Container(
              padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, bottomInset + 24),
              decoration: BoxDecoration(
                color: p.surfaceContainer,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
                border: Border.all(color: p.hairline),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: p.textTertiary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(AppRadii.r2),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s20),

                      // Header
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.cloud_sync_rounded,
                                color: p.accent, size: 24),
                          ),
                          const SizedBox(width: AppSpacing.s14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isSignUp
                                      ? context.l10n.browseCreateCloudAccount
                                      : context.l10n.browseSignInToCloud,
                                  style: TextStyle(
                                    color: p.textPrimary,
                                    fontSize: AppFontSize.title,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(context.l10n.syncAcrossDevices,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: AppFontSize.label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // 1-Tap Google Sign In Button
                      FilledButton(
                        onPressed: isLoading
                            ? null
                            : () =>
                                context.read<AuthCubit>().signInWithGoogle(),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.surface,
                          foregroundColor: p.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r14),
                            side: BorderSide(color: p.hairline),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Offline-safe "G" badge: no network asset, no
                            // webfont — renders identically offline.
                            Container(
                              height: 20,
                              width: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: p.surface,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                'G',
                                style: TextStyle(
                                  fontSize: AppFontSize.body,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF4285F4),
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(context.l10n.continueWithGoogle,
                              style: TextStyle(
                                fontSize: AppFontSize.callout,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.s20),

                      // Divider with "OR"
                      Row(
                        children: [
                          Expanded(child: Divider(color: p.hairline)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                            child: Text(context.l10n.orWithEmail,
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600,
                                letterSpacing: AppTracking.overline,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: p.hairline)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s18),

                      Builder(
                        builder: (context) {
                          final isLandscape =
                              MediaQuery.of(context).orientation == Orientation.landscape;

                          final emailField = TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: p.textPrimary),
                            decoration: InputDecoration(
                              hintText: context.l10n.browseEmailAddress,
                              hintStyle: TextStyle(color: p.textTertiary),
                              prefixIcon: Icon(Icons.email_outlined,
                                  color: p.textTertiary, size: 20),
                              filled: true,
                              fillColor: p.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r14),
                                borderSide: BorderSide(color: p.hairline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r14),
                                borderSide: BorderSide(color: p.hairline),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return context.l10n.browsePleaseEnterEmail;
                              }
                              if (!val.contains('@')) {
                                return context.l10n.browseInvalidEmail;
                              }
                              return null;
                            },
                          );

                          final passwordField = TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(color: p.textPrimary),
                            decoration: InputDecoration(
                              hintText: context.l10n.browsePassword,
                              hintStyle: TextStyle(color: p.textTertiary),
                              prefixIcon: Icon(Icons.lock_outline_rounded,
                                  color: p.textTertiary, size: 20),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? context.l10n.showPassword
                                    : context.l10n.hidePassword,
                                constraints: const BoxConstraints(
                                  minWidth: AppSpacing.minTouchTarget,
                                  minHeight: AppSpacing.minTouchTarget,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: p.textTertiary,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: p.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r14),
                                borderSide: BorderSide(color: p.hairline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadii.r14),
                                borderSide: BorderSide(color: p.hairline),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.length < 6) {
                                return context.l10n.browsePasswordMinChars;
                              }
                              return null;
                            },
                          );

                          if (isLandscape) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: emailField),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: passwordField),
                              ],
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              emailField,
                              const SizedBox(height: AppSpacing.sm),
                              passwordField,
                            ],
                          );
                        },
                      ),

                      if (!_isSignUp) ...[
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: (_isSendingReset || isLoading)
                                ? null
                                : () => _handlePasswordReset(
                                    context.read<AuthCubit>()),
                            child: _isSendingReset
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(context.l10n.forgotPassword,
                                    style: TextStyle(
                                        color: p.accent,
                                        fontSize: AppFontSize.label),
                                  ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // Email Submit Button
                      FilledButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                if (_formKey.currentState?.validate() == true) {
                                  final email = _emailController.text.trim();
                                  final password = _passwordController.text;
                                  if (_isSignUp) {
                                    context
                                        .read<AuthCubit>()
                                        .signUpWithEmail(email, password);
                                  } else {
                                    context
                                        .read<AuthCubit>()
                                        .signInWithEmail(email, password);
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r14),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(width: AppSpacing.s20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _isSignUp
                                    ? context.l10n.browseSignUp
                                    : context.l10n.signIn,
                                style: const TextStyle(
                                    fontSize: AppFontSize.callout, fontWeight: FontWeight.w600),
                              ),
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      // Toggle Sign Up / Sign In
                      TextButton(
                        onPressed: () {
                          _passwordController.clear();
                          setState(() => _isSignUp = !_isSignUp);
                        },
                        child: Text(
                          _isSignUp
                              ? context.l10n.browseAlreadyHaveAccount
                              : context.l10n.browseDontHaveAccount,
                          style:
                              TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                        ),
                      ),

                      if (AppConfig.ytmEnabled) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(child: Divider(color: p.hairline)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                              child: Text(
                                context.l10n.ytmHeader,
                                style: TextStyle(
                                  color: p.textTertiary,
                                  fontSize: AppFontSize.tiny,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: AppTracking.overline,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: p.hairline)),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ValueListenableBuilder<bool>(
                          valueListenable: getIt<YtmAccountService>().loginState,
                          builder: (context, isLoggedIn, _) {
                            final ytmAccount = getIt<YtmAccountService>();
                            return OutlinedButton.icon(
                              onPressed: () async {
                                if (isLoggedIn) {
                                  await showYtmAccountDisconnectDialog(context);
                                } else {
                                  final ok =
                                      await YtmWebLoginSheet.show(context);
                                  if (ok == true && context.mounted) {
                                    ScaffoldMessenger.of(context)
                                      ..clearSnackBars()
                                      ..showSnackBar(
                                        SnackBar(
                                          content:
                                              Text(context.l10n.ytmConnected),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: AppColors.ytRed,
                                size: 20,
                              ),
                              label: Text(
                                isLoggedIn
                                    ? '${context.l10n.browseYouTubeMusic}: ${ytmAccount.accountName ?? context.l10n.ytmConnected}'
                                    : context.l10n.connectYtm,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                side: BorderSide(color: p.hairline),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.r14),
                                ),
                              ),
                            );
                          },
                        ),
                        if (!getIt<YtmAccountService>().loginState.value) ...[
                          const SizedBox(height: AppSpacing.xs),
                          TextButton.icon(
                            onPressed: () async {
                              final ok =
                                  await YtmOAuthLoginSheet.show(context);
                              if (ok == true && context.mounted) {
                                ScaffoldMessenger.of(context)
                                  ..clearSnackBars()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(context.l10n.ytmConnected),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                              }
                            },
                            icon: Icon(Icons.phonelink_setup_rounded,
                                size: 18, color: p.textSecondary),
                            label: Text(
                              context.l10n.authUseCodeSignIn,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: AppFontSize.label,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
        );
      },
    );
  }
}
