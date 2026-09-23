import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/constants.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/warranty.dart';
import '../state/items_store.dart';
import '../theme.dart';

/// Space kept clear at the bottom of tab pages for the tab bar and its raised + button.
const tabBarClearance = 110.0;

const saveFailedMessage = "Couldn't save. Check your connection and try again.";

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 2600),
      ),
    );
}

TextStyle labelStyle(BuildContext context) =>
    TextStyle(fontSize: 13, height: 1.35, color: context.palette.ink2);
TextStyle mutedStyle(BuildContext context) =>
    TextStyle(fontSize: 14, height: 1.4, color: context.palette.ink2);

/// A tab page: the Owned wordmark, where data is saved, then scrolling content.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        gutter,
        top + 12,
        gutter,
        tabBarClearance + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Owned',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                    letterSpacing: -0.9,
                    height: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              const _ModeNote(),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _ModeNote extends StatelessWidget {
  const _ModeNote();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ItemsStore>();
    final p = context.palette;
    final style = TextStyle(fontSize: 13, color: p.ink3);
    if (store.mode == StoreMode.example) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('Example home, not saved', style: style),
          GestureDetector(
            onTap: store.leaveExample,
            child: Text(
              'Start my own',
              style: style.copyWith(
                color: p.status[WarrantyState.documented],
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      );
    }
    return Text(switch (store.mode) {
      StoreMode.account when store.isLocal => 'Saved on this phone',
      StoreMode.account when store.offline =>
        'Offline, showing your saved copy',
      StoreMode.account => 'Saved to your account',
      _ => 'Loading…',
    }, style: style);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.top = 26});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.state, {super.key});
  final WarrantyState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = p.status[state]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: p.statusBg[state],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            stateLabel[state]!,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The item's official image or photo, falling back to its category emoji.
class ItemThumb extends StatelessWidget {
  const ItemThumb(this.item, {super.key, required this.size, this.radius = 8});
  final Item item;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final src = item.officialImage ?? item.userPhoto;
    // Product pictures are cut-outs on white: show them whole. The user's photos fill the tile.
    final official = item.officialImage != null;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      padding: official ? EdgeInsets.all(size * 0.06) : null,
      decoration: BoxDecoration(
        color: official ? Colors.white : context.palette.tag,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: src != null
          ? ItemImage(
              src,
              width: size,
              height: size,
              fit: official ? BoxFit.contain : BoxFit.cover,
            )
          : Text(
              categoryOf(item).emoji,
              style: TextStyle(fontSize: size * 0.46),
            ),
    );
  }
}

class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

enum ButtonKind { primary, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton(
    this.title, {
    super.key,
    required this.onPressed,
    this.kind = ButtonKind.primary,
  });
  final String title;
  final VoidCallback? onPressed;
  final ButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = switch (kind) {
      ButtonKind.primary => p.ink,
      ButtonKind.ghost => p.card,
      ButtonKind.danger => Colors.transparent,
    };
    final fg = switch (kind) {
      ButtonKind.primary => p.paper,
      ButtonKind.ghost => p.ink,
      ButtonKind.danger => p.status[WarrantyState.expired]!,
    };
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledForegroundColor: fg.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: kind == ButtonKind.primary ? p.ink : p.rule),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Archivo',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      child: Text(title, textAlign: TextAlign.center),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip(
    this.label, {
    super.key,
    this.selected = false,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.ink : p.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? p.ink : p.rule),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? p.paper : p.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: mutedStyle(context).copyWith(fontSize: 16),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
      ],
    ),
  );
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onSubmitted: onSubmitted,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    autocorrect: false,
    style: const TextStyle(fontSize: 16),
    decoration: InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.palette.rule),
      ),
    ),
  );
}

class ItemRow extends StatelessWidget {
  const ItemRow(this.item, {super.key});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final meta = [
      item.room,
      item.brand,
      if (item.sold) 'Sold ${formatDate(parseDate(item.soldOn))}',
    ].where((s) => s.isNotEmpty).join(', ');
    return Opacity(
      opacity: item.sold ? 0.6 : 1,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.rule),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/item/${item.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ItemThumb(item, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        meta.isEmpty ? categoryOf(item).label : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle(context),
                      ),
                    ],
                  ),
                ),
                if (!item.sold) ...[
                  const SizedBox(width: 8),
                  StatusChip(warranty(item).state),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a photo reference: a stored photo in the account, a local file, or a web link.
class ItemImage extends StatefulWidget {
  const ItemImage(
    this.ref, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });
  final String ref;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<ItemImage> createState() => _ItemImageState();
}

class _ItemImageState extends State<ItemImage> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = context.read<ItemsStore>().photoUrl(widget.ref);
  }

  @override
  void didUpdateWidget(ItemImage old) {
    super.didUpdateWidget(old);
    if (old.ref != widget.ref) {
      _url = context.read<ItemsStore>().photoUrl(widget.ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.ref.startsWith('/')) {
      return Image.file(
        File(w.ref),
        width: w.width,
        height: w.height,
        fit: w.fit,
      );
    }
    final blank = SizedBox(width: w.width, height: w.height);
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return blank;
        if (url.startsWith('/')) {
          return Image.file(
            File(url),
            width: w.width,
            height: w.height,
            fit: w.fit,
          );
        }
        return Image.network(
          url,
          width: w.width,
          height: w.height,
          fit: w.fit,
          errorBuilder: (_, _, _) => SizedBox(
            width: w.width,
            height: w.height,
            child: Icon(
              Icons.broken_image_outlined,
              color: context.palette.ink3,
            ),
          ),
        );
      },
    );
  }
}

/// The user's own photo shown whole (nothing cropped). The space around it is filled
/// with a soft, blurred copy of the same photo, so portrait and landscape shots both look right.
class FittedPhoto extends StatelessWidget {
  const FittedPhoto(this.ref, {super.key, required this.height});
  final String ref;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ItemImage(ref, height: height),
          ),
          const ColoredBox(color: Color(0x33000000)),
          ItemImage(ref, height: height, fit: BoxFit.contain),
        ],
      ),
    ),
  );
}
