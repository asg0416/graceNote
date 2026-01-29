import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ShadcnSpinner extends StatelessWidget {
  final double size;
  final Color? color;

  const ShadcnSpinner({
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color ?? AppTheme.primaryViolet),
        ),
      ),
    );
  }
}
