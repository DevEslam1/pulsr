import 'package:flutter/material.dart';

/// Keeps a label and value readable when space or text scaling is constrained.
class PulsrKeyValue extends StatelessWidget {
  final Widget label;
  final Widget value;

  const PulsrKeyValue({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 6), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: 16),
              Flexible(child: value),
            ],
          );
        },
      );
}
