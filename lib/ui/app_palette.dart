import 'package:flutter/material.dart';

/// Palette borrowed from the reference SocialAIPrototype design.
///
/// Kept as simple `Color` constants so screens can compose their own gradients.
class AppPalette {
  // Ink / borders
  static const navyBlack = Color(0xff213036);

  // Primary (teal)
  static const primaryTint = Color(0xff95E3BB);
  static const primary = Color(0xff6EC2B1);
  static const primaryAccent = Color(0xff62ADAA);
  static const primaryShade = Color(0xff589EA5);

  // Secondary (coral)
  static const secondaryTint = Color(0xffFFBDBD);
  static const secondary = Color(0xffF58F92);
  static const secondaryAccent = Color(0xffFF7B7B);
  static const secondaryShade = Color(0xffFF545E);

  // Tertiary (blue-grey)
  static const tertiaryTint = Color(0xffDBE2E8);
  static const tertiary = Color(0xff677DA7);
  static const tertiaryShade = Color(0xff55667D);

  // Paper
  static const paper = Color(0xffffffff);
  static const pinkWhite = Color(0xffFEF4F4);

  // Common gradients
  static const primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryTint, primary, primaryAccent],
    stops: [0.0, 0.55, 1.0],
  );

  static const secondaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [secondary, secondaryAccent],
  );

  static const glassTopGlow = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xAFFFFFFF),
      Color(0x7AFFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 0.25, 1.0],
  );
}

