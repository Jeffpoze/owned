import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/constants.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/warranty.dart';
import '../state/items_store.dart';
import '../theme.dart';
import 'widgets.dart';

const _order = {
  WarrantyState.verified: 0,
  WarrantyState.documented: 0,
  WarrantyState.estimated: 1,
  WarrantyState.unknown: 2,
  WarrantyState.expired: 3,
};

/// The warranty wallet: every item with a warranty, soonest to end first, colour-coded by status.
class WarrantiesScreen extends StatelessWidget {
  const WarrantiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ItemsStore>();
    final p = context.palette;
    final list =
        [
          for (final i in store.active)
            if ((i.warrantyMonths ?? 0) > 0) (i, warranty(i)),
        ]..sort((a, b) {
          final o = _order[a.$2.state]!.compareTo(_order[b.$2.state]!);
          return o != 0
              ? o
              : (a.$2.days ?? 1 << 30).compareTo(b.$2.days ?? 1 << 30);
        });

    return TabPage(
      children: [
        CardBox(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              iconColor: p.ink2,
              collapsedIconColor: p.ink2,
              title: Text('What the colours mean', style: labelStyle(context)),
              children: [
                for (final s in WarrantyState.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        StatusChip(s),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stateMeaning[s]!,
                            style: labelStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          const EmptyState(
            title: 'No warranties yet',
            body: 'Add a warranty length to any item and it shows up here with the time left.',
          )
        else
          for (final (i, w) in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: p.card,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: p.rule),
                ),
                child: InkWell(
                  onTap: () => context.push('/item/${i.id}'),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 6, color: p.status[w.state]),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  w.state == WarrantyState.expired
                                      ? 'Expired'
                                      : w.end != null
                                      ? '${span(w.days!)}${w.days! < 45 ? ' left' : ''}'
                                      : 'Start date unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  i.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${w.end != null ? '${w.state == WarrantyState.expired ? 'Ended' : 'Until'} ${formatDate(w.end)}, ' : ''}'
                                  '${stateLabel[w.state]!.toLowerCase()}'
                                  '${w.used && i.transfer == Transfer.non ? ', not transferable' : ''}',
                                  style: labelStyle(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
