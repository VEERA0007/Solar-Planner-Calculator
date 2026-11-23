import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../core/estimator_data.dart';
import '../core/roof.dart';
import '../core/store.dart';
import 'theme.dart';

/// What the roof map hands back to the Estimator.
class RoofResult {
  final double areaM2;
  final int panels;
  final double kwp;
  const RoofResult(this.areaM2, this.panels, this.kwp);
}

/// Trace the roof on satellite imagery, pack panels inside it and export a DXF.
class RoofMapPage extends StatefulWidget {
  final AppState state;
  final PanelModel panel;
  const RoofMapPage({super.key, required this.state, required this.panel});
  @override
  State<RoofMapPage> createState() => _RoofMapPageState();
}

class _RoofMapPageState extends State<RoofMapPage> {
  final points = <LatLng>[];
  final gap = TextEditingController(text: '25'), rowGap = TextEditingController(text: '450'), setback = TextEditingController(text: '500');
  int orient = 0;
  bool closed = false;
  bool settings = false;

  double _n(TextEditingController c, double d) => double.tryParse(c.text.trim()) ?? d;

  @override
  void dispose() {
    gap.dispose();
    rowGap.dispose();
    setback.dispose();
    super.dispose();
  }

  RoofProjection get _proj => RoofProjection(points.first.latitude, points.first.longitude);
  List<Pt> get _local => [for (final p in points) _proj.toLocal(p.latitude, p.longitude)];

  RoofLayout? get _layout {
    if (!closed || points.length < 3) return null;
    return layoutPanels(_local, longMm: widget.panel.lengthMm, shortMm: widget.panel.widthMm, gapMm: _n(gap, 25), rowGapMm: _n(rowGap, 450), setbackMm: _n(setback, 500), orientation: orient);
  }

  Future<void> _export(RoofLayout l) async {
    final dxf = roofDxf(_local, l);
    await Share.shareXFiles([XFile.fromData(utf8.encode(dxf), mimeType: 'application/dxf', name: 'roof_layout.dxf')], fileNameOverrides: ['roof_layout.dxf']);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final center = LatLng(s.site.lat, s.site.lon);
    final layout = _layout;
    final proj = points.length >= 3 ? _proj : null;
    final kwp = layout == null ? 0.0 : layout.count * widget.panel.wp / 1000;
    final area = points.length >= 3 ? polygonArea(_local) : 0.0;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text('Trace roof', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(tooltip: 'Undo', onPressed: points.isEmpty ? null : () => setState(() {
                points.removeLast();
                closed = false;
              }), icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Clear', onPressed: points.isEmpty ? null : () => setState(() {
                points.clear();
                closed = false;
              }), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 19,
                maxZoom: 21,
                onTap: (_, p) {
                  if (closed) return;
                  setState(() => points.add(p));
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.solarplanner.calculator',
                  maxNativeZoom: 19,
                  maxZoom: 21,
                ),
                if (points.length >= 2) PolygonLayer(polygons: [Polygon(points: points, color: C.orange.withValues(alpha: closed ? .25 : .1), borderColor: C.orange, borderStrokeWidth: 3, isFilled: true)]),
                if (layout != null && proj != null)
                  PolygonLayer(polygons: [
                    for (final p in layout.panels)
                      Polygon(points: [for (final q in p) () { final ll = proj.toLatLon(q); return LatLng(ll.$1, ll.$2); }()], color: const Color(0xFF1E88E5).withValues(alpha: .75), borderColor: Colors.white, borderStrokeWidth: 1, isFilled: true),
                  ]),
                MarkerLayer(markers: [
                  for (var i = 0; i < points.length; i++)
                    Marker(point: points[i], width: 26, height: 26, child: Container(alignment: Alignment.center, decoration: BoxDecoration(color: C.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)))),
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('Imagery: Esri, Maxar, Earthstar Geographics')]),
              ],
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(14)),
                child: Text(closed ? 'Roof closed. Adjust spacing below, then apply.' : (points.isEmpty ? 'Tap each corner of the roof to trace the building.' : '${points.length} corner${points.length == 1 ? '' : 's'} placed. ${points.length < 3 ? 'Need at least 3.' : 'Tap more corners or Close shape.'}'), style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(color: C.card, border: Border(top: BorderSide(color: C.line))),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${widget.panel.wp} W panel · ${widget.panel.lengthMm.round()} × ${widget.panel.widthMm.round()} mm', style: TextStyle(color: C.mute, fontSize: 12.5))),
                TextButton(onPressed: () => setState(() => settings = !settings), child: Text(settings ? 'Hide spacing' : 'Spacing', style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              if (settings) ...[
                Row(children: [
                  for (final e in [(gap, 'Panel gap (mm)'), (rowGap, 'Row gap (mm)'), (setback, 'Setback (mm)')])
                    Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: TextField(controller: e.$1, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: e.$2, isDense: true)))),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final o in const [(0, 'Auto'), (1, 'Portrait'), (2, 'Landscape')]) ChoiceChip(label: Text(o.$2), selected: orient == o.$1, onSelected: (_) => setState(() => orient = o.$1)),
                ]),
                const SizedBox(height: 8),
              ],
              if (closed && layout != null) ...[
                Row(children: [
                  Expanded(child: Text('Enclosed area ${area.toStringAsFixed(1)} m² (${(area * 10.7639).round()} sq ft)', style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
                Text('Fits ${layout.count} × ${widget.panel.wp} W (${kwp.toStringAsFixed(2)} kWp), ${layout.landscape ? 'landscape' : 'portrait'}', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => _export(layout), icon: const Icon(Icons.download, size: 18), label: const Text('Export DXF', style: TextStyle(fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(context, RoofResult(area, layout.count, kwp)), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: C.orange), child: Text('Apply ${layout.count} panels (${kwp.toStringAsFixed(2)} kW)', style: const TextStyle(fontWeight: FontWeight.w800)))),
                ]),
              ] else
                FilledButton(
                  onPressed: points.length >= 3 ? () => setState(() => closed = true) : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: C.green),
                  child: const Text('Close shape & calculate', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
