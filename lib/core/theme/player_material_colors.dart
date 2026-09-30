// lib/core/theme/player_material_colors.dart
import 'package:flutter/material.dart';

/// Fixed material colours for the skeuomorphic player themes (vinyl, cassette,
/// turntable hardware).
///
/// These are intentionally **not** palette-driven: a vinyl record, a gimbal
/// bearing and a cassette shell must look like the physical object regardless
/// of the user's accent or light/dark mode. Centralising them here removes
/// anonymous `Color(0xFF…)` literals from the theme files while documenting
/// exactly which material each value represents.
///
/// Themed surfaces (card player background, immersive backdrop) live on
/// [PulsrPalette] instead — see `playerCard` / `deepShade`.
abstract class PlayerMaterialColors {
  PlayerMaterialColors._();

  // ── Turntable plinth ─────────────────────────────────────────────────────
  /// Matte plinth body behind the record.
  static const Color plinthSurface = Color(0xFF14151C);

  /// Plinth edge highlight.
  static const Color plinthBorder = Color(0xFF282B37);

  // ── Vinyl record ─────────────────────────────────────────────────────────
  /// Outer record disc base behind the sheen gradient.
  static const Color recordBase = Color(0xFF0C0D11);

  /// Vinyl radial sheen gradient stops (centre → rim).
  static const Color recordSheenCenter = Color(0xFF181A22);
  static const Color recordSheenMid = Color(0xFF101116);
  static const Color recordSheenDeep = Color(0xFF090A0D);
  static const Color recordSheenRim = Color(0xFF14151C);

  /// Record outer rim bead.
  static const Color recordRim = Color(0xFF2B2E3C);

  /// Idle (non-playing) RPM badge fill / border.
  static const Color rpmBadgeFill = Color(0xFF181A22);
  static const Color rpmBadgeBorder = Color(0xFF2B2E3C);

  /// Solid black disc used by the circle theme's record face.
  static const Color vinylBlack = Color(0xFF121212);

  // ── Tonearm gimbal base ──────────────────────────────────────────────────
  static const Color gimbalHighlight = Color(0xFF2C2F3C);
  static const Color gimbalMid = Color(0xFF1B1D26);
  static const Color gimbalShadow = Color(0xFF0F1015);
  static const Color gimbalRim = Color(0xFF424658);

  // ── Counterweight ────────────────────────────────────────────────────────
  static const Color counterweightStemLight = Color(0xFF8B8E9B);
  static const Color counterweightStemDark = Color(0xFF535664);
  static const Color counterweightEdge = Color(0xFF9EA2B2);
  static const Color counterweightHighlight = Color(0xFFE2E4EB);
  static const Color counterweightMid = Color(0xFF5A5D6C);
  static const Color counterweightShadow = Color(0xFF383A46);
  static const Color calibrationStrip = Color(0xFF14151B);

  // ── Headshell / arm rest ─────────────────────────────────────────────────
  static const Color collarMetal = Color(0xFFC0C3D0);
  static const Color headshellHighlight = Color(0xFF323544);
  static const Color headshellShadow = Color(0xFF161820);
  static const Color pivotCenterScrew = Color(0xFF1A1C24);
  static const Color armRestPost = Color(0xFF282B36);
  static const Color armRestClip = Color(0xFF4A4E60);

  // ── Cassette shell ───────────────────────────────────────────────────────
  static const Color cassetteShell = Color(0xFF1E2028);
  static const Color cassetteShellBorder = Color(0xFF323646);
  static const Color cassetteWindow = Color(0xFF0F1116);
  static const Color cassetteTape = Color(0xFF5A3825);

  // ── Immersive backdrop ───────────────────────────────────────────────────
  /// Deepest near-black backdrop used by the classic player.
  static const Color immersiveBackdrop = Color(0xFF080910);
}
