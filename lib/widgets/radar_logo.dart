import 'package:flutter/material.dart';

class RadarLogo extends StatelessWidget {
  const RadarLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Icon(
          Icons.radar_rounded,
          color: Theme.of(context).colorScheme.onPrimary,
          size: size * 0.66,
        ),
      ),
    );
  }
}
