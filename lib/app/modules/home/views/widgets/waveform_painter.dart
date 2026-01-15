import 'dart:math';
import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double progress;

  WaveformPainter({
    required this.data,
    required this.color,
    this.progress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final playedPaint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    // Draw background/unplayed waveform
    _drawWave(canvas, size, paint, data);

    // Draw played portion overlay (optional, or just color difference)
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      _drawWave(canvas, size, playedPaint, data);
      canvas.restore();
    }
  }

  void _drawWave(Canvas canvas, Size size, Paint paint, List<double> waveData) {
    final width = size.width;
    final height = size.height;
    final center = height / 2;

    // We want to draw mirrored waveform
    final count = waveData.length;
    final step = width / count;

    for (int i = 0; i < count; i++) {
      final val = waveData[i];
      final x = i * step;
      // Amplitude scaling: max height is half container
      final amp = val * (height * 0.4);

      // Draw bar (or line)
      // canvas.drawLine(Offset(x, center - amp), Offset(x, center + amp), paint);

      // Rounded rect for cleaner look
      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + step / 2, center),
          width: step * 0.8,
          height: max(2.0, amp * 2),
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.progress != progress;
  }
}
