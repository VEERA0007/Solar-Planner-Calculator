import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/i18n.dart';
import '../core/store.dart';
import '../core/update.dart';
import 'theme.dart';
import 'widgets.dart';

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

  String _trim(double v) {
    final t = v.toStringAsFixed(2);
    return t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Widget _drop<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged, Key? key}) =>
      DropdownButtonFormField<T>(
        key: key,
        initialValue: value,
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: C.mute),
        decoration: plainField(),
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: C.text, fontWeight: FontWeight.w700, fontSize: 15.5),
        items: items,
        onChanged: onChanged,
      );

  Widget _toggleCard(IconData icon, Color ic, String title, String sub, bool v, ValueChanged<bool> on) => SectionCard(
        child: Row(children: [
          Icon(icon, color: ic, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
          Switch(value: v, onChanged: on),
        ]),
      );

  // ------------------------------ tabs ------------------------------
  Widget _display() => ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), children: [
        SectionCard(
          icon: Icons.language,
          title: t('select_language'),
          tag: Tag(t('dropdown_menu'), C.sky, outlined: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _drop<String>(
              value: d.lang,
              items: [for (final e in kLangs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => d.lang = v ?? d.lang),
            ),
            const SizedBox(height: 8),
            Text(t('lang_help'), style: TextStyle(color: C.mute, fontSize: 12.5)),
          ]),
        ),
        _toggleCard(Icons.battery_full_outlined, C.green, t('battery_sim'), t('battery_sub'), d.battery, (v) => setState(() => d.battery = v)),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.wifi_tethering, color: C.sky, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('hourly_sync'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(t('sync_sub'), style: TextStyle(color: C.mute, fontSize: 12.5)),
                ]),
              ),
              Switch(value: d.autoSync, onChanged: (v) => setState(() => d.autoSync = v)),
            ]),
            Divider(color: C.line, height: 22),
            Row(children: [
              Icon(Icons.schedule, size: 17, color: C.mute),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.lastSync == null
                      ? '--:--'
                      : '${t('updated')}: ${s.lastSync!.hour.toString().padLeft(2, '0')}:${s.lastSync!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: C.mute, fontSize: 13, fontFamilyFallback: kMono),
                ),
              ),
              FilledButton.icon(
                onPressed: s.syncing
                    ? null
                    : () async {
                        await s.sync();
                        if (mounted) setState(() {});
                      },
                icon: const Icon(Icons.sync, size: 18),
                label: Text(t('sync_now'), style: const TextStyle(fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              ),
            ]),
          ]),
        ),
        SectionCard(
          icon: Icons.receipt_long_outlined,
          title: t('company'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: company, decoration: plainField()),
            FieldLabel(t('company_phone')),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: plainField()),
            FieldLabel('Quote note'),
            TextField(controller: note, maxLines: 2, decoration: plainField()),
          ]),
        ),
        SectionCard(
          icon: Icons.info_outline,
          title: t('about'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Version ${version.isEmpty ? '...' : version}', style: TextStyle(color: C.mute)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 8, children: [
              OutlinedButton(onPressed: checking ? null : _check, child: Text(checking ? '…' : 'Check for updates')),
              if (pending != null) FilledButton(onPressed: () => openUpdate(pending!), child: const Text('Download update')),
            ]),
            if (updateMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(updateMsg, style: TextStyle(color: C.mute, fontSize: 12.5))),
            const SizedBox(height: 10),
            Text('Sun data: NASA POWER long-term averages and Open-Meteo live weather. Place search: Open-Meteo, BigDataCloud.',
                style: TextStyle(color: C.mute, fontSize: 11)),
          ]),
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
    final stName = st.name(lang);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), children: [
      SectionCard(
        icon: Icons.location_on_outlined,
        title: t('select_state'),
        tag: Text(t('auto_synced'), style: TextStyle(color: C.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
        child: _drop<String>(
          key: ValueKey('st_${d.stateId}'),
          value: d.stateId,
          items: [for (final x in book.states) DropdownMenuItem(value: x.id, child: Text(x.name(lang)))],
          onChanged: (v) => setState(() {
            d.stateId = v ?? d.stateId;
            d.discomId = book.byId(d.stateId).discoms.first.id;
          }),
        ),
      ),
      SectionCard(
        icon: Icons.apartment,
        iconColor: C.purple,
        title: '${t('grids_in')} $stName',
        tag: Text('DISCOM', style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 12.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _drop<String>(
            key: ValueKey('dc_${d.stateId}_${d.discomId}'),
            value: d.discomId,
            items: [for (final x in st.discoms) DropdownMenuItem(value: x.id, child: Text(x.name))],
            onChanged: (v) => setState(() => d.discomId = v ?? d.discomId),
          ),
          const SizedBox(height: 8),
          Text('${t('coverage')}: ${dis.coverage}', style: TextStyle(color: C.mute, fontSize: 12.5)),
        ]),
      ),
      SectionCard(
        title: t('category'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (final c in const ['domestic', 'commercial', 'industrial']) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => d.category = c),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.category == c ? const Color(0xFF0A84D8) : C.chip,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: d.category == c ? const Color(0xFF0A84D8) : C.line),
                    ),
                    child: Text(t(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: d.category == c ? Colors.white : C.text)),
                  ),
                ),
              ),
              if (c != 'industrial') const SizedBox(width: 8),
            ]
          ]),
          const SizedBox(height: 8),
          Text('${cat.label} (${cat.slabLabel(units)})', style: TextStyle(color: C.mute, fontSize: 12.5)),
        ]),
      ),
      SectionCard(
        icon: Icons.bolt,
        iconColor: C.green,
        title: t('unit_price'),
        tint: C.green.withValues(alpha: C.dark ? .08 : .07),
        border: C.green.withValues(alpha: .55),
        tag: Tag(t('auto_synced'), C.green),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.green.withValues(alpha: .7))),
            child: Row(children: [
              Expanded(child: Text(_trim(price), style: TextStyle(fontFamilyFallback: kMono, fontSize: 19, fontWeight: FontWeight.w800, color: C.text))),
              Text(t('per_unit'), style: TextStyle(color: C.mute, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 8),
          Text('${t('approved_tariff')} $stName (${t(d.category).toUpperCase()})', style: TextStyle(color: C.green, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text('${units.round()} units/month · ${st.order} · ${st.effective}', style: TextStyle(color: C.mute, fontSize: 11)),
        ]),
      ),
      SectionCard(
        tint: C.amber.withValues(alpha: C.dark ? .08 : .08),
        border: C.amber.withValues(alpha: .35),
        child: Row(children: [
          Icon(Icons.show_chart, color: C.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('pr_title'), style: TextStyle(color: C.amber, fontWeight: FontWeight.w800, fontSize: 15)),
              Text('${t('pr_sub')} $stName', style: TextStyle(color: C.amber.withValues(alpha: .85), fontSize: 12.5)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: C.amber.withValues(alpha: .22), borderRadius: BorderRadius.circular(99)),
            child: Text('${st.pr.toStringAsFixed(1)}%', style: TextStyle(color: C.amber, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      SectionCard(
        child: Row(children: [
          Icon(Icons.trending_up, color: C.sky, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('export_credit'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(t('export_sub'), style: TextStyle(color: C.mute, fontSize: 12.5)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: C.sky.withValues(alpha: .18), borderRadius: BorderRadius.circular(99)),
            child: Text(st.exportRate == null ? t('not_applicable') : '₹${st.exportRate!.toStringAsFixed(2)} / kWh',
                style: TextStyle(color: C.sky, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
      ),
    ]);
  }

  Widget _alerts() => ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), children: [
        SectionCard(
          icon: Icons.notifications_none,
          title: t('dust_reminder'),
          child: Row(children: [
            for (final n in const [15, 30, 45, 60]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => d.dustDays = n),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: d.dustDays == n ? const Color(0xFF0A84D8) : C.chip,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: d.dustDays == n ? const Color(0xFF0A84D8) : C.line),
                    ),
                    child: Text('${n}d', style: TextStyle(fontWeight: FontWeight.w800, color: d.dustDays == n ? Colors.white : C.text)),
                  ),
                ),
              ),
              if (n != 60) const SizedBox(width: 8),
            ]
          ]),
        ),
        SectionCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('cloud_alerts'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(t('cloud_sub'), style: TextStyle(color: C.mute, fontSize: 12.5)),
              ]),
            ),
            Switch(value: d.cloudAlerts, onChanged: (v) => setState(() => d.cloudAlerts = v)),
          ]),
        ),
        Divider(color: C.line, height: 28),
        OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(t('reset_all'), style: const TextStyle(fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.red,
            side: BorderSide(color: C.red.withValues(alpha: .6)),
            backgroundColor: C.red.withValues(alpha: .06),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * .9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: C.chipBlue, shape: BoxShape.circle),
                child: Icon(Icons.settings_outlined, color: C.sky),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('app_settings'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(t('settings_sub'), style: TextStyle(color: C.mute, fontSize: 13)),
                ]),
              ),
              Material(
                color: C.chip,
                shape: const CircleBorder(),
                child: InkWell(customBorder: const CircleBorder(), onTap: () => Navigator.pop(context), child: const SizedBox(width: 42, height: 42, child: Icon(Icons.close, size: 20))),
              ),
            ]),
          ),
          Divider(color: C.line, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: PillTabs(controller: tabs, labels: [t('tab_display'), t('tab_tariffs'), t('tab_alerts')]),
          ),
          Flexible(
            child: SizedBox(
              height: h * .56,
              child: TabBarView(controller: tabs, children: [_display(), _tariffs(), _alerts()]),
            ),
          ),
          DialogFooter(cancel: t('cancel'), save: t('save_settings'), onCancel: () => Navigator.pop(context), onSave: _save),
        ]),
      ),
    );
  }
}
