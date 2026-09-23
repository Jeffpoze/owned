import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/constants.dart';
import 'package:owned/domain/dates.dart';
import 'package:owned/domain/models.dart';
import 'package:owned/domain/warranty.dart';

final now = DateTime(2026, 9, 22);
String ago({int months = 0, int days = 0}) =>
    toIsoDate(addDays(addMonths(now, -months), -days));

Item item({
  Acquisition acquisition = Acquisition.newItem,
  String? acquired,
  String? originalPurchase,
  int? warrantyMonths = 12,
  WarrantySource source = WarrantySource.receipt,
  bool mfrConfirmed = false,
  Transfer transfer = Transfer.unknown,
  List<EvidenceKind> evidence = const [],
  int? returnDays,
  List<MaintenanceTask> maintenance = const [],
  bool sold = false,
}) => Item(
  id: 't',
  name: 'Test',
  acquisition: acquisition,
  acquired: acquired ?? ago(months: 2),
  originalPurchase: originalPurchase,
  warrantyMonths: warrantyMonths,
  warrantySource: source,
  mfrConfirmed: mfrConfirmed,
  transfer: transfer,
  evidence: [for (final k in evidence) Evidence(k)],
  returnDays: returnDays,
  maintenance: maintenance,
  sold: sold,
  createdAt: 0,
);

WarrantyState stateOf(Item it) => warranty(it, now).state;

void main() {
  group('the five statuses', () {
    test('no warranty length is Unknown, even with a receipt', () {
      expect(
        stateOf(item(warrantyMonths: null, evidence: [EvidenceKind.receipt])),
        WarrantyState.unknown,
      );
      expect(stateOf(item(warrantyMonths: 0)), WarrantyState.unknown);
    });

    test('manufacturer confirmation is Verified', () {
      expect(stateOf(item(mfrConfirmed: true)), WarrantyState.verified);
    });

    test('strong proof is Documented', () {
      for (final k in [
        EvidenceKind.receipt,
        EvidenceKind.invoice,
        EvidenceKind.registration,
      ]) {
        expect(
          stateOf(item(evidence: [k])),
          WarrantyState.documented,
          reason: k.name,
        );
      }
    });

    test('moderate, weak or no proof is Estimated', () {
      for (final k in [
        EvidenceKind.marketplace,
        EvidenceKind.card,
        EvidenceKind.email,
        EvidenceKind.photo,
      ]) {
        expect(
          stateOf(item(evidence: [k])),
          WarrantyState.estimated,
          reason: k.name,
        );
      }
      expect(stateOf(item()), WarrantyState.estimated);
    });

    test('a typical length stays Estimated until a document backs it', () {
      expect(
        stateOf(item(source: WarrantySource.typical)),
        WarrantyState.estimated,
      );
      expect(
        warranty(item(source: WarrantySource.typical), now).why,
        contains("manufacturer's usual"),
      );
      expect(
        stateOf(
          item(
            source: WarrantySource.typical,
            evidence: [EvidenceKind.receipt],
          ),
        ),
        WarrantyState.documented,
      );
    });

    test('ended coverage is Expired, even when it was verified', () {
      final old = ago(months: 13);
      expect(
        stateOf(item(acquired: old, evidence: [EvidenceKind.receipt])),
        WarrantyState.expired,
      );
      expect(
        stateOf(item(acquired: old, mfrConfirmed: true)),
        WarrantyState.expired,
      );
    });

    test('the last day of coverage is not expired; the day after is', () {
      // 12 months from exactly one year ago ends today.
      final w = warranty(
        item(acquired: ago(months: 12), evidence: [EvidenceKind.receipt]),
        now,
      );
      expect(w.days, 0);
      expect(w.state, WarrantyState.documented);
      expect(
        stateOf(item(acquired: ago(months: 12, days: 1))),
        WarrantyState.expired,
      );
    });
  });

  group('used and gifted items', () {
    test('never count from the date the user got it', () {
      final it = item(acquisition: Acquisition.used, acquired: ago(days: 3));
      final w = warranty(it, now);
      expect(w.state, WarrantyState.estimated);
      expect(w.end, isNull);
      expect(w.why, contains('original purchase date is unknown'));
      expect(w.fix, 'Add the original purchase date');
    });

    test('gifts follow the same rule', () {
      final w = warranty(
        item(acquisition: Acquisition.gift, acquired: ago(days: 3)),
        now,
      );
      expect(w.end, isNull);
      expect(w.used, isTrue);
    });

    test('count from the original purchase when it is known', () {
      final it = item(
        acquisition: Acquisition.used,
        acquired: ago(days: 3),
        originalPurchase: ago(months: 10),
        warrantyMonths: 12,
      );
      final w = warranty(it, now);
      expect(w.start, parseDate(ago(months: 10)));
      expect(w.end, addMonths(parseDate(ago(months: 10))!, 12));
    });

    test('an original purchase over the warranty length is Expired, however recently it was bought', () {
      final it = item(
        acquisition: Acquisition.used,
        acquired: ago(days: 1),
        originalPurchase: ago(months: 30),
      );
      expect(stateOf(it), WarrantyState.expired);
    });

    test('non-transferable is Estimated even with strong proof', () {
      final it = item(
        acquisition: Acquisition.used,
        originalPurchase: ago(months: 3),
        transfer: Transfer.non,
        evidence: [EvidenceKind.receipt],
      );
      final w = warranty(it, now);
      expect(w.state, WarrantyState.estimated);
      expect(w.why, contains('tied to the original buyer'));
      expect(w.caveat, contains("likely doesn't cover you"));
    });

    test('manufacturer confirmation overrides non-transferable', () {
      final it = item(
        acquisition: Acquisition.used,
        originalPurchase: ago(months: 3),
        transfer: Transfer.non,
        mfrConfirmed: true,
      );
      expect(stateOf(it), WarrantyState.verified);
      expect(isCovered(it, now), isTrue);
    });

    test('every transfer setting has a caveat; new items have none', () {
      for (final t in Transfer.values) {
        expect(
          warranty(
            item(acquisition: Acquisition.used, transfer: t),
            now,
          ).caveat,
          isNotNull,
          reason: t.name,
        );
      }
      expect(warranty(item(), now).caveat, isNull);
    });
  });

  group(
    'under warranty (never claims coverage the app does not know about)',
    () {
      Item used(Transfer t, {List<EvidenceKind> evidence = const []}) => item(
        acquisition: Acquisition.used,
        originalPurchase: ago(months: 3),
        transfer: t,
        evidence: evidence,
      );

      test('new items with dated, unexpired coverage count', () {
        expect(isCovered(item(), now), isTrue);
        expect(isCovered(item(evidence: [EvidenceKind.receipt]), now), isTrue);
      });

      test('used items count only when the warranty transfers to them', () {
        expect(isCovered(used(Transfer.transferable), now), isTrue);
        expect(isCovered(used(Transfer.unknown), now), isFalse);
        expect(isCovered(used(Transfer.non), now), isFalse);
        expect(isCovered(used(Transfer.conditional), now), isFalse);
        expect(
          isCovered(
            used(Transfer.conditional, evidence: [EvidenceKind.receipt]),
            now,
          ),
          isTrue,
        );
      });

      test('undated, expired and sold items never count', () {
        expect(
          isCovered(
            item(
              acquisition: Acquisition.used,
              transfer: Transfer.transferable,
            ),
            now,
          ),
          isFalse,
        );
        expect(isCovered(item(acquired: ago(months: 13)), now), isFalse);
        expect(isCovered(item(sold: true), now), isFalse);
      });
    },
  );

  group('proof levels', () {
    test('strongest proof wins', () {
      expect(proofLevel(item()), isNull);
      expect(
        proofLevel(item(evidence: [EvidenceKind.photo])),
        ProofStrength.weak,
      );
      expect(
        proofLevel(item(evidence: [EvidenceKind.photo, EvidenceKind.card])),
        ProofStrength.moderate,
      );
      expect(
        proofLevel(item(evidence: [EvidenceKind.card, EvidenceKind.invoice])),
        ProofStrength.strong,
      );
    });

    test('a missing receipt only flags new purchases, and moderate proof clears it', () {
      expect(isMissingReceipt(item()), isTrue);
      expect(isMissingReceipt(item(evidence: [EvidenceKind.photo])), isTrue);
      expect(isMissingReceipt(item(evidence: [EvidenceKind.email])), isFalse);
      expect(isMissingReceipt(item(acquisition: Acquisition.used)), isFalse);
      expect(isMissingReceipt(item(sold: true)), isFalse);
    });

    test('a missing receipt never blocks a warranty status', () {
      expect(stateOf(item()), isNot(WarrantyState.unknown));
    });
  });

  group('needs attention', () {
    test('expiring: within 60 days, inclusive', () {
      // 12-month warranty bought 10 months + n days ago ends in about 61 - n days.
      final ends60 = item(
        acquired: toIsoDate(addMonths(addDays(now, expiringWithinDays), -12)),
      );
      final ends61 = item(
        acquired: toIsoDate(
          addMonths(addDays(now, expiringWithinDays + 1), -12),
        ),
      );
      expect(warranty(ends60, now).days, expiringWithinDays);
      expect(isExpiring(ends60, now), isTrue);
      expect(isExpiring(ends61, now), isFalse);
    });

    test('expiring skips expired, sold and non-transferable warranties', () {
      final soon = toIsoDate(addMonths(addDays(now, 10), -12));
      expect(isExpiring(item(acquired: soon), now), isTrue);
      expect(isExpiring(item(acquired: soon, sold: true), now), isFalse);
      expect(isExpiring(item(acquired: ago(months: 13)), now), isFalse);
      expect(
        isExpiring(
          item(
            acquisition: Acquisition.used,
            originalPurchase: soon,
            transfer: Transfer.non,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        isExpiring(
          item(
            acquisition: Acquisition.used,
            originalPurchase: soon,
            transfer: Transfer.unknown,
          ),
          now,
        ),
        isTrue,
      );
    });

    test(
      'return window: new items only, within 7 days, including the last day',
      () {
        Item bought(int daysAgo, {Acquisition a = Acquisition.newItem}) => item(
          acquired: ago(days: daysAgo),
          returnDays: 30,
          acquisition: a,
        );
        expect(returnWindow(bought(30), now)!.days, 0);
        expect(isReturnEnding(bought(30), now), isTrue);
        expect(isReturnEnding(bought(23), now), isTrue);
        expect(isReturnEnding(bought(22), now), isFalse);
        expect(isReturnEnding(bought(31), now), isFalse);
        expect(returnWindow(bought(10, a: Acquisition.used), now), isNull);
      },
    );

    test('maintenance: due within 14 days or overdue, counted from the last time it was done', () {
      Item every6(String? lastDone) => item(
        acquired: ago(months: 24),
        maintenance: [
          MaintenanceTask(task: 'Filter', everyMonths: 6, lastDone: lastDone),
        ],
      );
      String doneSoDueIn(int days) =>
          toIsoDate(addMonths(addDays(now, days), -6));
      expect(isMaintenanceDue(every6(doneSoDueIn(14)), now), isTrue);
      expect(isMaintenanceDue(every6(doneSoDueIn(15)), now), isFalse);
      expect(isMaintenanceDue(every6(ago(months: 8)), now), isTrue); // overdue
      expect(
        isMaintenanceDue(every6(null), now),
        isTrue,
      ); // never done: counts from purchase
      expect(isMaintenanceDue(every6(ago(days: 1)), now), isFalse);
    });
  });

  group('dates', () {
    test('month arithmetic clamps to shorter months and leap years', () {
      expect(addMonths(DateTime(2025, 1, 31), 1), DateTime(2025, 2, 28));
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(addMonths(DateTime(2024, 2, 29), 12), DateTime(2025, 2, 28));
      expect(addMonths(DateTime(2025, 11, 30), 3), DateTime(2026, 2, 28));
    });

    test('day counts ignore daylight-saving changes', () {
      expect(daysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
      expect(daysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
    });
  });
}
