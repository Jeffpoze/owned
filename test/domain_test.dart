import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/constants.dart';
import 'package:owned/domain/dates.dart';
import 'package:owned/domain/example.dart';
import 'package:owned/domain/models.dart';
import 'package:owned/domain/search.dart';
import 'package:owned/domain/warranty.dart';

void main() {
  final now = DateTime(2026, 9, 22);
  final items = exampleItems(now);
  List<String> ids(List<Item> l) => l.map((i) => i.id).toList();

  test('warranty states on the example home', () {
    final states = {for (final i in items) i.id: warranty(i, now).state};
    expect(states, {
      'x1': WarrantyState.documented,
      'x2': WarrantyState.documented,
      'x3': WarrantyState
          .estimated, // used: counts from the original purchase, typical length
      'x4': WarrantyState.estimated, // used, original purchase unknown
      'x5': WarrantyState.unknown,
      'x6': WarrantyState.unknown,
      'x7': WarrantyState.estimated,
      'x8': WarrantyState.verified,
      'x9': WarrantyState.expired,
      'x10': WarrantyState.unknown,
    });
  });

  test('used item never counts from the date the user got it', () {
    final macbook = items.firstWhere((i) => i.id == 'x4');
    final w = warranty(macbook, now);
    expect(w.end, isNull);
    expect(w.fix, 'Add the original purchase date');
  });

  test('filters', () {
    // x3 is used and its transfer is unknown, so the app can't say it's covered.
    expect(ids(applyFilter(items, ItemFilter.covered, now)), [
      'x1',
      'x2',
      'x7',
      'x8',
    ]);
    expect(ids(applyFilter(items, ItemFilter.expiring, now)), ['x2']);
    expect(ids(applyFilter(items, ItemFilter.returns, now)), ['x7']);
    expect(ids(applyFilter(items, ItemFilter.noreceipt, now)), ['x5', 'x7']);
    expect(ids(applyFilter(items, ItemFilter.maint, now)), ['x1', 'x8']);
    expect(ids(applyFilter(items, ItemFilter.used, now)), ['x3', 'x4']);
  });

  test('plain-language search', () {
    void check(String q, List<String> tags, List<String> expected) {
      final r = runQuery(items, q, now);
      expect(r.tags, tags, reason: q);
      expect(ids(r.list)..sort(), [...expected]..sort(), reason: q);
    }

    check('everything I bought from IKEA', ['From Ikea'], ['x5', 'x6']);
    check('what appliances do I have', ['Appliance'], ['x1', 'x8']);
    check(
      'which things are still under warranty',
      ['Under warranty'],
      ['x1', 'x2', 'x7', 'x8'],
    );
    check('no receipt', ['Missing receipt'], ['x5', 'x7']);
    check(
      'tvs in the living room',
      ['In Living Room', 'Electronics'],
      ['x2', 'x9'],
    );
    check(r'over $1000', [r'Over $1,000'], ['x1', 'x2', 'x4', 'x9']);
  });

  test('dates', () {
    expect(addMonths(DateTime(2025, 1, 31), 1), DateTime(2025, 2, 28));
    expect(span(22), '22 days');
    expect(span(800), '2 years 2 mo');
    expect(money(1799.99), r'$1,799.99');
    expect(money(2899), r'$2,899');
  });
}
