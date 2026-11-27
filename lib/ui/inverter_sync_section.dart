import 'package:flutter/material.dart';

import '../core/inverter_sync.dart';
import 'theme.dart';

/// Live inverter and data-logger sync in three modes: cloud portal login, local Wi-Fi logger,
/// or HTTPS bridge. Passwords stay in this widget's memory only and are never saved.
class InverterSyncSection extends StatefulWidget {
  final InverterSyncSource? source;
  const InverterSyncSection({super.key, this.source});

  @override
  State<InverterSyncSection> createState() => _InverterSyncSectionState();
}

class _InverterSyncSectionState extends State<InverterSyncSection> {
  InverterConnectMode mode = InverterConnectMode.cloudPortal;
  String brand = kInverterBrands.first.id;
  final user = TextEditingController();
  final pass = TextEditingController();
  final address = TextEditingController();
  bool busy = false;
  InverterSyncResult? result;
  String? stationId;

  InverterSyncSource? get _source => widget.source ?? defaultInverterSync();

  @override
  void dispose() {
    user.dispose();
    pass.dispose();
    address.dispose();
    super.dispose();
  }

  void _setMode(InverterConnectMode m) {
    setState(() {
      mode = m;
      result = null;
      stationId = null;
    });
  }

  Future<void> _sync({String? station}) async {
    final src = _source;
    if (src == null) {
      setState(() => result = InverterSyncResult.failed('The sync server is not set up in this build.'));
      return;
    }
    final needsAddress = mode != InverterConnectMode.cloudPortal;
    if (needsAddress && address.text.trim().isEmpty) {
      setState(() => result = InverterSyncResult.failed(mode == InverterConnectMode.localLogger
          ? 'Enter the logger address, for example 192.168.1.50.'
          : 'Enter the HTTPS bridge URL.'));
      return;
    }
    if (mode == InverterConnectMode.cloudPortal && (user.text.trim().isEmpty || pass.text.isEmpty)) {
      setState(() => result = InverterSyncResult.failed('Enter your portal username and password.'));
      return;
    }

    setState(() {
      busy = true;
      result = null;
    });

    final InverterSyncResult r;
    switch (mode) {
      case InverterConnectMode.cloudPortal:
        r = await src.sync(
          brand: brand,
          username: user.text.trim(),
          password: pass.text,
          stationId: station ?? stationId,
        );
        break;
      case InverterConnectMode.localLogger:
        r = await src.syncLocalLogger(
          brand: brand,
          loggerAddress: address.text,
          username: user.text,
          password: pass.text,
        );
        break;
      case InverterConnectMode.bridge:
        r = await src.syncBridge(
          brand: brand,
          bridgeUrl: address.text,
          username: user.text,
          password: pass.text,
        );
        break;
    }

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
          Expanded(child: Text('Live from inverter or data logger', style: title)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Read today\'s generation from your inverter. Logins are used once and not saved.',
          style: TextStyle(color: C.mute, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<InverterConnectMode>(
          initialValue: mode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'How to connect', isDense: true),
          items: [for (final m in InverterConnectMode.values) DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis))],
          onChanged: busy ? null : (v) => _setMode(v ?? mode),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: brand,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Inverter brand', isDense: true),
          items: [for (final b in kInverterBrands) DropdownMenuItem(value: b.id, child: Text(b.label, overflow: TextOverflow.ellipsis))],
          onChanged: busy ? null : (v) => setState(() => brand = v ?? brand),
        ),
        const SizedBox(height: 10),
        if (mode == InverterConnectMode.localLogger)
          TextField(
            controller: address,
            enabled: !busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Logger address on home Wi-Fi',
              hintText: '192.168.1.50',
              helperText: 'Find it in your router\'s device list, or use 10.10.100.254 in access-point mode.',
              isDense: true,
            ),
          ),
        if (mode == InverterConnectMode.bridge)
          TextField(
            controller: address,
            enabled: !busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'HTTPS bridge URL',
              hintText: 'https://solar.yourdomain.com/status.html',
              helperText: 'Must be https and reachable from the internet. Local IPs will not work here.',
              isDense: true,
            ),
          ),
        if (mode != InverterConnectMode.cloudPortal) const SizedBox(height: 10),
        TextField(
          controller: user,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: mode == InverterConnectMode.cloudPortal ? 'Portal username or email' : 'Login (optional)',
            helperText: mode == InverterConnectMode.localLogger ? 'Solis sticks often use admin / admin.' : null,
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: pass,
          enabled: !busy,
          obscureText: true,
          decoration: InputDecoration(
            labelText: mode == InverterConnectMode.cloudPortal ? 'Portal password' : 'Password (optional)',
            isDense: true,
          ),
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
        Text('This account has ${r.plants.length} plants. Pick one:', style: const TextStyle(fontWeight: FontWeight.w700)),
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
      if (r.statusNote != null && r.statusNote!.isNotEmpty) Text(r.statusNote!, style: TextStyle(color: C.mute, fontSize: 12)),
    ]);
  }
}
