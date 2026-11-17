// lib/features/player/presentation/widgets/custody_certificate_card.dart
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/chain_of_custody_service.dart';
import '../../../../core/services/custody_certificate_export.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../cubit/player_cubit.dart';

/// Measures the live signal chain and presents the result as an exportable
/// certificate. Nothing here claims bit-exactness: the verdict comes from the
/// digests the native engine measured during a real capture window.
class CustodyCertificateCard extends StatefulWidget {
  const CustodyCertificateCard({
    super.key,
    this.service,
    this.getTempDirectory,
  });

  final ChainOfCustodyService? service;
  final Future<Directory> Function()? getTempDirectory;

  @override
  State<CustodyCertificateCard> createState() => _CustodyCertificateCardState();
}

class _CustodyCertificateCardState extends State<CustodyCertificateCard> {
  ChainOfCustodyReport? _report;
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    if (_busy) return;
    final cubit = context.read<PlayerCubit>();
    final song = cubit.state.currentSong;
    if (song == null) {
      setState(() => _error = context.l10n.custodyRequiresPlayback);
      return;
    }
    if (!cubit.state.isPlaying) {
      // An idle engine produces no blocks, so no window can ever fill. Saying so
      // up front is better than reporting a mysterious "unverified".
      setState(() => _error = context.l10n.custodyRequiresPlayback);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // AUDIT-FIX (P0-7): try/catch/finally ensures _busy always clears and
    // platform/share failures surface cleanly instead of wedging the card.
    try {
      final report =
          await (widget.service ?? ChainOfCustodyService()).verifyChain(
        trackId: song.id.toString(),
        trackTitle: '${song.title} — ${song.artist}',
        filePath: song.path,
        decoderCodec: song.codec ?? 'Unknown',
        sourceSampleRate: song.sampleRate ?? 44100,
        sourceBitDepth: song.bitDepth ?? 16,
      );

      if (!mounted) return;
      setState(() {
        _report = report;
      });
    } catch (e, st) {
      ErrorLogger.log('Custody verification failed',
          error: e, stackTrace: st, category: 'CustodyCertificateCard');
      if (mounted) {
        setState(() {
          _error = context.l10n.somethingWentWrong;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _shareCertificate() async {
    if (_busy) return;
    final report = _report;
    if (report == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final shareSubject = context.l10n.custodyCertificateHeader;
      final directory =
          await (widget.getTempDirectory ?? getTemporaryDirectory)();
      final artifact =
          await exportCustodyCertificate(report, directory: directory);
      final result = await SharePlus.instance.share(ShareParams(
        text: artifact.jsonText,
        subject: shareSubject,
      ));
      if (!mounted || result.status == ShareResultStatus.dismissed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.custodyCertificateSaved),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      ErrorLogger.log('Custody certificate share failed',
          error: e, stackTrace: st, category: 'CustodyCertificateCard');
      if (mounted) {
        setState(() {
          _error = context.l10n.somethingWentWrong;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  String _verdictLabel(ChainOfCustodyReport report) {
    switch (report.verdict) {
      case CustodyVerdict.bitExactMeasured:
        return context.l10n.custodyBitExact;
      case CustodyVerdict.chainModifiedMeasured:
        return context.l10n.custodyChainModified;
      case CustodyVerdict.notSupported:
        return context.l10n.custodyNotSupported;
      case CustodyVerdict.unverified:
        return context.l10n.custodyUnverified;
    }
  }

  Color _verdictColor(CustodyVerdict verdict) {
    switch (verdict) {
      case CustodyVerdict.bitExactMeasured:
        return AppColors.studioGreen;
      case CustodyVerdict.chainModifiedMeasured:
        return context.palette.accent;
      case CustodyVerdict.unverified:
      case CustodyVerdict.notSupported:
        return context.palette.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final report = _report;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s14),
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.custodyVerifyTitle,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.wide,
                    color: p.accent,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _verify,
                tooltip:
                    _busy ? l10n.custodyVerifying : l10n.custodyVerifyTitle,
                icon: Icon(
                  _busy ? Icons.hourglass_top_rounded : Icons.verified_outlined,
                  color: p.accent,
                  size: 20,
                ),
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                _error!,
                style: TextStyle(
                    fontSize: AppFontSize.label, color: p.textSecondary),
              ),
            ),
          if (report != null) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _verdictColor(report.verdict),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _verdictLabel(report),
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              report.measurement == null
                  ? '${report.activeDspStages.length} stage(s) active'
                  : '${report.measurement!.frames} frames · '
                      '${report.measurement!.windowMs.toStringAsFixed(1)} ms · '
                      'in ${report.measurement!.inputSha256.substring(0, 12)}…',
              style: TextStyle(
                  fontSize: AppFontSize.caption, color: p.textSecondary),
            ),
            if (report.measurement != null)
              Text(
                'out ${report.measurement!.outputSha256.substring(0, 12)}…',
                style: TextStyle(
                    fontSize: AppFontSize.caption, color: p.textSecondary),
              ),
            if (report.limitations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  report.limitations.join('\n'),
                  style: TextStyle(
                      fontSize: AppFontSize.caption, color: p.textSecondary),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _busy ? null : _shareCertificate,
                child: Text(l10n.share),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
