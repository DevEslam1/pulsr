// lib/core/responsive/pulsr_viewport_debug_overlay.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import 'pulsr_responsive_tokens.dart';

/// Developer debug overlay that displays live viewport metrics, breakpoint tiers,
/// content constraints, grid columns, and safe area insets.
class PulsrViewportDebugOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const PulsrViewportDebugOverlay({
    super.key,
    required this.child,
    this.enabled = kDebugMode,
  });

  @override
  State<PulsrViewportDebugOverlay> createState() => _PulsrViewportDebugOverlayState();
}

class _PulsrViewportDebugOverlayState extends State<PulsrViewportDebugOverlay> {
  bool _minimized = true;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final vp = PulsrViewport.of(context);
    final insets = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        widget.child,
        PositionedDirectional(
          start: 8,
          top: insets.top + 8,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () => setState(() => _minimized = !_minimized),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadii.r8),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: _minimized
                    ? Text(
                        '📐 ${vp.width.round()}x${vp.height.round()} [${vp.sizeClass.name}]',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'VIEWPORT: ${vp.width.round()} x ${vp.height.round()}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Text('Class: ${vp.deviceClass.name} | Size: ${vp.sizeClass.name}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          Text('Orientation: ${vp.orientation.name} | Short: ${vp.isShortHeight}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          Text('Content Max: ${vp.contentMaxWidth.round()}dp | Pad: ${vp.pagePadding.round()}dp', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          Text('Grid Cols: ${vp.gridColumns} | Nav: ${vp.navMode.name}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          Text('Insets: T${insets.top.round()} B${insets.bottom.round()} L${insets.left.round()} R${insets.right.round()}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
