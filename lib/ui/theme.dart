import 'dart:math' as math;
import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF050A18);
  static const card = Color(0xFF0A1224);
  static const card2 = Color(0xFF0E182E);
  static const line = Color(0xFF1B2742);
  static const text = Color(0xFFF1F5F9);
  static const mute = Color(0xFF94A3B8);
  static const blue = Color(0xFF0A84FF);
  static const sky = Color(0xFF22B8FF);
  static const amber = Color(0xFFFBA10F);
  static const sun = Color(0xFFFBBF24);
  static const green = Color(0xFF22D39A);
  static const red = Color(0xFFF87171);
  static const purple = Color(0xFFA78BFA);
}

const List<String> kMono = ['Consolas', 'Menlo', 'Roboto Mono', 'monospace'];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.blue, brightness: Brightness.dark).copyWith(
    surface: C.bg,
    primary: C.blue,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    dialogTheme: const DialogThemeData(backgroundColor: C.card),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.amber, width: 2)),
      labelStyle: const TextStyle(color: C.mute),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF080F1F),
      indicatorColor: const Color(0xFF0E2238),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? const Color(0xFF2EA8FF) : const Color(0xFF8391AD),
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? const Color(0xFF2EA8FF) : const Color(0xFF8391AD))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Rounded dark card used across all screens.
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
          Text(subtitle, style: const TextStyle(color: C.mute, fontSize: 13.5)),
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
          Text(label, style: const TextStyle(color: C.mute, fontSize: 12)),
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
