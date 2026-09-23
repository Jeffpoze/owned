/// Reads a purchase from a receipt's recognised text: store, date, item lines,
/// total, return window and warranty. Pure rules, no AI; English and French.
library;

import 'dates.dart';

class ReceiptLine {
  const ReceiptLine(this.description, this.price);
  final String description;
  final double price;
}

class ReceiptFields {
  const ReceiptFields({
    this.retailer,
    this.date,
    this.lines = const [],
    this.total,
    this.returnDays,
    this.warrantyMonths,
  });

  final String? retailer;
  final DateTime? date;

  /// Merchandise only: no tax, totals or payment lines.
  final List<ReceiptLine> lines;
  final double? total;
  final int? returnDays;
  final int? warrantyMonths;

  bool get isEmpty =>
      retailer == null &&
      date == null &&
      lines.isEmpty &&
      total == null &&
      returnDays == null &&
      warrantyMonths == null;
}

/// Stores we can name from anywhere on the receipt, in their usual spelling.
const knownRetailers = [
  'Best Buy',
  'Walmart',
  'Costco',
  'Home Depot',
  'IKEA',
  'Amazon',
  'Target',
  'Canadian Tire',
  'Staples', //
  'Apple Store',
  'The Brick',
  "Lowe's",
  'London Drugs',
  'Visions Electronics',
  "Leon's",
  'Structube',
  'RONA',
  'Home Hardware',
  'Bureau en Gros',
  'Brault & Martineau',
  'Tanguay',
  'Linen Chest',
  'Simons',
  "Hudson's Bay",
  'The Source',
  'Sony Store',
  'Samsung',
  'Dyson',
  'Micro Center',
  'B&H',
  'GameStop',
  'EB Games',
  'Sporting Life',
  'Sport Chek',
  'Decathlon',
  'Long & McQuade',
  'Guitar Center',
  'Wayfair',
  'Newegg',
  'Kitchen Stuff Plus',
  'Crate & Barrel',
  'Pottery Barn',
  'Williams Sonoma',
  'Best Buy Canada',
  'Walmart Supercentre',
];

/// Lines that carry a price but aren't merchandise.
final _notMerchandise = RegExp(
  r'\b(sub\s*-?\s*total|total|tax|taxes|tps|tvq|gst|hst|pst|qst|change|monnaie|cash|comptant|visa|master\s*card|'
  r'amex|debit|débit|credit|crédit|balance|solde|tip|pourboire|savings|économies|you saved|points|rounding|arrondi|'
  r'payment|paiement|tendered|reçu|montant|amount due|eco\s*fee|écofrais|ehf|deposit|consigne)\b',
  caseSensitive: false,
);

final _price = RegExp(
  r'(-)?\$?\s?(\d{1,5}(?:[ ,]\d{3})*[.,]\d{2})\s*\$?\s*[A-Z]{0,3}\s*$',
);

double? _money(String s) {
  var t = s.replaceAll(' ', '');
  // "1,299.99" or "1 299,99" (French)
  if (RegExp(r',\d{2}$').hasMatch(t)) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  return double.tryParse(t);
}

const _months = {
  'jan': 1,
  'janv': 1,
  'january': 1,
  'janvier': 1,
  'feb': 2,
  'fev': 2,
  'fév': 2,
  'févr': 2,
  'february': 2, //
  'février': 2,
  'fevrier': 2,
  'mar': 3,
  'mars': 3,
  'march': 3,
  'apr': 4,
  'avr': 4,
  'april': 4,
  'avril': 4,
  'may': 5,
  'mai': 5,
  'jun': 6,
  'juin': 6,
  'june': 6,
  'jul': 7,
  'juil': 7,
  'july': 7,
  'juillet': 7,
  'aug': 8,
  'août': 8,
  'aout': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'septembre': 9,
  'oct': 10,
  'october': 10,
  'octobre': 10,
  'nov': 11,
  'november': 11,
  'novembre': 11,
  'dec': 12,
  'déc': 12,
  'december': 12, 'décembre': 12, 'decembre': 12,
};

DateTime? _valid(int y, int m, int d) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null; // rejects 31 Feb
}

/// Finds the purchase date. Numeric dates like 03/04/2026 are ambiguous: day-first is used when the
/// month-first reading would be in the future or is impossible.
DateTime? parseReceiptDate(String text, {DateTime? today}) {
  final now = today ?? DateTime.now();
  bool future(DateTime d) => d.isAfter(now.add(const Duration(days: 1)));

  // 2026-09-22 or 2026/09/22
  final iso = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b')
      .firstMatch(text);
  if (iso != null) {
    final d = _valid(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
    );
    if (d != null) return d;
  }

  // Sep 22, 2026 / 22 Sep 2026 / 22 sept. 2026
  final named = RegExp(
    r'\b(?:(\d{1,2})\s+([a-zéû]{3,9})\.?,?\s+(\d{2,4})|([a-zéû]{3,9})\.?\s+(\d{1,2}),?\s+(\d{2,4}))\b',
    caseSensitive: false,
  );
  for (final m in named.allMatches(text)) {
    final monthWord = (m[2] ?? m[4])!.toLowerCase();
    final month = _months[monthWord];
    if (month == null) continue;
    final d = _valid(
      int.parse((m[3] ?? m[6])!),
      month,
      int.parse((m[1] ?? m[5])!),
    );
    if (d != null && !future(d)) return d;
  }

  // 09/22/2026, 22/09/2026, 09-22-26
  for (final m in RegExp(
    r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b',
  ).allMatches(text)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
    final monthFirst = _valid(y, a, b);
    final dayFirst = _valid(y, b, a);
    if (monthFirst != null && !future(monthFirst)) return monthFirst;
    if (dayFirst != null && !future(dayFirst)) return dayFirst;
  }
  return null;
}

String? _retailer(List<String> lines) {
  final all = lines.join('\n').toLowerCase();
  String? best;
  var bestAt = 1 << 30;
  for (final r in knownRetailers) {
    final at = all.indexOf(r.toLowerCase());
    // Prefer the earliest mention; "Best Buy Canada" over "Best Buy" when both start at the same place.
    if (at >= 0 && (at < bestAt || (at == bestAt && r.length > best!.length))) {
      best = r;
      bestAt = at;
    }
  }
  if (best != null) return best;
  // Otherwise the store name is usually the first line of mostly letters at the top.
  for (final l in lines.take(4)) {
    final letters = l.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
    if (letters.length >= 3 &&
        letters.length >= l.replaceAll(' ', '').length * 0.7 &&
        !_notMerchandise.hasMatch(l)) {
      return l.trim();
    }
  }
  return null;
}

int? _returnDays(String text, DateTime? purchased) {
  final t = text.toLowerCase();
  final days = RegExp(
    r'(\d{1,3})[\s-]*(?:day|days|jours?)\s*(?:return|refund|exchange|retour|remboursement|échange)'
    r'|(?:return|refund|exchange|retour|remboursement|échange)s?[^.\n]{0,40}?(?:within|in|dans les|sous|de)\s*(\d{1,3})\s*(?:days|jours)',
  ).firstMatch(t);
  if (days != null) return int.parse((days[1] ?? days[2])!);
  // "Return by 10/22/2026"
  final by = RegExp(
    r'(?:return|retour)[^\n]{0,20}?(?:by|avant le|before|jusqu.au)\s*([^\n]{6,20})',
  ).firstMatch(t);
  if (by != null && purchased != null) {
    final end = parseReceiptDate(by[1]!, today: DateTime(2100));
    if (end != null && end.isAfter(purchased)) {
      return daysBetween(purchased, end);
    }
  }
  return null;
}

int? _warrantyMonths(String text) {
  final t = text.toLowerCase();
  final m = RegExp(
    r'(\d{1,2})[\s-]*(year|yr|years|yrs|ans?|month|months|mo|mois)\b[^\n]{0,30}?(?:warranty|protection|garantie|plan)'
    r'|(?:warranty|garantie|protection)[^\n]{0,20}?(\d{1,2})[\s-]*(year|yr|years|yrs|ans?|month|months|mo|mois)\b',
  ).firstMatch(t);
  if (m == null) return null;
  final n = int.parse((m[1] ?? m[3])!);
  final unit = (m[2] ?? m[4])!;
  return unit.startsWith('y') || unit.startsWith('an') ? n * 12 : n;
}

ReceiptFields parseReceipt(String text, {DateTime? today}) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final items = <ReceiptLine>[];
  double? total;

  for (final line in lines) {
    final m = _price.firstMatch(line);
    if (m == null) continue;
    final amount = _money(m[2]!);
    if (amount == null || m[1] == '-') continue; // discounts and refunds
    final label = line.substring(0, m.start).trim();
    final lower = label.toLowerCase();
    if (RegExp(r'\btotal\b').hasMatch(lower) &&
        !RegExp(r'sub\s*-?\s*total|sous-total').hasMatch(lower)) {
      total = amount; // the last TOTAL line wins (after tax)
      continue;
    }
    if (_notMerchandise.hasMatch(label) ||
        RegExp(r'sous-total').hasMatch(lower)) {
      continue;
    }
    // Item names have letters; skip SKU-only or quantity lines.
    final desc = label
        .replaceAll(RegExp(r'^\d{5,}\s+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (RegExp(r'[A-Za-zÀ-ÿ]{3,}').hasMatch(desc)) {
      items.add(ReceiptLine(desc, amount));
    }
  }

  final date = parseReceiptDate(text, today: today);
  return ReceiptFields(
    retailer: _retailer(lines),
    date: date,
    lines: items.take(15).toList(),
    total: total,
    returnDays: _returnDays(text, date),
    warrantyMonths: _warrantyMonths(text),
  );
}

/// The receipt line that is most likely this item: one whose words match the name or model
/// the user already has, else the only line, else the most expensive one.
ReceiptLine? pickLine(
  List<ReceiptLine> lines, {
  String name = '',
  String model = '',
}) {
  if (lines.isEmpty) return null;
  final words = '$name $model'
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 2)
      .toSet();
  if (words.isNotEmpty) {
    ReceiptLine? best;
    var bestHits = 0;
    for (final l in lines) {
      final d = l.description.toLowerCase();
      final hits = words.where(d.contains).length;
      if (hits > bestHits) {
        best = l;
        bestHits = hits;
      }
    }
    if (best != null) return best;
  }
  if (lines.length == 1) return lines.first;
  return null; // several lines and nothing to match: ask the user
}
