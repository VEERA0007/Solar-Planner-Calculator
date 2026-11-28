import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/calc.dart';
import '../core/estimator_data.dart';
import '../core/store.dart';
import '../core/sun.dart';
import 'roof_map.dart';
import 'solar_analysis_engine.dart';
import 'solar_analysis_painters.dart';
import 'theme.dart';

/// Complete Solar Analysis Suite matching the Web App:
/// - 5 Field Tools: 3D Shadow & Roof Map, Roof Sun Heatmap, Sun Compass, AR Sun View, Sun Timer
/// - 7-Step Engineering Workflow:
///   1. Site & Media (GPS, NASA POWER, OSM Surrounding Buildings Scan, Verification)
///   2. Roof Map (Satellite Roof Polygon Trace & Geodesic Capacity)
///   3. 2D CAD (AutoCAD Blueprint / Satellite CAD Overlay + PV Zones + Obstacles)
///   4. 3D Building (Rotatable 3D Building Shadows, Wireframe & 3D Heatmap Overlay)
///   5. MMS & Panels (4 Mounting Structure Presets + Assembly Layer Modes + Structural Frame)
///   6. 360° Tour (Interactive 360° Camera Orbit + Sun Sweep Walkthrough)
///   7. PVsyst & PDF (12-Month PVsyst Shading, String Topology, Horizon Profile, Setback Calc & Site Audit Report)
/// - Local Project Vault (Save / Load / Delete via SharedPreferences)
class SolarPage extends StatefulWidget {
  final AppState state;
  const SolarPage({super.key, required this.state});
  @override
  State<SolarPage> createState() => _SolarPageState();
}

class _SolarPageState extends State<SolarPage> {
  // Navigation Mode:
  // 'maps_3d' | 'heatmap' | 'sun_compass' | 'ar_view' | 'sun_timer' | 'shadow' (7-step workflow)
  String _suiteTab = 'shadow';
  int _workflowStep = 1; // 1..7

  // Sub-view toggles matching Web App
  int _step2Engine = 0; // 0 = Roof Polygon, 1 = 3D Shadow Map
  bool _step3Satellite = false; // false = 2D AutoCAD Blueprint, true = Satellite CAD Overlay
  bool _step4Wireframe = false; // false = 3D Building & Heatmap, true = AutoCAD 3D Wireframe
  bool _show3dHeatmap = true;
  int _step7SubTab = 0; // 0 = PVsyst Shading & Heatmap, 1 = Site Inspection & Report
  int _heatmapPeriod = 0; // 0 Annual, 1 Summer, 2 Winter, 3 Today
  bool _showObstaclesDrawer = false;

  // Astronomical Simulation & Playback State
  int _monthIdx = 5; // Default Jun 21 (Solstice)
  double _hour = 11.5;
  bool _sweeping = false;
  bool _tourOrbiting = false;
  Timer? _animTimer;

  // 3D Camera & AR Viewfinder State
  double _orbitYawDeg = 35.0;
  double _cameraPitchDeg = 34.0;
  double _arHeadingDeg = 180.0;
  double _map3dObjHeightM = 6.0;

  // Site Coordinates, Climate & OSM State
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();
  final TextEditingController _elevCtrl = TextEditingController(text: '520');
  final TextEditingController _projectTitleCtrl = TextEditingController();
  final TextEditingController _inspectorCtrl = TextEditingController(text: 'Solar Engineer');
  final TextEditingController _remarksCtrl = TextEditingController();

  double _siteLat = 17.385;
  double _siteLon = 78.4867;
  double _siteElevM = 520.0;
  String _siteName = 'Hyderabad';
  bool _locating = false;
  bool _scanningOsm = false;
  String? _osmStatusMsg;
  List<double>? _nasaMonthlyPsh;
  String? _nasaLabel;

  // Roof & Structural Engineering Config
  double _roofLenM = 14.0;
  double _roofWidM = 10.0;
  double _buildingHeightM = 6.0;
  double _parapetHeightM = 1.0;
  double _perimeterSetbackM = 0.6;
  String _roofStructureType = 'rcc_flat'; // rcc_flat | metal_shed | sloped_tile | elevated
  int _moduleWp = 550;
  RoofResult? _roofTrace;

  // PV Array, MMS & PVsyst Parameters
  double _tiltDeg = 18.0;
  double _azimuthDeg = 180.0;
  double _albedo = 0.20;
  double _collectorWidthM = 2.28;
  double _rowPitchM = 3.8;
  int _numRows = 3;
  int _mmsIndex = 0;
  String _assemblyLayer = 'structure_and_panels'; // building_only | structure_only | structure_and_panels
  double _columnSpacingM = 3.2;
  bool _crossBracing = true;
  bool _brickPedestals = true;
  String _stringTopologyId = 'halfcut_portrait';
  List<double> _horizonProfile = List<double>.from(kHorizonPresets['Flat Horizon']!);

  // Quick Setback Calculator Inputs (Step 7)
  double _setbackObsH = 2.4;
  double _setbackObsDist = 3.5;

  // Site Verification Flags (Step 1 & 2)
  bool _mapVerified = false;
  bool _buildingVerified = false;
  bool _obstaclesVerified = false;
  bool _footprintLocked = false;

  // Obstacles, PV Zones & Inspection Report State
  final List<RoofObstacle> _obstacles = [];
  int _obsSeq = 1;
  List<PvZone> _zones = [
    const PvZone(id: 'z1', name: 'Zone A (Main)', xFrac: 0.0, yFrac: 0.0, wFrac: 1.0, hFrac: 0.46),
    const PvZone(id: 'z2', name: 'Zone B (South)', xFrac: 0.0, yFrac: 0.54, wFrac: 1.0, hFrac: 0.46),
  ];
  int _zoneSeq = 3;
  String _surveyStatus = 'Draft'; // Draft | Reviewed | Approved
  final Map<String, bool> _checklist = {for (final item in kInspectionItems) item.$1: true};

  // Persistent Project Vault
  String _activeProjectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
  List<SolarVaultProject> _vaultProjects = [];

  AppState get state => widget.state;
  MmsPreset get _mms => kMmsPresets[_mmsIndex.clamp(0, kMmsPresets.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    final site = state.site;
    _siteLat = site.lat;
    _siteLon = site.lon;
    _siteName = site.city.isNotEmpty ? site.city : 'Site Location';
    _latCtrl.text = _siteLat.toStringAsFixed(5);
    _lonCtrl.text = _siteLon.toStringAsFixed(5);
    _projectTitleCtrl.text = '$_siteName Solar Analysis Survey';
    _tiltDeg = _siteLat.abs().clamp(8.0, 42.0).roundToDouble();
    _azimuthDeg = _siteLat >= 0 ? 180.0 : 0.0;
    _arHeadingDeg = _azimuthDeg;
    if (state.profile.roofSqft > 100) {
      final sqm = state.profile.roofSqft * 0.092903;
      final side = math.sqrt(sqm).clamp(5.0, 28.0).toDouble();
      _roofLenM = (side * 1.15).clamp(5.0, 32.0).toDouble();
      _roofWidM = (side * 0.87).clamp(4.0, 26.0).toDouble();
    }
    final now = DateTime.now();
    _hour = (now.hour + now.minute / 60.0).clamp(5.5, 18.5).toDouble();
    _loadInitialAsync();
  }

  Future<void> _loadInitialAsync() async {
    final saved = await SolarAnalysisEngine.loadVault();
    if (mounted) setState(() => _vaultProjects = saved);
    final nasa = await SolarAnalysisEngine.fetchNasaPowerClimate(_siteLat, _siteLon);
    if (mounted && nasa != null) {
      setState(() {
        _nasaMonthlyPsh = nasa.monthlyPsh;
        _nasaLabel = nasa.label;
      });
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _elevCtrl.dispose();
    _projectTitleCtrl.dispose();
    _inspectorCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  DateTime _simDate() {
    final year = DateTime.now().year;
    final opt = kMonthOptions[_monthIdx.clamp(0, kMonthOptions.length - 1).toInt()];
    final hh = _hour.floor().clamp(0, 23).toInt();
    final mm = ((_hour - hh) * 60).round().clamp(0, 59).toInt();
    return DateTime(year, opt.month, opt.day, hh, mm);
  }

  String _fmtClock(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtHour(double h) {
    final hh = h.floor().clamp(0, 23).toInt();
    final mm = ((h - hh) * 60).round().clamp(0, 59).toInt();
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  void _startOrStopAnimation({required bool sweepSun, required bool orbitCam}) {
    final wantRunning = sweepSun || orbitCam;
    if (!wantRunning) {
      _animTimer?.cancel();
      setState(() {
        _sweeping = false;
        _tourOrbiting = false;
      });
      return;
    }
    setState(() {
      _sweeping = sweepSun;
      _tourOrbiting = orbitCam;
    });
    _animTimer?.cancel();
    _animTimer = Timer.periodic(const Duration(milliseconds: 85), (_) {
      if (!mounted) return;
      setState(() {
        if (_sweeping) {
          _hour += 0.11;
          if (_hour > 18.5) _hour = 5.5;
        }
        if (_tourOrbiting) {
          _orbitYawDeg = (_orbitYawDeg + 2.2) % 360.0;
        }
      });
    });
  }

  void _resetNow() {
    _animTimer?.cancel();
    final now = DateTime.now();
    setState(() {
      _sweeping = false;
      _tourOrbiting = false;
      _monthIdx = (now.month - 1).clamp(0, 11).toInt();
      _hour = (now.hour + now.minute / 60.0).clamp(5.5, 18.5).toDouble();
    });
  }

  Future<void> _detectGps() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      await state.locate();
      if (!mounted) return;
      setState(() {
        _siteLat = state.site.lat;
        _siteLon = state.site.lon;
        _siteName = state.site.city.isNotEmpty ? state.site.city : _siteName;
        _latCtrl.text = _siteLat.toStringAsFixed(5);
        _lonCtrl.text = _siteLon.toStringAsFixed(5);
        _tiltDeg = _siteLat.abs().clamp(8.0, 42.0).roundToDouble();
        _azimuthDeg = _siteLat >= 0 ? 180.0 : 0.0;
      });
      final nasa = await SolarAnalysisEngine.fetchNasaPowerClimate(_siteLat, _siteLon);
      if (mounted && nasa != null) {
        setState(() {
          _nasaMonthlyPsh = nasa.monthlyPsh;
          _nasaLabel = nasa.label;
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyManualCoords() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    final elev = double.tryParse(_elevCtrl.text.trim());
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid latitude (-90..90) and longitude (-180..180).')),
      );
      return;
    }
    setState(() {
      _siteLat = lat;
      _siteLon = lon;
      if (elev != null) _siteElevM = elev;
      _tiltDeg = lat.abs().clamp(8.0, 42.0).roundToDouble();
      _azimuthDeg = lat >= 0 ? 180.0 : 0.0;
    });
    SolarAnalysisEngine.fetchNasaPowerClimate(lat, lon).then((nasa) {
      if (mounted && nasa != null) {
        setState(() {
          _nasaMonthlyPsh = nasa.monthlyPsh;
          _nasaLabel = nasa.label;
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied coordinates ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°')),
    );
  }

  Future<void> _openRoofMap() async {
    final panel = panelsFor(true).first;
    final res = await Navigator.of(context).push<RoofResult>(
      MaterialPageRoute(builder: (_) => RoofMapPage(state: state, panel: panel)),
    );
    if (res == null || !mounted) return;
    setState(() {
      _roofTrace = res;
      _mapVerified = true;
      _footprintLocked = true;
      if (res.areaM2 > 6) {
        final side = math.sqrt(res.areaM2).clamp(4.0, 32.0).toDouble();
        _roofLenM = (side * 1.18).clamp(4.0, 32.0).toDouble();
        _roofWidM = (res.areaM2 / _roofLenM).clamp(4.0, 26.0).toDouble();
      }
    });
  }

  Future<void> _openExternalGoogle3D() async {
    final url = Uri.parse('https://www.google.com/maps/@${_siteLat.toStringAsFixed(6)},${_siteLon.toStringAsFixed(6)},85m/data=!3m1!1e3');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _scanOsmBuildings() async {
    if (_scanningOsm) return;
    setState(() {
      _scanningOsm = true;
      _osmStatusMsg = 'Scanning OpenStreetMap surrounding buildings...';
    });
    final res = await SolarAnalysisEngine.scanOsmSurroundingBuildings(
      lat: _siteLat,
      lon: _siteLon,
      hostBuildingHeightM: _buildingHeightM,
    );
    if (!mounted) return;
    setState(() {
      _scanningOsm = false;
      _osmStatusMsg = res.message;
      if (res.buildings.isNotEmpty) {
        _obstacles.removeWhere((o) => o.fromOsm);
        _obstacles.addAll(res.buildings);
        _obstaclesVerified = true;
      }
    });
  }

  Future<void> _saveCurrentProjectToVault() async {
    final proj = SolarVaultProject(
      id: _activeProjectId,
      title: _projectTitleCtrl.text.trim().isEmpty ? '$_siteName Solar Survey' : _projectTitleCtrl.text.trim(),
      inspectorName: _inspectorCtrl.text.trim().isEmpty ? 'Solar Engineer' : _inspectorCtrl.text.trim(),
      status: _surveyStatus,
      remarks: _remarksCtrl.text.trim(),
      savedAtIso: DateTime.now().toIso8601String(),
      city: _siteName,
      lat: _siteLat,
      lon: _siteLon,
      elevationM: _siteElevM,
      roofLenM: _roofLenM,
      roofWidM: _roofWidM,
      buildingHeightM: _buildingHeightM,
      parapetHeightM: _parapetHeightM,
      perimeterSetbackM: _perimeterSetbackM,
      tiltDeg: _tiltDeg,
      azimuthDeg: _azimuthDeg,
      albedo: _albedo,
      rowPitchM: _rowPitchM,
      collectorWidthM: _collectorWidthM,
      numRows: _numRows,
      moduleWp: _moduleWp,
      roofStructureType: _roofStructureType,
      mmsIndex: _mmsIndex,
      assemblyLayer: _assemblyLayer,
      columnSpacingM: _columnSpacingM,
      crossBracing: _crossBracing,
      brickPedestals: _brickPedestals,
      stringTopologyId: _stringTopologyId,
      horizonProfile: List<double>.from(_horizonProfile),
      obstacles: List<RoofObstacle>.from(_obstacles),
      zones: List<PvZone>.from(_zones),
      checklist: Map<String, bool>.from(_checklist),
    );
    final updated = await SolarAnalysisEngine.saveToVault(proj);
    if (!mounted) return;
    setState(() => _vaultProjects = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${proj.title}" to Local Project Vault')),
    );
  }

  void _loadProjectFromVault(SolarVaultProject p) {
    setState(() {
      _activeProjectId = p.id;
      _projectTitleCtrl.text = p.title;
      _inspectorCtrl.text = p.inspectorName;
      _surveyStatus = p.status;
      _remarksCtrl.text = p.remarks;
      _siteName = p.city;
      _siteLat = p.lat;
      _siteLon = p.lon;
      _siteElevM = p.elevationM;
      _latCtrl.text = p.lat.toStringAsFixed(5);
      _lonCtrl.text = p.lon.toStringAsFixed(5);
      _elevCtrl.text = p.elevationM.round().toString();
      _roofLenM = p.roofLenM;
      _roofWidM = p.roofWidM;
      _buildingHeightM = p.buildingHeightM;
      _parapetHeightM = p.parapetHeightM;
      _perimeterSetbackM = p.perimeterSetbackM;
      _tiltDeg = p.tiltDeg;
      _azimuthDeg = p.azimuthDeg;
      _albedo = p.albedo;
      _rowPitchM = p.rowPitchM;
      _collectorWidthM = p.collectorWidthM;
      _numRows = p.numRows;
      _moduleWp = p.moduleWp;
      _roofStructureType = p.roofStructureType;
      _mmsIndex = p.mmsIndex;
      _assemblyLayer = p.assemblyLayer;
      _columnSpacingM = p.columnSpacingM;
      _crossBracing = p.crossBracing;
      _brickPedestals = p.brickPedestals;
      _stringTopologyId = p.stringTopologyId;
      _horizonProfile = List<double>.from(p.horizonProfile);
      _obstacles
        ..clear()
        ..addAll(p.obstacles);
      _zones = p.zones.isEmpty ? _zones : List<PvZone>.from(p.zones);
      _checklist
        ..clear()
        ..addAll(p.checklist);
    });
  }

  Future<void> _showVaultSheet() async {
    final latest = await SolarAnalysisEngine.loadVault();
    if (!mounted) return;
    setState(() => _vaultProjects = latest);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.storage_rounded, color: C.amber, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Solar Project Vault', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                FilledButton.icon(
                  onPressed: () async {
                    await _saveCurrentProjectToVault();
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  style: FilledButton.styleFrom(backgroundColor: C.orange, visualDensity: VisualDensity.compact),
                  label: const Text('Save Current', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 10),
              if (_vaultProjects.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                  child: Text('No saved solar analysis projects yet. Tap "Save Current" to store this site survey locally.', style: TextStyle(color: C.mute, fontSize: 12.5)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _vaultProjects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = _vaultProjects[i];
                      return Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                '${p.city} · ${p.roofLenM.toStringAsFixed(0)}×${p.roofWidM.toStringAsFixed(0)}m · ${p.obstacles.length} obstacles · ${p.status}',
                                style: TextStyle(color: C.mute, fontSize: 11),
                              ),
                            ]),
                          ),
                          TextButton(
                            onPressed: () {
                              _loadProjectFromVault(p);
                              Navigator.pop(ctx);
                            },
                            child: Text('Load', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: C.red, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              final next = await SolarAnalysisEngine.deleteFromVault(p.id);
                              if (!mounted) return;
                              setState(() => _vaultProjects = next);
                              setSheet(() {});
                            },
                          ),
                        ]),
                      );
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showObstacleSheet({RoofObstacle? edit, String? presetType}) async {
    String type = edit?.type ?? presetType ?? 'tank';
    double heightM = edit?.heightM ?? (type == 'parapet' ? 1.2 : type == 'tree' ? 6.0 : type == 'building' ? 7.5 : 2.5);
    double widthM = edit?.widthM ?? (type == 'parapet' ? 6.0 : type == 'building' ? 5.0 : 2.0);
    double distM = edit?.distM ?? (type == 'parapet' ? (_roofWidM / 2).clamp(2.0, 14.0).toDouble() : 4.5);
    double bearingDeg = edit?.bearingDeg ?? 180.0;

    String defaultName(String t) {
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

    final nameCtrl = TextEditingController(text: edit?.name ?? defaultName(type));

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
                Icon(Icons.domain_add_rounded, color: C.orange, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(edit == null ? 'Add Verified Obstacle' : 'Edit Obstacle', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 10),
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
                      if (edit == null) nameCtrl.text = defaultName(type);
                    }),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Obstacle Name',
                  filled: true,
                  fillColor: C.card2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.line)),
                ),
              ),
              const SizedBox(height: 10),
              _sliderRow('Height above roof', '${heightM.toStringAsFixed(1)} m (${(heightM * 3.28084).toStringAsFixed(1)} ft)', heightM, 0.5, 18.0, C.orange, (v) => setSheet(() => heightM = v)),
              _sliderRow('Width / Span', '${widthM.toStringAsFixed(1)} m', widthM, 0.8, 16.0, C.sky, (v) => setSheet(() => widthM = v)),
              _sliderRow('Distance from center', '${distM.toStringAsFixed(1)} m', distM, 1.0, 22.0, C.blue, (v) => setSheet(() => distM = v)),
              _sliderRow('Bearing Direction', '${bearingDeg.round()}° ${compass(bearingDeg)}', bearingDeg, 0.0, 355.0, C.amber, (v) => setSheet(() => bearingDeg = v)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final lbl = nameCtrl.text.trim().isEmpty ? defaultName(type) : nameCtrl.text.trim();
                    setState(() {
                      if (edit == null) {
                        _obstacles.add(RoofObstacle(
                          id: 'obs_${_obsSeq++}',
                          name: lbl,
                          type: type,
                          heightM: heightM,
                          widthM: widthM,
                          distM: distM,
                          bearingDeg: bearingDeg,
                        ));
                      } else {
                        final idx = _obstacles.indexWhere((x) => x.id == edit.id);
                        if (idx >= 0) {
                          _obstacles[idx] = edit.copyWith(name: lbl, type: type, heightM: heightM, widthM: widthM, distM: distM, bearingDeg: bearingDeg);
                        }
                      }
                      _obstaclesVerified = true;
                    });
                    Navigator.pop(ctx);
                  },
                  icon: Icon(edit == null ? Icons.add_rounded : Icons.check_rounded, size: 18),
                  style: FilledButton.styleFrom(backgroundColor: C.orange, minimumSize: const Size.fromHeight(46)),
                  label: Text(edit == null ? 'Add Obstacle' : 'Save Changes', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final simTime = _simDate();
    final pos = solarPosition(simTime, _siteLat, _siteLon);
    final day = dayInfo(simTime, _siteLat, _siteLon);
    final shadowAz = (pos.az + 180.0) % 360.0;

    final grossArea = _roofTrace?.areaM2 ?? (_roofLenM * _roofWidM);
    final effSetback = math.max(_perimeterSetbackM, _mms.setbackM);
    final usableArea = math.max(0.0, (_roofLenM - effSetback * 2) * (_roofWidM - effSetback * 2)) * _mms.fillFactor;
    final estPanels = _roofTrace?.panels ?? (usableArea / 2.58).floor().clamp(0, 800).toInt();
    final estKwp = _roofTrace?.kwp ?? (estPanels * (_moduleWp / 1000.0));
    final activeKwp = estKwp > 0.5 ? estKwp : state.site.kwp;

    final orientEff = SolarAnalysisEngine.orientationEfficiency(
      lat: _siteLat,
      tiltDeg: _tiltDeg,
      azimuthDeg: _azimuthDeg,
      albedo: _albedo,
    );
    final unshadedNow = SolarAnalysisEngine.unshadedFraction(
      roofLenM: _roofLenM,
      roofWidM: _roofWidM,
      setbackM: effSetback,
      mmsClearanceM: _mms.clearanceM,
      sunAlt: pos.alt,
      sunAz: pos.az,
      obstacles: _obstacles,
      horizonProfile: _horizonProfile,
    );

    final heatmapGrid = SolarAnalysisEngine.computeHeatmapGrid(
      lat: _siteLat,
      lon: _siteLon,
      periodMode: _heatmapPeriod,
      roofLenM: _roofLenM,
      roofWidM: _roofWidM,
      mmsClearanceM: _mms.clearanceM,
      orientEff: orientEff,
      obstacles: _obstacles,
    );

    final monthlyPsh = _nasaMonthlyPsh ?? state.monthly?.psh;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        // ===== TOP HEADER: Solar Analysis + Vault + GPS =====
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.t('solar'), style: TextStyle(color: C.text, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4)),
              const SizedBox(height: 2),
              Text(
                '$_siteName · ${_siteLat.toStringAsFixed(4)}°, ${_siteLon.toStringAsFixed(4)}°',
                style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _showVaultSheet,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: C.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.storage_rounded, color: C.amber, size: 15),
                const SizedBox(width: 5),
                Text('Vault (${_vaultProjects.length})', style: TextStyle(color: C.text, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _detectGps,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(11), border: Border.all(color: C.line)),
              child: _locating
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.sky))
                  : Icon(Icons.my_location_rounded, color: C.sky, size: 17),
            ),
          ),
        ]),

        const SizedBox(height: 10),

        // ===== SINGLE-ROW NAVIGATION: 5 FIELD TOOLS + 7 ENGINEERING WORKFLOW STEPS =====
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _navPill('maps_3d', Icons.public_rounded, '3D Shadow & Map', C.orange, isTool: true),
            const SizedBox(width: 6),
            _navPill('heatmap', Icons.local_fire_department_rounded, 'Sun Heatmap', C.amber, isTool: true),
            const SizedBox(width: 6),
            _navPill('sun_compass', Icons.explore_outlined, 'Sun Compass', C.sky, isTool: true),
            const SizedBox(width: 6),
            _navPill('ar_view', Icons.camera_alt_outlined, 'AR Sun View', C.purple, isTool: true),
            const SizedBox(width: 6),
            _navPill('sun_timer', Icons.schedule_rounded, 'Sun Timer', C.green, isTool: true),
            Container(width: 1.5, height: 22, color: C.line, margin: const EdgeInsets.symmetric(horizontal: 10)),
            for (final step in const [
              (1, '1. Site & Media'),
              (2, '2. Roof Map'),
              (3, '3. 2D CAD'),
              (4, '4. 3D Building'),
              (5, '5. MMS & Panels'),
              (6, '6. 360° Tour'),
              (7, '7. PVsyst & PDF'),
            ]) ...[
              _stepPill(step.$1, step.$2),
              if (step.$1 < 7) const SizedBox(width: 6),
            ],
          ]),
        ),

        const SizedBox(height: 12),

        // ===== ACTIVE VIEWPORT =====
        if (_suiteTab == 'maps_3d')
          _buildField3DShadowMapView(posAlt: pos.alt, posAz: pos.az, day: day, grossArea: grossArea, estPanels: estPanels, estKwp: estKwp, heatmapGrid: heatmapGrid)
        else if (_suiteTab == 'heatmap')
          _buildFieldHeatmapView(heatmapGrid: heatmapGrid, orientEff: orientEff, monthlyPsh: monthlyPsh)
        else if (_suiteTab == 'sun_compass')
          _buildFieldCompassView(simTime: simTime, posAlt: pos.alt, posAz: pos.az, day: day, shadowAz: shadowAz)
        else if (_suiteTab == 'ar_view')
          _buildFieldArSunView(simTime: simTime, posAlt: pos.alt, posAz: pos.az)
        else if (_suiteTab == 'sun_timer')
          _buildFieldSunTimerAndYieldView(day: day, monthlyPsh: monthlyPsh)
        else
          _buildWorkflowStageViewport(
            posAlt: pos.alt,
            posAz: pos.az,
            shadowAz: shadowAz,
            unshadedNow: unshadedNow,
            effSetback: effSetback,
            grossArea: grossArea,
            usableArea: usableArea,
            estPanels: estPanels,
            estKwp: estKwp,
            activeKwp: activeKwp,
            heatmapGrid: heatmapGrid,
            monthlyPsh: monthlyPsh,
          ),
      ],
    );
  }

  Widget _navPill(String id, IconData icon, String label, Color accent, {required bool isTool}) {
    final active = _suiteTab == id;
    return InkWell(
      onTap: () => setState(() => _suiteTab = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: active ? (isTool ? accent : C.sky) : C.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? accent : C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: active ? Colors.white : accent),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: active ? Colors.white : C.text, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _stepPill(int num, String label) {
    final active = _suiteTab == 'shadow' && _workflowStep == num;
    final verified = (num == 1 && (_mapVerified || _obstaclesVerified)) || (num == 2 && _footprintLocked);
    return InkWell(
      onTap: () => setState(() {
        _suiteTab = 'shadow';
        _workflowStep = num;
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: active ? C.blue : C.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? C.blue : C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: active ? Colors.white : C.text, fontSize: 12, fontWeight: FontWeight.w800)),
          if (verified) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle_rounded, size: 13, color: active ? Colors.white : C.green),
          ],
        ]),
      ),
    );
  }

  // ==========================================================================
  // SHARED TIME-OF-DAY, MONTH & VERIFIED OBSTACLES BAR (STEPS 3, 4, 5, 6)
  // ==========================================================================
  Widget _buildSharedSimBar({
    required double posAlt,
    required double posAz,
    required double unshadedNow,
    required double shadowAz,
  }) {
    final winterNoonAlt = (90.0 - (_siteLat.abs() + 23.44)).clamp(10.0, 89.0).toDouble();
    final shadeColor = posAlt <= 1.5 ? C.mute : (unshadedNow >= 0.90 ? C.green : (unshadedNow >= 0.75 ? C.amber : C.red));

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Telemetry + Month Dropdown + Obstacles Drawer Button
        Row(children: [
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_fmtHour(_hour), style: TextStyle(fontFamilyFallback: kMono, color: C.orange, fontSize: 13.5, fontWeight: FontWeight.w900)),
              Text('Alt ${posAlt.toStringAsFixed(1)}°', style: TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Az ${posAz.round()}° ${compass(posAz)}', style: TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(
                posAlt > 1.5 ? 'Unshaded ${(unshadedNow * 100).round()}%' : 'Night',
                style: TextStyle(color: shadeColor, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
          InkWell(
            onTap: () => setState(() => _showObstaclesDrawer = !_showObstaclesDrawer),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: _showObstaclesDrawer ? C.orange.withValues(alpha: .16) : C.card2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _showObstaclesDrawer ? C.orange : C.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.apartment_rounded, size: 14, color: _showObstaclesDrawer ? C.orange : C.sky),
                const SizedBox(width: 4),
                Text('Obstacles (${_obstacles.length})', style: TextStyle(color: C.text, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Month / Solstice Selector Strip
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < kMonthOptions.length; i++) ...[
              InkWell(
                onTap: () => setState(() => _monthIdx = i),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _monthIdx == i ? C.orange : C.card2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _monthIdx == i ? C.orange : C.line),
                  ),
                  child: Text(
                    kMonthOptions[i].label,
                    style: TextStyle(color: _monthIdx == i ? Colors.white : C.text, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (i < kMonthOptions.length - 1) const SizedBox(width: 5),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        // Time-of-Day Slider + Sweep Play + Now
        Row(children: [
          InkWell(
            onTap: () => _startOrStopAnimation(sweepSun: !_sweeping, orbitCam: _tourOrbiting),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(color: _sweeping ? C.orange : C.chipBlue, borderRadius: BorderRadius.circular(9)),
              child: Icon(_sweeping ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 17, color: _sweeping ? Colors.white : C.sky),
            ),
          ),
          const SizedBox(width: 6),
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
                  if (_sweeping) _startOrStopAnimation(sweepSun: false, orbitCam: _tourOrbiting);
                  setState(() => _hour = v);
                },
              ),
            ),
          ),
          InkWell(
            onTap: _resetNow,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(9), border: Border.all(color: C.line)),
              child: Text('Now', style: TextStyle(color: C.sky, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),

        // Expandable Verified Obstacles Manager Drawer
        if (_showObstaclesDrawer) ...[
          Divider(color: C.line, height: 18),
          Row(children: [
            const Expanded(child: Text('Verified Obstacles', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
            InkWell(
              onTap: _scanOsmBuildings,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.line)),
                child: Text(_scanningOsm ? 'Scanning...' : 'Scan OSM', style: TextStyle(color: C.sky, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _showObstacleSheet(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(8)),
                child: const Text('+ Add', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
          if (_osmStatusMsg != null) ...[
            const SizedBox(height: 6),
            Text(_osmStatusMsg!, style: TextStyle(color: C.sky, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          if (_obstacles.isEmpty)
            Text(
              'Zero obstacles currently added (no assumed defaults). Scan OSM surrounding buildings or add rooftop tanks, parapet walls, lift rooms, or trees.',
              style: TextStyle(color: C.mute, fontSize: 11.5, height: 1.35),
            )
          else
            for (final o in _obstacles) ...[
              _buildObstacleTile(o: o, posAlt: posAlt, shadowAz: shadowAz, winterNoonAlt: winterNoonAlt),
              const SizedBox(height: 6),
            ],
        ],
      ]),
    );
  }

  Widget _buildObstacleTile({
    required RoofObstacle o,
    required double posAlt,
    required double shadowAz,
    required double winterNoonAlt,
  }) {
    final effH = math.max(0.0, o.heightM - _mms.clearanceM);
    final shLen = posAlt > 2.0 ? effH / math.tan(posAlt * math.pi / 180.0) : 0.0;
    final setback = effH / math.tan(winterNoonAlt * math.pi / 180.0);
    final cleared = effH <= 0.05;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(11), border: Border.all(color: C.line)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(o.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
              if (o.fromOsm)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: C.chipPurple, borderRadius: BorderRadius.circular(6)),
                  child: Text('OSM', style: TextStyle(color: C.purple, fontSize: 9.5, fontWeight: FontWeight.w800)),
                ),
            ]),
            Text(
              'H ${o.heightM}m · W ${o.widthM}m · ${o.distM}m @ ${o.bearingDeg.round()}° ${compass(o.bearingDeg)}',
              style: TextStyle(color: C.mute, fontSize: 11),
            ),
            Text(
              cleared
                  ? 'Cleared by ${_mms.label} (${_mms.clearanceM.toStringAsFixed(1)}m)'
                  : posAlt > 2.0
                      ? 'Shadow: ${shLen.toStringAsFixed(1)}m → ${compass(shadowAz)} · Winter setback: ${setback.toStringAsFixed(1)}m'
                      : 'Winter-noon safe setback: ${setback.toStringAsFixed(1)}m',
              style: TextStyle(color: cleared ? C.green : C.sky, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        IconButton(icon: Icon(Icons.edit_outlined, size: 17, color: C.mute), visualDensity: VisualDensity.compact, onPressed: () => _showObstacleSheet(edit: o)),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 17, color: C.red),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _obstacles.removeWhere((x) => x.id == o.id)),
        ),
      ]),
    );
  }

  // ==========================================================================
  // 7-STEP SOLAR ENGINEERING WORKFLOW VIEWPORT
  // ==========================================================================
  Widget _buildWorkflowStageViewport({
    required double posAlt,
    required double posAz,
    required double shadowAz,
    required double unshadedNow,
    required double effSetback,
    required double grossArea,
    required double usableArea,
    required int estPanels,
    required double estKwp,
    required double activeKwp,
    required List<List<double>> heatmapGrid,
    required List<double>? monthlyPsh,
  }) {
    const stepTitles = [
      'Site Location, Climate & OSM Verification',
      'Satellite Roof Polygon & Geodesic Capacity',
      '2D AutoCAD Blueprint & Potential PV Zones',
      '3D Building Shadows & Roof Sunlight Heatmap',
      'Mounting Structure (MMS) Presets & Panel Layout',
      'Interactive 360° Walkthrough & Shadow Sweep',
      'PVsyst Shading Analysis, Horizon & Audit Report',
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Single-Row Step Progress Header
      Panel(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Step $_workflowStep of 7 · ${_footprintLocked ? 'Verified ${grossArea.toStringAsFixed(1)} m² · ${estKwp.toStringAsFixed(2)} kWp' : 'Roof Unmeasured'}',
                style: TextStyle(fontFamilyFallback: kMono, color: C.mute, fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(stepTitles[_workflowStep - 1], style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ]),
          ),
          if (!_footprintLocked)
            InkWell(
              onTap: _openRoofMap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(10)),
                child: const Text('Trace Roof', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),

      // Shared Date/Time/Obstacles Bar for Steps 3, 4, 5, 6
      if (_workflowStep >= 3 && _workflowStep <= 6) ...[
        _buildSharedSimBar(posAlt: posAlt, posAz: posAz, unshadedNow: unshadedNow, shadowAz: shadowAz),
        const SizedBox(height: 12),
      ],

      if (_workflowStep == 1)
        _buildStep1SiteAndVerification(grossArea: grossArea, estPanels: estPanels, estKwp: estKwp)
      else if (_workflowStep == 2)
        _buildStep2RoofMap(posAlt: posAlt, posAz: posAz, grossArea: grossArea, usableArea: usableArea, estPanels: estPanels, estKwp: estKwp, heatmapGrid: heatmapGrid)
      else if (_workflowStep == 3)
        _buildStep3CadAndZones(posAlt: posAlt, posAz: posAz, effSetback: effSetback)
      else if (_workflowStep == 4)
        _buildStep4Building3D(posAlt: posAlt, posAz: posAz, effSetback: effSetback, heatmapGrid: heatmapGrid)
      else if (_workflowStep == 5)
        _buildStep5MmsAndPanels(posAlt: posAlt, posAz: posAz, effSetback: effSetback, heatmapGrid: heatmapGrid)
      else if (_workflowStep == 6)
        _buildStep6Tour360(posAlt: posAlt, posAz: posAz, unshadedNow: unshadedNow, effSetback: effSetback, heatmapGrid: heatmapGrid)
      else
        _buildStep7PvSystAndReport(
          activeKwp: activeKwp,
          effSetback: effSetback,
          grossArea: grossArea,
          estPanels: estPanels,
          estKwp: estKwp,
          monthlyPsh: monthlyPsh,
        ),
    ]);
  }

  // -------------------- STEP 1: SITE, CLIMATE & OSM VERIFICATION --------------------
  Widget _buildStep1SiteAndVerification({
    required double grossArea,
    required int estPanels,
    required double estKwp,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.location_on_outlined, color: C.orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Exact Site Coordinates & NASA POWER', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            if (_nasaLabel != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: C.chipGreen, borderRadius: BorderRadius.circular(8)),
                child: Text('NASA Live', style: TextStyle(color: C.green, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
          ]),
          if (_nasaLabel != null) ...[
            const SizedBox(height: 6),
            Text(_nasaLabel!, style: TextStyle(color: C.green, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: 'Latitude', isDense: true, filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lonCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: 'Longitude', isDense: true, filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 78,
              child: TextField(
                controller: _elevCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Elev (m)', isDense: true, filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _detectGps,
                icon: Icon(Icons.my_location_rounded, size: 16, color: C.sky),
                label: Text(_locating ? 'Locating...' : 'Auto GPS', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _applyManualCoords,
                style: FilledButton.styleFrom(backgroundColor: C.orange),
                child: const Text('Apply Coordinates', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.home_work_outlined, color: C.sky, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Building & Roof Site Measurements', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final rt in const [
              ('rcc_flat', 'RCC Flat'),
              ('metal_shed', 'Metal Shed'),
              ('sloped_tile', 'Sloped Tile'),
              ('elevated', 'Elevated Pergola'),
            ])
              ChoiceChip(
                label: Text(rt.$2, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                selected: _roofStructureType == rt.$1,
                selectedColor: C.orange.withValues(alpha: .2),
                onSelected: (_) => setState(() {
                  _roofStructureType = rt.$1;
                  if (rt.$1 == 'elevated') _mmsIndex = 1;
                  if (rt.$1 == 'metal_shed' || rt.$1 == 'sloped_tile') _mmsIndex = 2;
                  if (rt.$1 == 'rcc_flat') _mmsIndex = 0;
                }),
              ),
          ]),
          const SizedBox(height: 8),
          _sliderRow('Roof Length (E–W)', '${_roofLenM.toStringAsFixed(1)} m', _roofLenM, 4.0, 32.0, C.sky, (v) => setState(() => _roofLenM = v)),
          _sliderRow('Roof Width (N–S)', '${_roofWidM.toStringAsFixed(1)} m', _roofWidM, 4.0, 26.0, C.sky, (v) => setState(() => _roofWidM = v)),
          _sliderRow('Building Height', '${_buildingHeightM.toStringAsFixed(1)} m', _buildingHeightM, 3.0, 20.0, C.blue, (v) => setState(() => _buildingHeightM = v)),
          _sliderRow('Parapet Wall Height', '${_parapetHeightM.toStringAsFixed(1)} m', _parapetHeightM, 0.0, 2.5, C.amber, (v) => setState(() => _parapetHeightM = v)),
          _sliderRow('Perimeter Setback', '${_perimeterSetbackM.toStringAsFixed(2)} m', _perimeterSetbackM, 0.2, 2.0, C.orange, (v) => setState(() => _perimeterSetbackM = v)),
          const SizedBox(height: 6),
          Row(children: [
            Text('Module Wattage:', style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final wp in const [440, 540, 550, 580, 600]) ...[
                    ChoiceChip(
                      label: Text('${wp}W', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      selected: _moduleWp == wp,
                      selectedColor: C.orange.withValues(alpha: .22),
                      onSelected: (_) => setState(() => _moduleWp = wp),
                    ),
                    const SizedBox(width: 5),
                  ],
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _miniStat('Gross Roof', '${grossArea.toStringAsFixed(1)} m²', C.text)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Est. Panels', '$estPanels × ${_moduleWp}W', C.sky)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Max Capacity', '${estKwp.toStringAsFixed(2)} kWp', C.green)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // OSM Surrounding Buildings & Verification Card
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.radar_rounded, color: C.purple, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Real Map & OSM Buildings Scan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _scanningOsm ? null : _scanOsmBuildings,
                icon: Icon(Icons.apartment_rounded, size: 16),
                style: FilledButton.styleFrom(backgroundColor: C.purple),
                label: Text(_scanningOsm ? 'Scanning OSM...' : 'Scan OSM Buildings', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showObstacleSheet(),
                icon: Icon(Icons.add_rounded, size: 16, color: C.orange),
                label: Text('Add Obstacle', style: TextStyle(color: C.orange, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
          if (_osmStatusMsg != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(10)),
              child: Text(_osmStatusMsg!, style: TextStyle(color: C.text, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(height: 10),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Satellite Map Imagery Verified', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            value: _mapVerified,
            activeColor: C.green,
            onChanged: (v) => setState(() => _mapVerified = v ?? false),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Building Height & Parapet Confirmed', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            value: _buildingVerified,
            activeColor: C.green,
            onChanged: (v) => setState(() => _buildingVerified = v ?? false),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Surrounding Obstacles Verified (${_obstacles.length} logged)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            value: _obstaclesVerified,
            activeColor: C.green,
            onChanged: (v) => setState(() => _obstaclesVerified = v ?? false),
          ),
          const SizedBox(height: 8),
          _nextStepButton('Next: Step 2 · Roof Map & Polygon', 2),
        ]),
      ),
    ]);
  }

  // -------------------- STEP 2: SATELLITE ROOF MAP & POLYGON TRACE --------------------
  Widget _buildStep2RoofMap({
    required double posAlt,
    required double posAz,
    required double grossArea,
    required double usableArea,
    required int estPanels,
    required double estKwp,
    required List<List<double>> heatmapGrid,
  }) {
    final perimeterM = 2 * (_roofLenM + _roofWidM);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _segChip('Roof Polygon & Auto-Detect', _step2Engine == 0, () => setState(() => _step2Engine = 0)),
            const SizedBox(width: 6),
            _segChip('3D Shadow Map', _step2Engine == 1, () => setState(() => _step2Engine = 1)),
          ]),
          const SizedBox(height: 12),
          if (_step2Engine == 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _footprintLocked ? C.chipGreen : C.chipSun,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (_footprintLocked ? C.green : C.orange).withValues(alpha: .45)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_footprintLocked ? Icons.verified_rounded : Icons.satellite_alt_rounded, color: _footprintLocked ? C.green : C.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _footprintLocked ? 'Roof Polygon Geodesically Measured' : 'Trace Your Real Roof on Satellite Map',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  _roofTrace != null
                      ? 'Traced footprint: ${_roofTrace!.areaM2.toStringAsFixed(1)} m² · ${_roofTrace!.panels} panels · ${_roofTrace!.kwp.toStringAsFixed(2)} kWp. Synced automatically to 2D CAD, 3D Building, Heatmap & PVsyst.'
                      : 'Open the interactive Satellite Roof Map to tap your exact building corners and compute geodesic area, panel count, and kWp.',
                  style: TextStyle(color: C.text, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openRoofMap,
                      icon: const Icon(Icons.edit_location_alt_rounded, size: 17),
                      style: FilledButton.styleFrom(backgroundColor: C.green),
                      label: Text(_roofTrace != null ? 'Re-Trace Satellite Roof' : 'Launch Satellite Roof Map', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openExternalGoogle3D,
                    icon: Icon(Icons.open_in_new_rounded, size: 15, color: C.sky),
                    label: Text('3D Maps', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _miniStat('Gross Area', '${grossArea.toStringAsFixed(1)} m²', C.text)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Usable PV', '${usableArea.toStringAsFixed(1)} m²', C.sky)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Perimeter', '${perimeterM.toStringAsFixed(1)} m', C.amber)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _miniStat('Max Panels', '$estPanels modules', C.orange)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Max DC Size', '${estKwp.toStringAsFixed(2)} kWp', C.green)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Footprint', '${_roofLenM.toStringAsFixed(1)}×${_roofWidM.toStringAsFixed(1)}m', C.blue)),
            ]),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 250,
                width: double.infinity,
                child: CustomPaint(
                  painter: Building3DShadowPainter(
                    wireframe: false,
                    showHeatmapOverlay: true,
                    heatmapGrid: heatmapGrid,
                    assemblyLayer: 'structure_and_panels',
                    orbitYawDeg: _orbitYawDeg,
                    cameraPitchDeg: _cameraPitchDeg,
                    roofLenM: _roofLenM,
                    roofWidM: _roofWidM,
                    buildingHeightM: _buildingHeightM,
                    parapetHeightM: _parapetHeightM,
                    setbackM: _perimeterSetbackM,
                    mmsClearanceM: _mms.clearanceM,
                    tiltDeg: _tiltDeg,
                    crossBracing: _crossBracing,
                    sunAlt: posAlt,
                    sunAz: posAz,
                    obstacles: _obstacles,
                    isDark: C.dark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _sliderRow('Orbit Angle', '${_orbitYawDeg.round()}°', _orbitYawDeg, 0, 360, C.orange, (v) => setState(() => _orbitYawDeg = v)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _footprintLocked = true;
                  _mapVerified = true;
                  _workflowStep = 3;
                }),
                icon: Icon(Icons.verified_outlined, size: 16, color: C.green),
                label: Text('Confirm Footprint', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _nextStepButton('Next: 2D CAD', 3)),
          ]),
        ]),
      ),
    ]);
  }

  // -------------------- STEP 3: 2D AUTOCAD BLUEPRINT & PV ZONES --------------------
  Widget _buildStep3CadAndZones({
    required double posAlt,
    required double posAz,
    required double effSetback,
  }) {
    final usableL = math.max(2.0, _roofLenM - effSetback * 2);
    final usableW = math.max(2.0, _roofWidM - effSetback * 2);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _segChip('2D AutoCAD Blueprint', !_step3Satellite, () => setState(() => _step3Satellite = false)),
            const SizedBox(width: 6),
            _segChip('Satellite CAD Overlay', _step3Satellite, () => setState(() => _step3Satellite = true)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 272,
              width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
              child: CustomPaint(
                painter: RoofCad2DPainter(
                  satelliteMode: _step3Satellite,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  setbackM: effSetback,
                  mmsClearanceM: _mms.clearanceM,
                  sunAlt: posAlt,
                  sunAz: posAz,
                  obstacles: _obstacles,
                  zones: _zones,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _legendDot(const Color(0xFF1D4ED8), 'PV Modules'),
            _legendDot(const Color(0xFF10B981), 'PV Zones'),
            _legendDot(const Color(0xFFEF4444), 'Obstacle'),
            _legendDot(const Color(0xFF7C3AED), 'OSM Building'),
            _legendDot(const Color(0xFF020617), 'Shadow'),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Potential PV Zones Manager
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.grid_view_rounded, color: C.green, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text('Potential PV Zones (${_zones.where((z) => z.enabled).length}/${_zones.length} active)', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
            InkWell(
              onTap: () {
                setState(() {
                  _zones = [
                    const PvZone(id: 'z1', name: 'Zone A (North)', xFrac: 0.0, yFrac: 0.0, wFrac: 1.0, hFrac: 0.45),
                    const PvZone(id: 'z2', name: 'Zone B (South)', xFrac: 0.0, yFrac: 0.55, wFrac: 1.0, hFrac: 0.45),
                  ];
                });
              },
              child: Text('Auto-Split', style: TextStyle(color: C.sky, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () {
                setState(() {
                  _zones.add(PvZone(
                    id: 'z_${_zoneSeq++}',
                    name: 'Zone ${_zones.length + 1}',
                    xFrac: (_zones.length.isEven ? 0.0 : 0.52),
                    yFrac: 0.1,
                    wFrac: 0.46,
                    hFrac: 0.8,
                  ));
                });
              },
              child: Text('+ Add Zone', style: TextStyle(color: C.orange, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final z in _zones) ...[
            Builder(builder: (_) {
              final zArea = usableL * usableW * z.wFrac * z.hFrac * _mms.fillFactor;
              final zPanels = (zArea / 2.58).floor().clamp(0, 400).toInt();
              final zKwp = zPanels * (_moduleWp / 1000.0);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(11), border: Border.all(color: C.line)),
                child: Row(children: [
                  Checkbox(
                    value: z.enabled,
                    activeColor: C.green,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() {
                      final idx = _zones.indexWhere((x) => x.id == z.id);
                      if (idx >= 0) _zones[idx] = z.copyWith(enabled: v ?? true);
                    }),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(z.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                      Text('${zArea.toStringAsFixed(1)} m² · $zPanels panels · ${zKwp.toStringAsFixed(2)} kWp', style: TextStyle(color: C.mute, fontSize: 11)),
                    ]),
                  ),
                  if (_zones.length > 1)
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 17, color: C.red),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _zones.removeWhere((x) => x.id == z.id)),
                    ),
                ]),
              );
            }),
          ],
          const SizedBox(height: 8),
          _nextStepButton('Next: Step 4 · 3D Building & Heatmap', 4),
        ]),
      ),
    ]);
  }

  // -------------------- STEP 4: 3D BUILDING SHADOWS & ROOF HEATMAP --------------------
  Widget _buildStep4Building3D({
    required double posAlt,
    required double posAz,
    required double effSetback,
    required List<List<double>> heatmapGrid,
  }) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _segChip('3D Building & Heatmap', !_step4Wireframe, () => setState(() => _step4Wireframe = false)),
          const SizedBox(width: 6),
          _segChip('AutoCAD 3D Wireframe', _step4Wireframe, () => setState(() => _step4Wireframe = true)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(14)),
            child: CustomPaint(
              painter: Building3DShadowPainter(
                wireframe: _step4Wireframe,
                showHeatmapOverlay: _show3dHeatmap,
                heatmapGrid: heatmapGrid,
                assemblyLayer: _assemblyLayer,
                orbitYawDeg: _orbitYawDeg,
                cameraPitchDeg: _cameraPitchDeg,
                roofLenM: _roofLenM,
                roofWidM: _roofWidM,
                buildingHeightM: _buildingHeightM,
                parapetHeightM: _parapetHeightM,
                setbackM: effSetback,
                mmsClearanceM: _mms.clearanceM,
                tiltDeg: _tiltDeg,
                crossBracing: _crossBracing,
                sunAlt: posAlt,
                sunAz: posAz,
                obstacles: _obstacles,
                isDark: C.dark,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('3D Roof Sunlight Heatmap Overlay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text('Colors roof slab by annual/seasonal solar exposure', style: TextStyle(color: C.mute, fontSize: 11)),
            ]),
          ),
          Switch(
            value: _show3dHeatmap,
            onChanged: (v) => setState(() => _show3dHeatmap = v),
          ),
        ]),
        _sliderRow('Camera Orbit Angle', '${_orbitYawDeg.round()}°', _orbitYawDeg, 0.0, 360.0, C.orange, (v) => setState(() => _orbitYawDeg = v)),
        _sliderRow('Camera Pitch Tilt', '${_cameraPitchDeg.round()}°', _cameraPitchDeg, 20.0, 72.0, C.sky, (v) => setState(() => _cameraPitchDeg = v)),
        const SizedBox(height: 8),
        _nextStepButton('Next: Step 5 · MMS Mounting Structure', 5),
      ]),
    );
  }

  // -------------------- STEP 5: MMS MOUNTING STRUCTURE PRESETS & PANEL LAYOUT --------------------
  Widget _buildStep5MmsAndPanels({
    required double posAlt,
    required double posAz,
    required double effSetback,
    required List<List<double>> heatmapGrid,
  }) {
    final recPitch = SolarAnalysisEngine.recommendedRowPitchM(
      lat: _siteLat,
      tiltDeg: _tiltDeg,
      collectorWidthM: _collectorWidthM,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AutoCAD Solar Mounting Structure Preset', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.35,
            children: [
              for (var i = 0; i < kMmsPresets.length; i++)
                InkWell(
                  onTap: () => setState(() => _mmsIndex = i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _mmsIndex == i ? C.sky.withValues(alpha: .15) : C.card2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _mmsIndex == i ? C.sky : C.line, width: _mmsIndex == i ? 1.5 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(kMmsPresets[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _mmsIndex == i ? C.sky : C.text, fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(kMmsPresets[i].desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 10)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Assembly Layer Inspection', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            for (final layer in const [
              ('building_only', 'Building Only'),
              ('structure_only', 'MMS Frame Only'),
              ('structure_and_panels', 'Structure + Panels'),
            ]) ...[
              Expanded(
                child: _segChip(layer.$2, _assemblyLayer == layer.$1, () => setState(() => _assemblyLayer = layer.$1)),
              ),
              if (layer.$1 != 'structure_and_panels') const SizedBox(width: 5),
            ],
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 245,
              width: double.infinity,
              child: CustomPaint(
                painter: Building3DShadowPainter(
                  wireframe: false,
                  showHeatmapOverlay: false,
                  heatmapGrid: heatmapGrid,
                  assemblyLayer: _assemblyLayer,
                  orbitYawDeg: _orbitYawDeg,
                  cameraPitchDeg: _cameraPitchDeg,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  buildingHeightM: _buildingHeightM,
                  parapetHeightM: _parapetHeightM,
                  setbackM: effSetback,
                  mmsClearanceM: _mms.clearanceM,
                  tiltDeg: _tiltDeg,
                  crossBracing: _crossBracing,
                  sunAlt: posAlt,
                  sunAz: posAz,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _sliderRow('Array Tilt Angle', '${_tiltDeg.round()}°', _tiltDeg, 0, 45, C.orange, (v) => setState(() => _tiltDeg = v)),
          _sliderRow('Column Grid Spacing', '${_columnSpacingM.toStringAsFixed(1)} m', _columnSpacingM, 2.0, 5.0, C.sky, (v) => setState(() => _columnSpacingM = v)),
          _sliderRow('Row Pitch (Min Rec: ${recPitch.toStringAsFixed(2)}m)', '${_rowPitchM.toStringAsFixed(2)} m', _rowPitchM, 1.8, 8.0, C.blue, (v) => setState(() => _rowPitchM = v)),
          Row(children: [
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cross-Bracing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                value: _crossBracing,
                activeColor: C.orange,
                onChanged: (v) => setState(() => _crossBracing = v ?? true),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('RCC Pedestals', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                value: _brickPedestals,
                activeColor: C.orange,
                onChanged: (v) => setState(() => _brickPedestals = v ?? true),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _nextStepButton('Next: Step 6 · 360° Walkthrough Tour', 6),
        ]),
      ),
    ]);
  }

  // -------------------- STEP 6: 360° INTERACTIVE SHADOW WALKTHROUGH TOUR --------------------
  Widget _buildStep6Tour360({
    required double posAlt,
    required double posAz,
    required double unshadedNow,
    required double effSetback,
    required List<List<double>> heatmapGrid,
  }) {
    final runningTour = _tourOrbiting || _sweeping;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.videocam_rounded, color: C.orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('360° Interactive Solar Shadow Tour', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          FilledButton.icon(
            onPressed: () => _startOrStopAnimation(sweepSun: !runningTour, orbitCam: !runningTour),
            icon: Icon(runningTour ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 17),
            style: FilledButton.styleFrom(backgroundColor: runningTour ? C.red : C.orange, visualDensity: VisualDensity.compact),
            label: Text(runningTour ? 'Stop Tour' : 'Play 360° Tour', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 285,
              width: double.infinity,
              child: CustomPaint(
                painter: Building3DShadowPainter(
                  wireframe: false,
                  showHeatmapOverlay: _show3dHeatmap,
                  heatmapGrid: heatmapGrid,
                  assemblyLayer: 'structure_and_panels',
                  orbitYawDeg: _orbitYawDeg,
                  cameraPitchDeg: _cameraPitchDeg,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  buildingHeightM: _buildingHeightM,
                  parapetHeightM: _parapetHeightM,
                  setbackM: effSetback,
                  mmsClearanceM: _mms.clearanceM,
                  tiltDeg: _tiltDeg,
                  crossBracing: _crossBracing,
                  sunAlt: posAlt,
                  sunAz: posAz,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFF0F172A).withValues(alpha: 0.82), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Yaw ${_orbitYawDeg.round()}° · ${_fmtHour(_hour)} · ${(unshadedNow * 100).round()}% Sun',
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _sliderRow('360° Orbit Camera Yaw', '${_orbitYawDeg.round()}°', _orbitYawDeg, 0, 360, C.orange, (v) => setState(() => _orbitYawDeg = v)),
        _sliderRow('Camera Elevation Pitch', '${_cameraPitchDeg.round()}°', _cameraPitchDeg, 20, 72, C.sky, (v) => setState(() => _cameraPitchDeg = v)),
        const SizedBox(height: 8),
        _nextStepButton('Next: Step 7 · PVsyst Shading & Audit Report', 7),
      ]),
    );
  }

  // -------------------- STEP 7: PVSYST SHADING ENGINE & SITE INSPECTION REPORT --------------------
  Widget _buildStep7PvSystAndReport({
    required double activeKwp,
    required double effSetback,
    required double grossArea,
    required int estPanels,
    required double estKwp,
    required List<double>? monthlyPsh,
  }) {
    final report = SolarAnalysisEngine.runAnnualPvSystSimulation(
      lat: _siteLat,
      lon: _siteLon,
      kwp: activeKwp,
      pr: state.pr,
      roofLenM: _roofLenM,
      roofWidM: _roofWidM,
      setbackM: effSetback,
      mmsClearanceM: _mms.clearanceM,
      tiltDeg: _tiltDeg,
      azimuthDeg: _azimuthDeg,
      albedo: _albedo,
      stringTopologyId: _stringTopologyId,
      obstacles: _obstacles,
      horizonProfile: _horizonProfile,
      monthlyPsh: monthlyPsh,
    );

    final winterNoonAlt = (90.0 - (_siteLat.abs() + 23.44)).clamp(10.0, 89.0).toDouble();
    final winterShadowM = _setbackObsH / math.tan(winterNoonAlt * math.pi / 180.0);
    final setbackSafe = _setbackObsDist >= winterShadowM;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Sub-tab switcher: PVsyst Shading vs Inspection Report
      Row(children: [
        Expanded(child: _segChip('PVsyst Shading & Horizon', _step7SubTab == 0, () => setState(() => _step7SubTab = 0))),
        const SizedBox(width: 8),
        Expanded(child: _segChip('Site Inspection & Report', _step7SubTab == 1, () => setState(() => _step7SubTab = 1))),
      ]),
      const SizedBox(height: 12),

      if (_step7SubTab == 0) ...[
        // KPI Summary Grid
        StatGrid([
          StatTile('Annual Unshaded', '${report.annualUnshadedPct.toStringAsFixed(1)}%', hi: true),
          StatTile('Electrical Loss', '-${report.annualElectricalLossPct.toStringAsFixed(1)}%'),
          StatTile('Horizon Loss', '-${report.annualHorizonLossPct.toStringAsFixed(1)}%'),
          StatTile('Net Annual Yield', '${groupIndian(report.annualNetKwh)} kWh'),
        ]),
        const SizedBox(height: 12),

        // String Topology & Optical Parameters
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('String Topology & Optical Model', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in kStringTopologies)
                ChoiceChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  selected: _stringTopologyId == t.id,
                  selectedColor: C.orange.withValues(alpha: .22),
                  onSelected: (_) => setState(() => _stringTopologyId = t.id),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              kStringTopologies.firstWhere((t) => t.id == _stringTopologyId, orElse: () => kStringTopologies.first).note,
              style: TextStyle(color: C.mute, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _miniStat('Linear Loss', '-${report.annualLinearLossPct.toStringAsFixed(1)}%', C.amber)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Orient Eff.', '${report.orientEffPct.toStringAsFixed(1)}%', C.sky)),
              const SizedBox(width: 6),
              Expanded(child: _miniStat('Specific Yield', '${report.specificYield.round()} kWh/kWp', C.green)),
            ]),
            const SizedBox(height: 10),
            _sliderRow('Tilt Angle', '${_tiltDeg.round()}°', _tiltDeg, 0, 45, C.orange, (v) => setState(() => _tiltDeg = v)),
            _sliderRow('Azimuth Facing', '${_azimuthDeg.round()}° ${compass(_azimuthDeg)}', _azimuthDeg, 0, 355, C.amber, (v) => setState(() => _azimuthDeg = v)),
            _sliderRow('Ground Albedo', _albedo.toStringAsFixed(2), _albedo, 0.12, 0.40, C.sky, (v) => setState(() => _albedo = v)),
          ]),
        ),
        const SizedBox(height: 12),

        // 12-Month PVsyst Net Yield BarChart & Table
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('12-Month PVsyst Net Yield (kWh)', style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            BarChart(
              series: [BarSeries('kWh', report.months.map((m) => m.netKwh).toList(), const Color(0xFF10B981))],
              labels: const ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'],
              highlight: DateTime.now().month - 1,
            ),
            const SizedBox(height: 10),
            for (final m in report.months)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 36, child: Text(m.monthLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
                  Expanded(child: Text('Sun ${m.unshadedPct.round()}% · Elec -${m.electricalLossPct.toStringAsFixed(1)}%', style: TextStyle(color: C.mute, fontSize: 11))),
                  Text('${m.netKwh.round()} kWh', style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Far-Horizon Profile Editor (8-Direction N..NW)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Far-Horizon Obstruction Profile', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final entry in kHorizonPresets.entries)
                OutlinedButton(
                  onPressed: () => setState(() => _horizonProfile = List<double>.from(entry.value)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(entry.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < 8; i++)
              _sliderRow(
                '${kHorizonDirs[i]} (${i * 45}°) Horizon',
                '${_horizonProfile[i].round()}°',
                _horizonProfile[i],
                0.0,
                45.0,
                C.purple,
                (v) => setState(() => _horizonProfile[i] = v),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Winter-Noon Shadow Setback Calculator
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Winter-Noon Obstacle Setback Calculator', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _sliderRow('Obstacle Height', '${_setbackObsH.toStringAsFixed(1)} m', _setbackObsH, 0.5, 12.0, C.orange, (v) => setState(() => _setbackObsH = v)),
            _sliderRow('Available Clearance Distance', '${_setbackObsDist.toStringAsFixed(1)} m', _setbackObsDist, 0.5, 15.0, C.sky, (v) => setState(() => _setbackObsDist = v)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: setbackSafe ? C.chipGreen : C.chipSun,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (setbackSafe ? C.green : C.orange).withValues(alpha: .4)),
              ),
              child: Text(
                setbackSafe
                    ? 'PASS: Clearance ${_setbackObsDist.toStringAsFixed(1)}m exceeds winter-noon shadow (${winterShadowM.toStringAsFixed(2)}m at ${winterNoonAlt.toStringAsFixed(1)}° sun altitude).'
                    : 'SHADE RISK: Minimum safe winter-noon setback is ${winterShadowM.toStringAsFixed(2)}m. Increase distance by ${(winterShadowM - _setbackObsDist).toStringAsFixed(2)}m or use Elevated Pergola MMS.',
                style: TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _step7SubTab = 1),
                icon: const Icon(Icons.assignment_turned_in_rounded, size: 17),
                style: FilledButton.styleFrom(backgroundColor: C.green),
                label: const Text('Proceed to Site Inspection & Audit Report', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ] else ...[
        // SUB-TAB B: SITE INSPECTION CHECKLIST & EXPORTABLE AUDIT REPORT
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Site Inspection & Engineering Audit Report', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              controller: _projectTitleCtrl,
              decoration: InputDecoration(labelText: 'Project / Survey Title', isDense: true, filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inspectorCtrl,
              decoration: InputDecoration(labelText: 'Inspector / Engineer Name', isDense: true, filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final st in const ['Draft', 'Reviewed', 'Approved']) ...[
                Expanded(child: _segChip(st, _surveyStatus == st, () => setState(() => _surveyStatus = st))),
                if (st != 'Approved') const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 10),
            Text('8-Point Engineering Verification Checklist', style: TextStyle(color: C.mute, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final item in kInspectionItems)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                subtitle: Text(item.$3, style: TextStyle(color: C.mute, fontSize: 11)),
                value: _checklist[item.$1] ?? true,
                activeColor: C.green,
                onChanged: (v) => setState(() => _checklist[item.$1] = v ?? false),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarksCtrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Engineer Remarks & Notes', filled: true, fillColor: C.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveCurrentProjectToVault,
                  icon: const Icon(Icons.save_rounded, size: 17),
                  style: FilledButton.styleFrom(backgroundColor: C.orange),
                  label: const Text('Save to Vault', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final passCount = _checklist.values.where((v) => v).length;
                    final summary = StringBuffer()
                      ..writeln('SOLAR ANALYSIS ENGINEERING AUDIT REPORT')
                      ..writeln('=======================================')
                      ..writeln('Project: ${_projectTitleCtrl.text.trim()}')
                      ..writeln('Inspector: ${_inspectorCtrl.text.trim()} | Status: $_surveyStatus')
                      ..writeln('Location: $_siteName (${_siteLat.toStringAsFixed(5)}, ${_siteLon.toStringAsFixed(5)}, Elev ${_siteElevM.round()}m)')
                      ..writeln('Roof: ${_roofLenM.toStringAsFixed(1)}m x ${_roofWidM.toStringAsFixed(1)}m (${grossArea.toStringAsFixed(1)} m²) | MMS: ${_mms.label}')
                      ..writeln('Capacity: $estPanels x ${_moduleWp}W = ${estKwp.toStringAsFixed(2)} kWp | Tilt ${_tiltDeg.round()}° | Az ${_azimuthDeg.round()}°')
                      ..writeln('Obstacles: ${_obstacles.length} verified | Annual Unshaded: ${report.annualUnshadedPct.toStringAsFixed(1)}%')
                      ..writeln('PVsyst Losses: Linear -${report.annualLinearLossPct.toStringAsFixed(1)}% | Electrical -${report.annualElectricalLossPct.toStringAsFixed(1)}% | Horizon -${report.annualHorizonLossPct.toStringAsFixed(1)}%')
                      ..writeln('Estimated Net Annual Yield: ${groupIndian(report.annualNetKwh)} kWh/yr (${report.specificYield.round()} kWh/kWp)')
                      ..writeln('Inspection Checklist: $passCount / ${kInspectionItems.length} Passed')
                      ..writeln('Remarks: ${_remarksCtrl.text.trim().isEmpty ? 'None' : _remarksCtrl.text.trim()}');
                    Clipboard.setData(ClipboardData(text: summary.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Full Engineering Audit Report copied to clipboard!')),
                    );
                  },
                  icon: const Icon(Icons.copy_all_rounded, size: 17),
                  style: FilledButton.styleFrom(backgroundColor: C.green),
                  label: const Text('Copy Report', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ]),
        ),
      ],
    ]);
  }

  // ==========================================================================
  // FIELD TOOL 1: 3D SHADOW & ROOF MAP
  // ==========================================================================
  Widget _buildField3DShadowMapView({
    required double posAlt,
    required double posAz,
    required DayInfo day,
    required double grossArea,
    required int estPanels,
    required double estKwp,
    required List<List<double>> heatmapGrid,
  }) {
    final shLen = posAlt > 2.0 ? _map3dObjHeightM / math.tan(posAlt * math.pi / 180.0) : 0.0;
    final shadowAz = (posAz + 180.0) % 360.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.public_rounded, color: C.orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('3D Shadow & Satellite Roof Map', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            FilledButton.icon(
              onPressed: _openRoofMap,
              icon: const Icon(Icons.satellite_alt_rounded, size: 15),
              style: FilledButton.styleFrom(backgroundColor: C.green, visualDensity: VisualDensity.compact),
              label: const Text('Trace Roof', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          // Quick Date Presets
          Row(children: [
            for (final d in const [(5, 'Jun 21'), (2, 'Equinox'), (11, 'Dec 21')]) ...[
              Expanded(child: _segChip(d.$2, _monthIdx == d.$1, () => setState(() => _monthIdx = d.$1))),
              const SizedBox(width: 6),
            ],
            Expanded(child: _segChip('Now', false, _resetNow)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 265,
              width: double.infinity,
              child: CustomPaint(
                painter: Building3DShadowPainter(
                  wireframe: false,
                  showHeatmapOverlay: _show3dHeatmap,
                  heatmapGrid: heatmapGrid,
                  assemblyLayer: 'structure_and_panels',
                  orbitYawDeg: _orbitYawDeg,
                  cameraPitchDeg: _cameraPitchDeg,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  buildingHeightM: _map3dObjHeightM,
                  parapetHeightM: _parapetHeightM,
                  setbackM: _perimeterSetbackM,
                  mmsClearanceM: _mms.clearanceM,
                  tiltDeg: _tiltDeg,
                  crossBracing: _crossBracing,
                  sunAlt: posAlt,
                  sunAz: posAz,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat('Time', _fmtHour(_hour), C.sky)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Sun Alt/Az', '${posAlt.round()}° / ${posAz.round()}°', C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Shadow', posAlt > 2 ? '${shLen.toStringAsFixed(1)}m ${compass(shadowAz)}' : 'Night', C.orange)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            InkWell(
              onTap: () => _startOrStopAnimation(sweepSun: !_sweeping, orbitCam: false),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: _sweeping ? C.orange : C.chipBlue, borderRadius: BorderRadius.circular(9)),
                child: Icon(_sweeping ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 17, color: _sweeping ? Colors.white : C.sky),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _hour.clamp(5.5, 18.5).toDouble(),
                min: 5.5,
                max: 18.5,
                activeColor: C.orange,
                onChanged: (v) => setState(() => _hour = v),
              ),
            ),
          ]),
          _sliderRow('Reference Object / Building Height', '${_map3dObjHeightM.toStringAsFixed(1)} m', _map3dObjHeightM, 2.0, 20.0, C.blue, (v) => setState(() => _map3dObjHeightM = v)),
          _sliderRow('3D Camera Orbit', '${_orbitYawDeg.round()}°', _orbitYawDeg, 0, 360, C.sky, (v) => setState(() => _orbitYawDeg = v)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openExternalGoogle3D,
                icon: Icon(Icons.open_in_new_rounded, size: 16, color: C.sky),
                label: Text('Open Google Maps 3D', style: TextStyle(color: C.sky, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() {
                  _suiteTab = 'shadow';
                  _workflowStep = 3;
                }),
                style: FilledButton.styleFrom(backgroundColor: C.orange),
                child: const Text('Open 7-Step Studio →', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile('Roof Area', '${grossArea.toStringAsFixed(1)} m²'),
        StatTile('Max Panels', '$estPanels × ${_moduleWp}W'),
        StatTile('Max Capacity', '${estKwp.toStringAsFixed(2)} kWp', hi: true),
        StatTile('Rise / Set', '${_fmtClock(day.rise)} / ${_fmtClock(day.set)}'),
      ]),
    ]);
  }

  // ==========================================================================
  // FIELD TOOL 2: ROOF SUN HEATMAP
  // ==========================================================================
  Widget _buildFieldHeatmapView({
    required List<List<double>> heatmapGrid,
    required double orientEff,
    required List<double>? monthlyPsh,
  }) {
    final flat = [for (final row in heatmapGrid) ...row];
    final avgRel = flat.fold(0.0, (a, b) => a + b) / flat.length;
    final peakRel = flat.fold(0.0, (a, b) => a > b ? a : b);
    final highSunPct = (flat.where((v) => v >= 0.78).length / flat.length) * 100.0;
    final basePsh = (monthlyPsh ?? kMonthPshHyd).reduce((a, b) => a + b) / 12.0;
    final mult = _heatmapPeriod == 1 ? 1.18 : (_heatmapPeriod == 2 ? 0.84 : 1.0);
    final avgSunHrs = (basePsh * mult * avgRel).clamp(1.0, 9.0).toDouble();
    final peakIrr = (basePsh * 365.0 * peakRel).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.local_fire_department_rounded, color: C.amber, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Roof Sunlight Irradiance Heatmap', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text('${(avgRel * 100).round()}% score', style: TextStyle(color: C.amber, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final p in const [(0, 'Annual'), (1, 'Summer'), (2, 'Winter'), (3, 'Today')]) ...[
              Expanded(child: _segChip(p.$2, _heatmapPeriod == p.$1, () => setState(() => _heatmapPeriod = p.$1))),
              if (p.$1 < 3) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 235,
              width: double.infinity,
              child: CustomPaint(
                painter: RoofHeatmapPainter(
                  grid: heatmapGrid,
                  roofLenM: _roofLenM,
                  roofWidM: _roofWidM,
                  obstacles: _obstacles,
                  isDark: C.dark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text('Shaded', style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFFACC15), Color(0xFFF97316)]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('Peak Sun', style: TextStyle(color: C.orange, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() {
                _show3dHeatmap = true;
                _step4Wireframe = false;
                _suiteTab = 'shadow';
                _workflowStep = 4;
              }),
              icon: const Icon(Icons.view_in_ar_rounded, size: 17),
              style: FilledButton.styleFrom(backgroundColor: C.amber),
              label: const Text('View Heatmap on 3D Building', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile('Avg Sun Hours', '${avgSunHrs.toStringAsFixed(1)} h/day', hi: true),
        StatTile('Peak Irradiance', '$peakIrr kWh/m²'),
        StatTile('High-Sun Roof', '${highSunPct.round()}% area'),
        StatTile('Orientation Eff.', '${(orientEff * 100).round()}%'),
      ]),
    ]);
  }

  // ==========================================================================
  // FIELD TOOL 3: 360° SUN COMPASS
  // ==========================================================================
  Widget _buildFieldCompassView({
    required DateTime simTime,
    required double posAlt,
    required double posAz,
    required DayInfo day,
    required double shadowAz,
  }) {
    final optAnnual = _siteLat.abs().clamp(5.0, 45.0).round();
    final optSummer = (_siteLat.abs() - 12.0).clamp(5.0, 40.0).round();
    final optWinter = (_siteLat.abs() + 12.0).clamp(12.0, 62.0).round();
    final bestFacing = _siteLat >= 0 ? 'True South (180°)' : 'True North (0°)';

    final arc = <({double alt, double az})>[];
    for (var m = 300; m <= 1140; m += 20) {
      final p = solarPosition(DateTime(simTime.year, simTime.month, simTime.day, m ~/ 60, m % 60), _siteLat, _siteLon);
      if (p.alt > 0) arc.add((alt: p.alt, az: p.az));
    }
    final riseAz = day.rise != null ? solarPosition(day.rise!, _siteLat, _siteLon).az : null;
    final setAz = day.set != null ? solarPosition(day.set!, _siteLat, _siteLon).az : null;
    final zenith = (90.0 - posAlt).clamp(0.0, 90.0).toDouble();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.explore_outlined, color: C.sky, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('360° Sun Path Compass', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text(_fmtHour(_hour), style: TextStyle(fontFamilyFallback: kMono, color: C.sky, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 245,
            width: double.infinity,
            child: CustomPaint(
              painter: SunCompassDialPainter(
                sunAz: posAz,
                sunAlt: posAlt,
                shadowAz: shadowAz,
                arcPoints: arc,
                riseAz: riseAz,
                setAz: setAz,
                panelAz: _azimuthDeg,
                isDark: C.dark,
              ),
            ),
          ),
          Slider(value: _hour.clamp(5.5, 18.5).toDouble(), min: 5.5, max: 18.5, activeColor: C.orange, onChanged: (v) => setState(() => _hour = v)),
          Row(children: [
            Expanded(child: _miniStat('Sun Azimuth', '${posAz.round()}° ${compass(posAz)}', C.orange)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Elevation', '${posAlt.toStringAsFixed(1)}°', C.amber)),
            const SizedBox(width: 6),
            Expanded(child: _miniStat('Zenith', '${zenith.toStringAsFixed(1)}°', C.sky)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Optimal Seasonal Tilt & Facing', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            Text(bestFacing, style: TextStyle(color: C.green, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
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
            child: OutlinedButton(
              onPressed: () => setState(() {
                _tiltDeg = optAnnual.toDouble();
                _azimuthDeg = _siteLat >= 0 ? 180.0 : 0.0;
                _suiteTab = 'shadow';
                _workflowStep = 5;
              }),
              child: Text('Apply $optAnnual° Optimal Tilt to Studio', style: TextStyle(color: C.orange, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ==========================================================================
  // FIELD TOOL 4: AR SUN VIEW (SKY-DOME & HORIZON OBSTRUCTION VIEWFINDER)
  // ==========================================================================
  Widget _buildFieldArSunView({
    required DateTime simTime,
    required double posAlt,
    required double posAz,
  }) {
    List<({double alt, double az})> sampleDay(int month, int day) {
      final pts = <({double alt, double az})>[];
      for (var m = 300; m <= 1140; m += 20) {
        final p = solarPosition(DateTime(simTime.year, month, day, m ~/ 60, m % 60), _siteLat, _siteLon);
        if (p.alt > 0) pts.add((alt: p.alt, az: p.az));
      }
      return pts;
    }

    final junArc = sampleDay(6, 21);
    final eqArc = sampleDay(3, 20);
    final decArc = sampleDay(12, 21);
    final hElev = SolarAnalysisEngine.horizonElevationAt(posAz, _horizonProfile);
    final clearOfHorizon = posAlt >= hElev;

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.camera_alt_outlined, color: C.purple, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('AR Sun-Path Sky Viewfinder', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
          Text('${_arHeadingDeg.round()}° ${compass(_arHeadingDeg)}', style: TextStyle(color: C.amber, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 270,
            width: double.infinity,
            child: CustomPaint(
              painter: ArSunSkyPainter(
                viewHeadingDeg: _arHeadingDeg,
                sunAlt: posAlt,
                sunAz: posAz,
                junArc: junArc,
                eqArc: eqArc,
                decArc: decArc,
                horizonProfile: _horizonProfile,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _legendDot(const Color(0xFFF97316), 'Jun 21 Solstice'),
          _legendDot(const Color(0xFFFACC15), 'Equinox'),
          _legendDot(const Color(0xFF38BDF8), 'Dec 21 Solstice'),
          _legendDot(const Color(0xFF020617), 'Horizon Skyline'),
        ]),
        const SizedBox(height: 10),
        _sliderRow('Pan Compass Heading', '${_arHeadingDeg.round()}° ${compass(_arHeadingDeg)}', _arHeadingDeg, 0, 355, C.purple, (v) => setState(() => _arHeadingDeg = v)),
        _sliderRow('Time of Day', _fmtHour(_hour), _hour, 5.5, 18.5, C.orange, (v) => setState(() => _hour = v)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: clearOfHorizon ? C.chipGreen : C.chipSun, borderRadius: BorderRadius.circular(11)),
          child: Text(
            posAlt <= 0
                ? 'Sun is below horizon at ${_fmtHour(_hour)}.'
                : clearOfHorizon
                    ? 'Direct Sun Clear: Solar altitude ${posAlt.toStringAsFixed(1)}° is above horizon skyline (${hElev.toStringAsFixed(1)}° at ${posAz.round()}°).'
                    : 'Horizon Obstruction: Sun (${posAlt.toStringAsFixed(1)}°) is blocked by far-horizon profile (${hElev.toStringAsFixed(1)}°).',
            style: TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  // ==========================================================================
  // FIELD TOOL 5: SUN TIMER & GENERATION YIELD FORECAST
  // ==========================================================================
  Widget _buildFieldSunTimerAndYieldView({
    required DayInfo day,
    required List<double>? monthlyPsh,
  }) {
    final site = state.site;
    final hk = state.solarHourlyKw();
    final psh = state.irr?.psh ?? 0.0;
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
      (i) => site.kwp * ((monthlyPsh != null && monthlyPsh.length == 12) ? monthlyPsh[i] : kMonthPshHyd[i]) * pr * health * DateTime(year, i + 2, 0).day,
    );
    final annual = monthly.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);

    DateTime? solarNoon;
    String daylightStr = '--';
    double dayProgress = 0.0;
    String morningGolden = '--';
    String eveningGolden = '--';
    double noonAlt = 0.0;

    if (day.rise != null && day.set != null) {
      final totalMins = day.set!.difference(day.rise!).inMinutes;
      daylightStr = '${totalMins ~/ 60}h ${totalMins % 60}m';
      solarNoon = day.rise!.add(Duration(minutes: totalMins ~/ 2));
      noonAlt = solarPosition(solarNoon, _siteLat, _siteLon).alt;
      morningGolden = '${_fmtClock(day.rise)} – ${_fmtClock(day.rise!.add(const Duration(minutes: 55)))}';
      eveningGolden = '${_fmtClock(day.set!.subtract(const Duration(minutes: 55)))} – ${_fmtClock(day.set)}';
      if (totalMins > 0) {
        dayProgress = (DateTime.now().difference(day.rise!).inMinutes / totalMins).clamp(0.0, 1.0).toDouble();
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.wb_twilight_rounded, color: C.orange, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Sun Timer & Ephemeris', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
            Text(daylightStr, style: TextStyle(color: C.amber, fontWeight: FontWeight.w800)),
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
            child: LinearProgressIndicator(value: dayProgress, minHeight: 8, backgroundColor: C.card2, valueColor: AlwaysStoppedAnimation<Color>(C.orange)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Morning Golden: $morningGolden', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w600))),
            Text('Evening: $eveningGolden', style: TextStyle(color: C.mute, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile('Plant size', '${site.kwp} kWp'),
        StatTile("Today's yield", '${fmt1(daily)} kWh'),
        StatTile('Peak sun hours', psh > 0 ? '${psh.toStringAsFixed(1)} h' : '-'),
        StatTile('Peak output', '${peakKw.toStringAsFixed(2)} kW'),
      ]),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today by hour (kW)', style: title),
          const SizedBox(height: 10),
          BarChart(series: [BarSeries('kW', hk, const Color(0xFFF59E0B))], labels: List.generate(24, (i) => i % 3 == 0 ? '$i' : null), highlight: DateTime.now().hour),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Typical monthly yield (kWh)', style: title),
          const SizedBox(height: 10),
          BarChart(series: [BarSeries('kWh', monthly, const Color(0xFF38BDF8))], labels: months, highlight: DateTime.now().month - 1),
        ]),
      ),
      const SizedBox(height: 12),
      StatGrid([
        StatTile('Annual generation', '${groupIndian(annual)} kWh', hi: true),
        StatTile('Specific yield', '${(annual / (site.kwp < 0.1 ? 0.1 : site.kwp)).round()} kWh/kWp'),
        StatTile('Annual value', '₹${groupIndian(annual * site.tariff)}'),
        StatTile('CO₂ avoided / yr', '${fmt1(annual * kCo2PerKwh / 1000)} t'),
      ]),
    ]);
  }

  // ==================== SHARED SMALL UI HELPERS ====================
  Widget _nextStepButton(String label, int nextStep) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => setState(() => _workflowStep = nextStep),
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          style: FilledButton.styleFrom(backgroundColor: C.blue, minimumSize: const Size.fromHeight(44)),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
      );

  Widget _segChip(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? C.orange : C.card2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? C.orange : C.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: active ? Colors.white : C.text, fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ),
      );

  Widget _sliderRow(String label, String valueText, double val, double min, double max, Color color, ValueChanged<double> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            Text(valueText, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3.5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5)),
            child: Slider(value: val.clamp(min, max).toDouble(), min: min, max: max, activeColor: color, onChanged: onChanged),
          ),
        ],
      );

  Widget _legendDot(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
      ]);

  Widget _miniStat(String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(11), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 10.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
      );
}
