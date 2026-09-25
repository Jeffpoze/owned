import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/dates.dart';
import 'package:owned/domain/export.dart';
import 'package:owned/domain/handoff.dart';
import 'package:owned/domain/models.dart';
import 'package:owned/domain/valuation.dart';
import 'package:owned/domain/warranty.dart';

final now = DateTime(2026, 9, 25);

Item bulbs({int quantity = 3, double? price = 2.99, int monthsAgo = 0}) => Item(
  id: 'b',
  name: 'LED light bulb',
  category: Category.other,
  price: price,
  quantity: quantity,
  acquired: toIsoDate(addMonths(now, -monthsAgo)),
  createdAt: 0,
);

void main() {
  test('total price is price each times quantity', () {
    expect(bulbs().totalPrice, closeTo(8.97, 1e-9));
    expect(bulbs(quantity: 1).totalPrice, 2.99);
    expect(bulbs(price: null).totalPrice, isNull);
  });

  test('items saved before quantities existed are a single item', () {
    final j = bulbs().toJson()..remove('quantity');
    expect(Item.fromJson(j).quantity, 1);
    expect(Item.fromJson({...bulbs().toJson(), 'quantity': 0}).quantity, 1);
    expect(Item.fromJson(bulbs(quantity: 4).toJson()).quantity, 4);
  });

  test('copyWith keeps or changes the quantity', () {
    expect(bulbs().copyWith(name: 'Bulb').quantity, 3);
    expect(bulbs().copyWith(quantity: 6).quantity, 6);
  });

  test('value and search count all of them', () {
    // Bought today: worth what was paid, for all three.
    expect(valueEstimate(bulbs(), now), closeTo(8.97, 1e-9));
    expect(estimatedValue(bulbs()), closeTo(8.97, 1e-9));
    // The same as one item bought for the total.
    final one = Item(
      id: 'o',
      category: Category.other,
      price: 3000,
      acquired: toIsoDate(addMonths(now, -12)),
      createdAt: 0,
    );
    final three = one.copyWith(price: 1000, quantity: 3);
    expect(valueEstimate(three, now), valueEstimate(one, now));
  });

  test('CSV has the quantity and the total', () {
    final lines = inventoryCsv([bulbs()], now).split('\n');
    final header = lines[0].split(',');
    final row = lines[1].split(',');
    expect(row[header.indexOf('price')], '2.99');
    expect(row[header.indexOf('quantity')], '3');
    expect(
      double.parse(row[header.indexOf('totalPrice')]),
      closeTo(8.97, 1e-9),
    );
  });

  test('handoff sheet mentions the quantity and both prices', () {
    final sheet = handoffSheet(bulbs(), now);
    expect(sheet, contains('Quantity: 3'));
    expect(sheet, contains(r'Original price: $2.99 each, $8.97 for 3'));
    expect(handoffSheet(bulbs(quantity: 1), now), isNot(contains('Quantity')));
  });
}
