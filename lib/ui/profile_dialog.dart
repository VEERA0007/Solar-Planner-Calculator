import 'package:flutter/material.dart';
import '../core/store.dart';
import 'theme.dart';

Future<void> showProfileDialog(BuildContext context, AppState s) =>
    showDialog<void>(context: context, builder: (_) => _ProfileDialog(state: s));

const _roofKeys = ['rcc', 'sheet', 'tile', 'asbestos'];

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _ProfileDialog extends StatefulWidget {
  final AppState state;
  const _ProfileDialog({required this.state});
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  late final Map<String, TextEditingController> c;
  late String roof;
  String? errMobile, errPin, errEmail;

  AppState get s => widget.state;
  String t(String k) => s.t(k);

  @override
  void initState() {
    super.initState();
    final p = s.profile;
    c = {
      'name': TextEditingController(text: p.name),
      'no': TextEditingController(text: p.serviceNo),
      'mobile': TextEditingController(text: p.mobile),
      'pin': TextEditingController(text: p.pin),
      'email': TextEditingController(text: p.email),
      'addr': TextEditingController(text: p.address.isEmpty ? s.site.label : p.address),
      'kwp': TextEditingController(text: _num(s.site.kwp)),
      'roof': TextEditingController(text: _num(p.roofSqft)),
      'panel': TextEditingController(text: p.panel),
      'inv': TextEditingController(text: p.inverter),
      'date': TextEditingController(text: p.commission),
      'war': TextEditingController(text: p.warranty.toString()),
    };
    roof = _roofKeys.contains(p.roofType) ? p.roofType : 'rcc';
  }

  String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    tabs.dispose();
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    final mobile = c['mobile']!.text.replaceAll(RegExp(r'\D'), '');
    final pin = c['pin']!.text.trim();
    final mail = c['email']!.text.trim();
    errMobile = mobile.isEmpty || RegExp(r'^(91)?[6-9]\d{9}$').hasMatch(mobile) ? null : '10-digit mobile number';
    errPin = pin.isEmpty || RegExp(r'^\d{6}$').hasMatch(pin) ? null : '6-digit PIN';
    errEmail = mail.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail) ? null : 'Check the email';
    setState(() {});
    if (errMobile != null || errPin != null || errEmail != null) {
      tabs.animateTo(0);
      return false;
    }
    return true;
  }

  void _save() {
    if (!_validate()) return;
    final p = s.profile;
    p
      ..name = c['name']!.text.trim()
      ..serviceNo = c['no']!.text.trim()
      ..mobile = c['mobile']!.text.trim()
      ..pin = c['pin']!.text.trim()
      ..email = c['email']!.text.trim()
      ..address = c['addr']!.text.trim()
      ..roofType = roof
      ..roofSqft = (double.tryParse(c['roof']!.text.trim()) ?? p.roofSqft).clamp(0, 1000000).toDouble()
      ..panel = c['panel']!.text.trim()
      ..inverter = c['inv']!.text.trim()
      ..commission = c['date']!.text.trim()
      ..warranty = (int.tryParse(c['war']!.text.trim()) ?? p.warranty).clamp(0, 50);
    s.site.kwp = (double.tryParse(c['kwp']!.text.trim()) ?? s.site.kwp).clamp(0.1, 10000).toDouble();
    // keep the customer used by the Estimator and quotes in step with the profile
    if (p.name.isNotEmpty) s.customer.name = p.name;
    if (p.mobile.isNotEmpty) s.customer.phone = p.mobile;
    if (p.address.isNotEmpty) s.customer.address = p.address;
    if (p.serviceNo.isNotEmpty) s.customer.usc = p.serviceNo;
    s.saveProfile();
    Navigator.pop(context);
    toast(context, t('saved'));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final cur = s.profile.commissionDate ?? now;
    final r = await showDatePicker(context: context, initialDate: cur.isAfter(now) ? now : cur, firstDate: DateTime(2000), lastDate: now);
    if (r != null) setState(() => c['date']!.text = fmtDate(r));
  }

  Widget _f(String label, String key,
      {TextInputType? kb, String? err, IconData? icon, int lines = 1, bool readOnly = false, VoidCallback? onTap, Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextField(
          controller: c[key],
          keyboardType: kb,
          maxLines: lines,
          readOnly: readOnly,
          onTap: onTap,
          decoration: InputDecoration(
            labelText: label,
            errorText: err,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: suffix,
          ),
        ),
      );

  Widget _owner() => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        _f(t('full_name'), 'name', icon: Icons.person_outline),
        _f(t('service_no'), 'no', icon: Icons.tag, kb: TextInputType.number),
        _f(t('mobile'), 'mobile', icon: Icons.phone_outlined, kb: TextInputType.phone, err: errMobile),
        _f(t('pin'), 'pin', icon: Icons.pin_drop_outlined, kb: TextInputType.number, err: errPin),
        _f(t('email'), 'email', icon: Icons.mail_outline, kb: TextInputType.emailAddress, err: errEmail),
        _f(t('address'), 'addr', icon: Icons.home_outlined, lines: 3),
      ]);

  Widget _specs() {
    final kw = double.tryParse(c['kwp']!.text) ?? s.site.kwp;
    final sq = double.tryParse(c['roof']!.text) ?? 0;
    final fit = sq / 100; // ~100 sq ft per kWp
    final war = int.tryParse(c['war']!.text) ?? 25;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
      Row(children: [
        Expanded(child: _f(t('capacity'), 'kwp', kb: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 10),
        Expanded(child: _f(t('roof_area'), 'roof', kb: TextInputType.number)),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: DropdownButtonFormField<String>(
          initialValue: roof,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('roof_type')),
          items: [for (final k in _roofKeys) DropdownMenuItem(value: k, child: Text(t('roof_$k'), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => roof = v ?? roof),
        ),
      ),
      _f(t('panel'), 'panel', icon: Icons.solar_power_outlined),
      _f(t('inverter'), 'inv', icon: Icons.electrical_services),
      Row(children: [
        Expanded(
          child: _f(t('commission'), 'date', readOnly: true, onTap: _pickDate, icon: Icons.event_outlined),
        ),
        const SizedBox(width: 10),
        Expanded(child: _f(t('warranty'), 'war', kb: TextInputType.number)),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            sq > 0 ? 'Roof fits about ${fit.toStringAsFixed(1)} kWp · plant ${kw.toStringAsFixed(2)} kWp ${kw <= fit ? '✓' : '✗ too large'}' : '-',
            style: TextStyle(color: kw <= fit || sq <= 0 ? C.green : C.red, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          if (s.profile.commissionDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${t('warranty')}: ${fmtDate(DateTime(s.profile.commissionDate!.year + war, s.profile.commissionDate!.month, s.profile.commissionDate!.day))}',
                  style: TextStyle(color: C.mute, fontSize: 12)),
            ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final name = c['name']!.text.trim();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * .9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFB8A2E), Color(0xFFF5A524)])),
                child: name.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 28)
                    : Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? t('profile') : name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  Text('★★★ ${t('pro_tier')}', style: TextStyle(color: C.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
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
            tabs: [Tab(text: t('tab_owner')), Tab(text: t('tab_specs'))],
          ),
          Flexible(
            child: SizedBox(height: h * .55, child: TabBarView(controller: tabs, children: [_owner(), _specs()])),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel')))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _save, child: Text(t('save_profile')))),
            ]),
          ),
        ]),
      ),
    );
  }
}
