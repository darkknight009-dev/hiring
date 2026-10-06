import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Launch animation: a radar sweep spins up, lights signal blips as it passes
/// them, and the FeedRadar wordmark fades in. The whole sequence is finite
/// (no repeating controllers), so it ends with [onFinished] and widget tests
/// settle normally.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static const duration = Duration(milliseconds: 2200);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashPage.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radarColor = Color(0xFF34D399);
    return Scaffold(
      backgroundColor: const Color(0xFF06140D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.3,
            colors: [Color(0xFF0D3323), Color(0xFF06140D)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _controller.value;
              final textOpacity =
                  ((progress - 0.35) / 0.3).clamp(0.0, 1.0).toDouble();
              final textSlide =
                  (1 - ((progress - 0.35) / 0.35).clamp(0.0, 1.0)) * 14;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 190,
                    height: 190,
                    child: CustomPaint(
                      painter: _SplashRadarPainter(
                        progress: progress,
                        color: radarColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Opacity(
                    opacity: textOpacity,
                    child: Transform.translate(
                      offset: Offset(0, textSlide),
                      child: Column(
                        children: [
                          Text(
                            'FeedRadar',
                            key: const Key('splash-wordmark'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Scanning your feed for opportunities.',
                            style: TextStyle(
                              color: radarColor.withValues(alpha: 0.75),
                              fontSize: 14,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SplashRadarPainter extends CustomPainter {
  const _SplashRadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  /// Total sweep rotations across the splash — enough motion to feel alive
  /// without being dizzy.
  static const turns = 2.25;

  /// Blip positions as (angle from 12 o'clock clockwise, radius fraction).
  static const blips = [
    (angle: 0.7, radius: 0.42),
    (angle: 2.6, radius: 0.66),
    (angle: 4.4, radius: 0.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    // Ease-out so the sweep spins up fast, then glides to a stop.
    final eased = 1 - math.pow(1 - progress, 2.2).toDouble();
    final sweepAngle = eased * turns * 2 * math.pi - math.pi / 2;

    // Static rings and crosshair.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.28);
    for (final fraction in const [0.34, 0.58, 0.82]) {
      canvas.drawCircle(center, maxRadius * fraction, ringPaint);
    }
    canvas.drawLine(
      Offset(center.dx - maxRadius * 0.82, center.dy),
      Offset(center.dx + maxRadius * 0.82, center.dy),
      Paint()
      ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.14),
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius * 0.82),
      Offset(center.dx, center.dy + maxRadius * 0.82),
      Paint()
      ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.14),
    );

    // Filled sweep cone: a full-circle shader that is transparent except for
    // the trailing quadrant behind the leading edge.
    final sweepRadius = maxRadius * 0.82;
    final sweepRect = Rect.fromCircle(center: center, radius: sweepRadius);
    final conePaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.32),
        ],
        stops: const [0, 0.62, 0.88, 1],
        transform: GradientRotation(sweepAngle),
      ).createShader(sweepRect);
    canvas.drawCircle(center, sweepRadius, conePaint);

    // Bright leading edge.
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * sweepRadius,
      Paint()
      ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9),
    );

    // Blips glow as the sweep passes them, then fade until the next pass.
    final normalizedSweep = (eased * turns) % 1.0;
    for (final blip in blips) {
      final blipTurns = blip.angle / (2 * math.pi);
      // Not reached yet by the leading edge: keep it dark.
      if (eased * turns < blipTurns) continue;
      var sincePass = normalizedSweep - blipTurns;
      if (sincePass < 0) sincePass += 1;
      final alpha = math.max(0.0, 1 - sincePass) * 0.95;
      final blipCenter = center +
          Offset(
            math.sin(blip.angle),
            -math.cos(blip.angle),
          ) *
              (maxRadius * blip.radius);
      // Expanding ping ring right after the pass.
      if (alpha > 0.15) {
        canvas.drawCircle(
          blipCenter,
          3 + (1 - alpha) * 16,
          Paint()
          ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = color.withValues(alpha: alpha * 0.5),
        );
      }
      canvas.drawCircle(blipCenter, 3.4, Paint()
        ..color = color.withValues(alpha: 0.35 + alpha * 0.65));
    }

    // Center hub.
    canvas.drawCircle(center, 4, Paint()..color = color);
    canvas.drawCircle(
      center,
      8 + progress * 4,
      Paint()
      ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: (1 - progress) * 0.5),
    );
  }

  @override
  bool shouldRepaint(_SplashRadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
