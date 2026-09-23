import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'state/auth_store.dart';
import 'state/items_backend.dart';
import 'state/items_store.dart';
import 'state/settings_store.dart';
import 'theme.dart';
import 'ui/auth_screens.dart';
import 'ui/edit_item_screen.dart';
import 'ui/home_screen.dart';
import 'ui/item_detail_screen.dart';
import 'ui/items_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/shell.dart';
import 'ui/warranties_screen.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  if (supabaseConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
  final auth = AuthStore(
    supabaseConfigured ? Supabase.instance.client.auth : null,
  );
  final items = ItemsStore();
  final settings = SettingsStore();
  await Future.wait([auth.load(), settings.load()]);

  // Accounts are switched off in builds without Supabase keys: items stay on this phone.
  if (!supabaseConfigured) await items.attach('local', LocalItemsBackend());

  // Load the signed-in account's items; forget them on sign-out.
  void syncItems() {
    if (!supabaseConfigured) return;
    final user = auth.user;
    if (user != null && items.userId != user.id) {
      items.attach(
        user.id,
        SupabaseItemsBackend(Supabase.instance.client, user.id),
      );
    } else if (user == null && items.userId != null) {
      items.detach();
    }
  }

  auth.addListener(syncItems);
  syncItems();

  FlutterNativeSplash.remove();
  runApp(OwnedApp(auth: auth, items: items, settings: settings));
}

const _authRoutes = {'/welcome', '/sign-in', '/verify'};

GoRouter _buildRouter(AuthStore auth) {
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!supabaseConfigured) return _authRoutes.contains(loc) ? '/' : null;
      return switch (auth.phase) {
        AuthPhase.signedIn => _authRoutes.contains(loc) ? '/' : null,
        AuthPhase.verifying => loc == '/verify' ? null : '/verify',
        // First open: create an account. Someone who has signed in here before goes to sign-in.
        AuthPhase.signedOut =>
          loc == '/welcome' || loc == '/sign-in'
              ? null
              : auth.lastEmail.isEmpty
              ? '/welcome'
              : '/sign-in',
      };
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const CreateAccountScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyEmailScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/items', builder: (_, _) => const ItemsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/warranties',
                builder: (_, _) => const WarrantiesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/item/:id',
        parentNavigatorKey: rootKey,
        builder: (_, state) =>
            ItemDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/edit',
        parentNavigatorKey: rootKey,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: EditItemScreen(id: state.uri.queryParameters['id']),
        ),
      ),
    ],
  );
}

class OwnedApp extends StatefulWidget {
  const OwnedApp({
    super.key,
    required this.auth,
    required this.items,
    required this.settings,
  });
  final AuthStore auth;
  final ItemsStore items;
  final SettingsStore settings;

  @override
  State<OwnedApp> createState() => _OwnedAppState();
}

class _OwnedAppState extends State<OwnedApp> {
  late final GoRouter _router = _buildRouter(widget.auth);

  // Pick up changes made on another device when the app comes back to the foreground.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: widget.items.refresh,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.items),
        ChangeNotifierProvider.value(value: widget.settings),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, s, _) => MaterialApp.router(
          title: 'Owned',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          routerConfig: _router,
        ),
      ),
    );
  }
}
