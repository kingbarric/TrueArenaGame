import 'package:flutter/material.dart';

/// Displays the transparent PlayHuud wordmark on the current screen background.
class PlayHuudLogo extends StatelessWidget {
  const PlayHuudLogo({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: Image.asset(
          'assets/images/branding/playhuud-wordmark-transparent.png',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          semanticLabel: 'PlayHuud',
        ),
      );
}
