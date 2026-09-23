import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/constants.dart';
import '../domain/dates.dart';
import '../domain/handoff.dart';
import '../domain/models.dart';
import '../domain/warranty.dart';
import '../state/items_store.dart';
import '../theme.dart';
import 'widgets.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final it = context.watch<ItemsStore>().byId(id);
    if (it == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          title: 'Item not found',
          body: 'It may have been deleted.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(it.name)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          8,
          gutter,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _IdentityTag(it),
          _WarrantyBlock(it),
          _OwnershipBlock(it),
          _ProofBlock(it),
          _MaintenanceBlock(it),
          if (it.notes.isNotEmpty)
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BlockTitle('Notes'),
                  Text(
                    it.notes,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),
          _Actions(it),
        ],
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );
}

const _body = TextStyle(fontSize: 14, height: 1.4);
const _bold = TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w700);

/// Product image (official, or the user's photo; tap to switch), then the identity fields.
class _IdentityTag extends StatefulWidget {
  const _IdentityTag(this.it);
  final Item it;

  @override
  State<_IdentityTag> createState() => _IdentityTagState();
}

class _IdentityTagState extends State<_IdentityTag> {
  int _which = 0;

  @override
  Widget build(BuildContext context) {
    final it = widget.it;
    final p = context.palette;
    final images = [
      it.officialImage,
      it.userPhoto,
    ].whereType<String>().toList();
    final rows = [
      ('Brand', it.brand),
      ('Model', it.model),
      ('Serial', it.serial),
      ('Kind', categoryOf(it).label),
      ('Room', it.room),
    ].where((r) => r.$2.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.tag,
        border: Border.all(color: p.tagEdge),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (images.isNotEmpty)
            GestureDetector(
              onTap: images.length > 1
                  ? () => setState(() => _which = (_which + 1) % images.length)
                  : null,
              child: Builder(
                builder: (_) {
                  final ref = images[_which % images.length];
                  final official = ref == it.officialImage;
                  if (!official) return FittedPhoto(ref, height: 280);
                  return Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    height: 280,
                    child: ItemImage(ref, height: 280, fit: BoxFit.contain),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.2,
                  ),
                ),
                Text(
                  [it.brand, it.model]
                      .where((s) => s.isNotEmpty)
                      .join(' ')
                      .ifEmpty(categoryOf(it).label),
                  style: mutedStyle(context),
                ),
                const SizedBox(height: 10),
                for (final (k, v) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 62,
                          child: Text(k, style: mutedStyle(context)),
                        ),
                        Expanded(
                          child: SelectableText(
                            v,
                            style: _body.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _WarrantyBlock extends StatelessWidget {
  const _WarrantyBlock(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = warranty(it);
    final r = returnWindow(it);
    final gap = const SizedBox(height: 6);
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _BlockTitle('Warranty'),
              const SizedBox(width: 8),
              StatusChip(w.state),
            ],
          ),
          if (w.end != null) ...[
            Text(
              w.state == WarrantyState.expired
                  ? 'Expired ${formatDate(w.end)}'
                  : '${span(w.days!)} remaining, until ${formatDate(w.end)}',
              style: _bold,
            ),
            gap,
          ],
          Text(w.why, style: mutedStyle(context)),
          if (w.caveat != null) ...[
            gap,
            Text(w.caveat!, style: mutedStyle(context)),
          ],
          if (w.fix != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: p.status[WarrantyState.documented],
                minimumSize: Size.zero,
              ),
              onPressed: () => context.push('/edit?id=${it.id}'),
              child: Text(
                w.fix!,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          if (isExpiring(it)) ...[
            gap,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Having a problem with it? ',
                    style: _bold,
                  ),
                  TextSpan(
                    text:
                        'Contact ${it.brand.ifEmpty('the manufacturer')} before ${formatDate(w.end)} with the model, '
                        'serial and receipt below.',
                  ),
                ],
              ),
              style: _body,
            ),
          ],
          if (r != null && r.days >= 0) ...[
            gap,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Return window: '),
                  TextSpan(
                    text: r.days == 0 ? 'ends today' : '${span(r.days)} left',
                    style: _bold,
                  ),
                  TextSpan(text: ' (${formatDate(r.end)})'),
                ],
              ),
              style: _body,
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnershipBlock extends StatelessWidget {
  const _OwnershipBlock(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) {
    final how = switch (it.acquisition) {
      Acquisition.used => 'Bought used',
      Acquisition.gift => 'Received as a gift',
      Acquisition.newItem => 'Bought new',
    };
    final got =
        '$how'
        '${it.acquired != null ? ' on ${formatDate(parseDate(it.acquired))}' : ''}'
        '${(it.price ?? 0) > 0 ? ' for ${money(it.price)}' : ''}'
        '${it.retailer.isNotEmpty ? ' from ${it.retailer}' : ''}.';
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle('Ownership'),
          Text(got, style: _body),
          if (!it.isNew) ...[
            const SizedBox(height: 6),
            Text(
              'Original purchase: ${it.originalPurchase != null ? formatDate(parseDate(it.originalPurchase)) + (it.originalRetailer.isNotEmpty ? ' at ${it.originalRetailer}' : '') : 'unknown'}',
              style: mutedStyle(context),
            ),
          ],
          if ((it.value ?? 0) > 0 && it.value != it.price) ...[
            const SizedBox(height: 6),
            Text(
              'Estimated value now: ${money(it.value)}',
              style: mutedStyle(context),
            ),
          ],
          if (it.sold) ...[
            const SizedBox(height: 6),
            Text('Sold ${formatDate(parseDate(it.soldOn))}', style: _bold),
          ],
        ],
      ),
    );
  }
}

class _ProofBlock extends StatelessWidget {
  const _ProofBlock(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle('Proof'),
          if (it.evidence.isEmpty)
            Text(
              'No proof saved. ${it.isNew ? 'A receipt photo makes the warranty exact.' : 'A marketplace record or card statement still helps.'}',
              style: mutedStyle(context),
            )
          else
            for (final (ix, e) in it.evidence.indexed) ...[
              if (ix > 0) Divider(height: 1, color: p.rule),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(evidenceInfo[e.kind]!.label, style: _body),
                    ),
                    Text(
                      evidenceInfo[e.kind]!.strength.name,
                      style: TextStyle(fontSize: 12, color: p.ink3),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _MaintenanceBlock extends StatelessWidget {
  const _MaintenanceBlock(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tasks = maintenanceDue(it);
    if (tasks.isEmpty) return const SizedBox.shrink();

    Future<void> markDone(int ix) async {
      final maintenance = [
        for (final (i, m) in it.maintenance.indexed)
          i == ix ? m.withLastDone(toIsoDate(today())) : m,
      ];
      final ok = await context.read<ItemsStore>().saveItem(
        it.copyWith(maintenance: maintenance),
      );
      if (context.mounted) {
        toast(context, ok ? 'Marked done' : saveFailedMessage);
      }
    }

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle('Maintenance'),
          for (final (ix, m) in tasks.indexed) ...[
            if (ix > 0) Divider(height: 1, color: p.rule),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.task.task, style: _body),
                        Text(
                          m.due == null
                              ? 'Every ${m.task.everyMonths} months'
                              : m.days! < 0
                              ? 'Overdue by ${span(m.days!)}'
                              : m.days == 0
                              ? 'Due today'
                              : 'Due in ${span(m.days!)}',
                          style: labelStyle(context),
                        ),
                      ],
                    ),
                  ),
                  if (!it.sold)
                    OutlinedButton(
                      onPressed: () => markDone(ix),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.ink,
                        side: BorderSide(color: p.rule),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text(
                        'Done today',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ItemsStore>();

    Future<void> copyHandoff() async {
      await Clipboard.setData(ClipboardData(text: handoffSheet(it)));
      if (context.mounted) toast(context, 'Handoff sheet copied');
    }

    Future<void> toggleSold() async {
      final wasSold = it.sold;
      final ok = await store.saveItem(
        it.copyWith(
          sold: !wasSold,
          soldOn: wasSold ? null : toIsoDate(today()),
        ),
      );
      if (!context.mounted) return;
      if (!ok) return toast(context, saveFailedMessage);
      toast(context, wasSold ? 'Moved back to your home' : 'Marked as sold');
      context.pop();
    }

    Future<void> confirmDelete() async {
      final ok = await showAdaptiveDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog.adaptive(
          title: Text('Delete ${it.name}?'),
          content: const Text('This removes it and its saved proof.'),
          actions: [
            adaptiveAction(ctx, 'Cancel', () => Navigator.pop(ctx, false)),
            adaptiveAction(
              ctx,
              'Delete',
              () => Navigator.pop(ctx, true),
              destructive: true,
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final deleted = await store.deleteItem(it.id);
      if (!context.mounted) return;
      if (!deleted) {
        return toast(
          context,
          "Couldn't delete. Check your connection and try again.",
        );
      }
      toast(context, 'Deleted');
      context.pop();
    }

    Widget cell(Widget child) => SizedBox(width: double.infinity, child: child);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: cell(
                  AppButton(
                    'Edit',
                    onPressed: () => context.push('/edit?id=${it.id}'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: cell(
                  AppButton(
                    'Copy handoff sheet',
                    kind: ButtonKind.ghost,
                    onPressed: copyHandoff,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: cell(
                  AppButton(
                    it.sold ? 'Move back to my home' : 'Mark as sold',
                    kind: ButtonKind.ghost,
                    onPressed: toggleSold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: cell(
                  AppButton(
                    'Delete',
                    kind: ButtonKind.danger,
                    onPressed: confirmDelete,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A dialog button that looks native on both iOS and Android.
Widget adaptiveAction(
  BuildContext context,
  String label,
  VoidCallback onPressed, {
  bool destructive = false,
}) {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      isDefaultAction: !destructive,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    style: destructive
        ? TextButton.styleFrom(
            foregroundColor: context.palette.status[WarrantyState.expired],
          )
        : null,
    child: Text(label),
  );
}
