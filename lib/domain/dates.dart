import 'package:intl/intl.dart';

import 'models.dart';

/// Midnight today, local time.
DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

IsoDate toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDate(IsoDate? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((p) => p == null || p == 0)) return null;
  return DateTime(parts[0]!, parts[1]!, parts[2]!);
}

/// Adds calendar months, clamping to the end of shorter months (Jan 31 + 1 month = Feb 28).
DateTime addMonths(DateTime d, int months) {
  final firstOfTarget = DateTime(d.year, d.month + months, 1);
  final lastDay = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return DateTime(
    firstOfTarget.year,
    firstOfTarget.month,
    d.day > lastDay ? lastDay : d.day,
  );
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Whole calendar days from [from] to [to], immune to daylight-saving shifts.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String formatDate(DateTime? d) => d == null ? '' : DateFormat.yMMMd().format(d);

/// Human length of time: "12 days", "8 months", "2 years 3 mo".
String span(int days) {
  final a = days.abs();
  if (a < 45) return '$a ${a == 1 ? 'day' : 'days'}';
  final m = (a / 30.44).round();
  if (m < 24) return '$m months';
  final y = m ~/ 12;
  final r = m % 12;
  return '$y ${y == 1 ? 'year' : 'years'}${r > 0 ? ' $r mo' : ''}';
}

final _whole = NumberFormat('#,##0', 'en_US');
final _cents = NumberFormat('#,##0.00', 'en_US');

String money(num? n) {
  if (n == null || n.isNaN) return '';
  return '\$${n % 1 != 0 ? _cents.format(n) : _whole.format(n)}';
}
