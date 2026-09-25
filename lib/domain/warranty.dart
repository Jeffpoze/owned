import 'constants.dart';
import 'dates.dart';
import 'models.dart';

/// True when the item has at least one piece of proof at [level] or stronger.
bool hasEvidence(Item it, ProofStrength level) =>
    it.evidence.any((e) => evidenceInfo[e.kind]!.strength.index >= level.index);

class WarrantyInfo {
  WarrantyState state = WarrantyState.unknown;
  int months = 0;

  /// Bought used or received as a gift.
  bool used = false;

  /// Plain-language reason for the state.
  String why = '';

  /// Transferability note for used and gifted items.
  String? caveat;

  /// What the user can add to make the status exact.
  String? fix;
  DateTime? start;
  DateTime? end;

  /// Days until the end date; negative once expired.
  int? days;
}

/// Warranty status. The warranty always counts from the ORIGINAL purchase:
/// for used and gifted items the date the user got it is never used as the start.
WarrantyInfo warranty(Item it, [DateTime? now]) {
  now ??= today();
  final out = WarrantyInfo()
    ..months = it.warrantyMonths ?? 0
    ..used = !it.isNew;
  final used = out.used;

  if (used) {
    out.caveat = switch (it.transfer) {
      Transfer.non => "The manufacturer ties this warranty to the original buyer, so it likely doesn't cover you.",
      Transfer.conditional => 'Coverage may continue, but the manufacturer asks for proof of the original purchase.',
      Transfer.transferable => 'The warranty transfers to later owners.',
      Transfer.unknown => "Unknown whether this manufacturer's warranty transfers to a new owner. Check before relying on it.",
    };
  }

  if (out.months <= 0) {
    out
      ..state = WarrantyState.unknown
      ..why = 'No warranty length recorded.';
    return out;
  }

  final startStr = (it.originalPurchase?.isNotEmpty ?? false)
      ? it.originalPurchase
      : (!used ? it.acquired : null);
  final start = parseDate(startStr);
  if (start == null) {
    out
      ..state = WarrantyState.estimated
      ..why = used
          ? "${out.months}-month warranty, but the original purchase date is unknown. The date you got it isn't used as the start."
          : "${out.months}-month warranty, but there's no purchase date to count from."
      ..fix = used ? 'Add the original purchase date' : 'Add the purchase date';
    return out;
  }

  out
    ..start = start
    ..end = addMonths(start, out.months);
  out.days = daysBetween(now, out.end!);

  if (out.days! < 0) {
    out
      ..state = WarrantyState.expired
      ..why = 'Ended ${formatDate(out.end)}.';
    return out;
  }

  if (it.mfrConfirmed) {
    out
      ..state = WarrantyState.verified
      ..why = 'Confirmed with the manufacturer.';
  } else if (hasEvidence(it, ProofStrength.strong)) {
    out
      ..state = WarrantyState.documented
      ..why = 'Receipt or invoice establishes the start date.';
  } else {
    out
      ..state = WarrantyState.estimated
      ..why = it.warrantySource == WarrantySource.typical
          ? "Based on the manufacturer's usual warranty length and a date without strong proof."
          : "Start date isn't backed by a receipt or invoice.";
  }
  // A warranty tied to the original buyer likely doesn't cover a later owner,
  // unless the manufacturer confirmed it does.
  if (used && it.transfer == Transfer.non && !it.mfrConfirmed) {
    out
      ..state = WarrantyState.estimated
      ..why =
          "Dates are known, but this warranty is tied to the original buyer.";
  }
  return out;
}

/// The strongest proof the item has, or null when there's none.
ProofStrength? proofLevel(Item it) {
  ProofStrength? best;
  for (final e in it.evidence) {
    final s = evidenceInfo[e.kind]!.strength;
    if (best == null || s.index > best.index) best = s;
  }
  return best;
}

/// Whether the warranty applies to this owner at all (dates aside).
/// New items: yes. Used and gifted items: only if the warranty transfers, the
/// manufacturer confirmed it, or it transfers with proof of the original purchase
/// and the user has that proof.
bool appliesToOwner(Item it) {
  if (it.isNew || it.mfrConfirmed) return true;
  return switch (it.transfer) {
    Transfer.transferable => true,
    Transfer.conditional => hasEvidence(it, ProofStrength.strong),
    Transfer.unknown || Transfer.non => false,
  };
}

class ReturnWindow {
  const ReturnWindow(this.end, this.days);
  final DateTime end;
  final int days;
}

ReturnWindow? returnWindow(Item it, [DateTime? now]) {
  final acquired = parseDate(it.acquired);
  if ((it.returnDays ?? 0) <= 0 || !it.isNew || acquired == null) return null;
  final end = addDays(acquired, it.returnDays!);
  return ReturnWindow(end, daysBetween(now ?? today(), end));
}

class MaintenanceStatus {
  const MaintenanceStatus(this.task, this.due, this.days);
  final MaintenanceTask task;
  final DateTime? due;
  final int? days;
}

List<MaintenanceStatus> maintenanceDue(Item it, [DateTime? now]) {
  now ??= today();
  return [
    for (final m in it.maintenance)
      () {
        final base = parseDate(m.lastDone) ?? parseDate(it.acquired);
        if (base == null || m.everyMonths <= 0) {
          return MaintenanceStatus(m, null, null);
        }
        final due = addMonths(base, m.everyMonths);
        return MaintenanceStatus(m, due, daysBetween(now!, due));
      }(),
  ];
}

/// For search ("over \$1000"): the value the user set, otherwise what they paid (for all of them).
/// The Home total uses [currentValue] from valuation.dart instead.
double estimatedValue(Item it) =>
    (it.value ?? 0) > 0 ? it.value! : (it.totalPrice ?? 0);

bool isMissingReceipt(Item it) =>
    !it.sold && it.isNew && !hasEvidence(it, ProofStrength.moderate);

/// Coverage ending within 60 days. Skips warranties tied to a previous owner,
/// since that coverage isn't the user's to lose.
bool isExpiring(Item it, [DateTime? now]) {
  final w = warranty(it, now);
  return !it.sold &&
      !(w.used && it.transfer == Transfer.non && !it.mfrConfirmed) &&
      w.end != null &&
      w.days! >= 0 &&
      w.days! <= expiringWithinDays;
}

bool isReturnEnding(Item it, [DateTime? now]) {
  final r = returnWindow(it, now);
  return !it.sold &&
      r != null &&
      r.days >= 0 &&
      r.days <= returnEndingWithinDays;
}

bool isMaintenanceDue(Item it, [DateTime? now]) =>
    !it.sold &&
    maintenanceDue(
      it,
      now,
    ).any((m) => m.days != null && m.days! <= maintenanceDueWithinDays);

/// Under warranty in a way the user can rely on: dated, not ended, and known to
/// apply to this owner. Never claims coverage the app can't back up.
bool isCovered(Item it, [DateTime? now]) {
  final w = warranty(it, now);
  return !it.sold && w.end != null && w.days! >= 0 && appliesToOwner(it);
}

List<Item> applyFilter(List<Item> list, ItemFilter f, [DateTime? now]) =>
    switch (f) {
      ItemFilter.covered => list.where((i) => isCovered(i, now)).toList(),
      ItemFilter.expiring => list.where((i) => isExpiring(i, now)).toList(),
      ItemFilter.returns => list.where((i) => isReturnEnding(i, now)).toList(),
      ItemFilter.noreceipt => list.where(isMissingReceipt).toList(),
      ItemFilter.maint => list.where((i) => isMaintenanceDue(i, now)).toList(),
      ItemFilter.used =>
        list
            .where((i) => !i.sold && i.acquisition == Acquisition.used)
            .toList(),
      ItemFilter.sold => list.where((i) => i.sold).toList(),
      ItemFilter.all => list.where((i) => !i.sold).toList(),
    };
