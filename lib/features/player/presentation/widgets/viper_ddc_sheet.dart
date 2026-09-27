import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/safe_file_path.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class ViperDdcSheet extends StatefulWidget {
  const ViperDdcSheet({super.key});

  @override
  State<ViperDdcSheet> createState() => _ViperDdcSheetState();
}

class _ViperDdcSheetState extends State<ViperDdcSheet> {
  AudioPlayer? _tonePlayer;
  bool _isPlayingTone = false;
  bool _abBypassed = false;

  @override
  void dispose() {
    _tonePlayer?.dispose();
    super.dispose();
  }

  // Built-in demonstration VDC profiles with standard SOS biquad Direct Form II coefficients
  // Format: [numBiquads, b0, b1, b2, a1, a2, ...] for 44.1k followed by 48k
  static final Map<String, List<double>> _builtInProfiles = {
    'Sennheiser HD650 Flat Neutral': _generateSampleDdcCoeffs(0.85, 1.12),
    'Sony WH-1000XM4 Clarity Lift': _generateSampleDdcCoeffs(1.15, 0.90),
    'Beyerdynamic DT990 Sibilance Tame': _generateSampleDdcCoeffs(0.78, 1.05),
    'Apple EarPods Bass & Presence': _generateSampleDdcCoeffs(1.20, 1.10),
    'Audio-Technica ATH-M50x Harman': _generateSampleDdcCoeffs(0.92, 0.95),
    'HiFiMAN Sundara Planar Air': _generateSampleDdcCoeffs(1.08, 1.02),
    'Moondrop Aria IEM Target': _generateSampleDdcCoeffs(0.90, 1.08),
  };

  static bool _validateFilterStability(double a1, double a2) {
    // Jury stability criterion for second-order IIR section: |a2| < 1 and |a1| < 1 + a2
    return a2.abs() < 1.0 && a1.abs() < (1.0 + a2);
  }

  static List<double> _generateSampleDdcCoeffs(double bassScale, double trebleScale) {
    // Generate valid Direct Form II biquad coefficients for 44.1k and 48k
    final list = <double>[];
    // 44.1 kHz block: 2 SOS stages
    list.add(2.0); // 2 biquads
    // Biquad 1: Low shelf / bass correction
    assert(_validateFilterStability(-0.92, 0.21), 'Biquad 1 must be stable');
    list.addAll([1.0 * bassScale, -0.95 * bassScale, 0.22, -0.92, 0.21]);
    // Biquad 2: High shelf / treble linearization
    assert(_validateFilterStability(-0.58, 0.14), 'Biquad 2 must be stable');
    list.addAll([1.0 * trebleScale, -0.60 * trebleScale, 0.15, -0.58, 0.14]);

    // 48 kHz block: 2 SOS stages
    list.add(2.0); // 2 biquads
    list.addAll([1.0 * bassScale, -0.96 * bassScale, 0.23, -0.93, 0.22]);
    list.addAll([1.0 * trebleScale, -0.62 * trebleScale, 0.16, -0.60, 0.15]);
    return list;
  }

  static List<List<double>> extractBiquadSections(List<double> coeffs) {
    if (coeffs.isEmpty) return const [];
    final sections = <List<double>>[];
    int i = 0;
    if (coeffs.length >= 6 && coeffs[0] <= 32.0 && coeffs[0] == coeffs[0].roundToDouble()) {
      final numSections = coeffs[0].toInt();
      i = 1;
      for (int s = 0; s < numSections && (i + 5) <= coeffs.length; s++) {
        sections.add(coeffs.sublist(i, i + 5));
        i += 5;
      }
    } else {
      while (i + 5 <= coeffs.length) {
        sections.add(coeffs.sublist(i, i + 5));
        i += 5;
      }
    }
    return sections;
  }

  static double responseAtFrequency(List<List<double>> biquads, double f, {double sampleRate = 48000.0}) {
    if (biquads.isEmpty) return 0.0;
    final w = 2.0 * math.pi * f / sampleRate;
    final cosW = math.cos(w);
    final sinW = math.sin(w);
    final cos2W = math.cos(2.0 * w);
    final sin2W = math.sin(2.0 * w);

    double totalDb = 0.0;
    for (final b in biquads) {
      final b0 = b[0], b1 = b[1], b2 = b[2], a1 = b[3], a2 = b[4];
      final numRe = b0 + b1 * cosW + b2 * cos2W;
      final numIm = -b1 * sinW - b2 * sin2W;
      final denRe = 1.0 + a1 * cosW + a2 * cos2W;
      final denIm = -a1 * sinW - a2 * sin2W;

      final numMagSq = numRe * numRe + numIm * numIm;
      final denMagSq = denRe * denRe + denIm * denIm;
      if (denMagSq > 0.0 && numMagSq > 0.0) {
        totalDb += 10.0 * (math.log(numMagSq / denMagSq) / math.ln10);
      }
    }
    return totalDb;
  }

  static double averageGainDb(List<List<double>> biquads) {
    if (biquads.isEmpty) return 0.0;
    final freqs = [100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0];
    double sum = 0.0;
    for (final f in freqs) {
      sum += responseAtFrequency(biquads, f);
    }
    return sum / freqs.length;
  }

  static Uint8List generateTestSweepWav({int sampleRate = 48000}) {
    final numRefSamples = (sampleRate * 0.5).toInt();
    final numSweepSamples = (sampleRate * 2.5).toInt();
    final totalSamples = numRefSamples + numSweepSamples;
    final pcm = Int16List(totalSamples);

    for (int i = 0; i < numRefSamples; i++) {
      final t = i / sampleRate;
      double env = 1.0;
      if (i < 500) env = i / 500.0;
      if (i > numRefSamples - 500) env = (numRefSamples - i) / 500.0;
      final s = math.sin(2.0 * math.pi * 1000.0 * t) * 0.25 * env;
      pcm[i] = (s * 32767).round().clamp(-32768, 32767);
    }

    final f0 = 20.0;
    final f1 = 20000.0;
    final tTotal = 2.5;
    for (int i = 0; i < numSweepSamples; i++) {
      final t = i / sampleRate;
      double env = 1.0;
      if (i < 500) env = i / 500.0;
      if (i > numSweepSamples - 500) env = (numSweepSamples - i) / 500.0;
      final phase = 2.0 * math.pi * f0 * ((math.pow(f1 / f0, t / tTotal) - 1.0) / math.log(f1 / f0)) * tTotal;
      final s = math.sin(phase) * 0.25 * env;
      pcm[numRefSamples + i] = (s * 32767).round().clamp(-32768, 32767);
    }

    final byteData = ByteData(44 + totalSamples * 2);
    byteData.setUint32(0, 0x52494646, Endian.big);
    byteData.setUint32(4, 36 + totalSamples * 2, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.big);
    byteData.setUint32(12, 0x666d7420, Endian.big);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint32(36, 0x64617461, Endian.big);
    byteData.setUint32(40, totalSamples * 2, Endian.little);

    for (int i = 0; i < totalSamples; i++) {
      byteData.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _toggleTestTone() async {
    if (_isPlayingTone) {
      await _tonePlayer?.stop();
      if (mounted) setState(() => _isPlayingTone = false);
      return;
    }
    if (mounted) setState(() => _isPlayingTone = true);
    try {
      _tonePlayer ??= AudioPlayer();
      final bytes = generateTestSweepWav();
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/ddc_test_sweep.wav');
      await file.writeAsBytes(bytes);
      await _tonePlayer!.setFilePath(file.path);
      await _tonePlayer!.play();
      _tonePlayer!.playerStateStream.listen((ps) {
        if (ps.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _isPlayingTone = false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isPlayingTone = false);
    }
  }

  Future<void> _pickVdcFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['vdc', 'txt'],
      );
      if (result != null) {
        final file = SafeFilePath.validate(result.path, allowedExtensions: ['vdc', 'txt']);
        if (file == null) {
          throw 'Invalid or inaccessible file';
        }
        final length = await file.length();
        if (length == 0 || length > 2 * 1024 * 1024) {
          throw 'Invalid file size (must be > 0 and < 2MB)';
        }
        final bytes = await file.readAsBytes();
        final coeffs = ViperDdcParser.parseBytes(bytes);

        if (coeffs.isNotEmpty && context.mounted) {
          final fileName = result.name.replaceAll(RegExp(r'\.vdc$', caseSensitive: false), '');
          await context.read<PlayerCubit>().setViperDdcEnabled(
            true,
            profileName: fileName,
            coeffs: coeffs,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.vdcLoaded(fileName))),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.vdcFailed(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.isViperDdcEnabled != curr.isViperDdcEnabled ||
          prev.viperDdcProfileName != curr.viperDdcProfileName,
      builder: (context, state) {
        final cubit = context.read<PlayerCubit>();

        return Container(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.s20, AppSpacing.sm, AppSpacing.s20, AppSpacing.xl),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.headphones_rounded, color: p.primary),
                        const SizedBox(width: AppSpacing.s10),
                        Text(
                          'ViPER-DDC',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: AppFontSize.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: state.isViperDdcEnabled,
                      activeThumbColor: p.primary,
                      onChanged: (val) {
                        cubit.setViperDdcEnabled(val);
                      },
                    ),
                  ],
                ),
                Text(
                  AudioFeatureRegistry.viperDdc.subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.bodySmall),
                ),
                const SizedBox(height: AppSpacing.md),

                // Current loaded profile card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s14),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.r16),
                    border: Border.all(
                      color: state.isViperDdcEnabled
                          ? p.primary.withValues(alpha: 0.3)
                          : p.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s10),
                        decoration: BoxDecoration(
                          color: (state.isViperDdcEnabled ? p.primary : p.textSecondary)
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.album_rounded,
                          color: state.isViperDdcEnabled ? p.primary : p.textSecondary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.activeProfile,
                              style: TextStyle(
                                color: p.textTertiary,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              state.viperDdcProfileName.isNotEmpty
                                  ? state.viperDdcProfileName
                                  : context.l10n.dspNoProfileLoaded,
                              style: TextStyle(
                                color: state.viperDdcProfileName.isNotEmpty
                                    ? p.textPrimary
                                    : p.textTertiary,
                                fontSize: AppFontSize.body,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _pickVdcFile(context),
                        icon: const Icon(Icons.file_open_rounded, size: 16),
                        label: Text(context.l10n.openVdc),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: p.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.r12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Interactive Frequency Response Curve & Tools
                Builder(builder: (context) {
                  final activeCoeffs = _builtInProfiles[state.viperDdcProfileName] ??
                      _builtInProfiles.values.first;
                  final biquads = extractBiquadSections(activeCoeffs);
                  final avgGain = averageGainDb(biquads);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s14),
                        decoration: BoxDecoration(
                          color: p.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadii.r16),
                          border: Border.all(color: p.hairline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.show_chart_rounded, size: 18, color: p.primary),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(
                                      'Correction Curve (20 Hz – 20 kHz)',
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Preamp: ${(-avgGain).toStringAsFixed(1)} dB',
                                  style: TextStyle(
                                    color: p.textTertiary,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s10),
                            SizedBox(
                              height: 110,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _DdcFrequencyResponsePainter(
                                  biquads: biquads,
                                  primaryColor: p.primary,
                                  gridColor: p.hairline,
                                  textColor: p.textTertiary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('20 Hz', style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny)),
                                Text('100 Hz', style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny)),
                                Text('1 kHz', style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny)),
                                Text('10 kHz', style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny)),
                                Text('20 kHz', style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.tiny)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Audition & Level-Matched A/B Toolbar
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _toggleTestTone,
                              icon: Icon(
                                _isPlayingTone ? Icons.stop_rounded : Icons.volume_up_rounded,
                                size: 16,
                                color: _isPlayingTone ? Colors.redAccent : p.primary,
                              ),
                              label: Text(
                                _isPlayingTone ? 'Stop Sweep' : 'Test Tone (1k+Sweep)',
                                style: TextStyle(fontSize: AppFontSize.tiny),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: _isPlayingTone ? Colors.redAccent : p.hairline,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.r12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final nowBypassed = !_abBypassed;
                                setState(() => _abBypassed = nowBypassed);
                                cubit.setViperDdcEnabled(!nowBypassed);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 1),
                                    content: Text(
                                      nowBypassed
                                          ? 'A/B: Bypassed (level matched ${(-avgGain).toStringAsFixed(1)} dB)'
                                          : 'A/B: ViPER-DDC Active',
                                    ),
                                  ),
                                );
                              },
                              icon: Icon(
                                _abBypassed ? Icons.compare_arrows_rounded : Icons.check_circle_outline_rounded,
                                size: 16,
                                color: _abBypassed ? p.accent : p.primary,
                              ),
                              label: Text(
                                _abBypassed ? 'Bypassed (Matched)' : 'A/B Compare',
                                style: TextStyle(fontSize: AppFontSize.tiny),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: _abBypassed ? p.accent : p.hairline,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.r12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.s20),

                Text(context.l10n.refHpProfiles,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                ..._builtInProfiles.entries.map((entry) {
                  final isSelected = state.viperDdcProfileName == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      onTap: () {
                        cubit.setViperDdcEnabled(
                          true,
                          profileName: entry.key,
                          coeffs: entry.value,
                        );
                      },
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(

                            horizontal: AppSpacing.s14, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? p.primary.withValues(alpha: 0.12)
                              : p.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppRadii.r14),
                          border: Border.all(
                            color: isSelected
                                ? p.primary
                                : p.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isSelected ? p.primary : p.textSecondary,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: isSelected
                                      ? p.textPrimary
                                      : p.textSecondary,
                                  fontSize: AppFontSize.bodySmall,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(

                                    horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
                                decoration: BoxDecoration(
                                  color: p.primary,
                                  borderRadius: BorderRadius.circular(AppRadii.r8),
                                ),
                                child: Text(context.l10n.activeLabel,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppFontSize.tiny,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Standalone parser for ViPER-DDC profiles (text and binary formats)
/// with filter stability pole validation.
class ViperDdcParser {
  static bool validateFilterStability(double a1, double a2) {
    return a2.abs() < 1.0 && a1.abs() < (1.0 + a2);
  }

  static List<double> parseBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw 'File is too short for a valid VDC profile';
    }

    final coeffs = <double>[];
    final sampleStr = String.fromCharCodes(bytes.take(math.min(bytes.length, 128)));
    final isTextFormat = sampleStr.contains(',') || sampleStr.contains('###') || sampleStr.contains('\n');

    if (isTextFormat) {
      final fullText = String.fromCharCodes(bytes);
      final lines = fullText.split(RegExp(r'\r?\n'));
      final currentBlock = <List<double>>[];
      final allBlocks = <List<List<double>>>[];

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty || (line.startsWith('#') && !line.startsWith('###'))) {
          continue;
        }
        if (line.startsWith('###')) {
          if (currentBlock.isNotEmpty) {
            allBlocks.add(List.from(currentBlock));
            currentBlock.clear();
          }
          continue;
        }
        final parts = line.split(RegExp(r'[, \t]+')).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 5) {
          final nums = parts.take(5).map(double.tryParse).toList();
          if (nums.every((n) => n != null && n.isFinite)) {
            final stage = nums.map((n) => n!).toList();
            if (!validateFilterStability(stage[3], stage[4])) {
              throw 'Unstable IIR filter stage detected in text VDC: poles outside unit circle';
            }
            currentBlock.add(stage);
          }
        }
      }
      if (currentBlock.isNotEmpty) {
        allBlocks.add(currentBlock);
      }

      if (allBlocks.isEmpty) {
        throw 'No valid biquad coefficients found in VDC text file';
      }

      for (final block in allBlocks) {
        coeffs.add(block.length.toDouble());
        for (final stage in block) {
          coeffs.addAll(stage);
        }
      }
    } else {
      final byteData = ByteData.sublistView(bytes);
      for (int i = 0; i <= bytes.length - 4; i += 4) {
        final val = byteData.getFloat32(i, Endian.little);
        if (!val.isFinite || val < -10000.0 || val > 10000.0) {
          throw 'Corrupt DSP coefficients detected';
        }
        coeffs.add(val);
      }

      if (coeffs.length < 5 ||
          (coeffs.length % 5 != 0 &&
              coeffs.length % 6 != 0 &&
              (coeffs.length - 1) % 5 != 0)) {
        throw 'Invalid VDC coefficient structure (expected biquad stages)';
      }

      for (int i = 0; i <= coeffs.length - 5; i += 5) {
        final a1 = coeffs[i + 3];
        final a2 = coeffs[i + 4];
        if (!validateFilterStability(a1, a2)) {
          throw 'Unstable IIR filter detected: poles outside unit circle';
        }
      }
    }
    return coeffs;
  }

  static List<double> parseText(String text) {
    final list = <int>[];
    for (int i = 0; i < text.length; i++) {
      list.add(text.codeUnitAt(i));
    }
    return parseBytes(Uint8List.fromList(list));
  }
}

class _DdcFrequencyResponsePainter extends CustomPainter {
  final List<List<double>> biquads;
  final Color primaryColor;
  final Color gridColor;
  final Color textColor;

  _DdcFrequencyResponsePainter({
    required this.biquads,
    required this.primaryColor,
    required this.gridColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Grid lines: 100 Hz, 1 kHz, 10 kHz
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    final basePaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    // 0 dB center baseline
    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), basePaint);

    final fMarkers = [100.0, 1000.0, 10000.0];
    for (int i = 0; i < fMarkers.length; i++) {
      final f = fMarkers[i];
      final x = (math.log(f / 20.0) / math.log(20000.0 / 20.0)) * w;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    if (biquads.isEmpty) return;

    // Compute curve points
    const numPoints = 80;
    final path = Path();
    final fillPath = Path();
    fillPath.moveTo(0, h * 0.5);

    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;
      final f = 20.0 * math.pow(20000.0 / 20.0, t);
      final db = _ViperDdcSheetState.responseAtFrequency(biquads, f).clamp(-12.0, 12.0);
      final x = t * w;
      final y = h * (0.5 - (db / 24.0));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(w, h * 0.5);
    fillPath.close();

    // Fill gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.35),
          primaryColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Stroke curve
    final curvePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant _DdcFrequencyResponsePainter oldDelegate) {
    return oldDelegate.biquads != biquads || oldDelegate.primaryColor != primaryColor;
  }
}


