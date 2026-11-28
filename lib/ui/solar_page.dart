import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/calc.dart';
import '../core/estimator_data.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'roof_map.dart';
import 'theme.dart';

/// Verified rooftop obstacle for real-time 2D/3D shadow & heatmap simulation.
class _RoofObstacle {
  final String id;
  final String name;
  final String type; // tank | parapet | lift | tree | building
  final double heightM;
  final double widthM;
  final double distM; // distance from roof center (m)
  final double bearingDeg; // 0 = N, 90 = E, 180 = S, 270 = W

  const _RoofObstacle({
    required this.id,
    required this.name,
    required this.type,
    required this.heightM,
    required this.widthM,
    required this.distM,
    required this.bearingDeg,
  });

  _RoofObstacle copyWith({
    String? name,
    String? type,
    double? heightM,
    double? widthM,
    double? distM,
    double? bearingDeg,
  }) =>
      _RoofObstacle(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        heightM: heightM ?? this.heightM,
        widthM: widthM ?? this.widthM,
        distM: distM ?? this.distM,
        bearingDeg: bearingDeg ?? this.bearingDeg,
      );
}

/// MMS Mounting Structure preset matching Solar Analysis Studio.
class _MmsPreset {
  final String id;
  final String label;
  final String subtitle;
  final double clearanceM;
  final double setbackM;
  final double fillFactor;

  const _MmsPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.clearanceM,
    required this.setbackM,
    required this.fillFactor,
  });
}

const List<_MmsPreset> _kMmsPresets = [
  _MmsPreset(
    id: 'low_rcc',
    label: 'Low-Rise RCC',
    subtitle: '0.4m clearance · 0.6m setback',
    clearanceM: 0.4,
    setbackM: 0.6,
    fillFactor: 0.72,
  ),
  _MmsPreset(
    id: 'elevated',
    label: 'Elevated Pergola',
    subtitle: '2.6m headroom · clears parapet',
    clearanceM: 2.6,
    setbackM: 0.35,
    fillFactor: 0.84,
  ),
  _MmsPreset(
    id: 'pitched',
    label: 'Pitched Flush',
    subtitle: '0.15m rail · metal/tile roof',
    clearanceM: 0.15,
    setbackM: 0.4,
    fillFactor: 0.80,
  ),
  _MmsPreset(
    id: 'tiered',
    label: 'Tiered Split',
    subtitle: '1.2m lift · dual-row clearance',
    clearanceM: 1.2,
    setbackM: 0.5,
    fillFactor: 0.76,
  ),
];

/// Full Solar Analysis Suite:
/// 0: Shadow Studio (2D CAD + 3D Isometric + Obstacles + MMS + PVsyst Loss)
/// 1: Roof Sun Heatmap (Annual / Summer / Winter / Today irradiance grid)
/// 2: Sun Compass & Optimal Seasonal Tilt
/// 3: Sun Timer & Generation Forecast (Hourly + Monthly + Annual)
class SolarPage extends StatefulWidget {
  final AppState state;
  const SolarPage({super.key, required this.state});
  @override
  State<SolarPage> createState() => _SolarPageState();
}

class _SolarPageState extends State<SolarPage> {
  int _suiteTab = 0; // 0 Studio, 1 Heatmap, 2 Compass, 3 Timer & Yield
  int _studioView = 0; // 0 = 2D CAD Plan, 1 = 3D Isometric
  int _datePreset = 0; // 0 Today, 1 Jun 21, 2 Equinox, 3 Dec 21
  int _heatmapPeriod = 0; // 0 Annual, 1 Summer, 2 Winter, 3 Today

  double _hour = (DateTime.now().hour + DateTime.now().minute / 60.0).clamp(5.5, 18.5).toDouble();
  bool _sweeping = false;
  Timer? _sweepTimer;
  bool _locating = false;

  // Roof & PV Engineering Parameters
  double _roofLenM = 12.0;
  double _roofWidM = 8.0;
  double _tiltDeg = 18.0;
  double _azimuthDeg = 180.0;
  int _mmsIndex = 0;
  RoofResult? _roofTrace;

  // Verified Obstacles (starts empty — zero fabricated obstacles)
  final List<_RoofObstacle> _obstacles = [];
  int _obsSeq = 1;

  AppState get state => widget.state;
  _MmsPreset get _mms => _kMmsPresets[_mmsIndex.clamp(0, _kMmsPresets.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    final lat = state.site.lat;
    _tiltDeg = lat.abs().clamp(8.0, 42.0).roundToDouble();
    _azimuthDeg = lat >= 0 ? 180.0 : 0.0;
    if (state.profile.roofSqft > 100) {
      final sqm = state.profile.roofSqft * 0.092903;
      final side = math.sqrt(sqm).clamp(5.0, 26.0).toDouble();
      _roofLenM = (side * 1.15).clamp(5.0, 30.0).toDouble();
      _roofWidM = (side * 0.87).clamp(4.0, 24.0).toDouble();
    }
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    super.dispose();
  }

  DateTime _simDate() {
    final now = DateTime.now();
    final hh = _hour.floor().clamp(0, 23).toInt();
    final mm = ((_hour - hh) * 60).round().clamp(0, 59).toInt();
    switch (_datePreset) {
      case 1:
        return DateTime(now.year, 6, 21, hh, mm);
      case 2:
        return DateTime(now.year, 3, 20, hh, mm);
      case 3:
        return DateTime(now.year, 12, 21, hh, mm);
      default:
        return DateTime(now.year, now.month, now.day, hh, mm);
    }
  }

  String _fmtClock(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtHourDouble(double h) {
    final hh = h.floor().clamp(0, 23).toInt();
    final mm = ((h - hh) * 60).round().clamp(0, 59).toInt();
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  void _toggleSweep() {
    if (_sweeping) {
      _sweepTimer?.cancel();
      setState(() => _sweeping = false);
      return;
    }
    setState(() => _sweeping = true);
    _sweepTimer?.cancel();
    _sweepTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!mounted) return;
      setState(() {
        _hour += 0.12;
        if (_hour > 18.5) _hour = 5.5;
      });
    });
  }

  void _resetNow() {
    _sweepTimer?.cancel();
    final now = DateTime.now();
    setState(() {
      _sweeping = false;
      _datePreset = 0;
      _hour = (now.hour + now.minute / 60.0).clamp(5.5, 18.5).toDouble();
    });
  }

  Future<void> _openRoofMap() async {
    final panel = panelsFor(true).first;
    final res = await Navigator.of(context).push<RoofResult>(
      MaterialPageRoute(builder: (_) => RoofMapPage(state: state, panel: panel)),
    );
    if (res == null || !mounted) return;
    setState(() {
      _roofTrace = res;
      if (res.areaM2 > 6) {
        final side = math.sqrt(res.areaM2).clamp(4.0, 30.0).toDouble();
        _roofLenM = (side * 1.18).clamp(4.0, 30.0).toDouble();
        _roofWidM = (res.areaM2 / _roofLenM).clamp(4.0, 25.0).toDouble();
      }
    });
  }

  Future<void> _locateSite() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      await state.locate();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Evaluates if a point (px, py in meters from roof center; +x = East, +y = North)
  /// is shaded by any verified obstacle at the given sun position.
  bool _isPointShaded(double px, double py, double sunAlt, double sunAz) {
    if (sunAlt <= 1.5) return true;
    if (_obstacles.isEmpty) return false;
    final tanAlt = math.tan(sunAlt * math.pi / 180.0);
    if (tanAlt <= 0.01) return true;
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final dx = math.sin(shAzRad); // East component of shadow ray
    final dy = math.cos(shAzRad); // North component of shadow ray

    for (final o in _obstacles) {
      final effH = o.heightM - _mms.clearanceM;
      if (effH <= 0.05) continue;
      final shLen = (effH / tanAlt).clamp(0.0, 60.0).toDouble();
      final bRad = o.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * o.distM;
      final oy = math.cos(bRad) * o.distM;

      // Vector from obstacle center to test point
      final vx = px - ox;
      final vy = py - oy;
      // Projection along shadow ray and perpendicular distance
      final along = vx * dx + vy * dy;
      final perp = (vx * dy - vy * dx).abs();
      final halfW = math.max(0.45, o.widthM / 2.0);
      if (along >= -halfW * 0.4 && along <= shLen && perp <= halfW) {
        return true;
      }
    }
    return false;
  }

  /// Fraction of usable PV roof area unshaded (0.0 .. 1.0) at a given sun position.
  double _unshadedFraction(double sunAlt, double sunAz) {
    if (sunAlt <= 1.5) return 0.0;
    if (_obstacles.isEmpty) return 1.0;
    final usableL = math.max(2.0, _roofLenM - _mms.setbackM * 2);
    final usableW = math.max(2.0, _roofWidM - _mms.setbackM * 2);
    const nx = 9;
    const ny = 7;
    var unshaded = 0;
    for (var ix = 0; ix < nx; ix++) {
      final px = -usableL / 2 + (ix + 0.5) * (usableL / nx);
      for (var iy = 0; iy < ny; iy++) {
        final py = -usableW / 2 + (iy + 0.5) * (usableW / ny);
        if (!_isPointShaded(px, py, sunAlt, sunAz)) unshaded++;
      }
    }
    return unshaded / (nx * ny);
  }

  /// Tilt & azimuth efficiency factor (0.72 .. 1.00) relative to ideal orientation.
  double _orientationEfficiency(double lat) {
    final optTilt = lat.abs().clamp(5.0, 45.0).toDouble();
    final optAz = lat >= 0 ? 180.0 : 0.0;
    final tiltDiff = (_tiltDeg - optTilt).abs();
    var azDiff = (_azimuthDeg - optAz).abs();
    if (azDiff > 180) azDiff = 360 - azDiff;
    final tiltLoss = (tiltDiff * tiltDiff) * 0.00018;
    final azLoss = (azDiff / 180.0) * 0.14 * (math.sin(_tiltDeg * math.pi / 180.0).clamp(0.15, 1.0).toDouble());
    return (1.0 - tiltLoss - azLoss).clamp(0.70, 1.0).toDouble();
  }

  /// Computes annual unshaded fraction by sampling daylight hours across 4 seasons.
  double _annualUnshadedFraction(double lat, double lon) {
    if (_obstacles.isEmpty) return 1.0;
    final year = DateTime.now().year;
    final sampleDays = [
      DateTime(year, 3, 20),
      DateTime(year, 6, 21),
      DateTime(year, 9, 22),
      DateTime(year, 12, 21),
    ];
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    for (final d in sampleDays) {
      for (var h = 7; h <= 17; h++) {
        final p = solarPosition(DateTime(d.year, d.month, d.day, h, 30), lat, lon);
        if (p.alt <= 2.0) continue;
        final w = math.sin(p.alt * math.pi / 180.0);
        weightedSum += _unshadedFraction(p.alt, p.az) * w;
        weightTotal += w;
      }
    }
    return weightTotal > 0 ? (weightedSum / weightTotal).clamp(0.0, 1.0).toDouble() : 1.0;
  }

  /// Builds a 12x8 roof irradiance heatmap matrix (values in 0.0 .. 1.0 relative to peak).
  List<List<double>> _computeHeatmapGrid(double lat, double lon) {
    const cols = 12;
    const rows = 8;
    final year = DateTime.now().year;
    final now = DateTime.now();
    final List<DateTime> dates;
    switch (_heatmapPeriod) {
      case 1:
        dates = [DateTime(year, 6, 21)];
        break;
      case 2:
        dates = [DateTime(year, 12, 21)];
        break;
      case 3:
        dates = [DateTime(now.year, now.month, now.day)];
        break;
      default:
        dates = [
          DateTime(year, 3, 20),
          DateTime(year, 6, 21),
          DateTime(year, 9, 22),
          DateTime(year, 12, 21),
        ];
    }

    // Precompute daylight sun samples
    final samples = <({double alt, double az, double w})>[];
    var totalW = 0.0;
    for (final d in dates) {
      for (var h = 7; h <= 17; h++) {
        final p = solarPosition(DateTime(d.year, d.month, d.day, h, 30), lat, lon);
        if (p.alt <= 2.0) continue;
        final w = math.sin(p.alt * math.pi / 180.0);
        samples.add((alt: p.alt, az: p.az, w: w));
        totalW += w;
      }
    }
    if (totalW <= 0) {
      return List.generate(rows, (_) => List.filled(cols, 0.85));
    }

    final orient = _orientationEfficiency(lat);
    return List.generate(rows, (r) {
      final py = _roofWidM / 2 - (r + 0.5) * (_roofWidM / rows);
      return List.generate(cols, (c) {
        final px = -_roofLenM / 2 + (c + 0.5) * (_roofLenM / cols);
        var sum = 0.0;
        for (final s in samples) {
          final lit = _isPointShaded(px, py, s.alt, s.az) ? 0.22 : 1.0; // diffuse sky = 22%
          sum += lit * s.w;
        }
        // Subtle edge setback shading penalty on outer rim cells
        final edge = (r == 0 || r == rows - 1 || c == 0 || c == cols - 1) ? 0.96 : 1.0;
        return ((sum / totalW) * orient * edge).clamp(0.15, 1.0).toDouble();
      });
    });
  }

  /// Opens bottom sheet to add or edit a verified rooftop obstacle.
  Future<void> _showObstacleSheet({_RoofObstacle? edit, String? presetType}) async {
    String type = edit?.type ?? presetType ?? 'tank';
    double heightM = edit?.heightM ?? (type == 'parapet' ? 1.2 : type == 'tree' ? 6.0 : type == 'building' ? 7.5 : 2.5);
    double widthM = edit?.widthM ?? (type == 'parapet' ? 6.0 : type == 'building' ? 5.0 : 2.0);
    double distM = edit?.distM ?? (type == 'parapet' ? (_roofWidM / 2).clamp(2.0, 12.0).toDouble() : 4.5);
    double bearingDeg = edit?.bearingDeg ?? 180.0;

    String defaultNameFor(String t) {
      switch (t) {
        case 'parapet':
          return 'Parapet Wall';
        case 'lift':
          return 'Lift / Staircase Room';
        case 'tree':
          return 'Nearby Tree';
        case 'building':
          return 'Adjacent Building';
        default:
          return 'Overhead Water Tank';
      }
    }

    final nameCtrl = TextEditingController(text: edit?.name ?? defaultNameFor(type));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: C.orange.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.domain_add_rounded, color: C.orange, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    edit == null ? 'Add Verified Obstacle' : 'Edit Obstacle',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 12),
              Text('Obstacle Type', style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final item in const [
                  ('tank', 'Water Tank'),
                  ('parapet', 'Parapet'),
                  ('lift', 'Lift Room'),
                  ('tree', 'Tree'),
                  ('building', 'Building'),
                ])
                  ChoiceChip(
                    label: Text(item.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    selected: type == item.$1,
                    selectedColor: C.orange.withValues(alpha: .22),
                    onSelected: (_) => setSheet(() {
                      type = item.$1;
                      if (edit == null) nameCtrl.text = defaultNameFor(type);
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Obstacle Label',
                  filled: true,
                  fillColor: C.card2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.line)),
                ),
              ),
              const SizedBox(height: 12),
              _sheetSlider(
                label: 'Height above roof',
                valueText: '${heightM.toStringAsFixed(1)} m (${(heightM * 3.28084).toStringAsFixed(1)} ft)',
                value: heightM,
                min: 0.5,
                max: 15.0,
                color: C.orange,
                onChanged: (v) => setSheet(() => heightM = v),
              ),
              _sheetSlider(
                label: 'Width / Span',
                valueText: '${widthM.toStringAsFixed(1)} m',
                value: widthM,
                min: 0.8,
                max: 14.0,
                color: C.sky,
                onChanged: (v) => setSheet(() => widthM = v),
              ),
              _sheetSlider(
                label: 'Distance from roof center',
                valueText: '${distM.toStringAsFixed(1)} m',
                value: distM,
                min: 1.0,
                max: 16.0,
                color: C.blue,
                onChanged: (v) => setSheet(() => distM = v),
              ),
              _sheetSlider(
                label: 'Direction from roof (Bearing)',
                valueText: '${bearingDeg.round()}° ${compass(bearingDeg)}',
                value: bearingDeg,
                min: 0.0,
                max: 355.0,
                color: C.amber,
                onChanged: (v) => setSheet(() => bearingDeg = v),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final label = nameCtrl.text.trim().isEmpty ? defaultNameFor(type) : nameCtrl.text.trim();
                    setState(() {
                      if (edit == null) {
                        _obstacles.add(_RoofObstacle(
                          id: 'obs_${_obsSeq++}',
                          name: label,
                          type: type,
                          heightM: heightM,
                          widthM: widthM,
                          distM: distM,
                          bearingDeg: bearingDeg,
                        ));
                      } else {
                        final idx = _obstacles.indexWhere((x) => x.id == edit.id);
                        if (idx >= 0) {
                          _obstacles[idx] = edit.copyWith(
                            name: label,
                            type: type,
                            heightM: heightM,
                            widthM: widthM,
                            distM: distM,
                            bearingDeg: bearingDeg,
                          );
                        }
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  icon: Icon(edit == null ? Icons.add_rounded : Icons.check_rounded, size: 18),
                  style: FilledButton.styleFrom(backgroundColor: C.orange, minimumSize: const Size.fromHeight(46)),
                  label: Text(edit == null ? 'Add Obstacle to Roof' : 'Save Changes', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  Widget _sheetSlider({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          Text(valueText, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
        ]),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          activeColor: color,
          onChanged: onChanged,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final site = state.site;
    final simTime = _simDate();
    final pos = solarPosition(simTime, site.lat, site.lon);
    final day = dayInfo(simTime, site.lat, site.lon);
    final shadowAz = (pos.az + 180.0) % 360.0;
    final unshadedNow = _unshadedFraction(pos.alt, pos.az);
    final unshadedAnnual = _annualUnshadedFraction(site.lat, site.lon);
    final orientEff = _orientationEfficiency(site.lat);

    final grossArea = _roofTrace?.areaM2 ?? (_roofLenM * _roofWidM);
    final usableArea = math.max(0.0, (_roofLenM - _mms.setbackM * 2) * (_roofWidM - _mms.setbackM * 2)) * _mms.fillFactor;
    final estPanels = _roofTrace?.panels ?? (usableArea / 2.58).floor().clamp(0, 500).toInt();
    final estKwp = _roofTrace?.kwp ?? (estPanels * 0.55);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        // 1. COMPACT TOP HEADER WITH ROOF MAP & GPS ACTIONS
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                state.t('solar'),
                style: TextStyle(color: C.text, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4),
              ),
              const SizedBox(height: 2),
              Text(
                '${site.city} · ${site.lat.toStringAsFixed(4)}°, ${site.lon.toStringAsFixed(4)}°',
                style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openRoofMap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: C.chipSun,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.orange.withValues(alpha: .4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.satellite_alt_rounded, color: C.orange, size: 16),
                const SizedBox(width: 5),
                Text('Roof Map', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _locateSite,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.line),
              ),
              child: _locating
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.sky))
                  : Icon(Icons.my_location_rounded, color: C.sky, size: 17),
            ),
          ),
        ]),

        if (_roofTrace != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: C.chipGreen,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.green.withValues(alpha: .35)),
            ),
            child: Row(children: [
              Icon(Icons.verified_rounded, color: C.green, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Measured Roof: ${_roofTrace!.areaM2.toStringAsFixed(1)} m² · ${_roofTrace!.panels} panels · ${_roofTrace!.kwp.toStringAsFixed(2)} kWp',
                  style: TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 12),

        // 2. SUITE TOOL BAR (Matches Web App Solar Analysis Tabs)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _suitePill(0, Icons.view_in_ar_rounded, 'Shadow Studio', C.orange),
            const SizedBox(width: 8),
            _suitePill(1, Icons.local_fire_department_rounded, 'Sun Heatmap', C.amber),
            const SizedBox(width: 8),
            _suitePill(2, Icons.explore_outlined, 'Sun Compass', C.sky),
            const SizedBox(width: 8),
            _suitePill(3, Icons.schedule_rounded, 'Sun Timer & Yield', C.green),
          ]),
        ),
        const SizedBox(height: 14),

        // 3. SHARED ASTRONOMICAL CONTROLS (for Studio, Heatmap, Compass)
        if (_suiteTab != 3) ...[
          _buildSunControlBar(sunAlt: pos.alt, sunAz: pos.az, day: day, unshadedNow: unshadedNow),
          const SizedBox(height: 14),
        ],

        // 4. ACTIVE SUITE TAB CONTENT
        if (_suiteTab == 0)
          _buildShadowStudioTab(
            site: site,
            sunAlt: pos.alt,
            sunAz: pos.az,
            shadowAz: shadowAz,
            unshadedAnnual: unshadedAnnual,
            orientEff: orientEff,
            grossArea: grossArea,
            usableArea: usableArea,
            estPanels: estPanels,
            estKwp: estKwp,
          )
        else if (_suiteTab == 1)
          _buildHeatmapTab(site: site, orientEff: orientEff)
        else if (_suiteTab == 2)
          _buildCompassTab(site: site, simTime: simTime, sunAlt: pos.alt, sunAz: pos.az, day: day, shadowAz: shadowAz)
        else
          _buildTimerAndYieldTab(site: site, day: day),
      ],
    );
  }

  Widget _suitePill(int idx, IconData icon, String label, Color accent) {
    final active = _suiteTab == idx;
    return InkWell(
      onTap: () => setState(() => _suiteTab = idx),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: active ? accent : C.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? accent : C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? Colors.white : accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : C.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSunControlBar({
    required double sunAlt,
    required double sunAz,
    required DayInfo day,
    required double unshadedNow,
  }) {
    final shadeColor = sunAlt <= 1.5
        ? C.mute
        : unshadedNow >= 0.90
            ? C.green
            : unshadedNow >= 0.75
                ? C.amber
                : C.red;

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Season / Solstice quick selector
        Row(children: [
          for (final p in const [
            (0, 'Today'),
            (1, 'Jun 21'),
            (2, 'Equinox'),
            (3, 'Dec 21'),
          ]) ...[
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _datePreset = p.$1),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _datePreset == p.$1 ? C.orange : C.card2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _datePreset == p.$1 ? C.orange : C.line),
                  ),
                  child: Text(
                    p.$2,
                    style: TextStyle(
                      color: _datePreset == p.$1 ? Colors.white : C.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            if (p.$1 < 3) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 10),
        // Time slider + Play Sweep + Live Now
        Row(children: [
          InkWell(
            onTap: _toggleSweep,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _sweeping ? C.orange : C.chipBlue,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _sweeping ? C.orange : C.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_sweeping ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 16, color: _sweeping ? Colors.white : C.sky),
                const SizedBox(width: 4),
                Text(
                  _sweeping ? 'Pause' : 'Sweep',
                  style: TextStyle(color: _sweeping ? Colors.white : C.text, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
              child: Slider(
                value: _hour.clamp(5.5, 18.5).toDouble(),
                min: 5.5,
                max: 18.5,
                divisions: 156,
                activeColor: C.orange,
                onChanged: (v) {
                  if (_sweeping) _sweepTimer?.cancel();
                  setState(() {
                    _sweeping = false;
                    _hour = v;
                  });
                },
              ),
            ),
          ),
          InkWell(
            onTap: _resetNow,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
              child: Text('Now', style: TextStyle(color: C.sky, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        // Live telemetry strip
        Row(children: [
          Expanded(child: _miniStat('Time', _fmtHourDouble(_hour), C.sky)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat('Alt', '${sunAlt.toStringAsFixed(1)}°', C.amber)),
          const SizedBox(width: 6),
          Expanded(child: _miniStat('Azimuth', '${sunAz.round()}° ${compass(sunAz)}', C.orange)),
          const SizedBox(width: 6),
          Expanded(
            child: _miniStat(
              'Unshaded',
              sunAlt > 1.5 ? '${(unshadedNow * 100).round()}%' : 'Night',
              shadeColor,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Rise ${_fmtClock(day.rise)} · Set ${_fmtClock(day.set)} · ${_obstacles.isEmpty ? 'No obstacles added yet' : '${_obstacles.length} verified obstacle${_obstacles.length == 1 ? '' : 's'}'}',
          style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  // ==================== TAB 0: SHADOW STUDIO ====================
  Widget _buildShadowStudioTab({
    required Site site,
    required double sunAlt,
    required double sunAz,
    required double shadowAz,
    required double unshadedAnnual,
    required double orientEff,
    required double grossArea,
    required double usableArea,
    required int estPanels,
    required double estKwp,
  }) {
    final winterNoonAlt = (90.0 - (site.lat.abs() + 23.44)).clamp(10.0, 89.0).toDouble();
    final annualBaseKwh = List.generate(
      12,
      (i) => site.kwp * (state.monthly?.psh[i] ?? kMonthPshHyd[i]) * state.pr * DateTime(DateTime.now().year, i + 2, 0).day,
    ).fold(0.0, (a, b) => a + b);
    final netAnnualKwh = annualBaseKwh * unshadedAnnual * orientEff;
    final shadingLossPct = ((1.0 - unshadedAnnual) * 100.0).clamp(0.0, 100.0).toDouble();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Interactive 2D CAD / 3D Isometric Shadow Canvas
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_studioView == 0 ? Icons.grid_on_rounded : Icons.view_in_ar_rounded, color: C.orange, size: 19),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Rooftop CAD & Live Shadow', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            // 2D / 3D toggle
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _segBtn('2D CAD', _studioView == 0, () => setState(() => _studioView = 0)),
                _segBtn('3D Iso', _studioView == 1, () => setState(() => _studioView = 1)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 268,
              width: double.infinity,
              decoration: BoxDecoration(
                color: C.dark ? const Color(0xFF0B1325) : const Color(0xFFF1F5F9),
                border: Border.all(color: C.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CustomPaint(
                painter: _RoofShadowPainter(
                  is3d: _studioView == 1,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  setbackM: _mms.setbackM,
                  mmsClearanceM: _mms.clearanceM,
                  tiltDeg: _tiltDeg,
                  sunAlt: sunAlt,
                  sunAz: sunAz,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _legendDot(const Color(0xFF1D4ED8), 'PV Array'),
            const SizedBox(width: 12),
            _legendDot(const Color(0xFFEF4444), 'Obstacle'),
            const SizedBox(width: 12),
            _legendDot(const Color(0xFF334155), 'Cast Shadow'),
            const Spacer(),
            Text(
              '${_roofLenM.toStringAsFixed(1)}m × ${_roofWidM.toStringAsFixed(1)}m',
              style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),

      // Verified Obstacles Manager
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: C.amber, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Verified Roof Obstacles (${_obstacles.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            InkWell(
              onTap: () => _showObstacleSheet(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 3),
                  Text('Add', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Quick-add obstacle presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final q in const [
                ('tank', '+ Water Tank'),
                ('parapet', '+ Parapet Wall'),
                ('lift', '+ Lift Room'),
                ('tree', '+ Tree'),
                ('building', '+ Neighbor Bldg'),
              ]) ...[
                InkWell(
                  onTap: () => _showObstacleSheet(presetType: q.$1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
                    child: Text(q.$2, style: TextStyle(color: C.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          if (_obstacles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
              child: Text(
                'No obstacles added yet. Add real site obstructions (water tank, parapet wall, lift room, tree, or nearby building) to simulate exact cast shadows and PVsyst shading loss.',
                style: TextStyle(color: C.text, fontSize: 12, height: 1.35),
              ),
            )
          else
            for (final obs in _obstacles) ...[
              _buildObstacleRow(obs: obs, sunAlt: sunAlt, shadowAz: shadowAz, winterNoonAlt: winterNoonAlt),
              const SizedBox(height: 8),
            ],
        ]),
      ),
      const SizedBox(height: 14),

      // Roof Dimensions, Tilt & MMS Mounting Preset
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.straighten_rounded, color: C.sky, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Roof Geometry & MMS Structure', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            InkWell(
              onTap: _openRoofMap,
              child: Text('Trace on Map →', style: TextStyle(color: C.orange, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Gross Area', '${grossArea.toStringAsFixed(1)} m²', C.text)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Usable PV', '${usableArea.toStringAsFixed(1)} m²', C.sky)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Capacity', '$estPanels × 550W · ${estKwp.toStringAsFixed(1)} kWp', C.green)),
          ]),
          const SizedBox(height: 10),
          _sheetSlider(
            label: 'Roof Length (E–W)',
            valueText: '${_roofLenM.toStringAsFixed(1)} m',
            value: _roofLenM,
            min: 4.0,
            max: 30.0,
            color: C.sky,
            onChanged: (v) => setState(() {
              _roofTrace = null;
              _roofLenM = v;
            }),
          ),
          _sheetSlider(
            label: 'Roof Width (N–S)',
            valueText: '${_roofWidM.toStringAsFixed(1)} m',
            value: _roofWidM,
            min: 4.0,
            max: 25.0,
            color: C.sky,
            onChanged: (v) => setState(() {
              _roofTrace = null;
              _roofWidM = v;
            }),
          ),
          _sheetSlider(
            label: 'Array Tilt Angle (Opt ${site.lat.abs().round()}°)',
            valueText: '${_tiltDeg.round()}°',
            value: _tiltDeg,
            min: 0.0,
            max: 45.0,
            color: C.orange,
            onChanged: (v) => setState(() => _tiltDeg = v),
          ),
          _sheetSlider(
            label: 'Array Azimuth (Facing)',
            valueText: '${_azimuthDeg.round()}° ${compass(_azimuthDeg)}',
            value: _azimuthDeg,
            min: 0.0,
            max: 355.0,
            color: C.amber,
            onChanged: (v) => setState(() => _azimuthDeg = v),
          ),
          const SizedBox(height: 6),
          Text('MMS Mounting Structure Preset', style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.35,
            children: [
              for (var i = 0; i < _kMmsPresets.length; i++)
                InkWell(
                  onTap: () => setState(() => _mmsIndex = i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _mmsIndex == i ? C.orange.withValues(alpha: .14) : C.card2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _mmsIndex == i ? C.orange : C.line, width: _mmsIndex == i ? 1.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(
                        _kMmsPresets[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _mmsIndex == i ? C.orange : C.text, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _kMmsPresets[i].subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: C.mute, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // PVsyst Shading Loss & Engineering Audit Summary
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.analytics_outlined, color: C.green, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('PVsyst Shading & Tilt Audit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: shadingLossPct < 5 ? C.chipGreen : C.chipSun,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                shadingLossPct < 5 ? 'Optimal Site' : shadingLossPct < 15 ? 'Moderate Shade' : 'High Shade',
                style: TextStyle(color: shadingLossPct < 5 ? C.green : C.orange, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Annual Unshaded', '${(unshadedAnnual * 100).toStringAsFixed(1)}%', C.green)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Shading Loss', '-${shadingLossPct.toStringAsFixed(1)}%', shadingLossPct > 8 ? C.red : C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Tilt Efficiency', '${(orientEff * 100).toStringAsFixed(1)}%', C.sky)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Estimated Net Annual Yield', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                Text('${groupIndian(netAnnualKwh)} kWh/yr', style: TextStyle(color: C.green, fontSize: 14, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Winter solstice noon sun altitude at ${site.city}: ${winterNoonAlt.toStringAsFixed(1)}°. '
                'Using ${_mms.label} (${_mms.clearanceM.toStringAsFixed(1)}m rail height) on ${site.kwp} kWp system.',
                style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildObstacleRow({
    required _RoofObstacle obs,
    required double sunAlt,
    required double shadowAz,
    required double winterNoonAlt,
  }) {
    final effH = math.max(0.0, obs.heightM - _mms.clearanceM);
    final shLen = sunAlt > 2.0 ? effH / math.tan(sunAlt * math.pi / 180.0) : 0.0;
    final winterSetback = effH / math.tan(winterNoonAlt * math.pi / 180.0);
    final clearedByMms = effH <= 0.05;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (clearedByMms ? C.green : C.red).withValues(alpha: .14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            obs.type == 'tree'
                ? Icons.park_rounded
                : obs.type == 'parapet'
                    ? Icons.view_stream_rounded
                    : Icons.apartment_rounded,
            color: clearedByMms ? C.green : C.red,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(obs.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'H ${obs.heightM.toStringAsFixed(1)}m · W ${obs.widthM.toStringAsFixed(1)}m · ${obs.distM.toStringAsFixed(1)}m @ ${obs.bearingDeg.round()}° ${compass(obs.bearingDeg)}',
              style: TextStyle(color: C.mute, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              clearedByMms
                  ? 'Cleared by ${_mms.label} (${_mms.clearanceM.toStringAsFixed(1)}m height)'
                  : sunAlt > 2.0
                      ? 'Shadow now: ${shLen.toStringAsFixed(1)}m → ${compass(shadowAz)} · Winter setback: ${winterSetback.toStringAsFixed(1)}m'
                      : 'Winter-noon safe clearance: ${winterSetback.toStringAsFixed(1)}m',
              style: TextStyle(color: clearedByMms ? C.green : C.sky, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 18, color: C.mute),
          visualDensity: VisualDensity.compact,
          onPressed: () => _showObstacleSheet(edit: obs),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 18, color: C.red),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _obstacles.removeWhere((x) => x.id == obs.id)),
        ),
      ]),
    );
  }

  // ==================== TAB 1: ROOF SUN HEATMAP ====================
  Widget _buildHeatmapTab({required Site site, required double orientEff}) {
    final grid = _computeHeatmapGrid(site.lat, site.lon);
    final flat = [for (final row in grid) ...row];
    final avgRel = flat.fold(0.0, (a, b) => a + b) / flat.length;
    final peakRel = flat.fold(0.0, (a, b) => a > b ? a : b);
    final unshadedPct = (flat.where((v) => v >= 0.78).length / flat.length) * 100.0;

    final basePsh = state.monthly?.annual ?? (kMonthPshHyd.reduce((a, b) => a + b) / 12.0);
    final periodMult = _heatmapPeriod == 1
        ? 1.18
        : _heatmapPeriod == 2
            ? 0.84
            : 1.0;
    final avgSunHrs = (basePsh * periodMult * avgRel).clamp(1.0, 9.0).toDouble();
    final peakIrrKwhM2 = (basePsh * 365.0 * peakRel).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.local_fire_department_rounded, color: C.amber, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Roof Sunlight Heatmap', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text('${(avgRel * 100).round()}% score', style: TextStyle(color: C.amber, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ]),
          const SizedBox(height: 10),
          // Period switcher
          Row(children: [
            for (final p in const [
              (0, 'Annual'),
              (1, 'Summer'),
              (2, 'Winter'),
              (3, 'Today'),
            ]) ...[
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _heatmapPeriod = p.$1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _heatmapPeriod == p.$1 ? C.amber : C.card2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _heatmapPeriod == p.$1 ? C.amber : C.line),
                    ),
                    child: Text(
                      p.$2,
                      style: TextStyle(
                        color: _heatmapPeriod == p.$1 ? Colors.black : C.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (p.$1 < 3) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 230,
              width: double.infinity,
              decoration: BoxDecoration(
                color: C.dark ? const Color(0xFF0B1325) : const Color(0xFFF1F5F9),
                border: Border.all(color: C.line),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CustomPaint(
                painter: _HeatmapPainter(
                  grid: grid,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Heatmap Gradient Legend
          Row(children: [
            Text('Shaded', style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(colors: [
                    Color(0xFF1E3A8A),
                    Color(0xFF0EA5E9),
                    Color(0xFF10B981),
                    Color(0xFFFACC15),
                    Color(0xFFF97316),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('Peak Sun', style: TextStyle(color: C.orange, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      StatGrid([
        StatTile('Avg sun hours', '${avgSunHrs.toStringAsFixed(1)} h/day', hi: true),
        StatTile('Peak irradiance', '$peakIrrKwhM2 kWh/m²'),
        StatTile('High-sun roof', '${unshadedPct.round()}% area'),
        StatTile('Orientation eff.', '${(orientEff * 100).round()}%'),
      ]),
      const SizedBox(height: 12),
      Panel(
        child: Text(
          _obstacles.isEmpty
              ? 'Full roof receives uniform peak solar exposure across ${_roofLenM.toStringAsFixed(1)}m × ${_roofWidM.toStringAsFixed(1)}m. Switch to Shadow Studio to add nearby buildings, tanks, or trees and inspect their exact shaded zones here.'
              : 'Heatmap accounts for ${_obstacles.length} verified obstacle${_obstacles.length == 1 ? '' : 's'} using ${_mms.label} (${_mms.clearanceM.toStringAsFixed(1)}m clearance). Place PV strings inside the bright amber/orange zones for maximum yield.',
          style: TextStyle(color: C.text, fontSize: 12.5, height: 1.4),
        ),
      ),
    ]);
  }

  // ==================== TAB 2: SUN COMPASS & OPTIMAL TILT ====================
  Widget _buildCompassTab({
    required Site site,
    required DateTime simTime,
    required double sunAlt,
    required double sunAz,
    required DayInfo day,
    required double shadowAz,
  }) {
    final optAnnual = site.lat.abs().clamp(5.0, 45.0).round();
    final optSummer = (site.lat.abs() - 12.0).clamp(5.0, 40.0).round();
    final optWinter = (site.lat.abs() + 12.0).clamp(12.0, 62.0).round();
    final bestFacing = site.lat >= 0 ? 'True South (180°)' : 'True North (0°)';

    // Sample full sunrise-to-sunset trajectory for the selected day
    final arc = <({double alt, double az})>[];
    for (var m = 300; m <= 1140; m += 20) {
      final t = DateTime(simTime.year, simTime.month, simTime.day, m ~/ 60, m % 60);
      final p = solarPosition(t, site.lat, site.lon);
      if (p.alt > 0) arc.add((alt: p.alt, az: p.az));
    }

    final riseAz = day.rise != null ? solarPosition(day.rise!, site.lat, site.lon).az : null;
    final setAz = day.set != null ? solarPosition(day.set!, site.lat, site.lon).az : null;
    final zenith = (90.0 - sunAlt).clamp(0.0, 90.0).toDouble();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.explore_outlined, color: C.sky, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('360° Sun Path Compass', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text(_fmtHourDouble(_hour), style: TextStyle(fontFamilyFallback: kMono, color: C.sky, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            width: double.infinity,
            child: CustomPaint(
              painter: _SunCompassPainter(
                sunAz: sunAz,
                sunAlt: sunAlt,
                shadowAz: shadowAz,
                arcPoints: arc,
                riseAz: riseAz,
                setAz: setAz,
                panelAz: _azimuthDeg,
                isDark: C.dark,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Sun Azimuth', '${sunAz.round()}° ${compass(sunAz)}', C.orange)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Elevation', '${sunAlt.toStringAsFixed(1)}°', C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Zenith', '${zenith.toStringAsFixed(1)}°', C.sky)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _miniStat('Shadow Cast', sunAlt > 1 ? '${shadowAz.round()}° ${compass(shadowAz)}' : 'Night', C.blue)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Sunrise Az', riseAz == null ? '-' : '${riseAz.round()}° ${compass(riseAz)}', C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Sunset Az', setAz == null ? '-' : '${setAz.round()}° ${compass(setAz)}', C.orange)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.architecture_rounded, color: C.orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Optimal Panel Tilt & Azimuth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            Text(bestFacing, style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Annual Fixed', '$optAnnual°', C.orange)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Summer Tilt', '$optSummer°', C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Winter Tilt', '$optWinter°', C.sky)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _tiltDeg = optAnnual.toDouble();
                  _azimuthDeg = site.lat >= 0 ? 180.0 : 0.0;
                  _suiteTab = 0;
                });
              },
              icon: Icon(Icons.auto_fix_high_rounded, size: 17, color: C.orange),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: C.orange.withValues(alpha: .5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              label: Text('Apply $optAnnual° Optimal Tilt to Shadow Studio', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ==================== TAB 3: SUN TIMER & GENERATION YIELD ====================
  Widget _buildTimerAndYieldTab({
    required Site site,
    required DayInfo day,
  }) {
    final hk = state.solarHourlyKw();
    final psh = state.irr?.psh ?? 0.0;
    final mp = state.monthly;
    final pr = state.pr;
    final age = state.profile.commissionDate == null
        ? 0.0
        : DateTime.now().difference(state.profile.commissionDate!).inDays / 365.25;
    final health = (1 - 0.005 * age).clamp(0.5, 1.0).toDouble();
    final daily = hk.fold(0.0, (a, b) => a + b);
    final peakKw = hk.fold(0.0, (a, b) => a > b ? a : b);
    final year = DateTime.now().year;
    final monthly = List.generate(
      12,
      (i) => site.kwp * (mp?.psh[i] ?? kMonthPshHyd[i]) * pr * health * DateTime(year, i + 2, 0).day,
    );
    final annual = monthly.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);

    // Solar Noon & Daylight Duration from day.rise / day.set
    DateTime? solarNoon;
    String daylightStr = '--';
    double dayProgress = 0.0;
    String morningGolden = '--';
    String eveningGolden = '--';
    double noonAlt = 0.0;

    if (day.rise != null && day.set != null) {
      final totalMins = day.set!.difference(day.rise!).inMinutes;
      final h = totalMins ~/ 60;
      final m = totalMins % 60;
      daylightStr = '${h}h ${m}m';
      solarNoon = day.rise!.add(Duration(minutes: totalMins ~/ 2));
      noonAlt = solarPosition(solarNoon, site.lat, site.lon).alt;
      morningGolden = '${_fmtClock(day.rise)} – ${_fmtClock(day.rise!.add(const Duration(minutes: 55)))}';
      eveningGolden = '${_fmtClock(day.set!.subtract(const Duration(minutes: 55)))} – ${_fmtClock(day.set)}';
      final now = DateTime.now();
      if (totalMins > 0) {
        dayProgress = (now.difference(day.rise!).inMinutes / totalMins).clamp(0.0, 1.0).toDouble();
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Sun Timer & Ephemeris Card
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.wb_twilight_rounded, color: C.orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Sun Timer & Daylight', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text(daylightStr, style: TextStyle(color: C.amber, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Sunrise', _fmtClock(day.rise), C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Solar Noon', '${_fmtClock(solarNoon)} · ${noonAlt.round()}°', C.orange)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Sunset', _fmtClock(day.set), C.sky)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: dayProgress,
              minHeight: 8,
              backgroundColor: C.card2,
              valueColor: AlwaysStoppedAnimation<Color>(C.orange),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Morning Golden: $morningGolden', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w600))),
            Text('Evening: $eveningGolden', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),

      // Existing Generation Forecast KPIs & Hourly Chart
      StatGrid([
        StatTile('Plant size', '${site.kwp} kWp'),
        StatTile("Today's yield", '${fmt1(daily)} kWh'),
        StatTile('Peak sun hours', psh > 0 ? '${psh.toStringAsFixed(1)} h' : '-'),
        StatTile('Peak output', '${peakKw.toStringAsFixed(2)} kW'),
      ]),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today by hour (kW)', style: title),
          const SizedBox(height: 10),
          BarChart(
            series: [BarSeries('kW', hk, const Color(0xFFF59E0B))],
            labels: List.generate(24, (i) => i % 3 == 0 ? '$i' : null),
            highlight: DateTime.now().hour,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Typical monthly yield (kWh)', style: title),
          const SizedBox(height: 10),
          BarChart(
            series: [BarSeries('kWh', monthly, const Color(0xFF38BDF8))],
            labels: months,
            highlight: DateTime.now().month - 1,
          ),
          const SizedBox(height: 6),
          Text(
            'Long-term average sunshine for ${site.city}${mp != null && mp.fetched ? '' : ' (estimate while offline)'}, performance ratio ${(pr * 100).toStringAsFixed(1)}%${age > 0 ? ', plant age ${age.toStringAsFixed(1)} y' : ''}.',
            style: TextStyle(color: C.mute, fontSize: 12.5),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      StatGrid([
        StatTile('Annual generation', '${groupIndian(annual)} kWh', hi: true),
        StatTile('Specific yield', '${(annual / (site.kwp < 0.1 ? 0.1 : site.kwp)).round()} kWh/kWp'),
        StatTile('Annual value', '₹${groupIndian(annual * site.tariff)}'),
        StatTile('CO₂ avoided / yr', '${fmt1(annual * kCo2PerKwh / 1000)} t'),
      ]),
    ]);
  }

  Widget _segBtn(String text, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? C.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: TextStyle(color: active ? Colors.white : C.mute, fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ),
      );

  Widget _legendDot(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
      ]);

  Widget _miniStat(String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 10.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      );
}

// ============================================================================
// CUSTOM PAINTER 1: 2D CAD PLAN & 3D ISOMETRIC ROOFTOP SHADOW CANVAS
// ============================================================================
class _RoofShadowPainter extends CustomPainter {
  final bool is3d;
  final double roofLenM, roofWidM, setbackM, mmsClearanceM, tiltDeg;
  final double sunAlt, sunAz;
  final List<_RoofObstacle> obstacles;
  final bool isDark;

  _RoofShadowPainter({
    required this.is3d,
    required this.roofLenM,
    required this.roofWidM,
    required this.setbackM,
    required this.mmsClearanceM,
    required this.tiltDeg,
    required this.sunAlt,
    required this.sunAz,
    required this.obstacles,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (is3d) {
      _paintIsometric3D(canvas, size);
    } else {
      _paint2dCad(canvas, size);
    }
  }

  void _paint2dCad(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxSpan = math.max(roofLenM, roofWidM) + 6.0;
    final scale = (math.min(size.width, size.height) - 34) / maxSpan;

    Offset worldToCanvas(double xM, double yM) => Offset(c.dx + xM * scale, c.dy - yM * scale);

    // Subtle CAD grid
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Roof footprint rectangle
    final roofRect = Rect.fromCenter(center: c, width: roofLenM * scale, height: roofWidM * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(4)),
      Paint()..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(4)),
      Paint()
        ..color = isDark ? const Color(0xFF64748B) : const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Usable PV setback zone
    final usableW = math.max(0.0, (roofLenM - setbackM * 2) * scale);
    final usableH = math.max(0.0, (roofWidM - setbackM * 2) * scale);
    if (usableW > 8 && usableH > 8) {
      final pvRect = Rect.fromCenter(center: c, width: usableW, height: usableH);
      canvas.drawRect(
        pvRect,
        Paint()
          ..color = const Color(0xFF0EA5E9).withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Draw PV panel rows inside usable area
      final cols = math.max(1, ((roofLenM - setbackM * 2) / 1.25).floor());
      final rows = math.max(1, ((roofWidM - setbackM * 2) / 2.4).floor());
      final cellW = usableW / cols;
      final cellH = usableH / rows;
      final panelFill = Paint()..color = const Color(0xFF1D4ED8).withValues(alpha: 0.78);
      final panelStroke = Paint()
        ..color = const Color(0xFF93C5FD).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      for (var r = 0; r < rows; r++) {
        for (var col = 0; col < cols; col++) {
          final pr = Rect.fromLTWH(
            pvRect.left + col * cellW + 1.5,
            pvRect.top + r * cellH + 2.5,
            math.max(2, cellW - 3),
            math.max(2, cellH - 5),
          );
          canvas.drawRect(pr, panelFill);
          canvas.drawRect(pr, panelStroke);
        }
      }
    }

    // Cast shadows from verified obstacles
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final dx = math.sin(shAzRad);
    final dy = math.cos(shAzRad);

    for (final obs in obstacles) {
      final bRad = obs.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * obs.distM;
      final oy = math.cos(bRad) * obs.distM;
      final effH = math.max(0.0, obs.heightM - mmsClearanceM);

      if (sunAlt > 1.5 && effH > 0.05) {
        final shLen = (effH / math.tan(sunAlt * math.pi / 180.0)).clamp(0.0, 28.0).toDouble();
        final px = -dy * (obs.widthM / 2.0);
        final py = dx * (obs.widthM / 2.0);

        final p1 = worldToCanvas(ox + px, oy + py);
        final p2 = worldToCanvas(ox - px, oy - py);
        final p3 = worldToCanvas(ox - px + dx * shLen, oy - py + dy * shLen);
        final p4 = worldToCanvas(ox + px + dx * shLen, oy + py + dy * shLen);

        final path = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..lineTo(p4.dx, p4.dy)
          ..close();

        canvas.drawPath(
          path,
          Paint()..color = (isDark ? const Color(0xFF020617) : const Color(0xFF0F172A)).withValues(alpha: 0.56),
        );
      }

      // Draw obstacle footprint
      final oPt = worldToCanvas(ox, oy);
      final oRadPx = (obs.widthM * scale / 2).clamp(5.0, 22.0).toDouble();
      if (obs.type == 'tree') {
        canvas.drawCircle(oPt, oRadPx, Paint()..color = const Color(0xFF16A34A));
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: oPt, width: oRadPx * 1.8, height: oRadPx * 1.3), const Radius.circular(3)),
          Paint()..color = const Color(0xFFEF4444),
        );
      }
    }

    // Live sun ray indicator at edge of canvas
    if (sunAlt > 0) {
      final sRad = (sunAz - 90.0) * math.pi / 180.0;
      final rayR = math.min(size.width, size.height) * 0.43;
      final sunPt = Offset(c.dx + math.cos(sRad) * rayR, c.dy + math.sin(sRad) * rayR);
      canvas.drawLine(
        sunPt,
        c,
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.45)
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(sunPt, 11, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.28));
      canvas.drawCircle(sunPt, 6, Paint()..color = const Color(0xFFF59E0B));
    }

    _drawNorthBadge(canvas, const Offset(22, 22), isDark);
  }

  void _paintIsometric3D(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.58);
    final maxSpan = math.max(roofLenM, roofWidM) + 6.0;
    final scale = (math.min(size.width, size.height) - 30) / (maxSpan * 1.25);

    Offset iso(double xM, double yM, double zM) {
      final sx = (xM - yM) * 0.866 * scale;
      final sy = (xM + yM) * 0.44 * scale - zM * 0.95 * scale;
      return Offset(c.dx + sx, c.dy + sy);
    }

    // Draw extruded host building walls (3m visual height below roof slab)
    const bH = -2.4;
    final hl = roofLenM / 2;
    final hw = roofWidM / 2;
    final r0 = iso(-hl, -hw, 0);
    final r1 = iso(hl, -hw, 0);
    final r2 = iso(hl, hw, 0);
    final r3 = iso(-hl, hw, 0);
    final b1 = iso(hl, -hw, bH);
    final b2 = iso(hl, hw, bH);
    final b3 = iso(-hl, hw, bH);

    // Right wall
    canvas.drawPath(
      Path()
        ..moveTo(r1.dx, r1.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(b2.dx, b2.dy)
        ..lineTo(b1.dx, b1.dy)
        ..close(),
      Paint()..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
    );
    // Front wall
    canvas.drawPath(
      Path()
        ..moveTo(r2.dx, r2.dy)
        ..lineTo(r3.dx, r3.dy)
        ..lineTo(b3.dx, b3.dy)
        ..lineTo(b2.dx, b2.dy)
        ..close(),
      Paint()..color = isDark ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
    );
    // Roof slab top
    final slabPath = Path()
      ..moveTo(r0.dx, r0.dy)
      ..lineTo(r1.dx, r1.dy)
      ..lineTo(r2.dx, r2.dy)
      ..lineTo(r3.dx, r3.dy)
      ..close();
    canvas.drawPath(slabPath, Paint()..color = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    canvas.drawPath(
      slabPath,
      Paint()
        ..color = isDark ? const Color(0xFF64748B) : const Color(0xFF475569)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // 3D PV array panels elevated at mmsClearanceM with tilt
    final usableL = math.max(1.5, roofLenM - setbackM * 2);
    final usableW = math.max(1.5, roofWidM - setbackM * 2);
    final rows = math.max(1, (usableW / 2.5).floor());
    final cols = math.max(1, (usableL / 1.4).floor());
    final cellL = usableL / cols;
    final cellW = usableW / rows;
    final lift = mmsClearanceM * 0.45;
    final tiltLift = math.sin(tiltDeg * math.pi / 180.0) * 1.1;

    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final x0 = -usableL / 2 + col * cellL + 0.1;
        final x1 = x0 + cellL - 0.2;
        final y0 = -usableW / 2 + r * cellW + 0.2;
        final y1 = y0 + cellW - 0.5;
        final p0 = iso(x0, y0, lift + tiltLift);
        final p1 = iso(x1, y0, lift + tiltLift);
        final p2 = iso(x1, y1, lift);
        final p3 = iso(x0, y1, lift);
        final pp = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close();
        canvas.drawPath(pp, Paint()..color = const Color(0xFF1D4ED8).withValues(alpha: 0.85));
        canvas.drawPath(
          pp,
          Paint()
            ..color = const Color(0xFF93C5FD).withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

    // Cast shadows & extruded 3D obstacles
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final dx = math.sin(shAzRad);
    final dy = -math.cos(shAzRad); // +y is South in iso projection

    for (final obs in obstacles) {
      final bRad = obs.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * obs.distM;
      final oy = -math.cos(bRad) * obs.distM;
      final oh = obs.heightM.clamp(0.5, 10.0).toDouble() * 0.55;
      final ow = (obs.widthM * 0.35).clamp(0.4, 2.5).toDouble();

      // Shadow polygon on roof plane
      if (sunAlt > 1.5 && obs.heightM > mmsClearanceM) {
        final shLen = ((obs.heightM - mmsClearanceM) / math.tan(sunAlt * math.pi / 180.0)).clamp(0.0, 22.0).toDouble();
        final sp0 = iso(ox - ow, oy, 0.02);
        final sp1 = iso(ox + ow, oy, 0.02);
        final sp2 = iso(ox + ow + dx * shLen, oy + dy * shLen, 0.02);
        final sp3 = iso(ox - ow + dx * shLen, oy + dy * shLen, 0.02);
        canvas.drawPath(
          Path()
            ..moveTo(sp0.dx, sp0.dy)
            ..lineTo(sp1.dx, sp1.dy)
            ..lineTo(sp2.dx, sp2.dy)
            ..lineTo(sp3.dx, sp3.dy)
            ..close(),
          Paint()..color = const Color(0xFF020617).withValues(alpha: 0.52),
        );
      }

      // 3D obstacle prism
      final base = iso(ox, oy, 0);
      final top = iso(ox, oy, oh);
      final col = obs.type == 'tree' ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
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

    // Live sun orb in sky
    if (sunAlt > 0) {
      final sX = size.width * (0.15 + ((sunAz.clamp(60.0, 300.0).toDouble() - 60.0) / 240.0) * 0.70);
      final sY = size.height * (0.34 - (sunAlt.clamp(0.0, 85.0).toDouble() / 85.0) * 0.25);
      final sunPt = Offset(sX, sY);
      canvas.drawCircle(sunPt, 14, Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.26));
      canvas.drawCircle(sunPt, 7, Paint()..color = const Color(0xFFF59E0B));
    }

    _drawNorthBadge(canvas, const Offset(22, 22), isDark);
  }

  void _drawNorthBadge(Canvas canvas, Offset center, bool isDark) {
    canvas.drawCircle(center, 12, Paint()..color = (isDark ? const Color(0xFF1E293B) : Colors.white).withValues(alpha: 0.9));
    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RoofShadowPainter old) => true;
}

// ============================================================================
// CUSTOM PAINTER 2: ROOF SUNLIGHT HEATMAP
// ============================================================================
class _HeatmapPainter extends CustomPainter {
  final List<List<double>> grid;
  final double roofLenM, roofWidM;
  final List<_RoofObstacle> obstacles;
  final bool isDark;

  _HeatmapPainter({
    required this.grid,
    required this.roofLenM,
    required this.roofWidM,
    required this.obstacles,
    required this.isDark,
  });

  Color _heatColor(double t) {
    final v = t.clamp(0.0, 1.0).toDouble();
    if (v < 0.35) {
      return Color.lerp(const Color(0xFF1E3A8A), const Color(0xFF0EA5E9), v / 0.35)!;
    } else if (v < 0.65) {
      return Color.lerp(const Color(0xFF0EA5E9), const Color(0xFF10B981), (v - 0.35) / 0.30)!;
    } else if (v < 0.85) {
      return Color.lerp(const Color(0xFF10B981), const Color(0xFFFACC15), (v - 0.65) / 0.20)!;
    } else {
      return Color.lerp(const Color(0xFFFACC15), const Color(0xFFF97316), (v - 0.85) / 0.15)!;
    }
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

    // Draw obstacle markers over heatmap
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

    // Cardinal labels
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
  bool shouldRepaint(covariant _HeatmapPainter old) => true;
}

// ============================================================================
// CUSTOM PAINTER 3: ENHANCED 360° SUN PATH COMPASS
// ============================================================================
class _SunCompassPainter extends CustomPainter {
  final double sunAz, sunAlt, shadowAz, panelAz;
  final List<({double alt, double az})> arcPoints;
  final double? riseAz, setAz;
  final bool isDark;

  _SunCompassPainter({
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

    // Sunrise & Sunset azimuth markers on horizon ring
    if (riseAz != null) {
      final p = polar(riseAz!, r);
      canvas.drawCircle(p, 4.5, Paint()..color = const Color(0xFFFACC15));
    }
    if (setAz != null) {
      final p = polar(setAz!, r);
      canvas.drawCircle(p, 4.5, Paint()..color = const Color(0xFFF97316));
    }

    // Full daylight solar arc path
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
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }

    // Panel facing direction arrow
    final pFacing = polar(panelAz, r * 0.38);
    canvas.drawLine(
      c,
      pFacing,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.85)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Center building/array dot
    canvas.drawCircle(c, 5.5, Paint()..color = const Color(0xFF0A84FF));

    if (sunAlt > 0) {
      final sunDist = r * (1.0 - (sunAlt.clamp(0.0, 90.0).toDouble() / 90.0) * 0.85);
      final sunPt = polar(sunAz, sunDist);
      final shPt = polar(shadowAz, r * (1.0 - (sunAlt.clamp(5.0, 90.0).toDouble() / 95.0) * 0.65));

      // Shadow ray
      canvas.drawLine(
        c,
        shPt,
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.85)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      // Sun ray
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
  bool shouldRepaint(covariant _SunCompassPainter old) =>
      old.sunAz != sunAz ||
      old.sunAlt != sunAlt ||
      old.shadowAz != shadowAz ||
      old.panelAz != panelAz ||
      old.riseAz != riseAz ||
      old.setAz != setAz ||
      old.arcPoints.length != arcPoints.length ||
      old.isDark != isDark;
}
