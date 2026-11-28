import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'solar_analysis_engine.dart';

// ============================================================================
// 1. 2D AUTOCAD BLUEPRINT & SATELLITE CAD OVERLAY PAINTER (STEP 3)
// ============================================================================
class RoofCad2DPainter extends CustomPainter {
  final bool satelliteMode;
  final double roofLenM, roofWidM, setbackM, mmsClearanceM;
  final double sunAlt, sunAz;
  final List<RoofObstacle> obstacles;
  final List<PvZone> zones;
  final bool isDark;

  RoofCad2DPainter({
    required this.satelliteMode,
    required this.roofLenM,
    required this.roofWidM,
    required this.setbackM,
    required this.mmsClearanceM,
    required this.sunAlt,
    required this.sunAz,
    required this.obstacles,
    required this.zones,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxSpan = math.max(roofLenM, roofWidM) + 6.5;
    final scale = (math.min(size.width, size.height) - 42) / maxSpan;
    Offset w2c(double xM, double yM) => Offset(c.dx + xM * scale, c.dy - yM * scale);

    // Background: AutoCAD Blueprint Grid vs Satellite Dark Terrain
    if (satelliteMode) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF14211D),
      );
      final texPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1;
      for (var i = 0.0; i < size.width; i += 28) {
        canvas.drawLine(Offset(i, 0), Offset(i, size.height), texPaint);
      }
      for (var j = 0.0; j < size.height; j += 28) {
        canvas.drawLine(Offset(0, j), Offset(size.width, j), texPaint);
      }
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = isDark ? const Color(0xFF0A1428) : const Color(0xFFF0F6FF),
      );
      final gridPaint = Paint()
        ..color = (isDark ? const Color(0xFF38BDF8) : const Color(0xFF1D4ED8)).withValues(alpha: 0.09)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 20) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (var y = 0.0; y < size.height; y += 20) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Host Roof Slab Footprint
    final roofRect = Rect.fromCenter(center: c, width: roofLenM * scale, height: roofWidM * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(3)),
      Paint()
        ..color = satelliteMode
            ? const Color(0xFF475569).withValues(alpha: 0.85)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(3)),
      Paint()
        ..color = satelliteMode ? const Color(0xFF10B981) : const Color(0xFF0EA5E9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // CAD Dimension Callout Lines (Length top, Width right)
    _drawDimLabel(canvas, '${roofLenM.toStringAsFixed(1)} m', Offset(c.dx, roofRect.top - 11), isDark || satelliteMode);
    _drawDimLabel(canvas, '${roofWidM.toStringAsFixed(1)} m', Offset(roofRect.right + 20, c.dy), isDark || satelliteMode);

    // Usable Setback Boundary + PV Zones
    final usableW = math.max(0.0, (roofLenM - setbackM * 2) * scale);
    final usableH = math.max(0.0, (roofWidM - setbackM * 2) * scale);
    if (usableW > 10 && usableH > 10) {
      final usableRect = Rect.fromCenter(center: c, width: usableW, height: usableH);
      canvas.drawRect(
        usableRect,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      final activeZones = zones.where((z) => z.enabled).toList();
      final listToDraw = activeZones.isEmpty
          ? [const PvZone(id: 'default', name: 'Zone A', xFrac: 0, yFrac: 0, wFrac: 1, hFrac: 1)]
          : activeZones;

      final panelFill = Paint()..color = const Color(0xFF1D4ED8).withValues(alpha: 0.82);
      final panelStroke = Paint()
        ..color = const Color(0xFF93C5FD).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      for (final z in listToDraw) {
        final zr = Rect.fromLTWH(
          usableRect.left + z.xFrac * usableRect.width,
          usableRect.top + z.yFrac * usableRect.height,
          z.wFrac * usableRect.width,
          z.hFrac * usableRect.height,
        );
        final zoneCols = math.max(1, ((roofLenM - setbackM * 2) * z.wFrac / 1.22).floor());
        final zoneRows = math.max(1, ((roofWidM - setbackM * 2) * z.hFrac / 2.35).floor());
        final cw = zr.width / zoneCols;
        final ch = zr.height / zoneRows;

        for (var r = 0; r < zoneRows; r++) {
          for (var col = 0; col < zoneCols; col++) {
            final pr = Rect.fromLTWH(
              zr.left + col * cw + 1.2,
              zr.top + r * ch + 2.0,
              math.max(2, cw - 2.4),
              math.max(2, ch - 4.0),
            );
            canvas.drawRect(pr, panelFill);
            canvas.drawRect(pr, panelStroke);
          }
        }
        canvas.drawRect(
          zr,
          Paint()
            ..color = const Color(0xFF10B981)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        // Zone tag badge
        final tp = TextPainter(
          text: TextSpan(
            text: z.name,
            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final badge = Rect.fromLTWH(zr.left + 3, zr.top + 3, tp.width + 8, tp.height + 3);
        canvas.drawRRect(RRect.fromRectAndRadius(badge, const Radius.circular(4)), Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.78));
        tp.paint(canvas, Offset(badge.left + 4, badge.top + 1.5));
      }
    }

    // Cast Shadows from Verified Obstacles
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final dx = math.sin(shAzRad);
    final dy = math.cos(shAzRad);

    for (final obs in obstacles) {
      final bRad = obs.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * obs.distM;
      final oy = math.cos(bRad) * obs.distM;
      final effH = math.max(0.0, obs.heightM - mmsClearanceM);

      if (sunAlt > 1.5 && effH > 0.05) {
        final shLen = (effH / math.tan(sunAlt * math.pi / 180.0)).clamp(0.0, 30.0).toDouble();
        final px = -dy * (obs.widthM / 2.0);
        final py = dx * (obs.widthM / 2.0);
        final p1 = w2c(ox + px, oy + py);
        final p2 = w2c(ox - px, oy - py);
        final p3 = w2c(ox - px + dx * shLen, oy - py + dy * shLen);
        final p4 = w2c(ox + px + dx * shLen, oy + py + dy * shLen);
        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..lineTo(p4.dx, p4.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFF020617).withValues(alpha: 0.56));
      }

      final oPt = w2c(ox, oy);
      final radPx = (obs.widthM * scale / 2).clamp(5.0, 20.0).toDouble();
      if (obs.type == 'tree') {
        canvas.drawCircle(oPt, radPx, Paint()..color = const Color(0xFF16A34A));
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: oPt, width: radPx * 1.8, height: radPx * 1.3), const Radius.circular(3)),
          Paint()..color = obs.fromOsm ? const Color(0xFF7C3AED) : const Color(0xFFEF4444),
        );
      }
    }

    // Live Sun Direction Indicator
    if (sunAlt > 0) {
      final sRad = (sunAz - 90.0) * math.pi / 180.0;
      final rayR = math.min(size.width, size.height) * 0.43;
      final sunPt = Offset(c.dx + math.cos(sRad) * rayR, c.dy + math.sin(sRad) * rayR);
      canvas.drawLine(
        sunPt,
        c,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.48)
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(sunPt, 11, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.28));
      canvas.drawCircle(sunPt, 6, Paint()..color = const Color(0xFFF59E0B));
    }

    _drawNorthBadge(canvas, const Offset(22, 22), isDark || satelliteMode);
  }

  void _drawDimLabel(Canvas canvas, String text, Offset pos, bool lightText) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: lightText ? const Color(0xFF93C5FD) : const Color(0xFF1E3A8A),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant RoofCad2DPainter old) => true;
}

// ============================================================================
// 2. ROTATABLE 3D BUILDING + MMS FRAME + HEATMAP + 360° TOUR PAINTER (STEPS 4, 5, 6)
// ============================================================================
class Building3DShadowPainter extends CustomPainter {
  final bool wireframe;
  final bool showHeatmapOverlay;
  final List<List<double>>? heatmapGrid;
  final String assemblyLayer; // building_only | structure_only | structure_and_panels
  final double orbitYawDeg; // 0..360 camera azimuth
  final double cameraPitchDeg; // 20..75 tilt
  final double roofLenM, roofWidM, buildingHeightM, parapetHeightM, setbackM, mmsClearanceM, tiltDeg;
  final bool crossBracing;
  final double sunAlt, sunAz;
  final List<RoofObstacle> obstacles;
  final bool isDark;

  Building3DShadowPainter({
    required this.wireframe,
    required this.showHeatmapOverlay,
    this.heatmapGrid,
    required this.assemblyLayer,
    required this.orbitYawDeg,
    required this.cameraPitchDeg,
    required this.roofLenM,
    required this.roofWidM,
    required this.buildingHeightM,
    required this.parapetHeightM,
    required this.setbackM,
    required this.mmsClearanceM,
    required this.tiltDeg,
    required this.crossBracing,
    required this.sunAlt,
    required this.sunAz,
    required this.obstacles,
    required this.isDark,
  });

  Color _heatColor(double t) {
    final v = t.clamp(0.0, 1.0).toDouble();
    if (v < 0.35) return Color.lerp(const Color(0xFF1E3A8A), const Color(0xFF0EA5E9), v / 0.35)!;
    if (v < 0.65) return Color.lerp(const Color(0xFF0EA5E9), const Color(0xFF10B981), (v - 0.35) / 0.30)!;
    if (v < 0.85) return Color.lerp(const Color(0xFF10B981), const Color(0xFFFACC15), (v - 0.65) / 0.20)!;
    return Color.lerp(const Color(0xFFFACC15), const Color(0xFFF97316), (v - 0.85) / 0.15)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.57);
    final maxSpan = math.max(roofLenM, roofWidM) + 6.5;
    final scale = (math.min(size.width, size.height) - 26) / (maxSpan * 1.28);

    final yawRad = orbitYawDeg * math.pi / 180.0;
    final pitchRad = cameraPitchDeg.clamp(18.0, 75.0).toDouble() * math.pi / 180.0;
    final cosY = math.cos(yawRad);
    final sinY = math.sin(yawRad);
    final sinP = math.sin(pitchRad);
    final cosP = math.cos(pitchRad);

    // True rotatable orthographic 3D projection: x=East, y=North, z=Up
    Offset proj(double xM, double yM, double zM) {
      final rx = xM * cosY - yM * sinY;
      final ry = xM * sinY + yM * cosY;
      final sx = rx * scale;
      final sy = (ry * sinP - zM * cosP) * scale;
      return Offset(c.dx + sx, c.dy + sy);
    }

    // Background sky/blueprint fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = wireframe
            ? const Color(0xFF06101F)
            : (isDark ? const Color(0xFF0B1325) : const Color(0xFFEFF6FF)),
    );

    // Ground reference plane grid
    final groundGrid = Paint()
      ..color = (wireframe ? const Color(0xFF38BDF8) : (isDark ? Colors.white : Colors.black)).withValues(alpha: wireframe ? 0.14 : 0.06)
      ..strokeWidth = 0.8;
    final bH = -(buildingHeightM.clamp(2.5, 9.0).toDouble() * 0.45);
    final gHalf = maxSpan * 0.55;
    for (var g = -gHalf; g <= gHalf; g += 3.0) {
      canvas.drawLine(proj(g, -gHalf, bH), proj(g, gHalf, bH), groundGrid);
      canvas.drawLine(proj(-gHalf, g, bH), proj(gHalf, g, bH), groundGrid);
    }

    // Extruded Host Building Box
    final hl = roofLenM / 2;
    final hw = roofWidM / 2;
    final topPts = [proj(-hl, -hw, 0), proj(hl, -hw, 0), proj(hl, hw, 0), proj(-hl, hw, 0)];
    final botPts = [proj(-hl, -hw, bH), proj(hl, -hw, bH), proj(hl, hw, bH), proj(-hl, hw, bH)];

    // Draw 4 side walls
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      final wall = Path()
        ..moveTo(topPts[i].dx, topPts[i].dy)
        ..lineTo(topPts[j].dx, topPts[j].dy)
        ..lineTo(botPts[j].dx, botPts[j].dy)
        ..lineTo(botPts[i].dx, botPts[i].dy)
        ..close();
      if (!wireframe) {
        canvas.drawPath(
          wall,
          Paint()
            ..color = i.isEven
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1))
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
        );
      }
      canvas.drawPath(
        wall,
        Paint()
          ..color = wireframe ? const Color(0xFF38BDF8).withValues(alpha: 0.65) : const Color(0xFF475569).withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = wireframe ? 1.1 : 0.8,
      );
    }

    // Roof Slab Top
    final roofPath = Path()
      ..moveTo(topPts[0].dx, topPts[0].dy)
      ..lineTo(topPts[1].dx, topPts[1].dy)
      ..lineTo(topPts[2].dx, topPts[2].dy)
      ..lineTo(topPts[3].dx, topPts[3].dy)
      ..close();
    if (!wireframe) {
      canvas.drawPath(roofPath, Paint()..color = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    }
    canvas.drawPath(
      roofPath,
      Paint()
        ..color = wireframe ? const Color(0xFF38BDF8) : const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Optional 3D Roof Sunlight Heatmap Overlay
    if (showHeatmapOverlay && !wireframe && heatmapGrid != null && heatmapGrid!.isNotEmpty) {
      final rows = heatmapGrid!.length;
      final cols = heatmapGrid!.first.length;
      final cellL = roofLenM / cols;
      final cellW = roofWidM / rows;
      for (var r = 0; r < rows; r++) {
        for (var col = 0; col < cols; col++) {
          final x0 = -hl + col * cellL;
          final x1 = x0 + cellL;
          final y0 = hw - r * cellW;
          final y1 = y0 - cellW;
          final p0 = proj(x0, y0, 0.02);
          final p1 = proj(x1, y0, 0.02);
          final p2 = proj(x1, y1, 0.02);
          final p3 = proj(x0, y1, 0.02);
          final cellPath = Path()
            ..moveTo(p0.dx, p0.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..close();
          canvas.drawPath(cellPath, Paint()..color = _heatColor(heatmapGrid![r][col]).withValues(alpha: 0.72));
        }
      }
    }

    // Parapet Rim Lines
    if (parapetHeightM > 0.1) {
      final ph = parapetHeightM.clamp(0.2, 2.0).toDouble() * 0.45;
      final parPts = [proj(-hl, -hw, ph), proj(hl, -hw, ph), proj(hl, hw, ph), proj(-hl, hw, ph)];
      final parPaint = Paint()
        ..color = wireframe ? const Color(0xFF0EA5E9).withValues(alpha: 0.7) : const Color(0xFF64748B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        canvas.drawLine(parPts[i], parPts[j], parPaint);
        canvas.drawLine(topPts[i], parPts[i], parPaint);
      }
    }

    // MMS Mounting Structure Columns/Rails + PV Panels (respecting assemblyLayer!)
    if (assemblyLayer != 'building_only') {
      final usableL = math.max(1.8, roofLenM - setbackM * 2);
      final usableW = math.max(1.8, roofWidM - setbackM * 2);
      final rows = math.max(1, (usableW / 2.5).floor());
      final cols = math.max(1, (usableL / 1.45).floor());
      final cellL = usableL / cols;
      final cellW = usableW / rows;
      final lift = mmsClearanceM * 0.48;
      final tiltLift = math.sin(tiltDeg * math.pi / 180.0) * 1.1;

      final steelPaint = Paint()
        ..color = wireframe ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)
        ..strokeWidth = 1.5;

      // Draw MMS steel legs, purlins & optional cross-bracing
      for (var r = 0; r < rows; r++) {
        final yFront = -usableW / 2 + r * cellW + 0.25;
        final yBack = yFront + cellW - 0.55;
        // Front & rear purlin rails
        canvas.drawLine(proj(-usableL / 2, yFront, lift), proj(usableL / 2, yFront, lift), steelPaint);
        canvas.drawLine(proj(-usableL / 2, yBack, lift + tiltLift), proj(usableL / 2, yBack, lift + tiltLift), steelPaint);

        final colStep = math.max(1, (cols / 3).ceil());
        for (var cIdx = 0; cIdx <= cols; cIdx += colStep) {
          final xPos = -usableL / 2 + math.min(cIdx * cellL, usableL);
          // Front & back vertical columns
          canvas.drawLine(proj(xPos, yFront, 0), proj(xPos, yFront, lift), steelPaint);
          canvas.drawLine(proj(xPos, yBack, 0), proj(xPos, yBack, lift + tiltLift), steelPaint);
          if (crossBracing && lift > 0.35) {
            canvas.drawLine(
              proj(xPos, yFront, 0),
              proj(xPos, yBack, lift + tiltLift),
              Paint()
                ..color = const Color(0xFFF59E0B).withValues(alpha: 0.55)
                ..strokeWidth = 0.9,
            );
          }
        }
      }

      // Draw PV Modules only when assemblyLayer == 'structure_and_panels'
      if (assemblyLayer == 'structure_and_panels') {
        for (var r = 0; r < rows; r++) {
          for (var col = 0; col < cols; col++) {
            final x0 = -usableL / 2 + col * cellL + 0.08;
            final x1 = x0 + cellL - 0.16;
            final yFront = -usableW / 2 + r * cellW + 0.25;
            final yBack = yFront + cellW - 0.55;
            final p0 = proj(x0, yBack, lift + tiltLift);
            final p1 = proj(x1, yBack, lift + tiltLift);
            final p2 = proj(x1, yFront, lift);
            final p3 = proj(x0, yFront, lift);
            final pp = Path()
              ..moveTo(p0.dx, p0.dy)
              ..lineTo(p1.dx, p1.dy)
              ..lineTo(p2.dx, p2.dy)
              ..lineTo(p3.dx, p3.dy)
              ..close();
            if (!wireframe) {
              canvas.drawPath(pp, Paint()..color = const Color(0xFF1D4ED8).withValues(alpha: 0.86));
            }
            canvas.drawPath(
              pp,
              Paint()
                ..color = wireframe ? const Color(0xFF38BDF8) : const Color(0xFF93C5FD).withValues(alpha: 0.72)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.85,
            );
          }
        }
      }
    }

    // Cast Shadows & 3D Extruded Obstacles
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final sdx = math.sin(shAzRad);
    final sdy = math.cos(shAzRad);

    for (final obs in obstacles) {
      final bRad = obs.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * obs.distM;
      final oy = math.cos(bRad) * obs.distM;
      final oh = obs.heightM.clamp(0.5, 12.0).toDouble() * 0.5;
      final ow = (obs.widthM * 0.35).clamp(0.4, 2.5).toDouble();

      if (sunAlt > 1.5 && obs.heightM > mmsClearanceM) {
        final shLen = ((obs.heightM - mmsClearanceM) / math.tan(sunAlt * math.pi / 180.0)).clamp(0.0, 24.0).toDouble();
        final sp0 = proj(ox - ow, oy, 0.03);
        final sp1 = proj(ox + ow, oy, 0.03);
        final sp2 = proj(ox + ow + sdx * shLen, oy + sdy * shLen, 0.03);
        final sp3 = proj(ox - ow + sdx * shLen, oy + sdy * shLen, 0.03);
        canvas.drawPath(
          Path()
            ..moveTo(sp0.dx, sp0.dy)
            ..lineTo(sp1.dx, sp1.dy)
            ..lineTo(sp2.dx, sp2.dy)
            ..lineTo(sp3.dx, sp3.dy)
            ..close(),
          Paint()..color = const Color(0xFF020617).withValues(alpha: 0.54),
        );
      }

      final base = proj(ox, oy, 0);
      final top = proj(ox, oy, oh);
      final col = obs.type == 'tree'
          ? const Color(0xFF16A34A)
          : obs.fromOsm
              ? const Color(0xFF7C3AED)
              : const Color(0xFFEF4444);
      canvas.drawLine(
        base,
        top,
        Paint()
          ..color = col
          ..strokeWidth = (ow * scale * 1.4).clamp(6.0, 18.0).toDouble()
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(top, (ow * scale * 0.85).clamp(5.0, 14.0).toDouble(), Paint()..color = col.withValues(alpha: 0.92));
    }

    // Live Sun Orb in Sky
    if (sunAlt > 0) {
      final sX = size.width * (0.14 + ((sunAz.clamp(60.0, 300.0).toDouble() - 60.0) / 240.0) * 0.72);
      final sY = size.height * (0.34 - (sunAlt.clamp(0.0, 85.0).toDouble() / 85.0) * 0.26);
      final sunPt = Offset(sX, sY);
      canvas.drawCircle(sunPt, 14, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.26));
      canvas.drawCircle(sunPt, 6.5, Paint()..color = const Color(0xFFF59E0B));
    }

    // Dynamic North compass indicator rotating with orbitYawDeg
    final nCenter = const Offset(24, 24);
    final nTip = Offset(nCenter.dx - math.sin(yawRad) * 10, nCenter.dy - math.cos(yawRad) * 10);
    canvas.drawCircle(nCenter, 13, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.78));
    canvas.drawLine(nCenter, nTip, Paint()..color = const Color(0xFFEF4444)..strokeWidth = 2.2..strokeCap = StrokeCap.round);
    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, nCenter - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant Building3DShadowPainter old) => true;
}

// ============================================================================
// 3. ROOF SUNLIGHT HEATMAP PAINTER
// ============================================================================
class RoofHeatmapPainter extends CustomPainter {
  final List<List<double>> grid;
  final double roofLenM, roofWidM;
  final List<RoofObstacle> obstacles;
  final bool isDark;

  RoofHeatmapPainter({
    required this.grid,
    required this.roofLenM,
    required this.roofWidM,
    required this.obstacles,
    required this.isDark,
  });

  Color _heatColor(double t) {
    final v = t.clamp(0.0, 1.0).toDouble();
    if (v < 0.35) return Color.lerp(const Color(0xFF1E3A8A), const Color(0xFF0EA5E9), v / 0.35)!;
    if (v < 0.65) return Color.lerp(const Color(0xFF0EA5E9), const Color(0xFF10B981), (v - 0.35) / 0.30)!;
    if (v < 0.85) return Color.lerp(const Color(0xFF10B981), const Color(0xFFFACC15), (v - 0.65) / 0.20)!;
    return Color.lerp(const Color(0xFFFACC15), const Color(0xFFF97316), (v - 0.85) / 0.15)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rows = grid.length;
    final cols = rows > 0 ? grid.first.length : 0;
    if (rows == 0 || cols == 0) return;

    const pad = 16.0;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cr = Rect.fromLTWH(rect.left + c * cellW, rect.top + r * cellH, cellW + 0.6, cellH + 0.6);
        canvas.drawRect(cr, Paint()..color = _heatColor(grid[r][c]));
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final obs in obstacles) {
      final bRad = obs.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * obs.distM;
      final oy = math.cos(bRad) * obs.distM;
      final nx = ((ox + roofLenM / 2) / roofLenM).clamp(0.0, 1.0).toDouble();
      final ny = ((roofWidM / 2 - oy) / roofWidM).clamp(0.0, 1.0).toDouble();
      final pt = Offset(rect.left + nx * rect.width, rect.top + ny * rect.height);
      canvas.drawCircle(pt, 7, Paint()..color = Colors.white);
      canvas.drawCircle(pt, 5, Paint()..color = const Color(0xFFEF4444));
    }

    void label(String txt, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: txt, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 10.5, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    label('N', Offset(size.width / 2, 8));
    label('S', Offset(size.width / 2, size.height - 8));
    label('W', Offset(8, size.height / 2));
    label('E', Offset(size.width - 8, size.height / 2));
  }

  @override
  bool shouldRepaint(covariant RoofHeatmapPainter old) => true;
}

// ============================================================================
// 4. 360° SUN PATH COMPASS DIAL PAINTER
// ============================================================================
class SunCompassDialPainter extends CustomPainter {
  final double sunAz, sunAlt, shadowAz, panelAz;
  final List<({double alt, double az})> arcPoints;
  final double? riseAz, setAz;
  final bool isDark;

  SunCompassDialPainter({
    required this.sunAz,
    required this.sunAlt,
    required this.shadowAz,
    required this.arcPoints,
    required this.riseAz,
    required this.setAz,
    required this.panelAz,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 22;
    final ring = Paint()
      ..color = isDark ? const Color(0xFF233252) : const Color(0xFFD6DFEE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * .66, ring);
    canvas.drawCircle(c, r * .33, ring);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), ring);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), ring);

    Offset polar(double deg, double dist) {
      final rad = (deg - 90.0) * math.pi / 180.0;
      return Offset(c.dx + math.cos(rad) * dist, c.dy + math.sin(rad) * dist);
    }

    void label(String text, Offset pos, {Color? color}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color ?? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    label('N', Offset(c.dx, c.dy - r - 11), color: const Color(0xFFEF4444));
    label('S', Offset(c.dx, c.dy + r + 11));
    label('E', Offset(c.dx + r + 12, c.dy));
    label('W', Offset(c.dx - r - 12, c.dy));

    if (riseAz != null) canvas.drawCircle(polar(riseAz!, r), 4.5, Paint()..color = const Color(0xFFFACC15));
    if (setAz != null) canvas.drawCircle(polar(setAz!, r), 4.5, Paint()..color = const Color(0xFFF97316));

    if (arcPoints.length >= 2) {
      final arcPath = Path();
      for (var i = 0; i < arcPoints.length; i++) {
        final pt = arcPoints[i];
        final dist = r * (1.0 - (pt.alt.clamp(0.0, 90.0).toDouble() / 90.0) * 0.85);
        final off = polar(pt.az, dist);
        if (i == 0) {
          arcPath.moveTo(off.dx, off.dy);
        } else {
          arcPath.lineTo(off.dx, off.dy);
        }
      }
      canvas.drawPath(
        arcPath,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.58)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    canvas.drawLine(
      c,
      polar(panelAz, r * 0.38),
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(c, 5.5, Paint()..color = const Color(0xFF0A84FF));

    if (sunAlt > 0) {
      final sunDist = r * (1.0 - (sunAlt.clamp(0.0, 90.0).toDouble() / 90.0) * 0.85);
      final sunPt = polar(sunAz, sunDist);
      final shPt = polar(shadowAz, r * (1.0 - (sunAlt.clamp(5.0, 90.0).toDouble() / 95.0) * 0.65));

      canvas.drawLine(
        c,
        shPt,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.85)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        c,
        sunPt,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.8)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(sunPt, 12, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.28));
      canvas.drawCircle(sunPt, 6.5, Paint()..color = const Color(0xFFF59E0B));
    }
  }

  @override
  bool shouldRepaint(covariant SunCompassDialPainter old) => true;
}

// ============================================================================
// 5. AR SUN SKY-DOME & HORIZON PROJECTION PAINTER (AR SUN VIEW TOOL)
// ============================================================================
class ArSunSkyPainter extends CustomPainter {
  final double viewHeadingDeg; // center azimuth of AR viewfinder (0..360)
  final double sunAlt, sunAz;
  final List<({double alt, double az})> junArc;
  final List<({double alt, double az})> eqArc;
  final List<({double alt, double az})> decArc;
  final List<double> horizonProfile;

  ArSunSkyPainter({
    required this.viewHeadingDeg,
    required this.sunAlt,
    required this.sunAz,
    required this.junArc,
    required this.eqArc,
    required this.decArc,
    required this.horizonProfile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Sky-to-horizon atmospheric gradient (AR Viewfinder aesthetic)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07142B), Color(0xFF0F294A), Color(0xFF1E3A5F), Color(0xFF0F172A)],
          stops: [0.0, 0.55, 0.82, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    const fovDeg = 160.0; // wide panoramic AR sky viewport
    final horizonY = size.height * 0.84;
    final topY = size.height * 0.08;

    double? mapAzX(double az) {
      var diff = ((az - viewHeadingDeg + 540.0) % 360.0) - 180.0;
      if (diff.abs() > fovDeg / 2 + 12) return null;
      return size.width / 2 + (diff / (fovDeg / 2)) * (size.width / 2);
    }

    double mapAltY(double alt) {
      final frac = (alt.clamp(0.0, 90.0).toDouble()) / 90.0;
      return horizonY - frac * (horizonY - topY);
    }

    // Altitude grid lines (15°, 30°, 45°, 60°, 75°)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (final alt in const [0.0, 15.0, 30.0, 45.0, 60.0, 75.0]) {
      final y = mapAltY(alt);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${alt.round()}°', style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(6, y - 12));
    }

    // Compass heading ticks along horizon
    for (var az = 0; az < 360; az += 45) {
      final x = mapAzX(az.toDouble());
      if (x == null) continue;
      canvas.drawLine(Offset(x, topY), Offset(x, horizonY), Paint()..color = Colors.white.withValues(alpha: 0.08));
      final lbl = kHorizonDirs[(az ~/ 45) % 8];
      final tp = TextPainter(
        text: TextSpan(
          text: '$lbl ($az°)',
          style: TextStyle(color: lbl == 'S' ? const Color(0xFFFACC15) : Colors.white70, fontSize: 10, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, horizonY + 5));
    }

    // Horizon Obstruction Skyline Polygon
    final skyPath = Path()..moveTo(0, size.height);
    for (var px = 0.0; px <= size.width; px += 8.0) {
      final az = (viewHeadingDeg + ((px - size.width / 2) / (size.width / 2)) * (fovDeg / 2) + 360.0) % 360.0;
      final hElev = SolarAnalysisEngine.horizonElevationAt(az, horizonProfile);
      skyPath.lineTo(px, mapAltY(hElev));
    }
    skyPath
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(skyPath, Paint()..color = const Color(0xFF020617).withValues(alpha: 0.72));

    // Helper to draw seasonal sun arc
    void drawArc(List<({double alt, double az})> pts, Color color, double width) {
      Path? path;
      for (final p in pts) {
        final x = mapAzX(p.az);
        if (x == null || p.alt < 0) {
          if (path != null) {
            canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = width);
            path = null;
          }
          continue;
        }
        final y = mapAltY(p.alt);
        if (path == null) {
          path = Path()..moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (path != null) {
        canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = width);
      }
    }

    drawArc(junArc, const Color(0xFFF97316), 2.2); // Summer Solstice
    drawArc(eqArc, const Color(0xFFFACC15), 2.0); // Equinox
    drawArc(decArc, const Color(0xFF38BDF8), 2.2); // Winter Solstice

    // AR Center Crosshair Reticle
    final cx = size.width / 2;
    final cy = size.height * 0.48;
    final retPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(cx, cy), 18, retPaint);
    canvas.drawLine(Offset(cx - 26, cy), Offset(cx - 10, cy), retPaint);
    canvas.drawLine(Offset(cx + 10, cy), Offset(cx + 26, cy), retPaint);
    canvas.drawLine(Offset(cx, cy - 26), Offset(cx, cy - 10), retPaint);
    canvas.drawLine(Offset(cx, cy + 10), Offset(cx, cy + 26), retPaint);

    // Live Sun Orb in AR Sky
    final sx = mapAzX(sunAz);
    if (sx != null && sunAlt > 0) {
      final sy = mapAltY(sunAlt);
      canvas.drawCircle(Offset(sx, sy), 18, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.28));
      canvas.drawCircle(Offset(sx, sy), 9, Paint()..color = const Color(0xFFFACC15));
      canvas.drawCircle(Offset(sx, sy), 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant ArSunSkyPainter old) => true;
}

void _drawNorthBadge(Canvas canvas, Offset center, bool darkBg) {
  canvas.drawCircle(center, 12, Paint()..color = (darkBg ? const Color(0xFF1E293B) : Colors.white).withValues(alpha: 0.9));
  final tp = TextPainter(
    text: const TextSpan(text: 'N', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w900)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}
