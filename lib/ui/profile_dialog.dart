import 'package:flutter/material.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

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
      {TextInputType? kb, String? err, IconData? icon, int lines = 1, bool readOnly = false, VoidCallback? onTap, Widget? suffix, bool mono = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FieldLabel(label, icon: icon),
        TextField(
          controller: c[key],
          keyboardType: kb,
          maxLines: lines,
          readOnly: readOnly,
          onTap: onTap,
          style: TextStyle(fontWeight: FontWeight.w600, fontFamilyFallback: mono ? kMono : null),
          decoration: plainField(error: err, suffix: suffix),
        ),
      ]);

  Widget _owner() => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
        _f(t('full_name'), 'name'),
        _f(t('service_no'), 'no', kb: TextInputType.text, mono: true),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _f(t('mobile'), 'mobile', icon: Icons.phone_outlined, kb: TextInputType.phone, err: errMobile)),
          const SizedBox(width: 12),
          Expanded(child: _f(t('pin'), 'pin', icon: Icons.location_on_outlined, kb: TextInputType.number, err: errPin)),
        ]),
        _f(t('email_addr'), 'email', icon: Icons.mail_outline, kb: TextInputType.emailAddress, err: errEmail),
        _f(t('address'), 'addr', lines: 3),
      ]);

  Widget _specs() {
    final kw = double.tryParse(c['kwp']!.text) ?? s.site.kwp;
    final sq = double.tryParse(c['roof']!.text) ?? 0;
    final fit = sq / 100; // ~100 sq ft per kWp
    final war = int.tryParse(c['war']!.text) ?? 25;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _f(t('capacity'), 'kwp', kb: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 12),
        Expanded(child: _f(t('roof_area'), 'roof', kb: TextInputType.number)),
      ]),
      FieldLabel(t('roof_type')),
      DropdownButtonFormField<String>(
        initialValue: roof,
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: C.mute),
        decoration: plainField(),
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: C.text, fontWeight: FontWeight.w600, fontSize: 15.5),
        items: [for (final k in _roofKeys) DropdownMenuItem(value: k, child: Text(t('roof_$k'), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => roof = v ?? roof),
      ),
      _f(t('panel'), 'panel'),
      _f(t('inverter'), 'inv'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _f(t('commission'), 'date', readOnly: true, onTap: _pickDate, suffix: Icon(Icons.keyboard_arrow_down, color: C.mute)),
        ),
        const SizedBox(width: 12),
        Expanded(child: _f(t('warranty'), 'war', kb: TextInputType.number)),
      ]),
      if (sq > 0 || s.profile.commissionDate != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            [
              if (sq > 0) '${t('owner_hint')} ${fit.toStringAsFixed(1)} kWp · ${kw.toStringAsFixed(2)} kWp ${kw <= fit ? '(OK)' : '(!)'}',
              if (s.profile.commissionDate != null)
                '${t('warranty')}: ${fmtDate(DateTime(s.profile.commissionDate!.year + war, s.profile.commissionDate!.month, s.profile.commissionDate!.day))}',
            ].join('\n'),
            style: TextStyle(color: kw <= fit || sq <= 0 ? C.green : C.red, fontSize: 12),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final name = c['name']!.text.trim();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: h * .9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            child: Row(children: [
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: 3,
                    top: 3,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B82F6), Color(0xFF2563EB)])),
                      child: const Icon(Icons.person_outline, color: Colors.white, size: 28),
                    ),
                  ),
                  Positioned(top: 0, right: 4, child: Icon(Icons.star, size: 12, color: C.sky)),
                  Positioned(bottom: 4, left: 0, child: Icon(Icons.star, size: 12, color: C.sky)),
                  Positioned(bottom: 2, right: 4, child: Icon(Icons.star, size: 12, color: C.sky)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isEmpty ? t('profile') : name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    for (var i = 0; i < 3; i++) const Icon(Icons.star, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(t('pro_tier'), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.w700))),
                  ]),
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
            child: PillTabs(controller: tabs, labels: [t('tab_owner'), t('tab_specs')]),
          ),
          Flexible(
            child: SizedBox(height: h * .52, child: TabBarView(controller: tabs, children: [_owner(), _specs()])),
          ),
          DialogFooter(cancel: t('cancel'), save: t('save_profile'), onCancel: () => Navigator.pop(context), onSave: _save),
        ]),
      ),
    );
  }
}
