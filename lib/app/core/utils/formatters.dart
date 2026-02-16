class Formatters {
  static String formatRemaining(double secs) {
    if (secs.isNaN || secs.isInfinite) return '00:00';
    if (secs < 0) secs = 0;
    final totalSeconds = secs.round();
    final mins = totalSeconds ~/ 60;
    final secInt = totalSeconds % 60;

    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(mins)}:${two(secInt)}';
  }

  static String formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
