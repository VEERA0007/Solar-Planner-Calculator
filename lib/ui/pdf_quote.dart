import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/calc.dart';
import '../core/store.dart';

/// Everything the proposal needs beyond the core numbers in [EstimateResult].
class QuoteInfo {
  final String architecture; // On-Grid / Hybrid / Off-Grid
  final String standard; // DCR ALMM (Subsidy Eligible) or Non-DCR
  final String category; // RESIDENTIAL / COMMERCIAL / AGRICULTURAL
  final String inverter; // e.g. "9 kW Havells Enviro GT"
  final String phase; // 1-Phase 230V or 3-Phase 415V
  final String panel; // module name, e.g. "550W DCR Mono PERC M10"
  final int panelCount;
  final double panelKwp;
  final double batteryKwh;
  final double psh; // peak sun hours per day (location yield)
  final double escalation; // yearly tariff rise, %
  final double omPct; // yearly maintenance, % of project cost
  final double tariff; // Rs per unit
  final String site; // address / location text
  final String sizingNote;
  final List<List<String>> bom; // [category, spec, quantity, status]

  const QuoteInfo({
    required this.architecture,
    required this.standard,
    required this.category,
    required this.inverter,
    required this.phase,
    required this.panel,
    required this.panelCount,
    required this.panelKwp,
    required this.batteryKwh,
    required this.psh,
    required this.escalation,
    required this.omPct,
    required this.tariff,
    required this.site,
    required this.sizingNote,
    required this.bom,
  });
}

String _pct(num v) => '${v.toStringAsFixed(1)}%';

Future<Uint8List> buildQuotePdf(Customer c, EstimateResult r, Brand brand, {QuoteInfo? info}) async {
  final doc = pw.Document();
  final now = DateTime.now();
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${now.day.toString().padLeft(2, '0')} ${mo[now.month - 1]} ${now.year}';
  final ref = 'SOL-${now.year}-${(r.panels * 53 + r.years).toString().padLeft(3, '0')}';

  final navy = PdfColor.fromInt(0xFF111827);
  final orange = PdfColor.fromInt(0xFFF97316);
  final blue = PdfColor.fromInt(0xFF2563EB);
  final green = PdfColor.fromInt(0xFF059669);
  final red = PdfColor.fromInt(0xFFDC2626);
  final amberBar = PdfColor.fromInt(0xFFFB923C);
  final mute = PdfColor.fromInt(0xFF6B7280);
  final line = PdfColor.fromInt(0xFFE5E7EB);
  final tint = PdfColor.fromInt(0xFFF8FAFC);
  final mint = PdfColor.fromInt(0xFFECFDF5);

  final i = info ??
      QuoteInfo(
        architecture: 'On-Grid',
        standard: r.subsidy > 0 ? 'DCR ALMM (Subsidy Eligible)' : 'Non-DCR',
        category: 'RESIDENTIAL',
        inverter: '${fmt1(r.kw)} kW inverter',
        phase: '1-Phase 230V',
        panel: '${r.panelWp.round()}W module',
        panelCount: r.panels,
        panelKwp: r.kw,
        batteryKwh: 0,
        psh: 0,
        escalation: 3,
        omPct: 1,
        tariff: 0,
        site: c.address,
        sizingNote: '',
        bom: const [],
      );

  final series = r.series;
  final maxCum = series.isEmpty ? 1.0 : series.map((e) => e.cumulative).fold<double>(r.netCost, (a, b) => a > b ? a : b);
  final om = r.cost * i.omPct / 100;
  final monthlySolar = r.monthlyGen;
  final monthlyUse = r.monthlyUnits;

  pw.Widget header(String title, String sub) => pw.Container(
        color: navy,
        padding: const pw.EdgeInsets.fromLTRB(36, 22, 36, 18),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(sub, style: pw.TextStyle(color: PdfColor.fromInt(0xFFD1D5DB), fontSize: 9.5)),
        ]),
      );

  pw.Widget sectionTitle(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 14, bottom: 8),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        color: tint,
        child: pw.Row(children: [
          pw.Container(width: 4, height: 14, color: orange),
          pw.SizedBox(width: 8),
          pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  pw.Widget kpi(String label, String value, String sub, PdfColor c) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: mute, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, color: c, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(sub, style: pw.TextStyle(fontSize: 7.5, color: mute)),
          ]),
        ),
      );

  pw.Widget row(String k, String v, {PdfColor? vc, int idx = 0}) => pw.Container(
        color: idx.isOdd ? tint : null,
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF374151)))),
          pw.Text(v, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: vc ?? PdfColors.black)),
        ]),
      );

  pw.Widget legend(PdfColor c, String t) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Container(width: 9, height: 9, color: c),
        pw.SizedBox(width: 4),
        pw.Text(t, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 12),
      ]);

  pw.Widget footer(pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(36, 0, 36, 0),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Solar System Proposal ($ref) • Engineering & ROI Estimate', style: pw.TextStyle(fontSize: 7.5, color: mute)),
          pw.Text('Generated $date  |  Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 7.5, color: mute)),
        ]),
      );

  // Section 1 table
  final monthlyDay = monthlyUse / 30;
  final sysRows = <List<String>>[
    ['Consumer Category & Supply Phase', '${i.category} (${i.phase})'],
    ['System Architecture', i.architecture == 'On-Grid' ? 'On-Grid (Net-Metered, Battery Not Required)' : i.architecture],
    ['PV Module Specification', i.panel],
    ['Selected Inverter Brand & Power', i.inverter],
    ['Battery Storage Bank', i.batteryKwh > 0 ? '${fmt1(i.batteryKwh)} kWh (Backup)' : '0 kWh (Grid Acts as Virtual Storage)'],
    ['Monthly / Daily Electricity Consumption', '${groupIndian(monthlyUse)} kWh/mo (${fmt1(monthlyDay)} kWh/day) @ Rs. ${fmt1(i.tariff)}/kWh'],
    ['Site Irradiance & Performance Ratio', '${fmt1(i.psh)} Peak Sun Hrs/day | PR 78%'],
    ['Estimated Monthly & Annual Solar Yield', '${groupIndian(monthlySolar)} kWh/mo (${groupIndian(r.gen1)} kWh/yr)'],
    ['Required Roof Area', '${r.roofSqm.round()} m2 (${r.roofSqft.round()} sq.ft)'],
  ];

  final cashRows = <List<String>>[
    ['Gross Turnkey Capex (${inr(i.panelKwp > 0 ? r.cost / i.panelKwp : 0)}/kW base)', inr(r.cost)],
    ['PM Surya Ghar Govt Subsidy (DBT Credit)', r.subsidy > 0 ? '- ${inr(r.subsidy)}' : inr(0)],
    ['Net Customer Investment (Payback Basis)', inr(r.netCost)],
    ['Estimated Year-1 Savings (Escalation ${fmt1(i.escalation)}%/yr · O&M ${fmt1(i.omPct)}%/yr)', '${inr(r.monthlySaving)}/mo  |  ${inr(r.year1Saving)}/yr'],
    ['Payback & 25-Yr Net Profit', '${r.paybackYears == null ? '-' : '${fmt1(r.paybackYears!)} Yrs'}  |  ${inr(r.lifetimeProfit)}'],
    ['25-Year Environmental Offset', '${fmt1(r.co2Tonnes)} Tonnes CO2 Avoided'],
  ];

  // Section 3 chart: monthly use vs solar yield (flat, from the averages)
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final maxMonth = math.max(monthlyUse, monthlySolar) * 1.15;
  pw.Widget monthChart() {
    const h = 120.0;
    return pw.Column(children: [
      pw.SizedBox(
        height: h,
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          for (final m in months)
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Expanded(child: pw.Container(height: h * monthlyUse / maxMonth, color: amberBar)),
                  pw.SizedBox(width: 1),
                  pw.Expanded(child: pw.Container(height: h * monthlySolar / maxMonth, color: green)),
                ]),
              ),
            ),
        ]),
      ),
      pw.Row(children: [
        for (final m in months) pw.Expanded(child: pw.Center(child: pw.Text(m, style: pw.TextStyle(fontSize: 7, color: mute)))),
      ]),
    ]);
  }

  // Section 4 chart: cumulative cash with break-even line
  pw.Widget cashChart() {
    const h = 130.0;
    const w = 500.0;
    final lineY = h * r.netCost / maxCum;
    return pw.SizedBox(
      width: w,
      height: h,
      child: pw.Stack(children: [
        pw.Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: pw.SizedBox(
            height: h,
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              for (final e in series)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                    child: pw.Container(
                      height: math.max(1, h * e.cumulative / maxCum),
                      color: e.cumulative < r.netCost ? amberBar : green,
                    ),
                  ),
                ),
            ]),
          ),
        ),
        pw.Positioned(left: 0, right: 0, bottom: lineY, child: pw.Container(height: 1.5, color: red)),
      ]),
    );
  }

  // Section 5: EMI on 80% loan at 9.9% p.a.
  double emi(double p, int months) {
    const rate = 0.099 / 12;
    final f = math.pow(1 + rate, months).toDouble();
    return p * rate * f / (f - 1);
  }

  final loan = r.netCost * 0.8;
  final tenureRows = <List<String>>[];
  for (final yrs in [3, 5, 7]) {
    final e = emi(loan, yrs * 12);
    tenureRows.add(['$yrs Years (${yrs * 12} EMIs)', inr(loan), inr(e), inr(r.monthlySaving), '${r.monthlySaving - e >= 0 ? '+' : '-'}${inr((r.monthlySaving - e).abs())}/mo']);
  }

  // Select years for the table, like the proposal layout
  const tableYears = [1, 2, 3, 4, 5, 7, 10, 15, 20, 25];
  final tableRows = <pw.TableRow>[];
  pw.Widget cell(String t, {bool bold = false, PdfColor? c, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: pw.Align(
          alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          child: pw.Text(t, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null, color: c ?? PdfColors.black)),
        ),
      );
  tableRows.add(pw.TableRow(
    decoration: pw.BoxDecoration(color: navy),
    children: [
      for (final t in ['Year', 'Gross Gain', 'O&M Cost', 'Cum. Net Cash', 'Net Position', 'Status'])
        cell(t, bold: true, c: PdfColors.white, right: t != 'Year' && t != 'Status'),
    ],
  ));
  for (final y in tableYears) {
    if (y < 1 || y > series.length) continue;
    final e = series[y - 1];
    final net = e.cumulative - r.netCost;
    final paid = net >= 0;
    tableRows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: y.isEven ? tint : null),
      children: [
        cell('Yr $y', bold: true),
        cell(inr(e.saving), right: true),
        cell(inr(om), right: true),
        cell(inr(e.cumulative), right: true),
        cell('${paid ? '+' : '-'}${inr(net.abs())}', bold: true, c: paid ? green : orange, right: true),
        cell(paid ? 'Profit' : 'Payback', bold: true, c: paid ? green : orange),
      ],
    ));
  }

  // Page 1: summary, system, cost
  final page1 = pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(top: 0, bottom: 24),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      header(
        'Solar System Engineering & Financial Proposal',
        'Site: ${i.site.isEmpty ? '-' : i.site}\n'
            'Standard: ${i.standard} | Category: ${i.category} | Ref: $ref\n'
            'Architecture: ${i.architecture.toUpperCase()} | Inverter: ${i.inverter} (${i.phase})',
      ),
      pw.Container(height: 4, color: orange),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(36, 14, 36, 0),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            kpi('SYSTEM CAPACITY', '${fmt1(i.panelKwp)} kW', '${i.panelCount} panels', blue),
            kpi('INVERTER & PHASE', i.inverter.split(' ').take(2).join(' '), i.phase, orange),
            kpi('NET INVESTMENT', inr(r.netCost), r.subsidy > 0 ? 'After ${inr(r.subsidy)} DBT' : 'No subsidy', orange),
            kpi('BREAK-EVEN / ${r.years}-YR', r.paybackYears == null ? '-' : '${fmt1(r.paybackYears!)} Yrs', '${r.years}-Yr profit ${inr(r.lifetimeProfit)}', green),
          ]),
          sectionTitle('1. Solar Array, Inverter Engineering & Site Profile'),
          for (var k = 0; k < sysRows.length; k++)
            row(sysRows[k][0], sysRows[k][1], vc: k == 7 ? green : null, idx: k),
          if (i.sizingNote.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: mint, border: pw.Border.all(color: green), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(i.sizingNote, style: pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF065F46))),
            ),
          ],
          sectionTitle('2. Cost Breakdown, Subsidy & Environmental Impact'),
          for (var k = 0; k < cashRows.length; k++)
            row(cashRows[k][0], cashRows[k][1], vc: k == 2 ? orange : (k == 1 && r.subsidy > 0 ? green : null), idx: k),
          pw.SizedBox(height: 4),
          pw.Text(i.standard.contains('DCR') ? 'Subsidy: PM Surya Ghar central DBT for DCR modules, paid into the consumer account after commissioning.' : 'Non-DCR modules: no government subsidy applies.',
              style: pw.TextStyle(fontSize: 7.5, color: mute)),
        ]),
      ),
      pw.Spacer(),
      footer(ctx),
    ]),
  );

  // Page 2: charts, cashflow table, EMI
  final page2 = pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(top: 0, bottom: 24),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        color: navy,
        padding: const pw.EdgeInsets.fromLTRB(36, 14, 36, 12),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Solar Proposal — ${fmt1(i.panelKwp)} kW ${i.standard.contains('DCR') ? 'DCR' : 'Non-DCR'} (${i.architecture.toUpperCase()})', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(i.site.isEmpty ? '' : i.site, style: pw.TextStyle(color: PdfColor.fromInt(0xFFD1D5DB), fontSize: 8.5)),
        ]),
      ),
      pw.Container(height: 4, color: orange),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(36, 6, 36, 0),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sectionTitle('3. 12-Month Consumption vs. Projected Solar Generation'),
          pw.Row(children: [
            legend(amberBar, 'Grid Usage (kWh)'),
            legend(green, 'Projected Solar Yield (kWh)'),
            pw.Spacer(),
            pw.Text('Annual Solar Offset: ${(r.gen1 / math.max(1, r.annualUse) * 100).round()}%', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: green)),
          ]),
          pw.SizedBox(height: 8),
          monthChart(),
          sectionTitle('4. ${r.years}-Year Cumulative Cashflow & Break-Even Trajectory'),
          pw.Row(children: [
            legend(amberBar, 'Payback Phase'),
            legend(green, 'Net Profit Phase'),
            legend(red, 'Break-Even Capex (${inr(r.netCost)})'),
          ]),
          pw.SizedBox(height: 8),
          cashChart(),
          pw.SizedBox(height: 16),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(1.3),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FlexColumnWidth(1.4),
              5: const pw.FlexColumnWidth(0.9),
            },
            children: tableRows,
          ),
          sectionTitle('5. Indicative Solar Loan / EMI vs. Monthly Savings (80% Financed @ 9.9% p.a.)'),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: navy),
                children: [
                  for (final t in ['Tenure', 'Loan Amount (80%)', 'Monthly EMI', 'Monthly Savings', 'Net Cash Impact'])
                    cell(t, bold: true, c: PdfColors.white),
                ],
              ),
              for (final t in tenureRows)
                pw.TableRow(children: [
                  cell(t[0], bold: true),
                  cell(t[1], right: true),
                  cell(t[2], right: true),
                  cell(t[3], right: true),
                  cell(t[4], bold: true, c: t[4].startsWith('-') ? orange : green, right: true),
                ]),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Illustrative down payment (20%): ${inr(r.netCost * 0.2)} · Net-positive cashflow indicates solar savings fully cover EMI.',
              style: pw.TextStyle(fontSize: 7.5, color: mute)),
        ]),
      ),
      pw.Spacer(),
      footer(ctx),
    ]),
  );

  // Page 3: BOM, omitted items, warranty
  final bom = i.bom;
  final page3 = pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.only(top: 0, bottom: 24),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        color: navy,
        padding: const pw.EdgeInsets.fromLTRB(36, 14, 36, 12),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Solar Proposal — ${fmt1(i.panelKwp)} kW ${i.standard.contains('DCR') ? 'DCR' : 'Non-DCR'} (${i.architecture.toUpperCase()})', style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(i.site.isEmpty ? '' : i.site, style: pw.TextStyle(color: PdfColor.fromInt(0xFFD1D5DB), fontSize: 8.5)),
        ]),
      ),
      pw.Container(height: 4, color: orange),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(36, 6, 36, 0),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sectionTitle('Bill of Materials (BOM) — ${i.architecture} (${i.standard})'),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(3.4),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FlexColumnWidth(0.9),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: navy),
                children: [
                  for (final t in ['Category', 'Component & Technical Specification', 'Quantity', 'Status'])
                    cell(t, bold: true, c: PdfColors.white),
                ],
              ),
              for (final b in bom)
                pw.TableRow(
                  decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: line))),
                  children: [
                    cell(b[0], bold: true),
                    cell(b[1]),
                    cell(b[2], bold: true),
                    cell(b[3], bold: true, c: green),
                  ],
                ),
            ],
          ),
          if (i.batteryKwh <= 0 && i.architecture == 'On-Grid') ...[
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              color: tint,
              child: pw.Text('Omitted for ${i.architecture.toUpperCase()} mode: Battery Storage Bank (0 kWh) · Battery BMS Harness & DC Breaker (MCCB) · Battery Mounting Rack',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: mute)),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('WARRANTY ASSURANCE & PROPOSAL ACCEPTANCE', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('Modules: 25-Yr Linear Output Warranty (≥84% Year 25)  |  Inverter: 7–10 Yr OEM Replacement Warranty  |  MMS & BOS: 5-Yr Workmanship',
                  style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF374151))),
              pw.SizedBox(height: 36),
              pw.Row(children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(height: 0.6, color: mute),
                    pw.SizedBox(height: 3),
                    pw.Text(brand.company.isEmpty ? 'Prepared By: Solar Project Engineer' : 'Prepared By: ${brand.company}', style: pw.TextStyle(fontSize: 7.5, color: mute)),
                  ]),
                ),
                pw.SizedBox(width: 30),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(height: 0.6, color: mute),
                    pw.SizedBox(height: 3),
                    pw.Text('Client Acceptance: Authorized Signatory & Date', style: pw.TextStyle(fontSize: 7.5, color: mute)),
                  ]),
                ),
              ]),
            ]),
          ),
          if (brand.note.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(brand.note, style: pw.TextStyle(fontSize: 7.5, color: mute)),
          ],
        ]),
      ),
      pw.Spacer(),
      footer(ctx),
    ]),
  );

  doc.addPage(page1);
  doc.addPage(page2);
  doc.addPage(page3);
  return doc.save();
}

Future<void> shareQuote(Customer c, EstimateResult r, Brand brand, {QuoteInfo? info}) async {
  final bytes = await buildQuotePdf(c, r, brand, info: info);
  final safe = (c.usc.isNotEmpty ? c.usc : (c.name.isNotEmpty ? c.name : 'quote')).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: 'Solar-Proposal-$safe.pdf');
}
