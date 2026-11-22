import 'package:flutter/material.dart';
import '../core/appliance_data.dart';
import '../core/store.dart';
import 'theme.dart';

String historyDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${mo[d.month - 1]} ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// List of saved Appliance Analysis calculations.
class ApplHistoryPage extends StatefulWidget {
  final AppState state;
  final void Function(ApplRecord) onOpen;
  final Future<void> Function(ApplRecord) onShare;
  const ApplHistoryPage({super.key, required this.state, required this.onOpen, required this.onShare});
  @override
  State<ApplHistoryPage> createState() => _ApplHistoryPageState();
}

class _ApplHistoryPageState extends State<ApplHistoryPage> {
  String q = '';
  AppState get s => widget.state;

  Future<void> _rename(ApplRecord r) async {
    final label = TextEditingController(text: r.label), note = TextEditingController(text: r.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename calculation'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, decoration: const InputDecoration(labelText: 'Customer / label')),
          const SizedBox(height: 10),
          TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
      ),
    );
    if (ok == true) {
      r.label = label.text.trim().isEmpty ? r.label : label.text.trim();
      r.note = note.text.trim();
      s.saveApplHistory();
    }
    label.dispose();
    note.dispose();
  }

  Future<void> _confirm(String title, String body, VoidCallback go) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
      ),
    );
    if (ok == true) go();
  }

  Widget _metric(String l, String v, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: TextStyle(color: C.mute, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .3)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, maxLines: 1, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14))),
        ]),
      );

  Widget _chip(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

  Widget _card(ApplRecord r) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                const SizedBox(height: 2),
                Text(historyDate(r.at), style: TextStyle(color: C.mute, fontSize: 12.5)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: C.mute),
              onSelected: (v) {
                if (v == 'rename') _rename(r);
                if (v == 'delete') {
                  _confirm('Delete calculation?', '"${r.label}" will be removed from history.', () {
                    s.applHistory.removeWhere((x) => x.id == r.id);
                    s.saveApplHistory();
                  });
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename / add note')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip(r.cfg.profile.label, C.chipBlue, C.sky),
            _chip(r.cfg.sys.label, C.chipSun, C.orange),
            _chip(r.cfg.dcr ? 'DCR' : 'Non-DCR', C.chipGreen, C.green),
            _chip('${r.items.length} appliances', C.chip, C.mute),
          ]),
          if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.note, style: TextStyle(color: C.mute, fontSize: 13, fontStyle: FontStyle.italic))),
          const SizedBox(height: 12),
          Row(children: [
            _metric('SYSTEM', '${r.kwp.toStringAsFixed(2)} kWp', C.text),
            _metric('USAGE', '${r.monthly.round()} kWh/mo', C.text),
            _metric('NET COST', rupee(r.net), C.orange),
            _metric('PAYBACK', '${r.payback.toStringAsFixed(1)} yrs', C.green),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(onPressed: () => widget.onOpen(r), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Open', style: TextStyle(fontWeight: FontWeight.w800))),
            TextButton.icon(onPressed: () => widget.onShare(r), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Proposal PDF', style: TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final all = s.applHistory;
          final t = q.trim().toLowerCase();
          final list = [for (final r in all) if (t.isEmpty || r.label.toLowerCase().contains(t) || r.note.toLowerCase().contains(t) || r.cfg.profile.label.toLowerCase().contains(t)) r];
          return Scaffold(
            backgroundColor: C.bg,
            appBar: AppBar(
              backgroundColor: C.bg,
              title: Text('Calculation History (${all.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
              actions: [
                if (all.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear all',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => _confirm('Clear all history?', 'All ${all.length} saved calculations will be deleted.', () {
                      s.applHistory.clear();
                      s.saveApplHistory();
                    }),
                  ),
              ],
            ),
            body: all.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history, size: 56, color: C.mute),
                        const SizedBox(height: 12),
                        const Text('No calculations yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 6),
                        Text('Every time you tap Calculate, the result is saved here so you can reopen it or send the proposal again.', textAlign: TextAlign.center, style: TextStyle(color: C.mute, height: 1.4)),
                      ]),
                    ),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: [
                    TextField(
                      onChanged: (v) => setState(() => q = v),
                      decoration: InputDecoration(
                        hintText: 'Search by customer, note or type',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: C.card2,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: C.line)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No match.', style: TextStyle(color: C.mute))),
                    for (final r in list) _card(r),
                  ]),
          );
        },
      );
}
