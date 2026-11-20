import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/store.dart';
import 'profile_dialog.dart' show fmtDate;
import 'theme.dart';

/// Service tab (placeholder layout until the exact design is supplied):
/// panel cleaning, warranty and the grid utility for the chosen state.
class ServicePage extends StatelessWidget {
  final AppState state;
  const ServicePage({super.key, required this.state});

  Future<void> _open(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final p = s.profile;
    final due = s.cleanDueInDays;
    final ends = p.warrantyEnds;
    final left = ends?.difference(DateTime.now()).inDays;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        PageHead(s.t('service'), p.panel.isEmpty ? s.slabText : p.panel),
        Panel(
          child: Row(children: [
            Icon(Icons.cleaning_services_outlined, color: C.amber, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('dust_reminder'), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  due == null
                      ? '${s.prefs.dustDays} d'
                      : due > 0
                          ? '${s.t('to_clean')}: $due d'
                          : '${s.t('to_clean')} (${-due} d)',
                  style: TextStyle(color: due != null && due <= 0 ? C.red : C.mute),
                ),
              ]),
            ),
            FilledButton(onPressed: s.markCleaned, child: const Text('✓')),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('warranty'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${s.t('commission')}: ${p.commissionDate == null ? '-' : fmtDate(p.commissionDate!)}', style: TextStyle(color: C.mute)),
            Text(
              ends == null ? '${p.warranty} y' : '${fmtDate(ends)}${left != null && left >= 0 ? '  ·  ${(left / 365).toStringAsFixed(1)} y left' : ''}',
              style: TextStyle(color: C.green, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          onTap: () => _open(s.discom.url),
          child: Row(children: [
            Icon(Icons.bolt, color: C.blue, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.discom.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(s.discom.coverage, style: TextStyle(color: C.mute, fontSize: 12.5)),
              ]),
            ),
            Icon(Icons.open_in_new, color: C.mute),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Text(
            'The full Service screens will be built to match once the Service screenshots are shared.',
            style: TextStyle(color: C.mute),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
