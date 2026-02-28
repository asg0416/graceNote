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

class ProfileCardSkeleton extends StatelessWidget {
  const ProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          AppSkeleton(
            width: 60,
            height: 60,
            borderRadius: BorderRadius.circular(30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeleton(width: 120, height: 24),
                const SizedBox(height: 8),
                const AppSkeleton(width: 80, height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MemberListSkeleton extends StatelessWidget {
  final int count;
  const MemberListSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              AppSkeleton(
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSkeleton(width: 80, height: 20),
                    const SizedBox(height: 8),
                    const AppSkeleton(width: 120, height: 14),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const AppSkeleton(width: 60, height: 32, borderRadius: BorderRadius.all(Radius.circular(16))),
            ],
          ),
        );
      },
    );
  }
}
