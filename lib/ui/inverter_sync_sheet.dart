import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/backend_service.dart';
import '../core/calc.dart';
import '../core/inverter_history.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

/// 2-Option Inverter Integration Dialog:
/// 1. Manufacturer Website Login (enter portal credentials)
/// 2. API Integration (API Key/Secret or custom HTTPS JSON endpoint)
Future<void> showInverterSyncDialog(BuildContext context, AppState s) =>
    showDialog<void>(context: context, builder: (_) => _InverterSyncDialog(state: s));

class _InverterSyncDialog extends StatefulWidget {
  final AppState state;
  const _InverterSyncDialog({required this.state});
  @override
  State<_InverterSyncDialog> createState() => _InverterSyncDialogState();
}

class _InverterSyncDialogState extends State<_InverterSyncDialog> {
  late String authMode; // 'website' | 'api'
  late String brand;
  late final TextEditingController username, password, apiKey, apiSecret, stationId, loggerSn, customUrl;
  bool obscure = true;
  bool busy = false;
  String statusMsg = '';
  bool statusError = false;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final c = s.inverterCfg;
    authMode = c.authMode == 'api' ? 'api' : 'website';
    brand = kInverterBrands.any((b) => b.$1 == c.brand) ? c.brand : kInverterBrands.first.$1;
    username = TextEditingController(text: c.username);
    password = TextEditingController();
    apiKey = TextEditingController(text: c.apiKey);
    apiSecret = TextEditingController();
    stationId = TextEditingController(text: c.stationId);
    loggerSn = TextEditingController(text: c.loggerSerial);
    customUrl = TextEditingController(text: c.customEndpoint);
  }

  @override
  void dispose() {
    for (final c in [username, password, apiKey, apiSecret, stationId, loggerSn, customUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  (String id, String label, String portalUrl) get _brandMeta =>
      kInverterBrands.firstWhere((b) => b.$1 == brand, orElse: () => kInverterBrands.first);

  InverterConfig _readConfig() => InverterConfig(
        authMode: authMode,
        brand: brand,
        username: username.text.trim(),
        apiKey: apiKey.text.trim(),
        stationId: stationId.text.trim(),
        loggerSerial: loggerSn.text.trim(),
        customEndpoint: customUrl.text.trim(),
      );

  Future<void> _syncNow() async {
    final cfg = _readConfig();
    if (authMode == 'website' && (cfg.username.isEmpty || password.text.isEmpty)) {
      setState(() {
        statusError = true;
        statusMsg = 'Enter your manufacturer website email/username and password.';
      });
      return;
    }
    if (authMode == 'api' && cfg.customEndpoint.isEmpty && (cfg.apiKey.isEmpty || apiSecret.text.isEmpty)) {
      setState(() {
        statusError = true;
        statusMsg = 'Enter API Key & Secret, or provide a Custom HTTPS JSON API URL.';
      });
      return;
    }

    setState(() {
      busy = true;
      statusMsg = 'Connecting to ${_brandMeta.$2}...';
      statusError = false;
    });

    s.inverterCfg = cfg;
    final res = await BackendService.syncInverter(
      rawBaseUrl: s.prefs.backendUrl,
      config: cfg,
      password: password.text,
      apiSecret: apiSecret.text,
    );

    if (!mounted) return;
    final loggedOk = res.ok && res.snapshot != null;
    s.addInverterLogin(InverterLoginItem(
      at: DateTime.now(),
      brand: _brandMeta.$2,
      authMode: authMode,
      account: authMode == 'website'
          ? cfg.username
          : (cfg.customEndpoint.isNotEmpty ? 'Custom API' : InverterLoginItem.maskKey(cfg.apiKey)),
      ok: loggedOk,
      message: loggedOk
          ? 'Synced ${res.snapshot!.plantName.isEmpty ? _brandMeta.$2 : res.snapshot!.plantName}'
          : (res.error ?? 'Could not sync inverter data.'),
    ));
    if (res.ok && res.snapshot != null) {
      s.inverterSnap = res.snapshot;
      if (res.snapshot!.ratedKw > 0) {
        s.site.kwp = res.snapshot!.ratedKw;
        s.saveSite();
      }
      s.saveInverter();
      setState(() {
        busy = false;
        statusError = false;
        statusMsg = 'Synced ${res.snapshot!.plantName.isEmpty ? _brandMeta.$2 : res.snapshot!.plantName} · '
            '${res.snapshot!.currentKw.toStringAsFixed(2)} kW live · ${fmt1(res.snapshot!.todayKwh)} kWh today.';
      });
    } else {
      s.saveInverter();
      setState(() {
        busy = false;
        statusError = true;
        statusMsg = res.error ?? 'Could not sync inverter data.';
      });
    }
  }

  Widget _modeChip(String id, IconData icon, String title, String sub) {
    final on = authMode == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          authMode = id;
          statusMsg = '';
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: on ? C.orange : C.card2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? C.orange : C.line),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: on ? Colors.white : C.sky),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: on ? Colors.white : C.text)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(sub, maxLines: 1, style: TextStyle(fontSize: 11, color: on ? Colors.white.withValues(alpha: .9) : C.mute)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final snap = s.inverterSnap;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * .9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.chipSun, shape: BoxShape.circle),
                child: Icon(Icons.electric_bolt, color: C.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Inverter Live Sync', style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800)),
                  Text('Manufacturer Website Login or API Integration', style: TextStyle(color: C.mute, fontSize: 12.5)),
                ]),
              ),
              Material(
                color: C.chip,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(width: 40, height: 40, child: Icon(Icons.close, size: 20)),
                ),
              ),
            ]),
          ),
          Divider(color: C.line, height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: [
                Row(children: [
                  _modeChip('website', Icons.login, 'Manufacturer Login', 'Portal credentials'),
                  const SizedBox(width: 10),
                  _modeChip('api', Icons.api, 'API Integration', 'Key / JSON endpoint'),
                ]),
                const SizedBox(height: 14),
                SectionCard(
                  icon: Icons.solar_power_outlined,
                  title: 'Inverter Manufacturer',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('inv_brand_$brand'),
                      initialValue: brand,
                      isExpanded: true,
                      decoration: plainField(),
                      items: [for (final b in kInverterBrands) DropdownMenuItem(value: b.$1, child: Text(b.$2))],
                      onChanged: (v) => setState(() => brand = v ?? brand),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(_brandMeta.$3), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text('Open ${_brandMeta.$2} Website'),
                      ),
                    ),
                  ]),
                ),
                if (authMode == 'website')
                  SectionCard(
                    icon: Icons.lock_outline,
                    title: 'Manufacturer Website Credentials',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const FieldLabel('Email / Username'),
                      TextField(controller: username, keyboardType: TextInputType.emailAddress, decoration: plainField()),
                      const FieldLabel('Password (not saved permanently)'),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        decoration: plainField(
                          suffix: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19),
                          ),
                        ),
                      ),
                      const FieldLabel('Plant / Station ID (Optional)'),
                      TextField(controller: stationId, decoration: plainField()),
                      const FieldLabel('Data Logger Serial No. (Optional)'),
                      TextField(controller: loggerSn, decoration: plainField()),
                    ]),
                  )
                else
                  SectionCard(
                    icon: Icons.vpn_key_outlined,
                    title: 'API Integration Credentials',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const FieldLabel('API Key / Key ID / Bearer Token'),
                      TextField(controller: apiKey, decoration: plainField()),
                      const FieldLabel('API Key Secret (for signed manufacturer APIs)'),
                      TextField(
                        controller: apiSecret,
                        obscureText: obscure,
                        decoration: plainField(
                          suffix: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19),
                          ),
                        ),
                      ),
                      const FieldLabel('Station / Plant ID (Optional)'),
                      TextField(controller: stationId, decoration: plainField()),
                      const FieldLabel('Custom HTTPS JSON API Endpoint (Optional)'),
                      TextField(controller: customUrl, keyboardType: TextInputType.url, decoration: plainField()),
                    ]),
                  ),
                if (statusMsg.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (statusError ? C.red : C.green).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: (statusError ? C.red : C.green).withValues(alpha: .45)),
                    ),
                    child: Text(statusMsg, style: TextStyle(color: statusError ? C.red : C.green, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                if (snap != null)
                  SectionCard(
                    icon: Icons.insights,
                    iconColor: C.green,
                    title: snap.plantName.isEmpty ? 'Latest Synced Telemetry' : snap.plantName,
                    tag: Tag(snap.isLoggerOnline ? 'Logger Online' : 'Logger ${snap.loggerStatus}', snap.isLoggerOnline ? C.green : C.amber),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: _kpi('Live Power', '${snap.currentKw.toStringAsFixed(2)} kW', C.orange)),
                        const SizedBox(width: 8),
                        Expanded(child: _kpi('Today', '${fmt1(snap.todayKwh)} kWh', C.green)),
                        const SizedBox(width: 8),
                        Expanded(child: _kpi('Total', '${groupIndian(snap.totalKwh)} kWh', C.sky)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Plant: ${snap.plantStatus.toUpperCase()} · Month: ${fmt1(snap.monthKwh)} kWh'
                        '${snap.gridVoltageV != null ? ' · Grid ${snap.gridVoltageV!.round()}V' : ''}'
                        '${snap.batterySocPct != null ? ' · Battery ${snap.batterySocPct!.round()}%' : ''}',
                        style: TextStyle(color: C.mute, fontSize: 12),
                      ),
                      if (snap.dailyLogs.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('Recent Daily Generation (kWh)', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 11.5)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 110,
                          child: BarChart(
                            series: [BarSeries('kWh', snap.dailyLogs.take(10).map((e) => e.kwh).toList(), C.green)],
                            labels: [for (final d in snap.dailyLogs.take(10)) d.date.length >= 5 ? d.date.substring(d.date.length - 2) : d.date],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            s.clearInverter();
                            setState(() => statusMsg = 'Disconnected synced telemetry.');
                          },
                          child: Text('Clear synced data', style: TextStyle(color: C.red)),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          Divider(color: C.line, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              Expanded(
                flex: 4,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    backgroundColor: C.chip,
                    foregroundColor: C.text,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: FilledButton.icon(
                  onPressed: busy ? null : _syncNow,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Icon(Icons.sync, size: 20),
                  label: Text(busy ? 'Syncing...' : 'Login & Sync Now', style: const TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: C.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _kpi(String label, String val, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: C.mute, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(val, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
      );
}
