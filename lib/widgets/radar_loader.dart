import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The animated radar loader shown while AI work runs in the background:
/// sweeping trail over static rings, a pulsing blip, and an expanding pulse.
class RadarLoader extends StatefulWidget {
  const RadarLoader({super.key, this.size = 48, this.color});

  final double size;
  final Color? color;

  @override
  State<RadarLoader> createState() => _RadarLoaderState();
}

class _RadarLoaderState extends State<RadarLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(progress: _controller.value, color: color),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final strokeWidth = math.max(1.0, size.shortestSide * 0.055);

    // Static rings.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.28);
    for (final fraction in const [0.34, 0.55, 0.76]) {
      canvas.drawCircle(center, maxRadius * fraction, ringPaint);
    }

    // Sweeping trail: a full circle stroked with a sweep gradient whose bright
    // end leads the rotation.
    final trailRect = Rect.fromCircle(
      center: center,
      radius: maxRadius * 0.76,
    ).deflate(strokeWidth);
    final angle = progress * 2 * math.pi;
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.5),
          color,
        ],
        stops: const [0, 0.55, 0.92, 1],
        transform: GradientRotation(-math.pi / 2 + angle),
      ).createShader(trailRect);
    canvas.drawCircle(center, maxRadius * 0.76 - strokeWidth / 2, sweepPaint);

    // Blip pulse expanding from the detected signal.
    final blipCenter = Offset(
      center.dx + maxRadius * 0.34,
      center.dy - maxRadius * 0.2,
    );
    final pulseRadius = strokeWidth + (maxRadius * 0.3) * progress;
    canvas.drawCircle(
      blipCenter,
      pulseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.8
        ..color = color.withValues(alpha: (1 - progress) * 0.6),
    );

    // Detected signal dot.
    canvas.drawCircle(
      blipCenter,
      strokeWidth * 1.2,
      Paint()..color = color.withValues(alpha: 0.65 + 0.35 * progress),
    );

    // Center dot.
    canvas.drawCircle(center, strokeWidth * 1.15, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
