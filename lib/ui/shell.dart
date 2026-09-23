import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';

const _tabs = [
  (Icons.home_outlined, Icons.home, 'Home'),
  (Icons.inventory_2_outlined, Icons.inventory_2, 'Items'),
  (Icons.verified_user_outlined, Icons.verified_user, 'Warranties'),
  (Icons.settings_outlined, Icons.settings, 'Settings'),
];

/// Tab scaffold with the raised centre + button from the prototype.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget tab(int ix) {
      final (icon, activeIcon, label) = _tabs[ix];
      final on = shell.currentIndex == ix;
      final color = on ? p.ink : p.ink3;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: () =>
                shell.goBranch(ix, initialLocation: ix == shell.currentIndex),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(on ? activeIcon : icon, color: color, size: 24),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.card,
          border: Border(top: BorderSide(color: p.rule, width: 0.5)),
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tab(0),
              tab(1),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Semantics(
                  button: true,
                  label: 'Add an item',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => context.push('/edit'),
                    child: Container(
                      width: 56,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: p.ink,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF18243F)
                                .withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(Icons.add, color: p.paper, size: 30),
                    ),
                  ),
                ),
              ),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );
  }
}
