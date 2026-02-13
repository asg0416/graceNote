import 'package:flutter/material.dart';

class AppSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? color;
  final EdgeInsets? margin; // [NEW] margin support

  const AppSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.color,
    this.margin,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            margin: widget.margin, // [NEW]
            decoration: BoxDecoration(
              color: widget.color ?? const Color(0xFFF1F5F9),
              borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}
