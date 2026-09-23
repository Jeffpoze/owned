import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/constants.dart';
import '../domain/search.dart';
import '../domain/warranty.dart';
import '../state/items_store.dart';
import 'widgets.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ItemsStore>();
    // A query set elsewhere (Home's search box, a hint) replaces what's in the box.
    if (store.query != _lastQuery) {
      _lastQuery = store.query;
      if (_search.text != store.query) _search.text = store.query;
    }

    final searching = store.query.trim().isNotEmpty;
    final result = searching ? runQuery(store.items, store.query) : null;
    final list = [...(result?.list ?? applyFilter(store.items, store.filter))]
      ..sort((a, b) {
        final r = (a.room.isEmpty ? '~' : a.room).compareTo(
          b.room.isEmpty ? '~' : b.room,
        );
        return r != 0 ? r : a.name.compareTo(b.name);
      });

    return TabPage(
      children: [
        Row(
          children: [
            Expanded(
              child: SearchField(
                controller: _search,
                hint: 'Try: everything I bought from IKEA',
                onChanged: (s) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 250),
                    () => store.setQuery(s),
                  );
                },
                onSubmitted: store.setQuery,
              ),
            ),
            if (searching) ...[
              const SizedBox(width: 8),
              AppButton(
                'Clear',
                kind: ButtonKind.ghost,
                onPressed: () {
                  _search.clear();
                  store.setQuery('');
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${result!.tags.isEmpty ? 'No filters recognised' : 'Showing: ${result.tags.join(', ')}'} (${list.length})',
              style: labelStyle(context),
            ),
          )
        else
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: ItemFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, ix) {
                final f = ItemFilter.values[ix];
                return PillChip(
                  filterLabel[f]!,
                  selected: store.filter == f,
                  onTap: () => store.setFilter(f),
                );
              },
            ),
          ),
        if (!searching) const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            title: 'No matches',
            body: store.items.isEmpty ? 'Add an item to start your inventory.' : 'Nothing fits that. Try a brand, a store, a room or a kind of thing.',
          )
        else
          for (final it in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ItemRow(it),
            ),
      ],
    );
  }
}
