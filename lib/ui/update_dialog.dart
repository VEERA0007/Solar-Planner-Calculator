import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/update.dart';

typedef UpdateDownloader = Future<String?> Function(String url, int size, void Function(int got, int total) onProgress, UpdateCancel cancel);
typedef UpdateInstaller = Future<String> Function(String path);

/// Shows the "Update Available" card: versions, a wavy download bar, then install.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo u,
  String currentLabel, {
  UpdateDownloader? downloader,
  UpdateInstaller? installer,
  bool? canDownload,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: u, currentLabel: currentLabel, downloader: downloader ?? downloadUpdate, installer: installer ?? installUpdate, canDownload: canDownload ?? (canDownloadUpdate && u.downloadUrl != null)),
    );

enum _Phase { ready, downloading, done, error }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final String currentLabel;
  final UpdateDownloader downloader;
  final UpdateInstaller installer;
  final bool canDownload;
  const UpdateDialog({super.key, required this.info, required this.currentLabel, required this.downloader, required this.installer, required this.canDownload});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> with SingleTickerProviderStateMixin {
  _Phase phase = _Phase.ready;
  int got = 0, total = 0;
  String message = '';
  String? path;
  UpdateCancel cancel = UpdateCancel();
  late final AnimationController wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void initState() {
    super.initState();
    total = widget.info.size;
  }

  @override
  void dispose() {
    cancel.cancel();
    wave.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!widget.canDownload) {
      // Web (reload) or a platform without in-app install: open the page or file.
      try {
        if (kIsWeb) {
          await widget.installer('');
        } else {
          await launchUrl(Uri.parse(widget.info.downloadUrl ?? widget.info.pageUrl), mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
      if (mounted) Navigator.pop(context);
      return;
    }
    cancel = UpdateCancel();
    setState(() {
      phase = _Phase.downloading;
      got = 0;
      message = '';
    });
    try {
      final f = await widget.downloader(widget.info.downloadUrl!, widget.info.size, (g, t) {
        if (!mounted) return;
        setState(() {
          got = g;
          total = t;
        });
      }, cancel);
      if (!mounted) return;
      if (f == null) {
        setState(() => phase = _Phase.ready); // cancelled
        return;
      }
      path = f;
      setState(() => phase = _Phase.done);
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        message = 'Download failed: $e';
      });
    }
  }

  Future<void> _install() async {
    try {
      final m = await widget.installer(path!);
      if (mounted) setState(() => message = m);
    } catch (e) {
      if (mounted) setState(() => message = 'Could not start the install: $e');
    }
  }

  String _mb(int b) => (b / 1048576).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF213B3E) : const Color(0xFFE4F4F2);
    final fg = dark ? const Color(0xFFE6EEF0) : const Color(0xFF10292B);
    final mute = dark ? const Color(0xFFB4C3C6) : const Color(0xFF4A6366);
    const cyan = Color(0xFF00D4DA);
    final cyanText = dark ? cyan : const Color(0xFF007C80);
    final chipBg = dark ? const Color(0xFF3A4547) : const Color(0xFFCFE3E1);
    final newBg = dark ? const Color(0xFF0B4A52) : const Color(0xFFB8EDEF);
    final pct = total > 0 ? (got / total).clamp(0.0, 1.0) : 0.0;

    Widget chip(String head, String v, Color bgc, Color tc) => Flexible(child: Column(children: [
          Text(head, style: TextStyle(color: mute, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: bgc, borderRadius: BorderRadius.circular(22)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(v, maxLines: 1, style: TextStyle(color: tc, fontSize: 18, fontWeight: FontWeight.w800))),
          ),
        ]));

    Widget outlined(String t, VoidCallback f) => OutlinedButton(
          onPressed: f,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: fg, side: BorderSide(color: cyan.withValues(alpha: .55), width: 1.5), shape: const StadiumBorder()),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
        );
    Widget filled(String t, VoidCallback f) => FilledButton(
          onPressed: f,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: cyan, foregroundColor: const Color(0xFF00292B), shape: const StadiumBorder()),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
        );

    final size = widget.info.size > 0 ? '${_mb(widget.info.size)} MB' : null;
    return Dialog(
      backgroundColor: bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: dark ? const Color(0xFF0B5560) : const Color(0xFF9EE6EA), borderRadius: BorderRadius.circular(26)),
                child: Icon(Icons.system_update_alt, color: dark ? cyan : const Color(0xFF00555A), size: 38),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Update Available', style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 6),
                  Text('A new version is ready', style: TextStyle(color: mute, fontSize: 18)),
                ]),
              ),
            ]),
            const SizedBox(height: 28),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                chip('Current', widget.currentLabel.isEmpty ? '-' : widget.currentLabel, chipBg, mute),
                Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 14), child: Icon(Icons.arrow_forward, color: cyanText, size: 26)),
                chip('New', widget.info.label, newBg, cyanText),
              ]),
            ),
            const SizedBox(height: 28),
            if (phase == _Phase.ready) ...[
              if (size != null) Center(child: Text('Download size $size', style: TextStyle(color: mute, fontSize: 15))),
              if (size != null) const SizedBox(height: 18),
              Row(children: [
                Expanded(child: outlined('Later', () => Navigator.pop(context))),
                const SizedBox(width: 12),
                Expanded(child: filled(widget.canDownload ? 'Update now' : (kIsWeb ? 'Reload now' : 'Open download'), _start)),
              ]),
            ],
            if (phase == _Phase.downloading) ...[
              Row(children: [
                const Icon(Icons.downloading, color: cyan, size: 26),
                const SizedBox(width: 14),
                Text('Downloading...', style: TextStyle(color: fg, fontSize: 21, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                height: 24,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: wave,
                  builder: (_, __) => CustomPaint(painter: WavyBarPainter(pct, wave.value * 2 * math.pi, cyan, dark ? const Color(0xFF3B4547) : const Color(0xFFBFD6D4))),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text(total > 0 ? '${_mb(got)} / ${_mb(total)} MB' : '${_mb(got)} MB', style: TextStyle(color: mute, fontSize: 17)),
                const Spacer(),
                Text('${(pct * 100).round()}%', style: TextStyle(color: cyanText, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 26),
              outlined('Cancel', () {
                cancel.cancel();
                Navigator.pop(context);
              }),
            ],
            if (phase == _Phase.done) ...[
              Row(children: [
                const Icon(Icons.check_circle, color: cyan, size: 26),
                const SizedBox(width: 12),
                Text('Download complete', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700)),
              ]),
              if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(message, style: TextStyle(color: mute, fontSize: 15, height: 1.35))),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: outlined('Close', () => Navigator.pop(context))),
                const SizedBox(width: 12),
                Expanded(child: filled('Install now', _install)),
              ]),
            ],
            if (phase == _Phase.error) ...[
              Text(message, style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 15, height: 1.35)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: outlined('Release page', () => launchUrl(Uri.parse(widget.info.pageUrl), mode: LaunchMode.externalApplication))),
                const SizedBox(width: 12),
                Expanded(child: filled('Retry', _start)),
              ]),
              const SizedBox(height: 8),
              Center(child: TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: mute)))),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A moving sine wave for the part already downloaded, a plain line for the rest.
class WavyBarPainter extends CustomPainter {
  final double progress, phase;
  final Color active, track;
  const WavyBarPainter(this.progress, this.phase, this.active, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, mid = size.height / 2, stroke = 8.0;
    final x1 = (w * progress).clamp(0.0, w);
    final tp = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(math.min(x1 + 10, w - stroke / 2), mid), Offset(w - stroke / 2, mid), tp);
    canvas.drawCircle(Offset(w - stroke / 2, mid), 3, Paint()..color = active);
    if (x1 <= 1) return;
    final path = Path();
    const amp = 5.0, len = 34.0;
    for (var x = stroke / 2; x <= x1; x += 1) {
      final y = mid + math.sin(x / len * 2 * math.pi - phase) * amp;
      x == stroke / 2 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = active..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(WavyBarPainter o) => o.progress != progress || o.phase != phase;
}
