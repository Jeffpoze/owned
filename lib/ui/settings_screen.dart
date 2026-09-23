import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/export.dart';
import '../state/auth_store.dart';
import '../state/items_store.dart';
import '../state/settings_store.dart';
import '../theme.dart';
import 'item_detail_screen.dart' show adaptiveAction;
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ItemsStore>();
    final settings = context.watch<SettingsStore>();
    final auth = context.watch<AuthStore>();
    final p = context.palette;

    return TabPage(
      children: [
        if (auth.user != null) ...[
          const SectionTitle('Account', top: 0),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Signed in as', style: labelStyle(context)),
                Text(
                  auth.user?.email ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(
                  'Sign out',
                  kind: ButtonKind.ghost,
                  onPressed: () => showAdaptiveDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog.adaptive(
                      title: const Text('Sign out?'),
                      content: const Text(
                        'Your items stay in your account. Sign in again to see them.',
                      ),
                      actions: [
                        adaptiveAction(ctx, 'Cancel', () => Navigator.pop(ctx)),
                        adaptiveAction(ctx, 'Sign out', () {
                          Navigator.pop(ctx);
                          auth.signOut();
                        }, destructive: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        SectionTitle('Appearance', top: auth.user != null ? 26 : 0),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.setThemeMode(s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected) ? p.ink : p.card,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (s) =>
                          s.contains(WidgetState.selected) ? p.paper : p.ink2,
                    ),
                    side: WidgetStatePropertyAll(BorderSide(color: p.rule)),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(
                        fontFamily: 'Archivo',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'System follows your phone’s light or dark setting.',
                style: labelStyle(context),
              ),
            ],
          ),
        ),
        const SectionTitle('Your data'),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                store.mode == StoreMode.example
                    ? "You're looking at an example home. Nothing is saved."
                    : store.isLocal
                    ? 'Your items and photos are saved on this phone.'
                    : 'Your items are saved to your account, so they show up on any phone you sign in on.',
                style: mutedStyle(context),
              ),
              const SizedBox(height: 12),
              AppButton(
                'Export for insurance (CSV)',
                kind: ButtonKind.ghost,
                onPressed: store.items.isEmpty
                    ? null
                    : () => SharePlus.instance.share(
                        ShareParams(
                          text: inventoryCsv(store.items),
                          subject: 'Owned inventory',
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              store.mode == StoreMode.example
                  ? AppButton('Start my own', onPressed: store.leaveExample)
                  : AppButton(
                      'Browse the example home',
                      kind: ButtonKind.ghost,
                      onPressed: store.enterExample,
                    ),
            ],
          ),
        ),
        const SectionTitle('How warranty status works'),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Owned never counts a warranty from the day you got a used item. It counts from the original purchase, '
                'and only calls coverage documented when a receipt or invoice backs that date.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Proof ranks from strong (original receipt, invoice, registration) to moderate (marketplace, card '
                'statement, emails) to weak (a photo, your own note).',
                style: mutedStyle(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
