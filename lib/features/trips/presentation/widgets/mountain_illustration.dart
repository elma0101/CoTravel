import 'package:flutter/material.dart';

/// The cover for trips without a photo: hills, a sun, and sand, as in the mockups.
class MountainIllustration extends StatelessWidget {
  const MountainIllustration({this.height = 148, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: const ExcludeSemantics(
        child: CustomPaint(painter: _MountainPainter()),
      ),
    );
  }
}

class _MountainPainter extends CustomPainter {
  const _MountainPainter();

  static const _sky = Color(0xFFC9D8D3);
  static const _sun = Color(0xFFE7B566);
  static const _farHills = Color(0xFF7F9C8E);
  static const _nearHills = Color(0xFF47705F);
  static const _sand = Color(0xFFDDB893);

  Path _hills(Size size, double base, List<Offset> peaks) {
    final path = Path()..moveTo(0, base);
    for (final peak in peaks) {
      path.lineTo(peak.dx * size.width, peak.dy * size.height);
    }
    return path
      ..lineTo(size.width, base)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.72;
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = _sky)
      ..drawCircle(
        Offset(size.width * 0.76, size.height * 0.24),
        size.height * 0.1,
        Paint()..color = _sun,
      )
      ..drawPath(
        _hills(size, horizon, const [
          Offset(0.14, 0.42),
          Offset(0.3, 0.58),
          Offset(0.46, 0.36),
          Offset(0.62, 0.54),
          Offset(0.86, 0.4),
        ]),
        Paint()..color = _farHills,
      )
      ..drawPath(
        _hills(size, horizon, const [
          Offset(0.26, 0.6),
          Offset(0.42, 0.64),
          Offset(0.7, 0.34),
          Offset(0.92, 0.58),
        ]),
        Paint()..color = _nearHills,
      )
      ..drawRect(
        Rect.fromLTRB(0, horizon, size.width, size.height),
        Paint()..color = _sand,
      );
  }

  @override
  bool shouldRepaint(_MountainPainter oldDelegate) => false;
}
