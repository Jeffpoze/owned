import 'dates.dart';
import 'models.dart';

/// How a kind of item typically loses value on the resale market: a drop when it
/// stops being new, then a yearly rate, never below a floor share of the price paid.
/// Rough, rule-based figures; the user's own "value now" always wins over them.
class DepreciationCurve {
  const DepreciationCurve({
    required this.firstDrop,
    required this.yearly,
    required this.floor,
  });

  /// Share lost over the first year, as it stops being new.
  final double firstDrop;

  /// Share of the remaining value lost each year after that.
  final double yearly;

  /// The estimate never goes below this share of the price paid.
  final double floor;
}

const depreciationCurves = <Category, DepreciationCurve>{
  // TVs, phones, laptops: new models push old ones down fast.
  Category.electronics: DepreciationCurve(
    firstDrop: 0.30,
    yearly: 0.20,
    floor: 0.10,
  ),
  Category.appliance: DepreciationCurve(
    firstDrop: 0.25,
    yearly: 0.12,
    floor: 0.15,
  ),
  Category.smarthome: DepreciationCurve(
    firstDrop: 0.35,
    yearly: 0.25,
    floor: 0.05,
  ),
  Category.furniture: DepreciationCurve(
    firstDrop: 0.30,
    yearly: 0.08,
    floor: 0.20,
  ),
  Category.kitchen: DepreciationCurve(
    firstDrop: 0.30,
    yearly: 0.10,
    floor: 0.15,
  ),
  Category.tools: DepreciationCurve(firstDrop: 0.20, yearly: 0.08, floor: 0.25),
  // Instruments and sports gear hold their value well.
  Category.gear: DepreciationCurve(firstDrop: 0.15, yearly: 0.04, floor: 0.45),
  Category.other: DepreciationCurve(firstDrop: 0.25, yearly: 0.10, floor: 0.15),
};

/// What the item would likely sell for today, estimated from the price paid, when it
/// was bought and its kind, for all of them when the record covers several.
/// Null when there's no price or no date to work from.
/// Items bought used were already second-hand, so they skip the first drop.
/// Rounded to the nearest $5 (or $1 under $50): it's an estimate, not a quote.
double? valueEstimate(Item it, [DateTime? now]) {
  final price = it.totalPrice ?? 0;
  final bought = parseDate(it.acquired);
  if (price <= 0 || bought == null) return null;
  final curve = depreciationCurves[it.category]!;
  final years = daysBetween(bought, now ?? today()).clamp(0, 1 << 30) / 365.25;
  if (years <= 0) return price;
  final double share;
  if (it.acquisition == Acquisition.used) {
    // Already second-hand: only the yearly rate applies.
    share = _pow(1 - curve.yearly, years);
  } else {
    // The first drop builds up over the first year, then the yearly rate takes over.
    final first = 1 - curve.firstDrop * (years < 1 ? years : 1);
    share = first * _pow(1 - curve.yearly, years > 1 ? years - 1 : 0);
  }
  final v = price * (share < curve.floor ? curve.floor : share);
  final step = v < 50 ? 1 : 5;
  return ((v / step).round() * step).toDouble();
}

double _pow(double base, double exp) {
  // Fractional power without dart:math, to keep domain code dependency-free.
  var result = 1.0;
  var whole = exp.floor();
  for (var i = 0; i < whole; i++) {
    result *= base;
  }
  final frac = exp - whole;
  // Linear between whole years is plenty for an estimate.
  return result * (1 - (1 - base) * frac);
}

/// The item's value now: the user's own figure if they set one, otherwise the estimate.
double currentValue(Item it, [DateTime? now]) =>
    (it.value ?? 0) > 0 ? it.value! : (valueEstimate(it, now) ?? 0);
