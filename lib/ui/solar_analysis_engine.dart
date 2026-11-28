import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/calc.dart';
import '../core/sun.dart';

/// Verified rooftop or surrounding obstacle for real-time 2D/3D shadow, heatmap, and PVsyst simulation.
class RoofObstacle {
  final String id;
  final String name;
  final String type; // tank | parapet | lift | tree | building
  final double heightM;
  final double widthM;
  final double depthM;
  final double distM;
  final double bearingDeg; // 0 = N, 90 = E, 180 = S, 270 = W
  final bool fromOsm;

  const RoofObstacle({
    required this.id,
    required this.name,
    required this.type,
    required this.heightM,
    required this.widthM,
    this.depthM = 2.0,
    required this.distM,
    required this.bearingDeg,
    this.fromOsm = false,
  });

  RoofObstacle copyWith({
    String? name,
    String? type,
    double? heightM,
    double? widthM,
    double? depthM,
    double? distM,
    double? bearingDeg,
    bool? fromOsm,
  }) =>
      RoofObstacle(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        heightM: heightM ?? this.heightM,
        widthM: widthM ?? this.widthM,
        depthM: depthM ?? this.depthM,
        distM: distM ?? this.distM,
        bearingDeg: bearingDeg ?? this.bearingDeg,
        fromOsm: fromOsm ?? this.fromOsm,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'heightM': heightM,
        'widthM': widthM,
        'depthM': depthM,
        'distM': distM,
        'bearingDeg': bearingDeg,
        'fromOsm': fromOsm,
      };

  factory RoofObstacle.fromJson(Map<String, dynamic> j) => RoofObstacle(
        id: (j['id'] as String?) ?? 'obs',
        name: (j['name'] as String?) ?? 'Obstacle',
        type: (j['type'] as String?) ?? 'tank',
        heightM: (j['heightM'] as num?)?.toDouble() ?? 2.0,
        widthM: (j['widthM'] as num?)?.toDouble() ?? 2.0,
        depthM: (j['depthM'] as num?)?.toDouble() ?? 2.0,
        distM: (j['distM'] as num?)?.toDouble() ?? 4.0,
        bearingDeg: (j['bearingDeg'] as num?)?.toDouble() ?? 180.0,
        fromOsm: (j['fromOsm'] as bool?) ?? false,
      );
}

/// Rooftop PV array zone inside the 2D CAD blueprint.
class PvZone {
  final String id;
  final String name;
  final double xFrac; // 0..1 left fraction within usable roof
  final double yFrac; // 0..1 top fraction within usable roof
  final double wFrac; // 0.1..1 width fraction
  final double hFrac; // 0.1..1 height fraction
  final bool enabled;

  const PvZone({
    required this.id,
    required this.name,
    required this.xFrac,
    required this.yFrac,
    required this.wFrac,
    required this.hFrac,
    this.enabled = true,
  });

  PvZone copyWith({
    String? name,
    double? xFrac,
    double? yFrac,
    double? wFrac,
    double? hFrac,
    bool? enabled,
  }) =>
      PvZone(
        id: id,
        name: name ?? this.name,
        xFrac: xFrac ?? this.xFrac,
        yFrac: yFrac ?? this.yFrac,
        wFrac: wFrac ?? this.wFrac,
        hFrac: hFrac ?? this.hFrac,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'xFrac': xFrac,
        'yFrac': yFrac,
        'wFrac': wFrac,
        'hFrac': hFrac,
        'enabled': enabled,
      };

  factory PvZone.fromJson(Map<String, dynamic> j) => PvZone(
        id: (j['id'] as String?) ?? 'z1',
        name: (j['name'] as String?) ?? 'PV Zone',
        xFrac: (j['xFrac'] as num?)?.toDouble() ?? 0.0,
        yFrac: (j['yFrac'] as num?)?.toDouble() ?? 0.0,
        wFrac: (j['wFrac'] as num?)?.toDouble() ?? 1.0,
        hFrac: (j['hFrac'] as num?)?.toDouble() ?? 1.0,
        enabled: (j['enabled'] as bool?) ?? true,
      );
}

/// MMS Mounting Structure preset matching Solar Analysis Studio.
class MmsPreset {
  final String id;
  final String label;
  final String desc;
  final double clearanceM;
  final double setbackM;
  final double fillFactor;

  const MmsPreset({
    required this.id,
    required this.label,
    required this.desc,
    required this.clearanceM,
    required this.setbackM,
    required this.fillFactor,
  });
}

const List<MmsPreset> kMmsPresets = [
  MmsPreset(
    id: 'low_rise',
    label: 'Low-Rise RCC',
    desc: '0.5m anchored rails · 0.6m setback',
    clearanceM: 0.50,
    setbackM: 0.60,
    fillFactor: 0.72,
  ),
  MmsPreset(
    id: 'elevated_pergola',
    label: 'Elevated Pergola',
    desc: '2.6m terrace headroom · clears parapet',
    clearanceM: 2.60,
    setbackM: 0.35,
    fillFactor: 0.85,
  ),
  MmsPreset(
    id: 'pitched_flush',
    label: 'Pitched Flush',
    desc: '0.15m rail · metal/tile roof flush',
    clearanceM: 0.15,
    setbackM: 0.40,
    fillFactor: 0.80,
  ),
  MmsPreset(
    id: 'tiered_split',
    label: 'Tiered Split',
    desc: '1.3m stepped dual-level array',
    clearanceM: 1.30,
    setbackM: 0.50,
    fillFactor: 0.77,
  ),
];

/// Month / Solstice options matching Web App Solar Analysis Studio.
class MonthOption {
  final String label;
  final int month;
  final int day;
  const MonthOption(this.label, this.month, this.day);
}

const List<MonthOption> kMonthOptions = [
  MonthOption('Jan 17', 1, 17),
  MonthOption('Feb 16', 2, 16),
  MonthOption('Mar 20 (Equinox)', 3, 20),
  MonthOption('Apr 15', 4, 15),
  MonthOption('May 15', 5, 15),
  MonthOption('Jun 21 (Solstice)', 6, 21),
  MonthOption('Jul 17', 7, 17),
  MonthOption('Aug 16', 8, 16),
  MonthOption('Sep 22 (Equinox)', 9, 22),
  MonthOption('Oct 15', 10, 15),
  MonthOption('Nov 14', 11, 14),
  MonthOption('Dec 21 (Solstice)', 12, 21),
];

/// 8-sector Horizon Profile presets (N, NE, E, SE, S, SW, W, NW elevation degrees).
const Map<String, List<double>> kHorizonPresets = {
  'Flat Horizon': [2, 2, 2, 2, 2, 2, 2, 2],
  'Urban Low-Rise': [8, 10, 12, 9, 7, 9, 12, 10],
  'Hilly Valley': [14, 18, 22, 16, 10, 15, 20, 16],
  'Dense City': [18, 22, 26, 20, 14, 20, 26, 22],
};

const List<String> kHorizonDirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// String Topology electrical shading multipliers matching PVsyst model.
class TopologyOption {
  final String id;
  final String label;
  final double electricalFactor; // multiplier over linear shading loss
  final String note;
  const TopologyOption(this.id, this.label, this.electricalFactor, this.note);
}

const List<TopologyOption> kStringTopologies = [
  TopologyOption('halfcut_portrait', 'Half-Cut Portrait', 1.25, 'Twin half-cell bypass diodes; low bottom-edge loss'),
  TopologyOption('halfcut_landscape', 'Half-Cut Landscape', 1.15, 'Best inter-row shadow tolerance in tilted rows'),
  TopologyOption('fullcell_portrait', 'Full-Cell Portrait', 1.65, 'Higher string mismatch when partial shadow hits bottom row'),
  TopologyOption('microinverter', 'Microinverter / Optimizer', 1.02, 'Module-level MPPT eliminates string mismatch loss'),
];

/// 8-item engineering site inspection checklist.
const List<(String id, String title, String detail)> kInspectionItems = [
  ('roof_struct', 'Structural Roof Integrity', 'RCC slab / purlins verified for dead + wind load'),
  ('earthing', 'Earthing & Lightning Arrester', '3-pit copper/chemical earthing + LA route clear'),
  ('acdb_dcdb', 'ACDB / DCDB Wall Space', 'Shaded, ventilated indoor wall for protection boxes'),
  ('inverter_loc', 'Inverter Ventilation & Shade', 'Cool, rain-protected location near DB / meter'),
  ('conduit', 'DC/AC Cable Conduit Route', 'UV-resistant HDPE/PVC conduit path without sharp bends'),
  ('shadow_core', 'Shadow-Free 09:00–15:00 Window', 'Core PV array clear of parapet & overhead tank shadow'),
  ('net_meter', 'DISCOM Net-Meter Access', 'Bidirectional meter enclosure & isolator reachable'),
  ('safety', 'Maintenance Walkway & Lifeline', 'Safe perimeter setback & cleaning water point available'),
];

/// PVsyst monthly result row.
class MonthlyShadingRow {
  final String monthLabel;
  final double unshadedPct;
  final double linearLossPct;
  final double electricalLossPct;
  final double horizonLossPct;
  final double netKwh;
  const MonthlyShadingRow({
    required this.monthLabel,
    required this.unshadedPct,
    required this.linearLossPct,
    required this.electricalLossPct,
    required this.horizonLossPct,
    required this.netKwh,
  });
}

/// Complete annual PVsyst simulation summary.
class AnnualShadingReport {
  final double annualUnshadedPct;
  final double annualLinearLossPct;
  final double annualElectricalLossPct;
  final double annualHorizonLossPct;
  final double orientEffPct;
  final double annualNetKwh;
  final double specificYield;
  final List<MonthlyShadingRow> months;
  const AnnualShadingReport({
    required this.annualUnshadedPct,
    required this.annualLinearLossPct,
    required this.annualElectricalLossPct,
    required this.annualHorizonLossPct,
    required this.orientEffPct,
    required this.annualNetKwh,
    required this.specificYield,
    required this.months,
  });
}

/// Persistent Solar Analysis Project record stored in SharedPreferences Vault.
class SolarVaultProject {
  final String id;
  final String title;
  final String inspectorName;
  final String status; // Draft | Reviewed | Approved
  final String remarks;
  final String savedAtIso;
  final String city;
  final double lat;
  final double lon;
  final double elevationM;
  final double roofLenM;
  final double roofWidM;
  final double buildingHeightM;
  final double parapetHeightM;
  final double perimeterSetbackM;
  final double tiltDeg;
  final double azimuthDeg;
  final double albedo;
  final double rowPitchM;
  final double collectorWidthM;
  final int numRows;
  final int moduleWp;
  final String roofStructureType;
  final int mmsIndex;
  final String assemblyLayer;
  final double columnSpacingM;
  final bool crossBracing;
  final bool brickPedestals;
  final String stringTopologyId;
  final List<double> horizonProfile;
  final List<RoofObstacle> obstacles;
  final List<PvZone> zones;
  final Map<String, bool> checklist;

  const SolarVaultProject({
    required this.id,
    required this.title,
    required this.inspectorName,
    required this.status,
    required this.remarks,
    required this.savedAtIso,
    required this.city,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.roofLenM,
    required this.roofWidM,
    required this.buildingHeightM,
    required this.parapetHeightM,
    required this.perimeterSetbackM,
    required this.tiltDeg,
    required this.azimuthDeg,
    required this.albedo,
    required this.rowPitchM,
    required this.collectorWidthM,
    required this.numRows,
    required this.moduleWp,
    required this.roofStructureType,
    required this.mmsIndex,
    required this.assemblyLayer,
    required this.columnSpacingM,
    required this.crossBracing,
    required this.brickPedestals,
    required this.stringTopologyId,
    required this.horizonProfile,
    required this.obstacles,
    required this.zones,
    required this.checklist,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'inspectorName': inspectorName,
        'status': status,
        'remarks': remarks,
        'savedAtIso': savedAtIso,
        'city': city,
        'lat': lat,
        'lon': lon,
        'elevationM': elevationM,
        'roofLenM': roofLenM,
        'roofWidM': roofWidM,
        'buildingHeightM': buildingHeightM,
        'parapetHeightM': parapetHeightM,
        'perimeterSetbackM': perimeterSetbackM,
        'tiltDeg': tiltDeg,
        'azimuthDeg': azimuthDeg,
        'albedo': albedo,
        'rowPitchM': rowPitchM,
        'collectorWidthM': collectorWidthM,
        'numRows': numRows,
        'moduleWp': moduleWp,
        'roofStructureType': roofStructureType,
        'mmsIndex': mmsIndex,
        'assemblyLayer': assemblyLayer,
        'columnSpacingM': columnSpacingM,
        'crossBracing': crossBracing,
        'brickPedestals': brickPedestals,
        'stringTopologyId': stringTopologyId,
        'horizonProfile': horizonProfile,
        'obstacles': obstacles.map((e) => e.toJson()).toList(),
        'zones': zones.map((e) => e.toJson()).toList(),
        'checklist': checklist,
      };

  factory SolarVaultProject.fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    int iv(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    final hpRaw = j['horizonProfile'];
    final hp = (hpRaw is List && hpRaw.length == 8)
        ? hpRaw.map((e) => (e as num?)?.toDouble() ?? 2.0).toList()
        : List<double>.from(kHorizonPresets['Flat Horizon']!);
    final obsRaw = j['obstacles'];
    final obs = obsRaw is List
        ? obsRaw.whereType<Map>().map((e) => RoofObstacle.fromJson(e.cast<String, dynamic>())).toList()
        : <RoofObstacle>[];
    final zRaw = j['zones'];
    final zs = zRaw is List
        ? zRaw.whereType<Map>().map((e) => PvZone.fromJson(e.cast<String, dynamic>())).toList()
        : <PvZone>[];
    final chkRaw = j['checklist'];
    final chk = <String, bool>{};
    if (chkRaw is Map) {
      chkRaw.forEach((k, v) => chk[k.toString()] = v == true);
    }
    return SolarVaultProject(
      id: (j['id'] as String?) ?? 'proj',
      title: (j['title'] as String?) ?? 'Solar Analysis Project',
      inspectorName: (j['inspectorName'] as String?) ?? 'Solar Engineer',
      status: (j['status'] as String?) ?? 'Draft',
      remarks: (j['remarks'] as String?) ?? '',
      savedAtIso: (j['savedAtIso'] as String?) ?? DateTime.now().toIso8601String(),
      city: (j['city'] as String?) ?? 'Site',
      lat: d('lat', 17.385),
      lon: d('lon', 78.4867),
      elevationM: d('elevationM', 520),
      roofLenM: d('roofLenM', 14),
      roofWidM: d('roofWidM', 10),
      buildingHeightM: d('buildingHeightM', 6.0),
      parapetHeightM: d('parapetHeightM', 1.0),
      perimeterSetbackM: d('perimeterSetbackM', 0.6),
      tiltDeg: d('tiltDeg', 18),
      azimuthDeg: d('azimuthDeg', 180),
      albedo: d('albedo', 0.20),
      rowPitchM: d('rowPitchM', 3.6),
      collectorWidthM: d('collectorWidthM', 2.28),
      numRows: iv('numRows', 3),
      moduleWp: iv('moduleWp', 550),
      roofStructureType: (j['roofStructureType'] as String?) ?? 'rcc_flat',
      mmsIndex: iv('mmsIndex', 0),
      assemblyLayer: (j['assemblyLayer'] as String?) ?? 'structure_and_panels',
      columnSpacingM: d('columnSpacingM', 3.2),
      crossBracing: (j['crossBracing'] as bool?) ?? true,
      brickPedestals: (j['brickPedestals'] as bool?) ?? true,
      stringTopologyId: (j['stringTopologyId'] as String?) ?? 'halfcut_portrait',
      horizonProfile: hp,
      obstacles: obs,
      zones: zs,
      checklist: chk,
    );
  }
}

/// Core Solar Analysis Physics, OSM Scanner, NASA POWER Fetcher, and Project Vault Storage.
class SolarAnalysisEngine {
  static const String _vaultKey = 'solar_analysis_vault_v1';

  /// Interpolates 8-sector horizon elevation angle (deg) for any solar azimuth (0..360).
  static double horizonElevationAt(double azDeg, List<double> profile8) {
    if (profile8.length != 8) return 2.0;
    final norm = ((azDeg % 360.0) + 360.0) % 360.0;
    final sector = norm / 45.0;
    final i0 = sector.floor() % 8;
    final i1 = (i0 + 1) % 8;
    final t = sector - sector.floor();
    return profile8[i0] * (1.0 - t) + profile8[i1] * t;
  }

  /// Checks if point (px, py meters from roof center; +x = East, +y = North) is shaded.
  static bool isPointShaded({
    required double px,
    required double py,
    required double sunAlt,
    required double sunAz,
    required double mmsClearanceM,
    required List<RoofObstacle> obstacles,
  }) {
    if (sunAlt <= 1.5) return true;
    if (obstacles.isEmpty) return false;
    final tanAlt = math.tan(sunAlt * math.pi / 180.0);
    if (tanAlt <= 0.01) return true;
    final shAzRad = ((sunAz + 180.0) % 360.0) * math.pi / 180.0;
    final dx = math.sin(shAzRad);
    final dy = math.cos(shAzRad);

    for (final o in obstacles) {
      final effH = o.heightM - mmsClearanceM;
      if (effH <= 0.05) continue;
      final shLen = (effH / tanAlt).clamp(0.0, 65.0).toDouble();
      final bRad = o.bearingDeg * math.pi / 180.0;
      final ox = math.sin(bRad) * o.distM;
      final oy = math.cos(bRad) * o.distM;

      final vx = px - ox;
      final vy = py - oy;
      final along = vx * dx + vy * dy;
      final perp = (vx * dy - vy * dx).abs();
      final halfW = math.max(0.45, o.widthM / 2.0);
      if (along >= -halfW * 0.4 && along <= shLen && perp <= halfW) {
        return true;
      }
    }
    return false;
  }

  /// Instantaneous unshaded roof fraction (0..1) including near obstacles & horizon line.
  static double unshadedFraction({
    required double roofLenM,
    required double roofWidM,
    required double setbackM,
    required double mmsClearanceM,
    required double sunAlt,
    required double sunAz,
    required List<RoofObstacle> obstacles,
    required List<double> horizonProfile,
  }) {
    if (sunAlt <= 1.5) return 0.0;
    final hElev = horizonElevationAt(sunAz, horizonProfile);
    if (sunAlt < hElev) return 0.18; // diffuse sky only when behind far horizon
    if (obstacles.isEmpty) return 1.0;

    final usableL = math.max(2.0, roofLenM - setbackM * 2);
    final usableW = math.max(2.0, roofWidM - setbackM * 2);
    const nx = 9;
    const ny = 7;
    var unshaded = 0;
    for (var ix = 0; ix < nx; ix++) {
      final px = -usableL / 2 + (ix + 0.5) * (usableL / nx);
      for (var iy = 0; iy < ny; iy++) {
        final py = -usableW / 2 + (iy + 0.5) * (usableW / ny);
        if (!isPointShaded(
          px: px,
          py: py,
          sunAlt: sunAlt,
          sunAz: sunAz,
          mmsClearanceM: mmsClearanceM,
          obstacles: obstacles,
        )) {
          unshaded++;
        }
      }
    }
    return unshaded / (nx * ny);
  }

  /// Orientation efficiency (tilt + azimuth + ground albedo bifacial/diffuse gain).
  static double orientationEfficiency({
    required double lat,
    required double tiltDeg,
    required double azimuthDeg,
    required double albedo,
  }) {
    final optTilt = lat.abs().clamp(5.0, 45.0).toDouble();
    final optAz = lat >= 0 ? 180.0 : 0.0;
    final tiltDiff = (tiltDeg - optTilt).abs();
    var azDiff = (azimuthDeg - optAz).abs();
    if (azDiff > 180) azDiff = 360 - azDiff;
    final tiltLoss = (tiltDiff * tiltDiff) * 0.00018;
    final azLoss = (azDiff / 180.0) * 0.14 * math.sin(tiltDeg * math.pi / 180.0).clamp(0.15, 1.0).toDouble();
    final albedoBonus = ((albedo - 0.20) * 0.06).clamp(-0.02, 0.04).toDouble();
    return (1.0 - tiltLoss - azLoss + albedoBonus).clamp(0.70, 1.03).toDouble();
  }

  /// Inter-row self-shading minimum row pitch (meters) at winter solstice 09:00–15:00.
  static double recommendedRowPitchM({
    required double lat,
    required double tiltDeg,
    required double collectorWidthM,
  }) {
    final winterNoonAlt = (90.0 - (lat.abs() + 23.44)).clamp(12.0, 80.0).toDouble();
    final designAlt = (winterNoonAlt * 0.72).clamp(10.0, 65.0).toDouble(); // ~09:30 / 14:30 winter sun
    final proj = collectorWidthM * math.cos(tiltDeg * math.pi / 180.0);
    final rise = collectorWidthM * math.sin(tiltDeg * math.pi / 180.0);
    final shadow = rise / math.tan(designAlt * math.pi / 180.0);
    return (proj + shadow).clamp(1.5, 12.0).toDouble();
  }

  /// Full 12-Month PVsyst Shading & Yield Simulation.
  static AnnualShadingReport runAnnualPvSystSimulation({
    required double lat,
    required double lon,
    required double kwp,
    required double pr,
    required double roofLenM,
    required double roofWidM,
    required double setbackM,
    required double mmsClearanceM,
    required double tiltDeg,
    required double azimuthDeg,
    required double albedo,
    required String stringTopologyId,
    required List<RoofObstacle> obstacles,
    required List<double> horizonProfile,
    required List<double>? monthlyPsh,
  }) {
    final topo = kStringTopologies.firstWhere(
      (t) => t.id == stringTopologyId,
      orElse: () => kStringTopologies.first,
    );
    final orientEff = orientationEfficiency(
      lat: lat,
      tiltDeg: tiltDeg,
      azimuthDeg: azimuthDeg,
      albedo: albedo,
    );
    final year = DateTime.now().year;
    const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final rows = <MonthlyShadingRow>[];

    var totalUnshadedW = 0.0;
    var totalHorizonW = 0.0;
    var totalLinearW = 0.0;
    var totalW = 0.0;
    var totalNetKwh = 0.0;

    for (var m = 0; m < 12; m++) {
      final d = DateTime(year, m + 1, 15);
      var mW = 0.0;
      var mUnshaded = 0.0;
      var mHorizonLoss = 0.0;
      var mNearLoss = 0.0;

      for (var h = 7; h <= 17; h++) {
        final p = solarPosition(DateTime(d.year, d.month, d.day, h, 30), lat, lon);
        if (p.alt <= 2.0) continue;
        final w = math.sin(p.alt * math.pi / 180.0);
        mW += w;
        final hElev = horizonElevationAt(p.az, horizonProfile);
        if (p.alt < hElev) {
          mHorizonLoss += 0.82 * w;
          mUnshaded += 0.18 * w;
        } else {
          final frac = unshadedFraction(
            roofLenM: roofLenM,
            roofWidM: roofWidM,
            setbackM: setbackM,
            mmsClearanceM: mmsClearanceM,
            sunAlt: p.alt,
            sunAz: p.az,
            obstacles: obstacles,
            horizonProfile: const [0, 0, 0, 0, 0, 0, 0, 0],
          );
          mNearLoss += (1.0 - frac) * w;
          mUnshaded += frac * w;
        }
      }

      final unshPct = mW > 0 ? (mUnshaded / mW * 100.0).clamp(0.0, 100.0).toDouble() : 100.0;
      final horPct = mW > 0 ? (mHorizonLoss / mW * 100.0).clamp(0.0, 100.0).toDouble() : 0.0;
      final linPct = mW > 0 ? (mNearLoss / mW * 100.0).clamp(0.0, 100.0).toDouble() : 0.0;
      final elecPct = (linPct * topo.electricalFactor).clamp(0.0, 85.0).toDouble();

      final psh = (monthlyPsh != null && monthlyPsh.length == 12) ? monthlyPsh[m] : kMonthPshHyd[m];
      final daysInMonth = DateTime(year, m + 2, 0).day;
      final baseKwh = kwp * psh * pr * daysInMonth * orientEff;
      final netFactor = (1.0 - (horPct + elecPct) / 100.0).clamp(0.15, 1.0).toDouble();
      final netKwh = baseKwh * netFactor;

      rows.add(MonthlyShadingRow(
        monthLabel: mNames[m],
        unshadedPct: unshPct,
        linearLossPct: linPct,
        electricalLossPct: elecPct,
        horizonLossPct: horPct,
        netKwh: netKwh,
      ));

      totalW += mW;
      totalUnshadedW += mUnshaded;
      totalHorizonW += mHorizonLoss;
      totalLinearW += mNearLoss;
      totalNetKwh += netKwh;
    }

    final annUnsh = totalW > 0 ? (totalUnshadedW / totalW * 100.0).clamp(0.0, 100.0).toDouble() : 100.0;
    final annHor = totalW > 0 ? (totalHorizonW / totalW * 100.0).clamp(0.0, 100.0).toDouble() : 0.0;
    final annLin = totalW > 0 ? (totalLinearW / totalW * 100.0).clamp(0.0, 100.0).toDouble() : 0.0;
    final annElec = (annLin * topo.electricalFactor).clamp(0.0, 85.0).toDouble();
    final specYield = kwp > 0.05 ? totalNetKwh / kwp : 0.0;

    return AnnualShadingReport(
      annualUnshadedPct: annUnsh,
      annualLinearLossPct: annLin,
      annualElectricalLossPct: annElec,
      annualHorizonLossPct: annHor,
      orientEffPct: orientEff * 100.0,
      annualNetKwh: totalNetKwh,
      specificYield: specYield,
      months: rows,
    );
  }

  /// Builds 12x8 roof irradiance heatmap matrix (0.15 .. 1.00 relative exposure).
  static List<List<double>> computeHeatmapGrid({
    required double lat,
    required double lon,
    required int periodMode, // 0 Annual, 1 Summer, 2 Winter, 3 Today
    required double roofLenM,
    required double roofWidM,
    required double mmsClearanceM,
    required double orientEff,
    required List<RoofObstacle> obstacles,
  }) {
    const cols = 12;
    const rows = 8;
    final year = DateTime.now().year;
    final now = DateTime.now();
    final List<DateTime> dates;
    switch (periodMode) {
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
    if (totalW <= 0) return List.generate(rows, (_) => List.filled(cols, 0.85));

    return List.generate(rows, (r) {
      final py = roofWidM / 2 - (r + 0.5) * (roofWidM / rows);
      return List.generate(cols, (c) {
        final px = -roofLenM / 2 + (c + 0.5) * (roofLenM / cols);
        var sum = 0.0;
        for (final s in samples) {
          final lit = isPointShaded(
            px: px,
            py: py,
            sunAlt: s.alt,
            sunAz: s.az,
            mmsClearanceM: mmsClearanceM,
            obstacles: obstacles,
          )
              ? 0.22
              : 1.0;
          sum += lit * s.w;
        }
        final edge = (r == 0 || r == rows - 1 || c == 0 || c == cols - 1) ? 0.96 : 1.0;
        return ((sum / totalW) * orientEff * edge).clamp(0.15, 1.0).toDouble();
      });
    });
  }

  /// Live OpenStreetMap Overpass API scan for real surrounding buildings around site lat/lon.
  static Future<({List<RoofObstacle> buildings, String message})> scanOsmSurroundingBuildings({
    required double lat,
    required double lon,
    required double hostBuildingHeightM,
    double radiusM = 45.0,
  }) async {
    try {
      final query = '[out:json][timeout:12];way["building"](around:${radiusM.round()},${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)});out center tags;';
      final uri = Uri.parse('https://overpass-api.de/api/interpreter');
      final resp = await http.post(uri, body: {'data': query}).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        return (buildings: <RoofObstacle>[], message: 'OSM Overpass returned HTTP ${resp.statusCode}. Add obstacles manually.');
      }
      final data = jsonDecode(resp.body);
      final elems = (data is Map && data['elements'] is List) ? data['elements'] as List : const [];
      final found = <RoofObstacle>[];
      var idx = 1;

      for (final el in elems) {
        if (el is! Map) continue;
        final center = el['center'];
        if (center is! Map) continue;
        final bLat = (center['lat'] as num?)?.toDouble();
        final bLon = (center['lon'] as num?)?.toDouble();
        if (bLat == null || bLon == null) continue;

        final dNorth = (bLat - lat) * 111320.0;
        final dEast = (bLon - lon) * 111320.0 * math.cos(lat * math.pi / 180.0);
        final dist = math.sqrt(dNorth * dNorth + dEast * dEast);
        if (dist < 4.5 || dist > radiusM) continue; // skip host footprint itself

        final bearing = ((math.atan2(dEast, dNorth) * 180.0 / math.pi) + 360.0) % 360.0;
        final tags = (el['tags'] is Map) ? (el['tags'] as Map) : const {};
        final rawH = double.tryParse((tags['height'] ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), ''));
        final levels = double.tryParse((tags['building:levels'] ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), ''));
        final absH = rawH ?? (levels != null ? levels * 3.2 : hostBuildingHeightM + 2.5);
        final relH = (absH - hostBuildingHeightM + 1.5).clamp(1.2, 24.0).toDouble();
        final name = (tags['name'] as String?)?.trim().isNotEmpty == true ? tags['name'].toString() : 'OSM Building #$idx';

        found.add(RoofObstacle(
          id: 'osm_${el['id'] ?? idx}',
          name: name,
          type: 'building',
          heightM: double.parse(relH.toStringAsFixed(1)),
          widthM: 6.5,
          depthM: 5.0,
          distM: double.parse(dist.clamp(4.5, 35.0).toDouble().toStringAsFixed(1)),
          bearingDeg: bearing.roundToDouble(),
          fromOsm: true,
        ));
        idx++;
        if (found.length >= 8) break;
      }

      if (found.isEmpty) {
        return (
          buildings: <RoofObstacle>[],
          message: 'OSM scan found no adjacent tall buildings within ${radiusM.round()}m. You can add rooftop tanks/parapets manually.',
        );
      }
      return (
        buildings: found,
        message: 'Imported ${found.length} verified OSM surrounding building${found.length == 1 ? '' : 's'} within ${radiusM.round()}m.',
      );
    } catch (_) {
      return (
        buildings: <RoofObstacle>[],
        message: 'OSM Overpass unavailable offline. Add site obstacles manually below.',
      );
    }
  }

  /// Fetches NASA POWER long-term monthly solar insolation (kWh/m²/day) for coordinates.
  static Future<({List<double> monthlyPsh, String label})?> fetchNasaPowerClimate(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://power.larc.nasa.gov/api/temporal/climatology/point'
        '?parameters=ALLSKY_SFC_SW_DWN&community=RE'
        '&longitude=${lon.toStringAsFixed(4)}&latitude=${lat.toStringAsFixed(4)}&format=JSON',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      final param = body?['properties']?['parameter']?['ALLSKY_SFC_SW_DWN'];
      if (param is! Map) return null;
      const keys = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
      final vals = <double>[];
      for (final k in keys) {
        final v = (param[k] as num?)?.toDouble();
        if (v == null || v <= 0) return null;
        vals.add(v);
      }
      final avg = vals.reduce((a, b) => a + b) / 12.0;
      return (monthlyPsh: vals, label: 'NASA POWER · ${avg.toStringAsFixed(2)} kWh/m²/d avg');
    } catch (_) {
      return null;
    }
  }

  /// Persistent Local Solar Project Vault (SharedPreferences).
  static Future<List<SolarVaultProject>> loadVault() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_vaultKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => SolarVaultProject.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SolarVaultProject>> saveToVault(SolarVaultProject proj) async {
    final list = await loadVault();
    list.removeWhere((x) => x.id == proj.id);
    list.insert(0, proj);
    if (list.length > 30) list.removeRange(30, list.length);
    final p = await SharedPreferences.getInstance();
    await p.setString(_vaultKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    return list;
  }

  static Future<List<SolarVaultProject>> deleteFromVault(String id) async {
    final list = await loadVault();
    list.removeWhere((x) => x.id == id);
    final p = await SharedPreferences.getInstance();
    await p.setString(_vaultKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    return list;
  }
}
