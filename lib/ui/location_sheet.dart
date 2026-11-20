import 'package:flutter/material.dart';
import '../core/geo.dart';
import '../core/store.dart';
import 'theme.dart';

Future<void> showLocationSheet(BuildContext context, AppState s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _LocationBody(state: s),
    ),
  );
}

class _LocationBody extends StatefulWidget {
  final AppState state;
  const _LocationBody({required this.state});
  @override
  State<_LocationBody> createState() => _LocationBodyState();
}

class _LocationBodyState extends State<_LocationBody> {
  final q = TextEditingController();
  List<GeoHit> hits = [];
  bool busy = false;
  String msg = '';

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      busy = true;
      msg = '';
    });
    final r = await searchPlaces(q.text);
    if (!mounted) return;
    setState(() {
      hits = r;
      busy = false;
      if (r.isEmpty) msg = '–';
    });
  }

  Future<void> _pick(GeoHit h) async {
    setState(() => busy = true);
    final p = await reverse(h.lat, h.lng);
    final place = Place(h.lat, h.lng, h.name, p.locality, p.region.isEmpty ? h.region : p.region, p.postcode);
    await widget.state.setPlace(place, user: true);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _gps() async {
    setState(() {
      busy = true;
      msg = '';
    });
    final p = await currentPlace();
    if (!mounted) return;
    if (p == null) {
      setState(() {
        busy = false;
        msg = 'Location permission is off or unavailable. Search a city instead.';
      });
      return;
    }
    await widget.state.setPlace(p);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.state.t;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.location_on, color: C.orange),
            const SizedBox(width: 8),
            Text(widget.state.site.city, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : _gps,
            icon: const Icon(Icons.my_location),
            label: Text(t('use_gps')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: t('search_city'),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: busy ? null : _search),
            ),
          ),
          if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg, style: TextStyle(color: C.mute))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final h in hits)
                ListTile(
                  leading: Icon(Icons.place_outlined, color: C.blue),
                  title: Text(h.name),
                  subtitle: Text(h.region),
                  onTap: busy ? null : () => _pick(h),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
