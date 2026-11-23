import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/bill_parse.dart';
import '../core/estimator_data.dart';
import '../core/store.dart';
import 'theme.dart';

/// What the user chose to keep from a bill page.
class FetchedBill {
  final String? usc;
  final Map<int, double> unitsByKey; // year*12+month-1 -> units
  final double? latestUnits;
  const FetchedBill(this.usc, this.unitsByKey, this.latestUnits);
}

bool get _webviewSupported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Opens the DISCOM bill site inside the app. The user types the USC number and
/// solves the captcha on the real page, then taps "Read bill from page".
class BillFetchPage extends StatefulWidget {
  final AppState state;
  final String usc;
  const BillFetchPage({super.key, required this.state, required this.usc});
  @override
  State<BillFetchPage> createState() => _BillFetchPageState();
}

class _BillFetchPageState extends State<BillFetchPage> {
  WebViewController? web;
  late Discom discom;
  final paste = TextEditingController();
  bool pasteMode = false;
  bool loading = true;
  String note = '';

  @override
  void initState() {
    super.initState();
    final list = widget.state.st.discoms;
    discom = list.first;
    pasteMode = !_webviewSupported;
    if (_webviewSupported) _load(discom);
  }

  @override
  void dispose() {
    paste.dispose();
    super.dispose();
  }

  void _load(Discom d) {
    discom = d;
    loading = true;
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (mounted) setState(() => loading = false);
      }))
      ..loadRequest(Uri.parse(d.url));
    setState(() {});
  }

  Future<String> _pageText() async {
    final c = web;
    if (c == null) return '';
    // Collect the visible text of the page and of any same-site frames.
    const js = "(function(){var t=document.body?document.body.innerText:'';var f=document.querySelectorAll('iframe');for(var i=0;i<f.length;i++){try{t+='\\n'+f[i].contentDocument.body.innerText;}catch(e){}}return t;})()";
    final r = await c.runJavaScriptReturningResult(js);
    var s = r.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).replaceAll(r'\n', '\n').replaceAll(r'\t', ' ').replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    return s;
  }

  Future<void> _read() async {
    try {
      final text = await _pageText();
      await _review(parseBillText(text));
    } catch (e) {
      if (mounted) setState(() => note = 'Could not read this page: $e');
    }
  }

  Future<void> _review(BillParse p) async {
    if (!p.found) {
      setState(() => note = 'No units found on this page. Open the page that shows the bill or the month-wise history and try again, or paste the page text.');
      return;
    }
    final months = last13Months(DateTime.now());
    final now = DateTime.now();
    final start = now.year * 12 + now.month - 1 - 13; // key of the oldest slot
    final rows = [for (final r in p.rows) if (r.key >= start && r.key < start + 13) r];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bill found'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.name != null) Text(p.name!, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (p.usc != null) Text('USC ${p.usc}', style: TextStyle(color: C.mute)),
            const SizedBox(height: 8),
            if (rows.isEmpty && p.latestUnits != null) Text('Units on this bill: ${p.latestUnits!.round()} kWh${p.latestAmount != null ? '  ·  ₹${p.latestAmount!.round()}' : ''}\nThis will be saved as last month.'),
            for (final r in rows) Text('${months[r.key - start]}:  ${r.units.round()} kWh${r.amount != null ? '   ₹${r.amount!.round()}' : ''}'),
            if (rows.isNotEmpty && rows.length < p.rows.length) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${p.rows.length - rows.length} older rows were outside the last 13 months and were skipped.', style: TextStyle(color: C.mute, fontSize: 12))),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use these units'))],
      ),
    );
    if (ok != true || !mounted) return;
    final map = {for (final r in rows) r.key: r.units};
    Navigator.pop(context, FetchedBill(p.usc, map, rows.isEmpty ? p.latestUnits : null));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.state.st.discoms;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        title: const Text('Fetch bill from DISCOM', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          if (_webviewSupported)
            IconButton(tooltip: pasteMode ? 'Show website' : 'Paste text instead', icon: Icon(pasteMode ? Icons.language : Icons.content_paste), onPressed: () => setState(() => pasteMode = !pasteMode)),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                child: ChoiceChip(
                  label: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  selected: discom.id == d.id,
                  onSelected: (_) => _webviewSupported ? _load(d) : setState(() => discom = d),
                ),
              ),
          ]),
        ),
        if (widget.usc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Row(children: [
              Expanded(child: Text('Your USC number: ${widget.usc}', style: TextStyle(color: C.mute, fontSize: 13))),
              TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: widget.usc)), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
            ]),
          ),
        Expanded(
          child: pasteMode
              ? ListView(padding: const EdgeInsets.all(14), children: [
                  Text(_webviewSupported ? 'Paste the text copied from the bill page.' : 'Open the DISCOM site, look up the bill, copy the bill text and paste it here.', style: TextStyle(color: C.mute, height: 1.35)),
                  if (!_webviewSupported) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse(discom.url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 18), label: Text('Open ${discom.name} bill site')),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: paste, maxLines: 10, decoration: const InputDecoration(hintText: 'Paste the bill or history text here', border: OutlineInputBorder())),
                ])
              : Stack(children: [
                  if (web != null) WebViewWidget(controller: web!),
                  if (loading) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
                ]),
        ),
        if (note.isNotEmpty)
          Container(width: double.infinity, color: C.amber.withValues(alpha: .15), padding: const EdgeInsets.all(10), child: Text(note, style: const TextStyle(fontSize: 13))),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!pasteMode) Text('Type the USC number and solve the captcha on the site, then open the bill or history and tap the button.', style: TextStyle(color: C.mute, fontSize: 12)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: pasteMode ? () => _review(parseBillText(paste.text)) : _read,
                  icon: const Icon(Icons.receipt_long),
                  label: Text(pasteMode ? 'Read pasted text' : 'Read bill from page', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  style: FilledButton.styleFrom(backgroundColor: C.orange, minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
