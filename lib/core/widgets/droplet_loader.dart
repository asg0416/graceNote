import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:grace_note/core/theme/app_theme.dart';

class DropletLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const DropletLoader({
    super.key,
    this.size = 80,
    this.color,
  });

  @override
  State<DropletLoader> createState() => _DropletLoaderState();
}

class _DropletLoaderState extends State<DropletLoader> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.primaryIndigo;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _rotationController]),
        builder: (context, child) {
          return CustomPaint(
            painter: _DropletPainter(
              animationValue: _mainController.value,
              rotationValue: _rotationController.value,
              color: color,
            ),
          );
        },
      ),
    );
  }
}

class _DropletPainter extends CustomPainter {
  final double animationValue;
  final double rotationValue;
  final Color color;

  _DropletPainter({
    required this.animationValue,
    required this.rotationValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Create a "metaball" or "droplet" effect by drawing multiple blobs
    // and slightly shifting them based on animation
    
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationValue * 2 * math.pi);

    for (int i = 0; i < 3; i++) {
      final phase = (animationValue + i / 3) % 1.0;
      final distance = radius * 0.2 * math.sin(phase * 2 * math.pi);
      final blobRadius = radius * (0.8 + 0.2 * math.cos(phase * 2 * math.pi));
      
      final angle = i * 2 * math.pi / 3;
      final offset = Offset(
        distance * math.cos(angle),
        distance * math.sin(angle),
      );

      canvas.drawCircle(offset, blobRadius, Paint()
        ..color = color.withOpacity(0.6 - i * 0.15)
        ..style = PaintingStyle.fill);
    }
    
    // Core pulsating circle
    final coreRadius = radius * (1.0 + 0.1 * math.sin(animationValue * 2 * math.pi));
    canvas.drawCircle(Offset.zero, coreRadius, paint);

    canvas.restore();
    
    // Add some subtle gloss
    final glossPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      center + Offset(-radius * 0.3, -radius * 0.3),
      radius * 0.2,
      glossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DropletPainter oldDelegate) => true;
}
