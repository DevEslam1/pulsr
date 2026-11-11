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
  static const Color cartridgeAccentRed = Color(0xFFE22D2D);

  // ── Turntable deck plinth gradient stops ─────────────────────────────────
  static const Color deckGradStart = Color(0xFF1A1C26);
  static const Color deckGradMid = Color(0xFF13141C);
  static const Color deckGradEnd = Color(0xFF0E0F15);

  // ── Circle stage rim gradient stops ──────────────────────────────────────
  static const Color circleSpindle = Color(0xFF101218);
  static const Color circleRimOuter = Color(0xFF222632);
  static const Color circleRimInner = Color(0xFF0E1015);

  // ── CD stage & optical mechanism ─────────────────────────────────────────
  static const Color cdSurfaceTop = Color(0xFF1E2129);
  static const Color cdSurfaceUpper = Color(0xFF282D37);
  static const Color cdSurfaceMid = Color(0xFF323846);
  static const Color cdSurfaceLower = Color(0xFF20232C);
  static const Color cdSurfaceBottom = Color(0xFF16181F);
  static const Color cdClampWell = Color(0xFF1E212A);
  static const Color cdClampBorder = Color(0xFF383C4D);
  static const Color cdPivotHigh = Color(0xFF3A3F4E);
  static const Color cdPivotMid = Color(0xFF232733);
  static const Color cdPivotLow = Color(0xFF141720);
  static const Color cdPivotBase = Color(0xFF161922);
  static const Color cdStem = Color(0xFF2C303D);
  static const Color cdWeightHigh = Color(0xFF5A6072);
  static const Color cdWeightMid = Color(0xFF353945);
  static const Color cdWeightLow = Color(0xFF21242C);
  static const Color cdWeightRim = Color(0xFF4B5162);
  static const Color cdCollar = Color(0xFF282C38);
  static const Color cdHeadHigh = Color(0xFF454B5C);
  static const Color cdHeadMid = Color(0xFF252833);
  static const Color cdHeadLow = Color(0xFF171920);
  static const Color cdTrayGradStart = Color(0xFF141824);
  static const Color cdTrayGradEnd = Color(0xFF0B0E15);

  // ── Cassette shell & mechanism ───────────────────────────────────────────
  static const Color cassetteShell = Color(0xFF1E2028);
  static const Color cassetteShellBorder = Color(0xFF323646);
  static const Color cassetteWindow = Color(0xFF0F1116);
  static const Color cassetteTape = Color(0xFF5A3825);
  static const Color cassetteBodyTop = Color(0xFF1E212B);
  static const Color cassetteBodyMid = Color(0xFF15171F);
  static const Color cassetteBodyBottom = Color(0xFF101218);
  static const Color cassetteBodyBorder = Color(0xFF343848);
  static const Color cassetteWell = Color(0xFF0C0E14);
  static const Color cassetteBridge = Color(0xFF1B1D25);
  static const Color cassetteBridgeBorder = Color(0xFF383C4E);
  static const Color cassetteScrew = Color(0xFF4C526A);
  static const Color cassetteTapeOuter = Color(0xFF4A2F21);
  static const Color cassetteTapeMid = Color(0xFF321D14);
  static const Color cassetteTapeInner = Color(0xFF22130C);
  static const Color cassetteReelHub = Color(0xFFF0F1F5);
  static const Color cassetteReelRim = Color(0xFFB0B4C4);
  static const Color cassetteCapstanBorder = Color(0xFF2F3445);
  static const Color cassetteHeadBorder = Color(0xFF383C48);
  static const Color cassetteHeadFill = Color(0xFF14161C);
  static const Color cassetteVuPeak = Color(0xFFFF1744);
  static const Color cassetteVuWarn = Color(0xFFFFD600);
  static const Color cassetteVuNormal = Color(0xFF00E676);
  static const Color cassettePinchGold = Color(0xFFC89E48);
  static const Color cassettePinchRim = Color(0xFF4A4E62);
  static const Color cassettePinchCore = Color(0xFF14161F);
  static const Color cassetteRibbonStart = Color(0xFF382015);
  static const Color cassetteRibbonMid = Color(0xFF4A2B1D);
  static const Color cassetteRibbonEnd = Color(0xFF26140D);

  // ── Immersive backdrop ───────────────────────────────────────────────────
  /// Deepest near-black backdrop used by the classic player.
  static const Color immersiveBackdrop = Color(0xFF080910);
}
