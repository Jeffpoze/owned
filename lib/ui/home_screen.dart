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

const _hints = [
  ('What appliances do I have?', 'What appliances do I have?'),
  ('Which things are still under warranty?', 'Still under warranty'),
  ('Everything with no receipt', 'No receipt'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String q) {
    if (q.trim().isEmpty) return;
    context.read<ItemsStore>().setQuery(q);
    _search.clear();
    context.go('/items');
  }

  void _openFilter(ItemFilter f) {
    context.read<ItemsStore>().setFilter(f);
    context.go('/items');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ItemsStore>();
    final p = context.palette;
    final list = store.active;

    if (list.isEmpty) {
      return TabPage(
        children: [
          EmptyState(
            title: 'Nothing here yet',
            body:
                'Photograph a product label to add your first item. Owned reads the model and serial, '
                'keeps the receipt, and watches the warranty.',
            actions: [
              AppButton(
                'Add your first item',
                onPressed: () => context.push('/edit'),
              ),
              if (store.mode != StoreMode.example)
                AppButton(
                  'See an example home',
                  kind: ButtonKind.ghost,
                  onPressed: store.enterExample,
                ),
            ],
          ),
        ],
      );
    }

    final value = list.fold<double>(0, (s, i) => s + estimatedValue(i));
    int count(bool Function(Item) f) => list.where(f).length;
    final expiring = count(isExpiring);
    final returns = count(isReturnEnding);
    final noReceipt = count(isMissingReceipt);
    final maint = count(isMaintenanceDue);
    final rows = [
      (
        ItemFilter.expiring,
        expiring,
        expiring == 1
            ? 'warranty expiring in the next 60 days'
            : 'warranties expiring in the next 60 days',
      ),
      (
        ItemFilter.returns,
        returns,
        returns == 1
            ? 'return window ending this week'
            : 'return windows ending this week',
      ),
      (
        ItemFilter.noreceipt,
        noReceipt,
        noReceipt == 1
            ? 'new purchase missing a receipt'
            : 'new purchases missing receipts',
      ),
      (
        ItemFilter.maint,
        maint,
        maint == 1 ? 'item due for maintenance' : 'items due for maintenance',
      ),
    ].where((r) => r.$2 > 0).toList();
    final recent = [...list]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final estimated = list
        .where(
          (i) =>
              (i.warrantyMonths ?? 0) > 0 &&
              const {
                WarrantyState.estimated,
                WarrantyState.unknown,
              }.contains(warranty(i).state),
        )
        .length;

    return TabPage(
      children: [
        _TagHero(count: list.length, value: value),
        SearchField(
          controller: _search,
          hint: 'Ask about your stuff',
          onSubmitted: _runSearch,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (q, label) in _hints)
              Material(
                color: Colors.transparent,
                shape: StadiumBorder(side: BorderSide(color: p.rule)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _runSearch(q),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    child: Text(label, style: labelStyle(context)),
                  ),
                ),
              ),
          ],
        ),
        const SectionTitle('Needs attention'),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.card,
            border: Border.all(color: p.rule),
            borderRadius: BorderRadius.circular(14),
          ),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nothing needs you right now.',
                    style: mutedStyle(context).copyWith(fontSize: 16),
                  ),
                )
              : Material(
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      for (final (ix, (f, n, label)) in rows.indexed) ...[
                        if (ix > 0) Divider(height: 1, color: p.rule),
                        InkWell(
                          onTap: () => _openFilter(f),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '$n',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: p.ink3),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        if (estimated > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$estimated ${estimated == 1 ? 'warranty is' : 'warranties are'} estimated. Adding a purchase date or '
              'receipt makes ${estimated == 1 ? 'it' : 'them'} exact.',
              style: labelStyle(context),
            ),
          ),
        const SectionTitle('Recently added'),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: recent.length.clamp(0, 8),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, ix) {
              final it = recent[ix];
              return Material(
                color: p.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: p.rule),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/item/${it.id}'),
                  child: Container(
                    width: 118,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ItemThumb(it, size: 96),
                        const SizedBox(height: 8),
                        Text(
                          it.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The luggage-tag hero: item count and estimated value.
class _TagHero extends StatelessWidget {
  const _TagHero({required this.count, required this.value});
  final int count;
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$count items, ${money(value)} estimated value',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 22),
        decoration: BoxDecoration(
          color: p.tag,
          border: Border.all(color: p.tagEdge),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(6),
            right: Radius.circular(22),
          ),
        ),
        child: Stack(
          children: [
            // punched hole
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: p.paper,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.tagEdge, width: 2),
                  ),
                ),
              ),
            ),
            // perforation
            Positioned(
              left: 46,
              top: 12,
              bottom: 12,
              child: LayoutBuilder(
                builder: (context, c) {
                  final n = (c.maxHeight / 10).floor();
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      n,
                      (_) => Container(width: 2, height: 5, color: p.tagEdge),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(58, 22, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🏠 Home',
                    style: mutedStyle(context).copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 64,
                          height: 1,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        count == 1 ? 'item' : 'items',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 23,
                          color: p.ink2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: money(value),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: ' estimated value',
                          style: TextStyle(color: p.ink2),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
