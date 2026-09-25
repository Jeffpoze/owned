import 'constants.dart';
import 'dates.dart';
import 'models.dart';
import 'warranty.dart';

String _cell(Object? v) {
  final s = v == null ? '' : '$v';
  return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Inventory as CSV for an insurer.
String inventoryCsv(List<Item> items, [DateTime? now]) {
  const header = [
    'name',
    'brand',
    'model',
    'serial',
    'category',
    'room',
    'acquisition',
    'acquired',
    'price',
    'quantity',
    'totalPrice',
    'retailer', //
    'originalPurchase',
    'value',
    'warrantyMonths',
    'warrantyStatus',
    'warrantyEnds',
    'proof',
    'sold',
  ];
  final rows = items.map((i) {
    final w = warranty(i, now);
    final j = i.toJson();
    return [
      i.name,
      i.brand,
      i.model,
      i.serial,
      categoryOf(i).label,
      i.room,
      j['acquisition'],
      i.acquired,
      i.price, //
      i.quantity,
      i.totalPrice,
      i.retailer,
      i.originalPurchase,
      i.value,
      i.warrantyMonths,
      stateLabel[w.state],
      w.end == null ? '' : toIsoDate(w.end!),
      i.evidence.map((e) => evidenceInfo[e.kind]!.label).join('; '),
      i.sold ? 'yes' : '',
    ].map(_cell).join(',');
  });
  return [header.join(','), ...rows].join('\n');
}
