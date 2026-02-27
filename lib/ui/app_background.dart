import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Full-screen classroom background.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Classroom background — shown at natural proportions (contain),
        // so the full scene is visible without zooming/cropping.
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFF0B1C23),
            child: Image.asset(
              'assets/ui/classroom_background.png',
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
            ),
          ),
        ),

        // Foreground
        child,
      ],
    );
  }
}
