import 'package:flutter/material.dart';

import '../core/inverter_sync.dart';
import 'theme.dart';

/// Live inverter sync: log in to the brand's cloud portal through the backend and show
/// today's generation. Credentials stay in this widget's memory only. They are not saved.
class InverterSyncSection extends StatefulWidget {
  final InverterSyncSource? source;
  const InverterSyncSection({super.key, this.source});

  @override
  State<InverterSyncSection> createState() => _InverterSyncSectionState();
}

class _InverterSyncSectionState extends State<InverterSyncSection> {
  String brand = kInverterBrands.first.id;
  final user = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  InverterSyncResult? result;
  String? stationId;

  InverterSyncSource? get _source => widget.source ?? defaultInverterSync();

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _sync({String? station}) async {
    final src = _source;
    if (src == null) {
      setState(() => result = InverterSyncResult.failed('The sync server is not set up in this build.'));
      return;
    }
    if (user.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => result = InverterSyncResult.failed('Enter your portal username and password.'));
      return;
    }
    setState(() {
      busy = true;
      result = null;
    });
    final r = await src.sync(
      brand: brand,
      username: user.text.trim(),
      password: pass.text,
      stationId: station ?? stationId,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      result = r;
      if (station != null) stationId = station;
      // Keep the password while the account needs a plant pick, so the next tap can reuse it.
      if (r.ok) pass.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    final title = TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cloud_sync_outlined, color: C.amber),
          const SizedBox(width: 8),
          Expanded(child: Text('Live from inverter portal', style: title)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Log in to your inverter brand portal. Today\'s generation is read once. The password is not saved.',
          style: TextStyle(color: C.mute, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: brand,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Inverter brand', isDense: true),
          items: [for (final b in kInverterBrands) DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis))],
          onChanged: busy ? null : (v) => setState(() => brand = v ?? brand),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: user,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Portal username or email', isDense: true),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: pass,
          enabled: !busy,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Portal password', isDense: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            onPressed: busy ? null : () => _sync(),
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
            label: Text(busy ? 'Syncing…' : 'Sync now', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
        if (r != null) ...[
          const SizedBox(height: 12),
          _result(r),
        ],
      ]),
    );
  }

  Widget _result(InverterSyncResult r) {
    if (!r.ok && r.needsPlant && r.plants.isNotEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('This account has ${r.plants.length} plants. Pick one:', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final p in r.plants)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: busy ? null : () => _sync(station: p.stationId),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${p.name}${p.capacityKwp != null ? ' · ${p.capacityKwp!.toStringAsFixed(2)} kWp' : ''}'),
              ),
            ),
          ),
      ]);
    }
    if (!r.ok) {
      return Text(r.error ?? 'Sync failed. No data was shown.', style: TextStyle(color: C.red, fontSize: 13));
    }
    final lines = <(String, String)>[
      if (r.plantName != null) ('Plant', r.plantName!),
      if (r.model != null) ('Inverter', r.model!),
      if (r.todayGenKwh != null) ("Today's generation", '${r.todayGenKwh!.toStringAsFixed(2)} kWh'),
      if (r.livePowerKw != null) ('Power now', '${r.livePowerKw!.toStringAsFixed(2)} kW'),
      if (r.lifetimeKwh != null) ('Lifetime generation', '${r.lifetimeKwh!.toStringAsFixed(0)} kWh'),
      if (r.syncedAtIst != null) ('Synced (IST)', r.syncedAtIst!),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (r.providerName != null) Text(r.providerName!, style: TextStyle(color: C.mute, fontSize: 12)),
      const SizedBox(height: 6),
      for (final (k, v) in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: C.mute, fontSize: 13))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      if (r.statusNote != null && r.statusNote!.isNotEmpty)
        Text(r.statusNote!, style: TextStyle(color: C.mute, fontSize: 12)),
    ]);
  }
}
