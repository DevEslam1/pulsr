// lib/features/player/presentation/widgets/exclusive_usb_chip.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../domain/services/usb_exclusive_service.dart';
import 'sync_diagnostics_sheet.dart';

/// Status chip displaying live bit-perfect USB streaming status with real-time underrun counter.
class ExclusiveUsbChip extends StatefulWidget {
  final bool compact;

  const ExclusiveUsbChip({
    super.key,
    this.compact = false,
  });

  @override
  State<ExclusiveUsbChip> createState() => _ExclusiveUsbChipState();
}

class _ExclusiveUsbChipState extends State<ExclusiveUsbChip> {
  final UsbExclusiveService _service = UsbExclusiveService();
  StreamSubscription<UsbExclusiveStatus>? _statusSub;
  Timer? _pollTimer;

  bool _isActive = false;
  int _underruns = 0;

  @override
  void initState() {
    super.initState();
    _isActive = _service.lastStatus.streamingActive;
    _statusSub = _service.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isActive = status.streamingActive;
        });
        if (_isActive) {
          _startPolling();
        } else {
          _stopPolling();
        }
      }
    });

    if (_isActive) {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollDiagnostics();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollDiagnostics());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollDiagnostics() async {
    final diag = await _service.getDiagnostics();
    if (!mounted) return;
    final isStreaming = diag['isStreamActive'] == true;
    final underruns = (diag['underrunCount'] as num?)?.toInt() ?? 0;
    if (_isActive != isStreaming || _underruns != underruns) {
      setState(() {
        _isActive = isStreaming;
        _underruns = underruns;
      });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => SyncDiagnosticsSheet.show(context),
        borderRadius: BorderRadius.circular(AppRadii.r20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 8 : 10,
            vertical: widget.compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: AppColors.dacGold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadii.r20),
            border: Border.all(
              color: AppColors.dacGold.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              const Icon(
                Icons.usb_rounded,
                size: 13,
                color: AppColors.dacGold,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                context.l10n.exclusiveUsbActive,
                style: TextStyle(
                  color: AppColors.dacGold,
                  fontSize: widget.compact ? AppFontSize.tiny : AppFontSize.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.dacGold.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                context.l10n.underrunsCount(_underruns),
                style: TextStyle(
                  color: _underruns > 0 ? AppColors.warning : AppColors.dacGold.withValues(alpha: 0.8),
                  fontSize: widget.compact ? AppFontSize.tiny : AppFontSize.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
