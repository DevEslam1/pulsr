import 'package:flutter/material.dart';

import '../../../../core/responsive/pulsr_responsive_tokens.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

class QuickActionsRow extends StatelessWidget {
  final List<Widget> cards;

  const QuickActionsRow({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final vp = PulsrViewport.of(context);
    if (vp.isShortHeight) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s10),
              SizedBox(width: 140, child: cards[i]),
            ],
          ],
        ),
      );
    }
    final isNarrow = vp.width < 360;
    if (isNarrow && cards.length == 3) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: AppSpacing.s10),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}
