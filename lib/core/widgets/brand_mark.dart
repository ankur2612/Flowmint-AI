import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// FLOWMINT logo mark: three flowing strokes forming an abstract "F".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final paint = Paint()
      ..color = AppColors.onBrand
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.11;
    final left = w * 0.3;
    final stem = Path()
      ..moveTo(left, w * 0.72)
      ..lineTo(left, w * 0.36)
      ..quadraticBezierTo(left, w * 0.28, left + w * 0.08, w * 0.28)
      ..lineTo(w * 0.72, w * 0.28);
    canvas.drawPath(stem, paint);
    canvas.drawLine(Offset(left, w * 0.5), Offset(w * 0.6, w * 0.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.markSize = 32});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        SizedBox(width: markSize * 0.32),
        Text.rich(
          TextSpan(
            text: 'FLOWMINT',
            children: const [
              TextSpan(
                text: ' AI',
                style: TextStyle(color: AppColors.brand),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            letterSpacing: 1.6,
            fontSize: markSize * 0.5,
          ),
        ),
      ],
    );
  }
}
