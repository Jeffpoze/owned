import 'constants.dart';
import 'dates.dart';
import 'models.dart';
import 'warranty.dart';

const _transferText = {
  Transfer.transferable: 'yes',
  Transfer.conditional: 'with proof of original purchase',
  Transfer.non: 'no',
};

/// Plain-text summary to hand to a buyer: identity, original purchase, warranty and documents.
String handoffSheet(Item it, [DateTime? now]) {
  final w = warranty(it, now);
  final originalDate = (it.originalPurchase?.isNotEmpty ?? false)
      ? it.originalPurchase
      : (it.isNew ? it.acquired : null);
  final originalStore = it.originalRetailer.isNotEmpty
      ? it.originalRetailer
      : (it.isNew ? it.retailer : '');
  final purchase = formatDate(parseDate(originalDate));

  return [
    it.name,
    if (it.quantity > 1) 'Quantity: ${it.quantity}',
    if (it.brand.isNotEmpty) 'Brand: ${it.brand}',
    if (it.model.isNotEmpty) 'Model: ${it.model}',
    if (it.serial.isNotEmpty) 'Serial: ${it.serial}',
    '',
    if ((it.originalPurchase?.isNotEmpty ?? false) || it.isNew)
      'Original purchase: ${purchase.isEmpty ? 'unknown' : purchase}${originalStore.isNotEmpty ? ', $originalStore' : ''}',
    if (it.isNew && (it.price ?? 0) > 0)
      it.quantity > 1
          ? 'Original price: ${money(it.price)} each, ${money(it.totalPrice)} for ${it.quantity}'
          : 'Original price: ${money(it.price)}',
    w.end != null
        ? 'Warranty: ${w.state == WarrantyState.expired ? 'ended' : 'potentially valid until'} ${formatDate(w.end)} (${stateLabel[w.state]!.toLowerCase()})'
        : 'Warranty: ${w.months > 0 ? '${w.months} months, start date unknown' : 'unknown'}',
    if (it.transfer != Transfer.unknown)
      'Transferable: ${_transferText[it.transfer]}',
    '',
    'Documents:',
    if (it.evidence.isEmpty)
      'None saved'
    else
      for (final e in it.evidence) '✓ ${evidenceInfo[e.kind]!.label}',
  ].join('\n');
}
