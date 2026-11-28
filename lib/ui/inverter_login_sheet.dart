import 'package:flutter/material.dart';
import '../core/backend_service.dart';
import '../core/inverter_history.dart';
import '../core/store.dart';
import 'theme.dart';

/// Bottom sheet to log in to a saved inverter account. The username is filled in and the
/// user types the password. The password is used once and never stored.
/// [stationId] picks a plant on this login; null keeps the saved choice.
Future<void> showInverterLoginSheet(BuildContext context, AppState s, InverterLoginItem account, {String? stationId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: C.card,
      builder: (_) => _InverterLoginSheet(state: s, account: account, stationId: stationId),
    );

class _InverterLoginSheet extends StatefulWidget {
  final AppState state;
  final InverterLoginItem account;
  final String? stationId;
  const _InverterLoginSheet({required this.state, required this.account, this.stationId});

  @override
  State<_InverterLoginSheet> createState() => _InverterLoginSheetState();
}

class _InverterLoginSheetState extends State<_InverterLoginSheet> {
  final password = TextEditingController();
  late final TextEditingController userCtrl = TextEditingController(text: widget.account.account);
  bool busy = false;
  bool obscure = true;
  String msg = '';
  bool err = false;

  AppState get s => widget.state;

  /// The saved account settings, with the chosen plant applied.
  InverterConfig get cfg {
    final base = widget.account.cfg ?? s.inverterCfg;
    return InverterConfig(
      authMode: base.authMode,
      brand: base.brand,
      username: base.username,
      apiKey: base.apiKey,
      stationId: widget.stationId ?? base.stationId,
      loggerSerial: base.loggerSerial,
      inverterSerial: base.inverterSerial,
      customEndpoint: base.customEndpoint,
    );
  }

  @override
  void dispose() {
    password.dispose();
    userCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (password.text.isEmpty) {
      setState(() {
        err = true;
        msg = 'Enter your password to log in.';
      });
      return;
    }
    final c = cfg;
    setState(() {
      busy = true;
      err = false;
      msg = 'Logging in to ${widget.account.brand}...';
    });
    final res = await BackendService.syncInverter(
      rawBaseUrl: s.prefs.backendUrl,
      config: c,
      password: password.text,
      apiSecret: '',
    );
    password.clear();
    if (!mounted) return;
    final ok = res.ok && res.snapshot != null;
    s.addInverterLogin(InverterLoginItem(
      at: DateTime.now(),
      brand: widget.account.brand,
      authMode: c.authMode,
      account: widget.account.account,
      ok: ok,
      message: ok ? 'Logged in' : (res.error ?? 'Login failed.'),
      cfg: c,
      snap: ok ? res.snapshot : null,
    ));
    if (ok) {
      s.inverterCfg = c;
      s.inverterSnap = res.snapshot;
      if (res.snapshot!.ratedKw > 0) {
        s.site.kwp = res.snapshot!.ratedKw;
        s.saveSite();
      }
      s.saveInverter();
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() {
        busy = false;
        err = true;
        msg = res.error ?? 'Login failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Log in to ${a.brand}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        const SizedBox(height: 4),
        Text('Enter the password for this account. It is not saved.', style: TextStyle(color: C.mute, fontSize: 12.5)),
        const SizedBox(height: 14),
        TextField(
          readOnly: true,
          controller: userCtrl,
          decoration: const InputDecoration(labelText: 'Username', isDense: true),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: password,
          obscureText: obscure,
          autofocus: true,
          onSubmitted: (_) => busy ? null : _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 19),
              onPressed: () => setState(() => obscure = !obscure),
            ),
          ),
        ),
        if (msg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: err ? C.red : C.mute, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: C.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: busy ? null : _login,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login, size: 18),
            label: Text(busy ? 'Logging in...' : 'Login', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
