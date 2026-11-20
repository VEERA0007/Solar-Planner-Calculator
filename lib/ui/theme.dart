import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Colour tokens. Call [C.apply] when the day/night mode changes; the root
/// widget rebuilds so every screen picks the new values up.
class C {
  static bool dark = true;
  static Color bg = const Color(0xFF050A18);
  static Color card = const Color(0xFF0A1224);
  static Color card2 = const Color(0xFF0E182E);
  static Color chip = const Color(0xFF131C31);
  static Color line = const Color(0xFF1B2742);
  static Color text = const Color(0xFFF1F5F9);
  static Color mute = const Color(0xFF94A3B8);
  static Color blue = const Color(0xFF0A84FF);
  static Color sky = const Color(0xFF22B8FF);
  static Color amber = const Color(0xFFFBA10F);
  static Color sun = const Color(0xFFFBBF24);
  static Color green = const Color(0xFF22D39A);
  static Color red = const Color(0xFFF87171);
  static Color purple = const Color(0xFFA78BFA);
  static Color orange = const Color(0xFFFB8A2E);
  static Color nav = const Color(0xFF080F1F);
  // pastel icon chips (background, foreground)
  static Color chipSun = const Color(0xFF2A1F12);
  static Color chipBlue = const Color(0xFF0D2238);
  static Color chipPurple = const Color(0xFF221941);
  static Color chipGreen = const Color(0xFF0C2A24);

  static void apply(bool isDark) {
    dark = isDark;
    if (isDark) {
      bg = const Color(0xFF050A18);
      card = const Color(0xFF0A1224);
      card2 = const Color(0xFF0E182E);
      chip = const Color(0xFF131C31);
      line = const Color(0xFF1B2742);
      text = const Color(0xFFF1F5F9);
      mute = const Color(0xFF94A3B8);
      blue = const Color(0xFF0A84FF);
      sky = const Color(0xFF22B8FF);
      amber = const Color(0xFFFBA10F);
      green = const Color(0xFF22D39A);
      red = const Color(0xFFF87171);
      purple = const Color(0xFFA78BFA);
      nav = const Color(0xFF080F1F);
      chipSun = const Color(0xFF2A1F12);
      chipBlue = const Color(0xFF0D2238);
      chipPurple = const Color(0xFF221941);
      chipGreen = const Color(0xFF0C2A24);
    } else {
      bg = const Color(0xFFF6F8FC);
      card = const Color(0xFFFFFFFF);
      card2 = const Color(0xFFF1F5FB);
      chip = const Color(0xFFEFF3FA);
      line = const Color(0xFFE3E9F3);
      text = const Color(0xFF0F172A);
      mute = const Color(0xFF64748B);
      blue = const Color(0xFF0A74E8);
      sky = const Color(0xFF0B8FD6);
      amber = const Color(0xFFE08A00);
      green = const Color(0xFF0E9F6E);
      red = const Color(0xFFDC2626);
      purple = const Color(0xFF7C3AED);
      nav = const Color(0xFFFFFFFF);
      chipSun = const Color(0xFFFFF1D6);
      chipBlue = const Color(0xFFDDEEFF);
      chipPurple = const Color(0xFFEBE4FF);
      chipGreen = const Color(0xFFD9F5EA);
    }
  }
}

const List<String> kMono = ['Consolas', 'Menlo', 'Roboto Mono', 'monospace'];

/// Text scale chosen from the device's screen size, so no manual control is
/// needed. The system accessibility scale is only allowed a small nudge.
double autoTextScale(MediaQueryData mq) {
  final w = mq.size.shortestSide;
  final base = w < 340 ? 0.88 : w < 380 ? 0.94 : w < 440 ? 1.0 : w < 600 ? 1.05 : w < 840 ? 1.12 : 1.2;
  final sys = mq.textScaler.scale(10) / 10;
  return base * sys.clamp(0.92, 1.1);
}

ThemeData buildTheme(bool dark) {
  C.apply(dark);
  final b = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: C.blue, brightness: b).copyWith(
    surface: C.bg,
    primary: C.blue,
  );
  OutlineInputBorder ob(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    dialogTheme: DialogThemeData(backgroundColor: C.card, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(C.line),
      enabledBorder: ob(C.line),
      focusedBorder: ob(C.amber, 2),
      labelStyle: TextStyle(color: C.mute),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.nav,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.chipBlue,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? C.blue : C.mute,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.blue : C.mute)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Rounded card used across all screens.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? border;
  final VoidCallback? onTap;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 22, this.border, this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? C.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

class PageHead extends StatelessWidget {
  final String title, subtitle;
  const PageHead(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: C.mute, fontSize: 13.5)),
        ]),
      );
}

class StatTile extends StatelessWidget {
  final String label, value;
  final bool hi;
  const StatTile(this.label, this.value, {super.key, this.hi = false});
  @override
  Widget build(BuildContext context) => Panel(
        radius: 16,
        padding: const EdgeInsets.all(12),
        border: hi ? C.amber : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: C.mute, fontSize: 12)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Two-column grid of stat tiles that adapts to content height.
class StatGrid extends StatelessWidget {
  final List<Widget> tiles;
  const StatGrid(this.tiles, {super.key});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

// ---------------- charts ----------------

class BarSeries {
  final String name;
  final List<double> data;
  final Color color;
  const BarSeries(this.name, this.data, this.color);
}

class BarChart extends StatelessWidget {
  final List<BarSeries> series;
  final List<String?> labels;
  final int highlight;
  final double height;
  const BarChart({super.key, required this.series, required this.labels, this.highlight = -1, this.height = 170});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _BarPainter(series, labels, highlight)));
}

class _BarPainter extends CustomPainter {
  final List<BarSeries> series;
  final List<String?> labels;
  final int highlight;
  _BarPainter(this.series, this.labels, this.highlight);

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 20.0, top = 8.0;
    final n = series.first.data.length;
    final maxV = math.max(0.001, series.expand((s) => s.data).fold<double>(0.0, (a, b) => a > b ? a : b));
    final gw = size.width / n;
    final bw = math.max(1.0, gw / series.length - 2);
    final plotH = size.height - bottom - top;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < series.length; j++) {
        final v = series[j].data[i];
        final h = (v / maxV) * plotH;
        final dim = highlight >= 0 && highlight != i;
        final paint = Paint()..color = series[j].color.withValues(alpha: dim ? 0.55 : 1);
        final x = i * gw + j * (bw + 1) + 1;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - bottom - h, bw, math.max(0, h)), const Radius.circular(2)),
          paint,
        );
      }
      final l = i < labels.length ? labels[i] : null;
      if (l != null) {
        final tp = TextPainter(
          text: TextSpan(text: l, style: const TextStyle(color: Color(0xFF7C8AA8), fontSize: 10.5)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * gw + gw / 2 - tp.width / 2, size.height - bottom + 5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

/// Cumulative net savings: red below zero, green above.
class NetChart extends StatelessWidget {
  final List<double> values;
  const NetChart(this.values, {super.key});
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 190, width: double.infinity, child: CustomPaint(painter: _NetPainter(values)));
}

class _NetPainter extends CustomPainter {
  final List<double> v;
  _NetPainter(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    const top = 10.0, bottom = 22.0;
    final maxV = math.max(1.0, v.fold<double>(0.0, (a, b) => a > b ? a : b));
    final minV = math.min(0.0, v.fold<double>(0.0, (a, b) => a < b ? a : b));
    double y(double val) => top + (1 - (val - minV) / (maxV - minV)) * (size.height - top - bottom);
    final bw = size.width / v.length;
    final zero = y(0);
    for (var i = 0; i < v.length; i++) {
      final a = y(math.max(0, v[i])), b = y(math.min(0, v[i]));
      final paint = Paint()..color = v[i] >= 0 ? C.green : C.red;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * bw + 1, a, bw - 2, math.max(1, b - a)), const Radius.circular(2)),
        paint,
      );
    }
    canvas.drawLine(Offset(0, zero), Offset(size.width, zero), Paint()..color = const Color(0xFF475569));
    for (final n in {1, (v.length / 2).ceil(), v.length}) {
      final tp = TextPainter(
        text: TextSpan(text: 'Yr $n', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((n - 0.5) * bw - tp.width / 2, size.height - 16));
    }
  }

  @override
  bool shouldRepaint(covariant _NetPainter old) => true;
}
