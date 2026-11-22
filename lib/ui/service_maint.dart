import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/service_data.dart';
import '../core/store.dart';
import 'profile_dialog.dart' show fmtDate;
import 'service_page.dart' show CapsLabel;
import 'theme.dart';
import 'widgets.dart';

const _soilLabels = {
  'clean': 'Clean / Light Dust',
  'light': 'Light Dust',
  'moderate': 'Moderate Dirt',
  'heavy': 'Heavy Soiling',
};
const _statusLabels = {
  'healthy': 'Healthy / Normal',
  'attention': 'Needs Attention',
  'fault': 'Fault Found',
};
const _typeLabels = {
  ServiceType.cleaning: 'Panel Cleaning',
  ServiceType.inverter: 'Inverter Inspection',
  ServiceType.electrical: 'Electrical / Earthing Check',
  ServiceType.general: 'General Maintenance',
};

String _levelLabel(ServiceEntry e) =>
    e.type == ServiceType.cleaning ? 'Soiling: ${_soilLabels[e.soiling] ?? 'Moderate Dirt'}' : 'Status: ${_statusLabels[e.soiling] ?? 'Healthy / Normal'}';

Color _typeColor(ServiceType t) => switch (t) {
      ServiceType.cleaning => C.sky,
      ServiceType.inverter => C.green,
      ServiceType.electrical => C.amber,
      ServiceType.general => C.purple,
    };

class MaintenanceTab extends StatefulWidget {
  final AppState state;
  const MaintenanceTab({super.key, required this.state});
  @override
  State<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<MaintenanceTab> {
  ServiceType? filter;
  AppState get s => widget.state;

  Future<void> _call(String number) async {
    final u = Uri.parse('tel:${number.replaceAll(RegExp(r'[^0-9+]'), '')}');
    if (await canLaunchUrl(u)) await launchUrl(u);
  }

  @override
  Widget build(BuildContext context) {
    final p = s.profile;
    final all = s.services;
    final shown = filter == null ? all : all.where((e) => e.type == filter).toList();
    final comm = p.commissionDate;
    final ends = p.warrantyEnds;
    final yearsLeft = ends == null ? null : (ends.difference(DateTime.now()).inDays / 365).floor().clamp(0, p.warranty);
    final city = s.site.city;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [
      // ---------------- customer & plant card
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: C.chipBlue, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.person_outline, color: C.blue, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name.isEmpty ? 'Add customer name' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Text(
                  [if (comm != null) 'Commissioned ${isoDate(comm)}', if (city.isNotEmpty) city].join(' · ').ifEmpty('Commissioning date not set'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.mute, fontSize: 13),
                ),
              ]),
            ),
            TextButton.icon(
              onPressed: () => showPlantProfileDialog(context, s),
              icon: Icon(Icons.edit_outlined, size: 18, color: C.blue),
              label: Text('Edit Profile', style: TextStyle(color: C.blue, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _MiniCard(
                title: 'Installed Plant Capacity',
                value: Text('${s.site.kwp.toStringAsFixed(2)} kWp', style: TextStyle(fontFamilyFallback: kMono, fontSize: 21, fontWeight: FontWeight.w700, color: C.text)),
                caption: p.panel.isEmpty ? 'Panel make not set' : p.panel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniCard(
                title: 'Inverter & Warranty',
                value: Text(p.inverter.isEmpty ? 'Inverter not set' : p.inverter, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                caption: yearsLeft == null ? '${p.warranty} yrs warranty' : '$yearsLeft of ${p.warranty} yrs remaining',
                captionColor: C.green,
              ),
            ),
          ])),
          const SizedBox(height: 12),
          Divider(color: C.line, height: 1),
          InkWell(
            onTap: p.helpline.isEmpty ? null : () => _call(p.helpline),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(Icons.phone_outlined, color: C.blue, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text('Installer / O&M Helpline', style: TextStyle(color: C.mute, fontSize: 14))),
                Text(p.helpline.isEmpty ? '–' : p.helpline, style: TextStyle(fontFamilyFallback: kMono, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _cleaningCard(context),
      const SizedBox(height: 18),
      // ---------------- history
      Row(children: [
        Expanded(child: CapsLabel('Service & Inspection History (${all.length})', color: C.text)),
        TextButton(
          onPressed: () => showServiceDialog(context, s, preset: ServiceType.general),
          child: Text('+ Log Service', style: TextStyle(color: C.blue, fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          for (final f in <(String, ServiceType?)>[
            ('All (${all.length})', null),
            ('Cleaning', ServiceType.cleaning),
            ('Inverter', ServiceType.inverter),
            ('Electrical', ServiceType.electrical),
          ])
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => filter = f.$2),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(color: filter == f.$2 ? C.card : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(f.$1, style: TextStyle(fontWeight: FontWeight.w700, color: filter == f.$2 ? C.text : C.mute))),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        Panel(
          child: Column(children: [
            Icon(Icons.build_circle_outlined, size: 40, color: C.mute),
            const SizedBox(height: 8),
            Text(all.isEmpty ? 'No service records yet' : 'No records in this category', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Tap “+ Log Service” or “+ Log Wash” to add the first one.', textAlign: TextAlign.center, style: TextStyle(color: C.mute)),
          ]),
        ),
      for (final e in shown) ...[
        _entryCard(context, e),
        const SizedBox(height: 12),
      ],
    ]);
  }

  // ------------------------------------------------------------ cleaning card
  Widget _cleaningCard(BuildContext context) {
    final now = DateTime.now();
    final cleans = s.services.where((e) => e.type == ServiceType.cleaning).toList();
    final last = cleans.isEmpty ? (s.lastCleaned ?? s.profile.commissionDate) : cleans.first.date;
    final daysSince = last == null ? null : now.difference(last).inDays;
    DateTime? due = cleans.isNotEmpty ? cleans.first.nextDue : null;
    if (due == null && last != null) due = last.add(Duration(days: s.prefs.dustDays));
    final dueIn = due == null ? null : DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final loss = daysSince == null ? null : soilingLossPct(daysSince);
    final w = s.weather;
    final good = w != null && w.cloud < 60 && !w.rain;
    String headline;
    if (dueIn == null) {
      headline = 'Log your first wash';
    } else if (dueIn > 0) {
      headline = 'Next Cleaning in $dueIn Days';
    } else if (dueIn == 0) {
      headline = 'Cleaning due today';
    } else {
      headline = 'Cleaning overdue by ${-dueIn} Days';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B3A7A), Color(0xFF14296B), Color(0xFF0B1235)]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule, color: Color(0xFFFFC53D), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Panel Cleaning & Soiling Monitor', style: const TextStyle(color: Color(0xFFFFC53D), fontWeight: FontWeight.w800, fontSize: 15))),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: TextStyle(color: dueIn != null && dueIn < 0 ? const Color(0xFFFF8A8A) : Colors.white, fontSize: 23, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 8),
              if (daysSince != null)
                Text.rich(
                  TextSpan(style: const TextStyle(color: Color(0xFFC9D6F2), fontSize: 14.5, height: 1.45), children: [
                    TextSpan(text: '$daysSince days since last wash · Estimated soiling loss '),
                    TextSpan(text: '~${loss!.toStringAsFixed(1)}%', style: const TextStyle(color: Color(0xFFFFC53D), fontWeight: FontWeight.w800, fontFamilyFallback: kMono)),
                    TextSpan(text: '.${due == null ? '' : ' Scheduled due date: ${isoDate(due)}'}'),
                  ]),
                )
              else
                const Text('No wash recorded yet. Add the commissioning date or log a wash to start tracking dust loss.', style: TextStyle(color: Color(0xFFC9D6F2), fontSize: 14.5, height: 1.45)),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => showServiceDialog(context, s, preset: ServiceType.cleaning),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF9F0A),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('+ Log Wash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: .18), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.wb_cloudy_outlined, color: Color(0xFFFFC53D), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              w == null
                  ? 'Weather unavailable. Sync to see the cleaning window.'
                  : good
                      ? 'Good weather window for soft-water microfiber panel cleaning'
                      : (w.rain ? 'Rain now: wait for a dry spell before cleaning' : 'Cloudy: a clear, cool morning is better for cleaning'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFE2EAFB), fontSize: 14),
            ),
          ),
          if (w != null) Text('${w.tempC.round()}°C', style: const TextStyle(color: Color(0xFFE2EAFB), fontFamilyFallback: kMono, fontSize: 15)),
        ]),
      ]),
    );
  }

  // --------------------------------------------------------------- entry card
  Widget _entryCard(BuildContext context, ServiceEntry e) {
    final col = _typeColor(e.type);
    final sub = [isoDate(e.date), if (e.technician.isNotEmpty) 'By ${e.technician}'];
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: col.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.build_outlined, color: col)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title.isEmpty ? _typeLabels[e.type]! : e.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25)),
              const SizedBox(height: 3),
              Text(sub.join(' · '), style: TextStyle(color: C.mute, fontSize: 13)),
            ]),
          ),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => showServiceDialog(context, s, edit: e), icon: Icon(Icons.edit_outlined, color: C.mute, size: 22)),
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _confirmDelete(context, e), icon: Icon(Icons.delete_outline, color: C.mute, size: 22)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_levelLabel(e), style: TextStyle(fontWeight: FontWeight.w700, color: e.type == ServiceType.cleaning ? C.mute : C.blue)),
          if (e.type == ServiceType.cleaning && e.yieldGain > 0) Text('· +${e.yieldGain.toStringAsFixed(1)}% Yield Restored', style: TextStyle(color: C.green, fontWeight: FontWeight.w800)),
          if (e.cost > 0) Text('· ₹${e.cost.round()}', style: TextStyle(color: C.mute, fontFamilyFallback: kMono)),
        ]),
        if (e.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14)),
            child: Text(e.notes, style: const TextStyle(height: 1.45, fontSize: 14.5)),
          ),
        ],
        if (e.nextDue != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 17, color: C.blue),
            const SizedBox(width: 8),
            Text('Next Due Date: ', style: TextStyle(color: C.mute, fontSize: 13.5)),
            Text(isoDate(e.nextDue!), style: TextStyle(color: C.mute, fontWeight: FontWeight.w800, fontSize: 13.5)),
          ]),
        ],
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ServiceEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(e.title.isEmpty ? _typeLabels[e.type]! : e.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Delete', style: TextStyle(color: C.red))),
        ],
      ),
    );
    if (ok == true) {
      s.services.removeWhere((x) => x.id == e.id);
      s.saveServices();
    }
  }
}

extension _Str on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _MiniCard extends StatelessWidget {
  final String title, caption;
  final Widget value;
  final Color? captionColor;
  const _MiniCard({required this.title, required this.value, required this.caption, this.captionColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.mute, fontSize: 13)),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value)),
          const SizedBox(height: 4),
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: captionColor ?? C.mute, fontSize: 13)),
        ]),
      );
}

// ============================================================ dialogs

InputDecoration _dec({Widget? suffix}) => plainField(suffix: suffix);

Widget _dialogShell(BuildContext context, String title, Widget body, Widget footer) => Dialog(
      backgroundColor: C.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 10, 6),
            child: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: C.mute)),
            ]),
          ),
          Divider(color: C.line, height: 1),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 4, 22, 14), child: body)),
          footer,
        ]),
      ),
    );

Widget _footer(BuildContext context, String save, VoidCallback onSave) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: C.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), foregroundColor: C.text),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: const Color(0xFF0A84D8), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            child: Text(save, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );

TextStyle _fieldStyle(BuildContext context) => Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600);

Future<DateTime?> _pick(BuildContext context, DateTime cur, {DateTime? first, DateTime? last}) => showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: first ?? DateTime(2000),
      lastDate: last ?? DateTime(2100),
    );

// ---------------------------------------------------- Customer & Plant Profile

Future<void> showPlantProfileDialog(BuildContext context, AppState s) =>
    showDialog(context: context, builder: (_) => _PlantProfileDialog(state: s));

class _PlantProfileDialog extends StatefulWidget {
  final AppState state;
  const _PlantProfileDialog({required this.state});
  @override
  State<_PlantProfileDialog> createState() => _PlantProfileDialogState();
}

class _PlantProfileDialogState extends State<_PlantProfileDialog> {
  late final name = TextEditingController(text: s.profile.name);
  late final kwp = TextEditingController(text: s.site.kwp == s.site.kwp.roundToDouble() ? s.site.kwp.round().toString() : s.site.kwp.toString());
  late final inv = TextEditingController(text: s.profile.inverter);
  late final panel = TextEditingController(text: s.profile.panel);
  late final help = TextEditingController(text: s.profile.helpline);
  late DateTime? date = s.profile.commissionDate;
  AppState get s => widget.state;

  @override
  void dispose() {
    for (final c in [name, kwp, inv, panel, help]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final k = double.tryParse(kwp.text.trim());
    s.profile
      ..name = name.text.trim()
      ..inverter = inv.text.trim()
      ..panel = panel.text.trim()
      ..helpline = help.text.trim()
      ..commission = date == null ? '' : fmtDate(date!);
    if (k != null && k > 0) s.site.kwp = k;
    s.saveProfile();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final st = _fieldStyle(context);
    return _dialogShell(
      context,
      'Customer & Plant Profile',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FieldLabel('Customer Name'),
        TextField(controller: name, style: st, decoration: _dec()),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Commissioning Date'),
              TextField(
                readOnly: true,
                controller: TextEditingController(text: date == null ? '' : fmtDate(date!)),
                style: st,
                decoration: _dec(suffix: Icon(Icons.keyboard_arrow_down, color: C.mute)),
                onTap: () async {
                  final d = await _pick(context, date ?? DateTime.now(), last: DateTime.now());
                  if (d != null) setState(() => date = d);
                },
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Capacity (kWp)'),
              TextField(controller: kwp, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: st, decoration: _dec()),
            ]),
          ),
        ]),
        const FieldLabel('Inverter Model'),
        TextField(controller: inv, style: st, decoration: _dec()),
        const FieldLabel('Panel Make & Model'),
        TextField(controller: panel, style: st, decoration: _dec()),
        const FieldLabel('Installer Helpline / Contact'),
        TextField(controller: help, keyboardType: TextInputType.phone, style: st, decoration: _dec()),
        const SizedBox(height: 8),
      ]),
      _footer(context, 'Update Profile', _save),
    );
  }
}

// ---------------------------------------------------------- Log Maintenance

Future<void> showServiceDialog(BuildContext context, AppState s, {ServiceEntry? edit, ServiceType? preset}) =>
    showDialog(context: context, builder: (_) => _ServiceDialog(state: s, edit: edit, preset: preset ?? ServiceType.cleaning));

class _ServiceDialog extends StatefulWidget {
  final AppState state;
  final ServiceEntry? edit;
  final ServiceType preset;
  const _ServiceDialog({required this.state, this.edit, required this.preset});
  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late ServiceType type = widget.edit?.type ?? widget.preset;
  late DateTime date = widget.edit?.date ?? DateTime.now();
  late DateTime? nextDue = widget.edit == null ? _defaultDue(widget.preset, DateTime.now()) : widget.edit!.nextDue;
  late String level = widget.edit?.soiling ?? (type == ServiceType.cleaning ? 'moderate' : 'healthy');
  late final title = TextEditingController(text: widget.edit?.title ?? _defaultTitle(type));
  late final gain = TextEditingController(text: widget.edit == null ? '' : widget.edit!.yieldGain.toString());
  late final tech = TextEditingController(text: widget.edit?.technician ?? '');
  late final cost = TextEditingController(text: widget.edit == null || widget.edit!.cost == 0 ? '' : widget.edit!.cost.round().toString());
  late final notes = TextEditingController(text: widget.edit?.notes ?? '');
  bool titleTouched = false;
  AppState get s => widget.state;

  static String _defaultTitle(ServiceType t) => switch (t) {
        ServiceType.cleaning => 'Quarterly Panel Washing & Inspection',
        ServiceType.inverter => 'Inverter Health & DC String Check',
        ServiceType.electrical => 'Earthing Pit Resistance & SPD Audit',
        ServiceType.general => 'General Maintenance Visit',
      };

  DateTime? _defaultDue(ServiceType t, DateTime from) => from.add(Duration(
        days: switch (t) {
          ServiceType.cleaning => s.prefs.dustDays,
          ServiceType.inverter => 180,
          ServiceType.electrical => 365,
          ServiceType.general => 90,
        },
      ));

  @override
  void dispose() {
    for (final c in [title, gain, tech, cost, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _levels => type == ServiceType.cleaning ? _soilLabels.keys.toList() : _statusLabels.keys.toList();

  void _save() {
    final e = widget.edit ??
        ServiceEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), type: type, date: date);
    e
      ..type = type
      ..date = date
      ..title = title.text.trim()
      ..technician = tech.text.trim()
      ..notes = notes.text.trim()
      ..soiling = level
      ..nextDue = nextDue
      ..yieldGain = double.tryParse(gain.text.trim()) ?? 0
      ..cost = double.tryParse(cost.text.trim()) ?? 0;
    if (widget.edit == null) s.services.add(e);
    s.saveServices();
    Navigator.pop(context);
  }

  Widget _dateField(DateTime? v, ValueChanged<DateTime> onPick) => TextField(
        readOnly: true,
        controller: TextEditingController(text: v == null ? '' : fmtDate(v)),
        style: _fieldStyle(context),
        decoration: _dec(suffix: Icon(Icons.keyboard_arrow_down, color: C.mute)),
        onTap: () async {
          final d = await _pick(context, v ?? DateTime.now());
          if (d != null) onPick(d);
        },
      );

  @override
  Widget build(BuildContext context) {
    final st = _fieldStyle(context);
    return _dialogShell(
      context,
      widget.edit == null ? 'Log Maintenance Event' : 'Edit Maintenance Event',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Service Type'),
              DropdownButtonFormField<ServiceType>(
                initialValue: type,
                isExpanded: true,
                style: st,
                decoration: _dec(),
                items: [for (final t in ServiceType.values) DropdownMenuItem(value: t, child: Text(_typeLabels[t]!, maxLines: 1, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() {
                  type = v!;
                  level = type == ServiceType.cleaning ? 'moderate' : 'healthy';
                  if (!titleTouched) title.text = _defaultTitle(type);
                  if (widget.edit == null) nextDue = _defaultDue(type, date);
                }),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Date'),
              _dateField(date, (d) => setState(() {
                    date = d;
                    if (widget.edit == null) nextDue = _defaultDue(type, d);
                  })),
            ]),
          ),
        ]),
        const FieldLabel('Service Title / Summary'),
        TextField(controller: title, style: st, decoration: _dec(), onChanged: (_) => titleTouched = true),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel(type == ServiceType.cleaning ? 'Soiling Level' : 'Status'),
              DropdownButtonFormField<String>(
                key: ValueKey(type == ServiceType.cleaning),
                initialValue: _levels.contains(level) ? level : _levels.first,
                isExpanded: true,
                style: st,
                decoration: _dec(),
                items: [for (final k in _levels) DropdownMenuItem(value: k, child: Text(type == ServiceType.cleaning ? _soilLabels[k]! : _statusLabels[k]!, maxLines: 1, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => level = v!),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Est. Yield Gain (%)'),
              TextField(controller: gain, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: st, decoration: _dec()),
            ]),
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Technician / Agency'),
              TextField(controller: tech, style: st, decoration: _dec()),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Service Cost (₹)'),
              TextField(controller: cost, keyboardType: TextInputType.number, style: st, decoration: _dec()),
            ]),
          ),
        ]),
        const FieldLabel('Next Due Date (Reminder)'),
        _dateField(nextDue, (d) => setState(() => nextDue = d)),
        const FieldLabel('Technician Observations & Notes'),
        TextField(controller: notes, minLines: 2, maxLines: 4, style: st, decoration: _dec()),
        const SizedBox(height: 8),
      ]),
      _footer(context, 'Save Record', _save),
    );
  }
}
