import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/calc.dart';
import '../core/store.dart';

Future<Uint8List> buildQuotePdf(Customer c, EstimateResult r, Brand brand) async {
  final doc = pw.Document();
  final amber = PdfColor.fromInt(0xFFF59E0B);
  final grey = PdfColor.fromInt(0xFF6B7280);
  final now = DateTime.now();
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${now.day.toString().padLeft(2, '0')} ${mo[now.month - 1]} ${now.year}';

  pw.Widget section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFB45309))),
          pw.Divider(color: PdfColors.grey300, height: 6),
        ]),
      );
  pw.Widget kv(String k, String v, {bool strong = false}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        color: strong ? PdfColor.fromInt(0xFFFEF3C7) : null,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(k, style: pw.TextStyle(fontSize: 11.5, color: strong ? PdfColor.fromInt(0xFF92400E) : grey, fontWeight: strong ? pw.FontWeight.bold : null)),
          pw.Text(v, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: strong ? PdfColor.fromInt(0xFF92400E) : PdfColors.black)),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        color: amber,
        padding: const pw.EdgeInsets.fromLTRB(40, 32, 40, 28),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(brand.company.isEmpty ? 'Solar Quote' : brand.company, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Rooftop Solar Estimate', style: const pw.TextStyle(fontSize: 13)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(date, style: const pw.TextStyle(fontSize: 12)),
            if (brand.phone.isNotEmpty) pw.Text(brand.phone, style: const pw.TextStyle(fontSize: 12)),
          ]),
        ]),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 40),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          section('Customer'),
          kv('Name', c.name.isEmpty ? '-' : c.name),
          kv('USC number', c.usc.isEmpty ? '-' : c.usc),
          kv('Phone', c.phone.isEmpty ? '-' : c.phone),
          kv('Location', c.address.isEmpty ? '-' : c.address),
          section('Proposed system'),
          kv('System size', '${fmt1(r.kw)} kW'),
          kv('Solar panels', '${r.panels} x ${r.panelWp.round()} Wp'),
          kv('Roof area needed', '${r.roofSqft.round()} sq ft'),
          kv('Expected generation', '${groupIndian(r.gen1)} kWh / year'),
          section('Investment'),
          kv('Project cost', inr(r.cost)),
          kv('Government subsidy', r.subsidy > 0 ? '- ${inr(r.subsidy)}' : 'Not applicable'),
          kv('Net investment', inr(r.netCost), strong: true),
          section('Returns'),
          kv('Saving in year 1', inr(r.year1Saving)),
          kv('Average saving per month', inr(r.monthlySaving)),
          kv('Payback period', r.paybackYears == null ? '-' : '${fmt1(r.paybackYears!)} years'),
          kv('Total profit over ${r.years} years', inr(r.lifetimeProfit)),
          kv('CO2 avoided per year', '${fmt1(r.co2Tonnes)} tonnes'),
          pw.SizedBox(height: 40),
          pw.Text(brand.note, style: pw.TextStyle(fontSize: 9.5, color: grey)),
        ]),
      ),
    ]),
  ));
  return doc.save();
}

Future<void> shareQuote(Customer c, EstimateResult r, Brand brand) async {
  final bytes = await buildQuotePdf(c, r, brand);
  final safe = (c.usc.isNotEmpty ? c.usc : (c.name.isNotEmpty ? c.name : 'quote')).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: 'Solar-Quote-$safe.pdf');
}
