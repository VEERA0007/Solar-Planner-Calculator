/// Reads units and bill amounts out of the text of a DISCOM bill page.
/// DISCOM portals differ a lot, so this looks for common patterns: a month
/// followed by units (and an amount), and labelled "units" / "amount" values.
class BillRow {
  final int year, month; // month 1-12
  final double units;
  final double? amount;
  const BillRow(this.year, this.month, this.units, this.amount);
  int get key => year * 12 + month - 1;
}

class BillParse {
  final List<BillRow> rows;
  final String? usc, name;
  final double? latestUnits, latestAmount;
  const BillParse(this.rows, this.usc, this.name, this.latestUnits, this.latestAmount);
  bool get found => rows.isNotEmpty || latestUnits != null;
}

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

double? _num(String s) => double.tryParse(s.replaceAll(',', ''));

int _year(String y) {
  final v = int.parse(y);
  return v < 100 ? 2000 + v : v;
}

BillParse parseBillText(String text) {
  final lines = text.replaceAll('\r', '\n').split('\n').map((l) => l.replaceAll(RegExp(r'[\t ]+'), ' ').replaceAll(RegExp(r' {2,}'), ' ').trim()).where((l) => l.isNotEmpty).toList();
  final rows = <int, BillRow>{};
  final monthRe = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s\-/,.]*((?:20)?\d{2})\b', caseSensitive: false);
  final numRe = RegExp(r'(?<![\d/\-.])(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?(?![\d/\-])');
  final slashRe = RegExp(r'\b(0?[1-9]|1[0-2])[/\-](20\d{2})\b');

  for (final l in lines) {
    int? m, y;
    String rest = l;
    final a = monthRe.firstMatch(l);
    if (a != null) {
      m = _months[a.group(1)!.toLowerCase()];
      y = _year(a.group(2)!);
      rest = l.substring(a.end);
    } else {
      final b = slashRe.firstMatch(l);
      if (b != null) {
        m = int.parse(b.group(1)!);
        y = int.parse(b.group(2)!);
        rest = l.substring(b.end);
      }
    }
    if (m == null || y == null || y < 2015 || y > 2100) continue;
    final nums = <double>[];
    for (final x in numRe.allMatches(rest)) {
      final v = _num('${x.group(1)}${x.group(2) ?? ''}');
      if (v != null) nums.add(v);
    }
    if (nums.isEmpty) continue;
    final units = nums.first;
    if (units <= 0 || units > 100000) continue;
    final amount = nums.length > 1 ? nums[1] : null;
    final r = BillRow(y, m, units, amount);
    rows.putIfAbsent(r.key, () => r);
  }

  double? labelled(RegExp re) {
    for (final l in lines) {
      final x = re.firstMatch(l);
      if (x != null) {
        final v = _num(x.group(x.groupCount)!);
        if (v != null) return v;
      }
    }
    return null;
  }

  final units = labelled(RegExp(r'(?:units?\s*consumed|consumption|total\s*units?|units?\s*billed|kwh)[^0-9\n]{0,30}(\d[\d,]*\.?\d*)', caseSensitive: false));
  final amount = labelled(RegExp(r'(?:total\s*bill\s*amount|bill\s*amount|net\s*amount|amount\s*payable|total\s*amount|current\s*demand)[^0-9\n]{0,30}(\d[\d,]*\.?\d*)', caseSensitive: false));
  String? usc;
  for (final l in lines) {
    final x = RegExp(r'(?:usc|service\s*(?:no|number)|consumer\s*(?:no|number)|scno)[^0-9]{0,25}(\d{8,12})', caseSensitive: false).firstMatch(l);
    if (x != null) {
      usc = x.group(1);
      break;
    }
  }
  String? name;
  for (final l in lines) {
    final x = RegExp(r'(?:consumer\s*name|customer\s*name|name)\s*[:\-]\s*([A-Za-z][A-Za-z .]{2,40})', caseSensitive: false).firstMatch(l);
    if (x != null) {
      name = x.group(1)!.trim();
      break;
    }
  }
  final list = rows.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  return BillParse(list, usc, name, units != null && units > 0 && units < 100000 ? units : null, amount);
}
