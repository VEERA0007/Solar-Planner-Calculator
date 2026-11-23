import 'dart:math' as math;

/// A point in metres on a flat plane around the first traced corner.
class Pt {
  final double x, y;
  const Pt(this.x, this.y);
}

/// Converts traced corners (lat, lon) to metres and back. Good to a few cm over a roof.
class RoofProjection {
  final double lat0, lon0;
  RoofProjection(this.lat0, this.lon0);
  double get _mx => 111320 * math.cos(lat0 * math.pi / 180);
  Pt toLocal(double lat, double lon) => Pt((lon - lon0) * _mx, (lat - lat0) * 110540);
  (double, double) toLatLon(Pt p) => (lat0 + p.y / 110540, lon0 + p.x / _mx);
}

double polygonArea(List<Pt> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].x * p[j].y - p[j].x * p[i].y;
  }
  return a.abs() / 2;
}

double polygonPerimeter(List<Pt> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    s += math.sqrt(math.pow(p[j].x - p[i].x, 2) + math.pow(p[j].y - p[i].y, 2));
  }
  return s;
}

bool pointInPolygon(Pt q, List<Pt> p) {
  var inside = false;
  for (var i = 0, j = p.length - 1; i < p.length; j = i++) {
    final a = p[i], b = p[j];
    if ((a.y > q.y) != (b.y > q.y) && q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}

double _distToSegment(Pt q, Pt a, Pt b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((q.x - a.x) * dx + (q.y - a.y) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final px = a.x + t * dx, py = a.y + t * dy;
  return math.sqrt(math.pow(q.x - px, 2) + math.pow(q.y - py, 2));
}

double distToPolygonEdge(Pt q, List<Pt> p) {
  var d = double.infinity;
  for (var i = 0; i < p.length; i++) {
    d = math.min(d, _distToSegment(q, p[i], p[(i + 1) % p.length]));
  }
  return d;
}

Pt _rot(Pt p, double a) => Pt(p.x * math.cos(a) - p.y * math.sin(a), p.x * math.sin(a) + p.y * math.cos(a));

/// Panels placed inside a roof outline.
class RoofLayout {
  final double areaM2;
  final List<List<Pt>> panels; // four corners each, in the roof's metre plane
  final bool landscape;
  const RoofLayout(this.areaM2, this.panels, this.landscape);
  int get count => panels.length;
}

/// Packs panels of [longMm] x [shortMm] in rows along the roof's longest edge.
/// [orientation]: 0 auto (best of both), 1 portrait, 2 landscape.
RoofLayout layoutPanels(
  List<Pt> roof, {
  required double longMm,
  required double shortMm,
  double gapMm = 25,
  double rowGapMm = 450,
  double setbackMm = 500,
  int orientation = 0,
}) {
  final area = polygonArea(roof);
  if (roof.length < 3 || area < 1) return RoofLayout(area, const [], true);
  // align the grid with the longest edge
  var best = 0.0, ang = 0.0;
  for (var i = 0; i < roof.length; i++) {
    final b = roof[(i + 1) % roof.length];
    final l = math.sqrt(math.pow(b.x - roof[i].x, 2) + math.pow(b.y - roof[i].y, 2));
    if (l > best) {
      best = l;
      ang = math.atan2(b.y - roof[i].y, b.x - roof[i].x);
    }
  }
  final aligned = [for (final p in roof) _rot(p, -ang)];
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final p in aligned) {
    minX = math.min(minX, p.x);
    minY = math.min(minY, p.y);
    maxX = math.max(maxX, p.x);
    maxY = math.max(maxY, p.y);
  }
  final setback = setbackMm / 1000;

  List<List<Pt>> run(bool landscape) {
    final w = (landscape ? longMm : shortMm) / 1000, h = (landscape ? shortMm : longMm) / 1000;
    final sx = w + gapMm / 1000, sy = h + rowGapMm / 1000;
    final out = <List<Pt>>[];
    for (var y = minY + setback; y + h <= maxY - setback + 1e-9; y += sy) {
      for (var x = minX + setback; x + w <= maxX - setback + 1e-9; x += sx) {
        final c = [Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)];
        var ok = true;
        for (final q in c) {
          if (!pointInPolygon(q, aligned) || distToPolygonEdge(q, aligned) < setback - 1e-9) {
            ok = false;
            break;
          }
        }
        if (ok) out.add([for (final q in c) _rot(q, ang)]);
      }
    }
    return out;
  }

  final land = orientation == 1 ? <List<Pt>>[] : run(true);
  final port = orientation == 2 ? <List<Pt>>[] : run(false);
  final useLand = orientation == 2 || (orientation == 0 && land.length >= port.length);
  return RoofLayout(area, useLand ? land : port, useLand);
}

/// A minimal ASCII DXF (R12) with the roof outline and the panels, in metres.
String roofDxf(List<Pt> roof, RoofLayout layout) {
  final b = StringBuffer('0\nSECTION\n2\nENTITIES\n');
  void line(String layer, Pt a, Pt c) {
    b.write('0\nLINE\n8\n$layer\n10\n${a.x.toStringAsFixed(4)}\n20\n${a.y.toStringAsFixed(4)}\n30\n0.0\n11\n${c.x.toStringAsFixed(4)}\n21\n${c.y.toStringAsFixed(4)}\n31\n0.0\n');
  }

  for (var i = 0; i < roof.length; i++) {
    line('ROOF_BOUNDARY', roof[i], roof[(i + 1) % roof.length]);
  }
  for (final p in layout.panels) {
    for (var i = 0; i < 4; i++) {
      line('PANELS', p[i], p[(i + 1) % 4]);
    }
  }
  b.write('0\nENDSEC\n0\nEOF\n');
  return b.toString();
}
