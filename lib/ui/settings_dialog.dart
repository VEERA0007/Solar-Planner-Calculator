import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/i18n.dart';
import '../core/store.dart';
import '../core/update.dart';
import 'theme.dart';

Future<void> showSettingsDialog(BuildContext context, AppState s) =>
    showDialog<void>(context: context, builder: (_) => _SettingsDialog(state: s));

class _SettingsDialog extends StatefulWidget {
  final AppState state;
  const _SettingsDialog({required this.state});
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this);
  late Prefs d; // draft
  late final TextEditingController company, phone, note;
  String version = '', updateMsg = '';
  UpdateInfo? pending;
  bool checking = false;

  AppState get s => widget.state;
  String t(String k) => tr(d.lang, k);

  @override
  void initState() {
    super.initState();
    d = Prefs.fromJson(s.prefs.toJson());
    company = TextEditingController(text: s.brand.company);
    phone = TextEditingController(text: s.brand.phone);
    note = TextEditingController(text: s.brand.note);
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => version = '${i.version} (build ${i.buildNumber})');
    }).catchError((_) {});
  }

  @override
  void dispose() {
    tabs.dispose();
    company.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  void _save() {
    s.prefs
      ..lang = d.lang
      ..stateId = d.stateId
      ..discomId = d.discomId
      ..category = d.category
      ..battery = d.battery
      ..autoSync = d.autoSync
      ..cloudAlerts = d.cloudAlerts
      ..dustDays = d.dustDays;
    s.brand
      ..company = company.text.trim()
      ..phone = phone.text.trim()
      ..note = note.text.trim();
    s.savePrefs();
    s.saveBrand();
    Navigator.pop(context);
    toast(context, tr(d.lang, 'saved'));
  }

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

  Widget _label(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(color: C.mute, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: .3))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _switchRow(String title, String sub, bool v, ValueChanged<bool> on, {IconData? icon}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: C.blue), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(color: C.mute, fontSize: 12)),
            ]),
          ),
          Switch(value: v, onChanged: on),
        ]),
      );

  // ------------------------------ tabs ------------------------------
  Widget _display() => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        _label(t('language')),
        DropdownButtonFormField<String>(
          initialValue: d.lang,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.language)),
          items: [for (final e in kLangs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => d.lang = v ?? d.lang),
        ),
        _switchRow(t('battery_sim'), t('battery_sub'), d.battery, (v) => setState(() => d.battery = v), icon: Icons.battery_charging_full),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
          child: Column(children: [
            Row(children: [
              Icon(Icons.wifi_tethering, color: C.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('hourly_sync'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    s.lastSync == null
                        ? '--:--'
                        : '${t('updated')}: ${s.lastSync!.hour.toString().padLeft(2, '0')}:${s.lastSync!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: C.mute, fontSize: 12, fontFamilyFallback: kMono),
                  ),
                ]),
              ),
              Switch(value: d.autoSync, onChanged: (v) => setState(() => d.autoSync = v)),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: s.syncing
                    ? null
                    : () async {
                        await s.sync();
                        if (mounted) setState(() {});
                      },
                icon: const Icon(Icons.sync, size: 18),
                label: Text(t('sync_now')),
              ),
            ),
          ]),
        ),
        _label(t('company')),
        TextField(controller: company, decoration: const InputDecoration()),
        _label(t('company_phone')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration()),
        _label('Quote note'),
        TextField(controller: note, maxLines: 2, decoration: const InputDecoration()),
        _label(t('about')),
        Text('Version ${version.isEmpty ? '...' : version}', style: TextStyle(color: C.mute)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton(onPressed: checking ? null : _check, child: Text(checking ? '…' : 'Check for updates')),
          if (pending != null) FilledButton(onPressed: () => openUpdate(pending!), child: const Text('Download update')),
        ]),
        if (updateMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(updateMsg, style: TextStyle(color: C.mute, fontSize: 12.5))),
        const SizedBox(height: 14),
        Text(
          'Sun data: NASA POWER long-term averages and Open-Meteo live weather. Place search: Open-Meteo, BigDataCloud.',
          style: TextStyle(color: C.mute, fontSize: 11),
        ),
      ]);

  Widget _tariffs() {
    final book = s.book!;
    final st = book.byId(d.stateId);
    if (!st.discoms.any((x) => x.id == d.discomId)) d.discomId = st.discoms.first.id;
    final dis = st.discoms.firstWhere((x) => x.id == d.discomId);
    final cat = st.cat(d.category);
    final units = s.monthlyUnits;
    final price = cat.marginal(units);
    final lang = d.lang;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      _label(t('state'), trailing: _pill(t('auto_synced'), C.green)),
      DropdownButtonFormField<String>(
        key: ValueKey('st_${d.stateId}'),
        initialValue: d.stateId,
        isExpanded: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.map_outlined)),
        items: [for (final x in book.states) DropdownMenuItem(value: x.id, child: Text(x.name(lang)))],
        onChanged: (v) => setState(() {
          d.stateId = v ?? d.stateId;
          d.discomId = book.byId(d.stateId).discoms.first.id;
        }),
      ),
      _label('${t('grids_in')} ${st.name(lang)}'),
      DropdownButtonFormField<String>(
        key: ValueKey('dc_${d.stateId}_${d.discomId}'),
        initialValue: d.discomId,
        isExpanded: true,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.bolt)),
        items: [for (final x in st.discoms) DropdownMenuItem(value: x.id, child: Text(x.name))],
        onChanged: (v) => setState(() => d.discomId = v ?? d.discomId),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(dis.coverage, style: TextStyle(color: C.mute, fontSize: 12)),
      ),
      _label(t('category')),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'domestic', label: Text(t('domestic'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ButtonSegment(value: 'commercial', label: Text(t('commercial'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ButtonSegment(value: 'industrial', label: Text(t('industrial'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        selected: {d.category},
        onSelectionChanged: (v) => setState(() => d.category = v.first),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text('${cat.label} (${cat.slabLabel(units)})', style: TextStyle(color: C.mute, fontSize: 12)),
      ),
      _label(t('unit_price')),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Row(children: [
          Icon(Icons.lock_outline, size: 18, color: C.mute),
          const SizedBox(width: 10),
          Expanded(child: Text('₹ ${price.toStringAsFixed(2)}', style: TextStyle(fontFamilyFallback: kMono, fontSize: 20, fontWeight: FontWeight.w700, color: C.amber))),
          _pill(t('auto_synced'), C.green),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          '${units.round()} units/month · avg ₹${cat.average(units).toStringAsFixed(2)}/unit\n${st.order} · ${st.effective}',
          style: TextStyle(color: C.mute, fontSize: 11.5),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _chip(Icons.wb_sunny_outlined, '${t('solar_pr')} ${st.pr.toStringAsFixed(1)}%', C.sun),
        _chip(Icons.swap_horiz, '${t('export_credit')} ${st.exportRate == null ? t('not_applicable') : '₹${st.exportRate!.toStringAsFixed(2)}/kWh'}', C.green),
      ]),
    ]);
  }

  Widget _chip(IconData i, String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: c),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5))),
        ]),
      );

  Widget _alerts() => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        _label(t('dust_reminder')),
        Wrap(spacing: 10, children: [
          for (final n in const [15, 30, 45, 60])
            ChoiceChip(
              label: Text('${n}d'),
              selected: d.dustDays == n,
              onSelected: (_) => setState(() => d.dustDays = n),
            ),
        ]),
        _switchRow(t('cloud_alerts'), t('cloud_sub'), d.cloudAlerts, (v) => setState(() => d.cloudAlerts = v), icon: Icons.cloud_outlined),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(t('reset_all')),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
        ),
      ]);

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('reset_all')),
        content: Text(t('reset_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await s.resetAll();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * .88),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(children: [
              Icon(Icons.settings_outlined, color: C.blue),
              const SizedBox(width: 10),
              Expanded(child: Text(t('settings'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          TabBar(
            controller: tabs,
            dividerColor: C.line,
            labelColor: C.blue,
            unselectedLabelColor: C.mute,
            indicatorColor: C.blue,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: t('tab_display')),
              Tab(text: t('tab_tariffs')),
              Tab(text: t('tab_alerts')),
            ],
          ),
          Flexible(
            child: SizedBox(
              height: h * .6,
              child: TabBarView(controller: tabs, children: [_display(), _tariffs(), _alerts()]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel')))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _save, child: Text(t('save_settings')))),
            ]),
          ),
        ]),
      ),
    );
  }
}
