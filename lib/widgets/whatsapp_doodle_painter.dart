import 'package:flutter/material.dart';

class WhatsAppDoodleBackground extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const WhatsAppDoodleBackground({
    super.key,
    required this.child,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DoodlePainter(isDark: isDark),
      child: child,
    );
  }
}

class _DoodlePainter extends CustomPainter {
  final bool isDark;

  _DoodlePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF0B141B) : const Color(0xFFEFEAE2);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final iconPaint = Paint()
      ..color = isDark
          ? const Color(0xFF182229).withValues(alpha: 0.6)
          : const Color(0xFFD6CEBF).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    final double stepX = 75.0;
    final double stepY = 75.0;

    int rowIndex = 0;
    for (double y = 20; y < size.height + 40; y += stepY) {
      int colIndex = 0;
      double offsetX = (rowIndex % 2 == 1) ? stepX / 2 : 0;
      for (double x = -20 + offsetX; x < size.width + 40; x += stepX) {
        final shapeType = (rowIndex * 7 + colIndex) % 8;
        _drawDoodle(canvas, Offset(x, y), shapeType, iconPaint);
        colIndex++;
      }
      rowIndex++;
    }
  }

  void _drawDoodle(Canvas canvas, Offset pos, int type, Paint paint) {
    switch (type) {
      case 0:
        // Chat bubble doodle
        final rrect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: 22, height: 16),
          const Radius.circular(5),
        );
        canvas.drawRRect(rrect, paint);
        final path = Path()
          ..moveTo(pos.dx - 6, pos.dy + 8)
          ..lineTo(pos.dx - 10, pos.dy + 12)
          ..lineTo(pos.dx - 2, pos.dy + 8);
        canvas.drawPath(path, paint);
        break;

      case 1:
        // Camera doodle
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: 20, height: 14),
          const Radius.circular(3),
        );
        canvas.drawRRect(body, paint);
        canvas.drawCircle(pos, 4, paint);
        break;

      case 2:
        // Music note
        canvas.drawCircle(Offset(pos.dx - 4, pos.dy + 4), 3, paint);
        canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 2), 3, paint);
        canvas.drawLine(Offset(pos.dx - 1, pos.dy + 4), Offset(pos.dx - 1, pos.dy - 6), paint);
        canvas.drawLine(Offset(pos.dx + 7, pos.dy + 2), Offset(pos.dx + 7, pos.dy - 8), paint);
        canvas.drawLine(Offset(pos.dx - 1, pos.dy - 6), Offset(pos.dx + 7, pos.dy - 8), paint);
        break;

      case 3:
        // Clock / timer
        canvas.drawCircle(pos, 8, paint);
        canvas.drawLine(pos, Offset(pos.dx, pos.dy - 4), paint);
        canvas.drawLine(pos, Offset(pos.dx + 3, pos.dy), paint);
        break;

      case 4:
        // Star
        canvas.drawLine(Offset(pos.dx, pos.dy - 7), Offset(pos.dx, pos.dy + 7), paint);
        canvas.drawLine(Offset(pos.dx - 7, pos.dy), Offset(pos.dx + 7, pos.dy), paint);
        canvas.drawLine(Offset(pos.dx - 5, pos.dy - 5), Offset(pos.dx + 5, pos.dy + 5), paint);
        canvas.drawLine(Offset(pos.dx - 5, pos.dy + 5), Offset(pos.dx + 5, pos.dy - 5), paint);
        break;

      case 5:
        // Heart doodle
        final path = Path();
        path.moveTo(pos.dx, pos.dy + 6);
        path.cubicTo(pos.dx - 8, pos.dy + 1, pos.dx - 8, pos.dy - 6, pos.dx, pos.dy - 3);
        path.cubicTo(pos.dx + 8, pos.dy - 6, pos.dx + 8, pos.dy + 1, pos.dx, pos.dy + 6);
        canvas.drawPath(path, paint);
        break;

      case 6:
        // Coffee cup doodle
        final cup = RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: 14, height: 12),
          const Radius.circular(3),
        );
        canvas.drawRRect(cup, paint);
        final handle = Path()
          ..addArc(Rect.fromLTWH(pos.dx + 7, pos.dy - 5, 6, 8), -1.5, 3.14);
        canvas.drawPath(handle, paint);
        break;

      case 7:
        // Smiley doodle
        canvas.drawCircle(pos, 8, paint);
        canvas.drawCircle(Offset(pos.dx - 3, pos.dy - 2), 1, paint);
        canvas.drawCircle(Offset(pos.dx + 3, pos.dy - 2), 1, paint);
        final smile = Path()
          ..addArc(Rect.fromCenter(center: Offset(pos.dx, pos.dy + 1), width: 8, height: 6), 0.2, 2.7);
        canvas.drawPath(smile, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
