// lib/features/settings/presentation/widgets/settings_picker_sheets.dart
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/ytm_locale.dart';
import '../../../auth/presentation/ytm_web_login_sheet.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

export 'settings_theme_pickers.dart';
export 'settings_playback_pickers.dart';



void showYtmWebOptionsSheet(BuildContext context) {
  final p = context.palette;
  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: p.accentContainer,
                            borderRadius: BorderRadius.circular(AppRadii.r10),
                          ),
                          child: Icon(Icons.language_rounded,
                              color: p.accent, size: 22),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ctx.l10n.youtubeMusicWeb,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppFontSize.bodyLarge,
                                ),
                              ),
                              Text(
                                ctx.l10n.selectPageToOpen,
                                style: TextStyle(
                                    color: p.textSecondary, fontSize: AppFontSize.label),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.home_rounded,
                      title: ctx.l10n.homePage,
                      subtitle: ctx.l10n.homePageSubtitle,
                      url: YtmLocale.homeUrl(),
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.video_library_rounded,
                      title: ctx.l10n.youtubeWeb,
                      subtitle: ctx.l10n.youtubeWebSubtitle,
                      url: 'https://www.youtube.com',
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.explore_rounded,
                      title: ctx.l10n.exploreAndCharts,
                      subtitle: ctx.l10n.exploreAndChartsSubtitle,
                      url: YtmLocale.withLocaleParams(
                          'https://music.youtube.com/explore'),
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.library_music_rounded,
                      title: ctx.l10n.yourLibrary,
                      subtitle: ctx.l10n.yourLibrarySubtitle,
                      url: YtmLocale.withLocaleParams(
                          'https://music.youtube.com/library'),
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.favorite_rounded,
                      title: ctx.l10n.likedMusic,
                      subtitle: ctx.l10n.likedMusicSubtitle,
                      url: YtmLocale.withLocaleParams(
                          'https://music.youtube.com/playlist?list=LM'),
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.fiber_new_rounded,
                      title: ctx.l10n.newReleases,
                      subtitle: ctx.l10n.newReleasesSubtitle,
                      url: YtmLocale.withLocaleParams(
                          'https://music.youtube.com/new_releases'),
                      p: p,
                    ),
                    _ytmWebOptionTile(
                      ctx,
                      icon: Icons.history_rounded,
                      title: ctx.l10n.listeningHistory,
                      subtitle: ctx.l10n.listeningHistorySubtitle,
                      url: YtmLocale.withLocaleParams(
                          'https://music.youtube.com/history'),
                      p: p,
                    ),
                  ],
                ),
              ),
            );
          },
  );
}

Widget _ytmWebOptionTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required String url,
  required PulsrPalette p,
}) {
  return Material(
    color: Colors.transparent,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs, vertical: AppSpacing.s2),
      leading: Container(
        width: AppSpacing.s40,
        height: AppSpacing.s40,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppRadii.r10),
          border: Border.all(color: p.hairline),
        ),
        child: Icon(icon, color: p.accent, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: AppFontSize.body),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: p.textTertiary),
      onTap: () {
        Navigator.pop(context);
        YtmWebLoginSheet.show(
          context,
          initialUrl: url,
          title: title,
          isBrowseMode: true,
        );
      },
    ),
  );
}

void showPrivacyGuaranteeSheet(BuildContext context) {
  final p = context.palette;
  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.s20, AppSpacing.s20, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.security_rounded, color: p.accent, size: 24),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: Text(
                      context.l10n.privacyGuarantee,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.title,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _privacyPoint(
                context,
                Icons.offline_bolt_rounded,
                context.l10n.settingsPrivacyOfflineTitle,
                context.l10n.settingsPrivacyOfflineBody,
              ),
              _privacyPoint(
                context,
                Icons.visibility_off_rounded,
                context.l10n.settingsPrivacyNoTrackersTitle,
                context.l10n.settingsPrivacyNoTrackersBody,
              ),
              _privacyPoint(
                context,
                Icons.folder_shared_rounded,
                context.l10n.settingsPrivacyPermissionsTitle,
                context.l10n.settingsPrivacyPermissionsBody,
              ),
              _privacyPoint(
                context,
                Icons.cloud_off_rounded,
                context.l10n.settingsPrivacyControlTitle,
                context.l10n.settingsPrivacyControlBody,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _privacyPoint(
    BuildContext context, IconData icon, String title, String body) {
  final p = context.palette;
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: p.accent, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppFontSize.body,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                body,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.label,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

void showAboutSheet(BuildContext context) {
  final p = context.palette;
  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.accentContainer,
                borderRadius: BorderRadius.circular(AppRadii.r18),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: p.accent, size: 34),
            ),
            const SizedBox(height: AppSpacing.s14),
            Text(
              AppConfig.appTitle,
              style: TextStyle(
                color: p.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: AppFontSize.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${context.l10n.version} ${AppConfig.appVersion}',
              style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.code_rounded, size: 14, color: p.accent),
                const SizedBox(width: AppSpacing.xs),
                // FIX-L8: Extract developer name constant to AppConfig.developerName
                Text(
                  'Developer: ${AppConfig.developerName}',
                  style: TextStyle(
                    color: p.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: AppFontSize.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(context.l10n.aboutBlurb,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: AppFontSize.bodySmall,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showWhatsNewSheet(context);
                    },
                    child: const Text("What's New"),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.l10n.close),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void showWhatsNewSheet(BuildContext context) {
  final p = context.palette;
  final highlights = const [
    (
      Icons.speed_rounded,
      'Bit-Perfect & Hi-Res Output',
      'Direct USB DAC streaming, hardware volume control, and native DSD/DoP playback.'
    ),
    (
      Icons.tune_rounded,
      'Pro Studio DSP Suite',
      'Arbitrary response parametric EQ, multiband compressor, lookahead limiter, and binaural crossfeed.'
    ),
    (
      Icons.palette_rounded,
      'Adaptive Player Themes',
      '8 handcrafted player themes with full phone landscape, tablet two-pane, and AMOLED optimization.'
    ),
    (
      Icons.accessibility_new_rounded,
      'Accessibility & Fluid Gestures',
      'WCAG 2.1 AA contrast compliance, dynamic type 2.0x support, and full screen-reader semantics.'
    ),
  ];

  PulsrSheetHelper.showPulsrSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: p.accentContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.new_releases_rounded, color: p.accent, size: 24),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's New in Pulsr",
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSize.title,
                        ),
                      ),
                      Text(
                        'Version ${AppConfig.appVersion}',
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (final h in highlights) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: p.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadii.r8),
                      ),
                      child: Icon(h.$1, size: 16, color: p.accent),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.$2,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: AppFontSize.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            h.$3,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

