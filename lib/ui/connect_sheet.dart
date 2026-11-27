import 'package:flutter/material.dart';

import 'inverter_sync_section.dart';
import 'theme.dart';
import 'usc_section.dart';

/// Opens the connect sheet from the home screen: inverter and data-logger sync, and the
/// USC bill lookup. Both need the backend URL set at build time.
Future<void> showConnectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: C.bg,
    builder: (_) => const _ConnectSheet(),
  );
}

/// Home-screen card that opens the connect sheet.
class ConnectCard extends StatelessWidget {
  const ConnectCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cable, color: C.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Connect inverter, data logger and bill', style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Link your inverter or data logger cloud account, or look up a customer bill by USC number.',
          style: TextStyle(color: C.mute, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showConnectSheet(context),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet();

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final UscLink _usc = UscLink();

  @override
  void dispose() {
    _usc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Connect', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.text))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ]),
          const SizedBox(height: 6),
          const InverterSyncSection(),
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bill lookup by USC number', style: TextStyle(color: C.amber, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              UscSection(
                link: _usc,
                onApply: (r) => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${r.avgUnits.round()} kWh/month, ${r.discom.code} 12-month average')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
