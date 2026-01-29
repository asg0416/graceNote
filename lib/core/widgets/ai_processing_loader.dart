import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:grace_note/core/theme/app_theme.dart';

class AIProcessingLoader extends StatefulWidget {
  final double size;
  final String? message;

  const AIProcessingLoader({
    super.key,
    this.size = 120,
    this.message,
  });

  @override
  State<AIProcessingLoader> createState() => _AIProcessingLoaderState();
}

class _AIProcessingLoaderState extends State<AIProcessingLoader> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _rotationController]),
            builder: (context, child) {
              return CustomPaint(
                painter: _AILoaderPainter(
                  pulseValue: _pulseController.value,
                  rotationValue: _rotationController.value,
                  color: AppTheme.primaryViolet,
                ),
              );
            },
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 24),
          Text(
            widget.message!,
            style: const TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: -0.5,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ],
    );
  }
}

class _AILoaderPainter extends CustomPainter {
  final double pulseValue;
  final double rotationValue;
  final Color color;

  _AILoaderPainter({
    required this.pulseValue,
    required this.rotationValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 4;

    // 1. Outer Soft Glow (Pulsing Layer)
    final glowPaint = Paint()
      ..color = color.withOpacity(0.1 + (0.1 * pulseValue))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, baseRadius * (1.5 + 0.3 * pulseValue), glowPaint);

    // 2. Liquid Blobs (Moving Layers)
    for (int i = 0; i < 3; i++) {
      final layerPaint = Paint()
        ..color = color.withOpacity(0.3 - (i * 0.05))
        ..style = PaintingStyle.fill;
      
      final angle = (rotationValue * 2 * math.pi) + (i * math.pi * 0.6);
      final offset = Offset(
        math.cos(angle) * (10 * pulseValue),
        math.sin(angle * 1.5) * (10 * pulseValue),
      );

      final blobRadius = baseRadius * (1.0 + 0.1 * math.sin(angle + pulseValue * 2));
      canvas.drawCircle(center + offset, blobRadius, layerPaint);
    }

    // 3. Core Solid Circle
    final corePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final coreRadius = baseRadius * (0.9 + 0.1 * math.sin(pulseValue * math.pi));
    canvas.drawCircle(center, coreRadius, corePaint);

    // 4. Subtle Glossy Highlight
    final glossPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center + Offset(-coreRadius * 0.3, -coreRadius * 0.3),
      coreRadius * 0.2,
      glossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AILoaderPainter oldDelegate) => true;
}
