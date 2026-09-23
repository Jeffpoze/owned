import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/dates.dart';
import 'package:owned/domain/models.dart';
import 'package:owned/domain/valuation.dart';

final now = DateTime(2026, 9, 23);

Item item({
  double? price = 1000,
  double? value,
  Category category = Category.electronics,
  Acquisition acquisition = Acquisition.newItem,
  int monthsAgo = 12,
}) => Item(
  id: 't',
  name: 'Test',
  price: price,
  value: value,
  category: category,
  acquisition: acquisition,
  acquired: toIsoDate(addMonths(now, -monthsAgo)),
  createdAt: 0,
);

void main() {
  test('electronics lose the first drop over year one, then a yearly rate', () {
    // Half a year in, half the 30% first drop: about 850.
    expect(valueEstimate(item(monthsAgo: 6), now), 850);
    // One year: 1000 × 0.70 = 700
    expect(valueEstimate(item(), now), 700);
    // Two years: 1000 × 0.70 × 0.80 = 560
    expect(valueEstimate(item(monthsAgo: 24), now), 560);
  });

  test('a few days after buying, it is still worth almost what was paid', () {
    final tv = Item(
      id: 't',
      price: 1799.99,
      category: Category.electronics,
      acquired: toIsoDate(addDays(now, -3)),
      createdAt: 0,
    );
    expect(valueEstimate(tv, now), greaterThan(1790));
  });

  test('never below the floor for its kind', () {
    // Electronics floor is 10%: a 15-year-old TV bought for 1000 is still ~100.
    expect(valueEstimate(item(monthsAgo: 180), now), 100);
    // Guitars and sports gear hold 45% or more.
    expect(
      valueEstimate(item(category: Category.gear, monthsAgo: 240), now),
      450,
    );
  });

  test('instruments hold value better than electronics', () {
    final guitar = valueEstimate(
      item(category: Category.gear, monthsAgo: 36),
      now,
    )!;
    final tv = valueEstimate(item(monthsAgo: 36), now)!;
    expect(guitar, greaterThan(tv));
  });

  test('items bought used skip the first drop', () {
    expect(
      valueEstimate(item(acquisition: Acquisition.used), now)!,
      greaterThan(valueEstimate(item(), now)!),
    );
    expect(valueEstimate(item(acquisition: Acquisition.used), now), 800);
  });

  test('bought today is worth what was paid', () {
    expect(valueEstimate(item(monthsAgo: 0), now), 1000);
  });

  test('no estimate without a price or a date', () {
    expect(valueEstimate(item(price: null), now), isNull);
    expect(valueEstimate(item(price: 0), now), isNull);
    expect(
      valueEstimate(
        Item(id: 't', price: 500, acquired: null, createdAt: 0),
        now,
      ),
      isNull,
    );
  });

  test("the user's own value always wins", () {
    expect(currentValue(item(value: 1200), now), 1200);
    expect(currentValue(item(), now), 700);
    expect(currentValue(item(price: null), now), 0);
  });

  test('small amounts round to the dollar, larger ones to \$5', () {
    expect(valueEstimate(item(price: 49.99), now), 35); // 49.99 × 0.70 = 34.99
    expect(valueEstimate(item(price: 1799.99), now)! % 5, 0);
  });
}
