import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/appliance_data.dart';
import '../core/store.dart';

// The default PDF font has no rupee glyph, so the proposal writes "Rs.".
String _rs(num v) => 'Rs. ${rupee(v).substring(1)}';
String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// One-page-style proposal for an appliance analysis: load, system, price,
/// savings and the bill of materials with a price per line.
Future<Uint8List> buildApplianceProposal({
  required Analysis an,
  required List<LoadItem> items,
  required Brand brand,
  required String label,
  required double tariff,
}) async {
  final o = an.selected;
  final cfg = an.cfg;
  final bom = buildBom(o, dcr: cfg.dcr, profile: cfg.profile, rates: an.rates);
  final eco = economics(o, an.monthly);
  final now = DateTime.now();
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${now.day.toString().padLeft(2, '0')} ${mo[now.month - 1]} ${now.year}';
  final amber = PdfColor.fromInt(0xFFF59E0B);
  final grey = PdfColor.fromInt(0xFF6B7280);
  final brown = PdfColor.fromInt(0xFFB45309);

  pw.Widget section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: brown)),
          pw.Divider(color: PdfColors.grey300, height: 6),
        ]),
      );
  pw.Widget kv(String k, String v, {bool strong = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        color: strong ? PdfColor.fromInt(0xFFFEF3C7) : null,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: pw.TextStyle(fontSize: 10.5, color: strong ? PdfColor.fromInt(0xFF92400E) : grey, fontWeight: strong ? pw.FontWeight.bold : null)),
          pw.Text(v, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]),
      );
  pw.Widget cell(String t, {bool head = false, pw.TextAlign a = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
        child: pw.Text(t, textAlign: a, style: pw.TextStyle(fontSize: head ? 9.5 : 9.5, fontWeight: head ? pw.FontWeight.bold : null, color: head ? brown : PdfColors.black)),
      );

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 0, 36, 30),
    header: (ctx) => ctx.pageNumber > 1
        ? pw.Padding(padding: const pw.EdgeInsets.only(top: 18, bottom: 4), child: pw.Text('${brand.company.isEmpty ? 'Solar Proposal' : brand.company} · $label', style: pw.TextStyle(fontSize: 9, color: grey)))
        : pw.SizedBox(),
    footer: (ctx) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 8.5, color: grey))),
    build: (ctx) => [
      pw.Container(
        color: amber,
        margin: const pw.EdgeInsets.only(left: -36, right: -36),
        padding: const pw.EdgeInsets.fromLTRB(36, 28, 36, 22),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(brand.company.isEmpty ? 'Solar Proposal' : brand.company, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text('${o.type.label} Solar System Proposal', style: const pw.TextStyle(fontSize: 12.5)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(date, style: const pw.TextStyle(fontSize: 11)),
            if (brand.phone.isNotEmpty) pw.Text(brand.phone, style: const pw.TextStyle(fontSize: 11)),
          ]),
        ]),
      ),
      section('Prepared for'),
      kv('Customer / reference', label),
      kv('Customer type', cfg.profile.label),
      section('Load summary'),
      kv('Monthly consumption', '${an.monthly.round()} kWh'),
      kv('Daily consumption', '${an.daily.toStringAsFixed(1)} kWh'),
      kv('Connected load', '${an.stats.connectedKw.toStringAsFixed(2)} kW'),
      kv('Daytime share (6am - 6pm)', '${(an.stats.dayShare * 100).round()}%'),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5), bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(.9), 3: pw.FlexColumnWidth(1.2), 4: pw.FlexColumnWidth(1.6)},
        children: [
          pw.TableRow(children: [cell('Appliance', head: true), cell('Watts', head: true, a: pw.TextAlign.right), cell('Qty', head: true, a: pw.TextAlign.right), cell('Hrs/day', head: true, a: pw.TextAlign.right), cell('kWh / month', head: true, a: pw.TextAlign.right)]),
          for (final a in items)
            pw.TableRow(children: [
              cell(a.backup ? '${a.name} (backup)' : a.name),
              cell(_n(a.watts), a: pw.TextAlign.right),
              cell('${a.qty}', a: pw.TextAlign.right),
              cell(_n(a.hours), a: pw.TextAlign.right),
              cell((a.kwhDay * 30 * cfg.profile.factor).toStringAsFixed(1), a: pw.TextAlign.right),
            ]),
        ],
      ),
      section('Recommended system'),
      kv('System type', o.type.label),
      kv('Module standard', cfg.dcr ? 'DCR (ALMM, made in India)' : 'Non-DCR'),
      kv('Solar array', '${o.kwp.toStringAsFixed(2)} kWp (${o.panels} x 550 W)'),
      kv('Inverter', o.invLabel),
      kv('Battery', o.batteryKwh > 0 ? '${o.batteryKwh.toStringAsFixed(1)} kWh LiFePO4' : 'Not required'),
      kv('Supply', o.threePhase ? 'Three-phase 415 V' : 'Single-phase 230 V'),
      kv('Roof / shadow-free area', '${o.footprintM2.toStringAsFixed(0)} sq m'),
      section('Investment'),
      kv('System price', _rs(o.gross)),
      if (o.subsidy > 0) kv('Central subsidy (PM Surya Ghar)', '- ${_rs(o.subsidy)}'),
      kv(o.subsidy > 0 ? 'Net cost after subsidy' : 'Net cost', _rs(o.net), strong: true),
      section('Savings'),
      kv('Electricity bill before solar', '${_rs(eco.billBefore / 12)} / month'),
      kv('Electricity bill after solar', '${_rs(eco.billAfter / 12)} / month'),
      kv('Saving per year', _rs(eco.saveYear)),
      kv('Payback', '${o.payback.toStringAsFixed(1)} years'),
      kv('25-year saving (3% tariff rise, 0.5% degradation)', _rs(eco.save25)),
      kv('CO2 avoided per year', '${(eco.co2Year / 1000).toStringAsFixed(1)} tonnes'),
      section('Bill of materials'),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5), bottom: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        columnWidths: const {0: pw.FlexColumnWidth(5), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1.8)},
        children: [
          pw.TableRow(children: [cell('Item', head: true), cell('Qty', head: true), cell('Amount', head: true, a: pw.TextAlign.right)]),
          for (final i in bom.items)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(i.title, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(i.spec, style: pw.TextStyle(fontSize: 8, color: grey)),
                ]),
              ),
              cell(i.qty),
              cell(_rs(i.price), a: pw.TextAlign.right),
            ]),
          pw.TableRow(decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF3C7)), children: [cell('Total', head: true), cell(''), cell(_rs(bom.total), head: true, a: pw.TextAlign.right)]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Text('Prices are indicative and include supply, installation and net-metering liaison unless stated. ${subsidyNote(cfg.profile, cfg.dcr, o.type)} Generation is an estimate based on location solar data and ${(cfg.shadePct).round()}% shading.', style: pw.TextStyle(fontSize: 8.5, color: grey)),
      if (brand.note.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(brand.note, style: pw.TextStyle(fontSize: 9, color: grey))),
    ],
  ));
  return doc.save();
}

Future<void> shareApplianceProposal(Uint8List bytes, String label) =>
    Printing.sharePdf(bytes: bytes, filename: 'Solar-Proposal-${label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.pdf');
