import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/receipt_parser.dart';

void main() {
  final today = DateTime(2026, 9, 23);

  test('Best Buy receipt: store, date, item, total, return window and protection plan', () {
    final r = parseReceipt('''
BEST BUY
Store 942  Montreal QC
09/20/2026  14:32
6515876  SAMSUNG 65" QN90A TV  1799.99
4 YR PROTECTION PLAN  249.99
SUBTOTAL  2049.98
GST 5%  102.50
QST 9.975%  204.49
TOTAL  2356.97
VISA  2356.97
Returns accepted within 15 days of purchase.
''', today: today);
    expect(r.retailer, 'Best Buy');
    expect(r.date, DateTime(2026, 9, 20));
    expect(r.lines.map((l) => l.description), ['SAMSUNG 65" QN90A TV', '4 YR PROTECTION PLAN']);
    expect(r.lines.first.price, 1799.99);
    expect(r.total, 2356.97);
    expect(r.returnDays, 15);
    expect(r.warrantyMonths, 48);
  });

  test('French receipt: comma decimals, French date and return policy, taxes skipped', () {
    final r = parseReceipt('''
Brault & Martineau
Laval (Québec)
22 sept. 2026
Laveuse Whirlpool WFW5620HW   1 049,99 \$
Livraison   79,00 \$
Sous-total   1 128,99 \$
TPS   56,45 \$
TVQ   112,62 \$
Total   1 298,06 \$
Retour accepté dans les 30 jours
Garantie du fabricant 1 an
''', today: today);
    expect(r.retailer, 'Brault & Martineau');
    expect(r.date, DateTime(2026, 9, 22));
    expect(r.lines.first.description, 'Laveuse Whirlpool WFW5620HW');
    expect(r.lines.first.price, 1049.99);
    expect(r.total, 1298.06);
    expect(r.returnDays, 30);
    expect(r.warrantyMonths, 12);
  });

  test('ambiguous numeric dates prefer month-first unless that is in the future', () {
    expect(parseReceiptDate('03/04/2026', today: today), DateTime(2026, 3, 4));
    expect(parseReceiptDate('22/09/2026', today: today), DateTime(2026, 9, 22)); // day-first: 22 can't be a month
    expect(parseReceiptDate('12/09/2026', today: today), DateTime(2026, 9, 12)); // Dec 9 is in the future
    expect(parseReceiptDate('2026-09-01'), DateTime(2026, 9, 1));
    expect(parseReceiptDate('Sep 5, 2026', today: today), DateTime(2026, 9, 5));
    expect(parseReceiptDate('no date here'), isNull);
  });

  test('"Return by" date becomes a window in days', () {
    final r = parseReceipt('IKEA\n2026-09-01\nKALLAX shelf 119.00\nReturn by 2026-10-31', today: today);
    expect(r.retailer, 'IKEA');
    expect(r.returnDays, 60);
  });

  test('discounts, payment and deposit lines are not items', () {
    final r = parseReceipt('''
Costco
DYSON V15 DETECT  949.99
INSTANT SAVINGS  -150.00
ECO FEE  1.50
MASTERCARD  801.49
CHANGE  0.00
''', today: today);
    expect(r.lines.map((l) => l.description), ['DYSON V15 DETECT']);
  });

  test('unknown store: the first mostly-letters line at the top', () {
    final r = parseReceipt('La Boutique du Coin\n123 rue Principale\nLampe de table 45.00', today: today);
    expect(r.retailer, 'La Boutique du Coin');
  });

  group('choosing the line for this item', () {
    const lines = [ReceiptLine('SAMSUNG 65" QN90A TV', 1799.99), ReceiptLine('HDMI CABLE 2M', 29.99)];

    test('matches the name or model the user has', () {
      expect(pickLine(lines, name: 'Samsung TV')!.price, 1799.99);
      expect(pickLine(lines, model: 'QN90A')!.price, 1799.99);
      expect(pickLine(lines, name: 'hdmi cable')!.price, 29.99);
    });

    test('a single line is the item; several with no match means ask', () {
      expect(pickLine([lines.first])!.price, 1799.99);
      expect(pickLine(lines), isNull);
      expect(pickLine(const []), isNull);
    });
  });
}
