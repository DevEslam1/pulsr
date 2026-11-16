import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/home/presentation/widgets/hero_mix_card.dart';
import 'package:pulsr/features/home/presentation/widgets/quick_card.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

void main() {
  group('P3 Design-system enforcement', () {
    test('ScrollbarThemeData uses palette accent, surfaceContainer, 6dp, r3',
        () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final calm in [false, true]) {
          final theme = AuraTheme.customTheme(
            AppColors.primary,
            brightness: brightness,
            isCalmDensity: calm,
          );
          final p = theme.extension<PulsrPalette>()!;
          final sb = theme.scrollbarTheme;

          expect(sb.thickness?.resolve({}), 6.0);
          expect(sb.radius, const Radius.circular(AppRadii.r3));
          expect(sb.trackColor?.resolve({}), p.surfaceContainer);
          expect(sb.trackBorderColor?.resolve({}), p.hairline);

          final idleThumb = sb.thumbColor?.resolve({});
          final hoverThumb = sb.thumbColor?.resolve({WidgetState.hovered});
          final dragThumb = sb.thumbColor?.resolve({WidgetState.dragged});
          expect(idleThumb, p.accent.withValues(alpha: 0.40));
          expect(hoverThumb, p.accent.withValues(alpha: 0.70));
          expect(dragThumb, p.accent.withValues(alpha: 0.70));
        }
      }
    });

    test('VisualDensityMode.calm lowers palette chrome scale tokens', () {
      expect(VisualDensityMode.values,
          containsAll([VisualDensityMode.comfortable, VisualDensityMode.calm]));

      final comfy = AuraTheme.customTheme(
        AppColors.primary,
        brightness: Brightness.dark,
        isCalmDensity: false,
      ).extension<PulsrPalette>()!;
      final calm = AuraTheme.customTheme(
        AppColors.primary,
        brightness: Brightness.dark,
        isCalmDensity: true,
      ).extension<PulsrPalette>()!;

      expect(comfy.isCalmDensity, isFalse);
      expect(calm.isCalmDensity, isTrue);
      expect(calm.chromeGlowScale, lessThan(comfy.chromeGlowScale));
      expect(calm.specularScale, lessThan(comfy.specularScale));
      expect(calm.glow.a, lessThan(comfy.glow.a));
    });

    testWidgets(
        'QuickCard and HeroMixCard drop gradient/glow shadows in Calm density',
        (tester) async {
      GpuBudget.setEnabled(false);

      Future<BoxDecoration> pumpAndInspectQuickCard(bool calm) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AuraTheme.customTheme(
              AppColors.primary,
              brightness: Brightness.dark,
              isCalmDensity: calm,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  QuickCard(
                    title: 'Quick',
                    subtitle: 'Sub',
                    icon: Icons.favorite,
                    color: AppColors.primary,
                    onTap: () {},
                  ),
                  HeroMixCard(
                    overline: 'MIX',
                    title: 'Daily Mix',
                    subtitle: 'Curated',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        final containers = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .toList();
        await tester.pumpAndSettle();
        final settledContainers = tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .toList();
        return (settledContainers.isEmpty ? containers : settledContainers)
            .firstWhere(
          (d) => d.borderRadius == AppRadii.r18All,
        );
      }

      final comfyDecor = await pumpAndInspectQuickCard(false);
      expect(comfyDecor.gradient, isNotNull);

      final calmDecor = await pumpAndInspectQuickCard(true);
      expect(calmDecor.gradient, isNull);
    });

    test('AppColors.textOnAccent chooses readable foreground for any fill', () {
      expect(AppColors.textOnAccent(Colors.white), AppColors.onBright);
      expect(AppColors.textOnAccent(const Color(0xFF0A0A0D)), Colors.white);
      expect(AppColors.textOnAccent(AppColors.ytRedDeep), Colors.white);
    });
  });
}
