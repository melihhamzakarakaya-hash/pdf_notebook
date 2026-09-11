import 'package:flutter/material.dart';

/// Design tokens pulled from the "PDF Defterim Tablet UI" Claude Design
/// project (claude.ai/design/p/7053aeac-887e-40c8-9f87-aa14f12f8788).
class AppColors {
  AppColors._();

  static const primary = Color(0xFF4C5BA9);
  static const primaryHover = Color(0xFF323C82);

  static const accentContainer = Color(0xFFDEE0FF);
  static const onAccentContainer = Color(0xFF131A66);
  static const iconBadgeStroke = Color(0xFF010A54);

  static const canvasBackground = Color(0xFFEDEBF2);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDim = Color(0xFFFBF8FF);
  static const viewerBody = Color(0xFFEFEDF4);
  static const emptyIconBackground = Color(0xFFE7E8FB);

  static const textPrimary = Color(0xFF1B1B21);
  static const textSecondary = Color(0xFF46464F);
  static const textTertiary = Color(0xFF757680);

  static const borderSubtle = Color(0xFFE6E4EE);
  static const borderCard = Color(0xFFC6C5D0);
  static const borderMuted = Color(0xFFDCDAE5);
  static const borderPaper = Color(0xFFD9D7E3);
  static const borderHeader = Color(0xFFE0DEE9);
  static const borderToolbar = Color(0xFFDEDCE7);

  static const thumbLine = Color(0xFFD6D4E0);
  static const thumbLineFaint = Color(0xFFE6E4EE);
  static const thumbFill = Color(0xFFF1EFF7);

  static const error = Color(0xFFBA1A1A);

  static const penBlack = Color(0xFF1B1B21);
  static const penRed = Color(0xFFC62828);
  static const penBlue = Color(0xFF1B57C4);
  static const penGreen = Color(0xFF2E7D4F);

  static const penColors = <Color>[penBlack, penRed, penBlue, penGreen];

  static const cardPlaceholderTints = <Color>[
    Color(0xFFEF9A9A),
    Color(0xFF90CAF9),
    Color(0xFFA5D6A7),
    Color(0xFFFFCC80),
    Color(0xFFCE93D8),
    Color(0xFF80CBC4),
  ];
}
