import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/store.dart';
import '../core/update.dart';
import 'theme.dart';

Future<void> showSettingsSheet(BuildContext context, AppState s) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SettingsBody(state: s),
    ),
  );
}

class _SettingsBody extends StatefulWidget {
  final AppState state;
  const _SettingsBody({required this.state});
  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  late final TextEditingController city, label, lat, lon, kwp, tariff, company, phone, note;
  String version = '';
  String updateMsg = '';
  UpdateInfo? pending;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    city = TextEditingController(text: s.site.city);
    label = TextEditingController(text: s.site.label);
    lat = TextEditingController(text: s.site.lat.toString());
    lon = TextEditingController(text: s.site.lon.toString());
    kwp = TextEditingController(text: s.site.kwp.toString());
    tariff = TextEditingController(text: s.site.tariff.toString());
    company = TextEditingController(text: s.brand.company);
    phone = TextEditingController(text: s.brand.phone);
    note = TextEditingController(text: s.brand.note);
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (build ${i.buildNumber})');
    });
  }

  @override
  void dispose() {
    for (final c in [city, label, lat, lon, kwp, tariff, company, phone, note]) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(TextEditingController c, double d) => double.tryParse(c.text.trim()) ?? d;

  void _save() {
    final s = widget.state;
    s.site
      ..city = city.text.trim().isEmpty ? s.site.city : city.text.trim()
      ..label = label.text.trim()
      ..lat = _n(lat, s.site.lat).clamp(-90, 90).toDouble()
      ..lon = _n(lon, s.site.lon).clamp(-180, 180).toDouble()
      ..kwp = _n(kwp, s.site.kwp).clamp(0.1, 10000).toDouble()
      ..tariff = _n(tariff, s.site.tariff).clamp(0.1, 1000).toDouble();
    s.brand
      ..company = company.text.trim()
      ..phone = phone.text.trim()
      ..note = note.text.trim();
    s.saveSite();
    s.saveBrand();
    s.sync();
    Navigator.pop(context);
  }

  Widget _f(String l, TextEditingController c, {bool num = false}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
          decoration: InputDecoration(labelText: l),
        ),
      );

  Future<void> _check() async {
    setState(() {
      checking = true;
      updateMsg = '';
    });
    final r = await checkForUpdate();
    if (!mounted) return;
    setState(() {
      checking = false;
      pending = r.update;
      updateMsg = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('Site & plant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.amber)),
          _f('City', city),
          _f('Location label', label),
          Row(children: [
            Expanded(child: _f('Latitude', lat, num: true)),
            const SizedBox(width: 10),
            Expanded(child: _f('Longitude', lon, num: true)),
          ]),
          Row(children: [
            Expanded(child: _f('Plant size (kWp)', kwp, num: true)),
            const SizedBox(width: 10),
            Expanded(child: _f('Tariff (Rs./kWh)', tariff, num: true)),
          ]),
          const SizedBox(height: 20),
          const Text('Quote branding', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.amber)),
          _f('Company name', company),
          _f('Phone / WhatsApp', phone),
          _f('Quote footer note', note),
          const SizedBox(height: 20),
          const Text('About & updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.amber)),
          const SizedBox(height: 8),
          Text('Version ${version.isEmpty ? '...' : version}', style: const TextStyle(color: C.mute)),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(onPressed: checking ? null : _check, child: Text(checking ? 'Checking...' : 'Check for updates')),
            const SizedBox(width: 10),
            if (pending != null) FilledButton(onPressed: () => openUpdate(pending!), child: const Text('Download update')),
          ]),
          if (updateMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(updateMsg, style: const TextStyle(color: C.mute, fontSize: 13))),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
          ]),
        ],
      ),
    );
  }
}
