// lib/core/widgets/artwork_placeholder.dart
import 'package:material_ui/material_ui.dart';
import 'mesh_gradient_placeholder.dart';

/// {@category DesignSystem}
/// Dynamic artwork placeholder replacing the identical purple waveform box
/// with deterministic, tasteful seeded mesh gradients.
class ArtworkPlaceholder extends StatelessWidget {
  final double size;
  final double borderRadius;
  final IconData? icon;
  final int? seed;
  final String? title;
  final String? artist;

  const ArtworkPlaceholder({
    super.key,
    this.size = 56.0,
    this.borderRadius = 12.0,
    this.icon,
    this.seed,
    this.title,
    this.artist,
  });

  @override
  Widget build(BuildContext context) {
    return MeshGradientPlaceholder(
      size: size,
      borderRadius: borderRadius,
      icon: icon,
      seed: seed,
      title: title,
      artist: artist,
    );
  }
}
