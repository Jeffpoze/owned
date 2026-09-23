# Owned

Know what you own. Know what's covered. Keep the proof.

A Flutter app for iOS and Android. See `AGENTS.md` for the product spec and build order, and `prototype/owned.html` for the reference web prototype.

## Download

Android: the latest APK is on the [android-latest release](https://github.com/Jeffpoze/owned/releases/tag/android-latest). GitHub Actions builds it from every push to `main`. It's debug-signed, for sideloading only.

## Run it

No account or setup is needed: items and photos are saved on the phone.

```bash
flutter pub get
flutter run              # phone or simulator
flutter run --release    # runs without this computer
```

## Accounts (optional, switched off for now)

Sign-up with email verification, sign-in and syncing items across phones are built but only turn on when the app is
built with Supabase project keys. Without them the app skips sign-in entirely.

To turn accounts on:

1. Create a project at supabase.com.
2. SQL Editor: run `supabase/schema.sql` (items table, photo bucket, and rules so each account only sees its own data).
3. Authentication → URL Configuration → Redirect URLs: add `com.jeffpoze.owned://login-callback`.
4. Authentication → Sign In / Providers → Email: keep "Confirm email" on.
5. Copy `supabase.example.json` to `supabase.json` and fill in the Project URL and publishable key
   (Project Settings → API Keys). `supabase.json` is git-ignored.
6. Build with the keys: `flutter run --dart-define-from-file=supabase.json`. In VS Code, use the "Owned (with accounts)"
   launch configuration.

iOS builds sign with the Personal Team set in `ios/Runner.xcodeproj`. Local Android builds need Android Studio (for the Android SDK).

## Layout

- `lib/domain/` – pure logic ported from the prototype: warranty status, proof levels, attention rules, plain-language search, handoff sheet, CSV export, example data.
- `lib/state/` – the item store (on the phone, or synced to an account when accounts are on), accounts, and app settings (light/dark mode).
- `lib/ui/` – screens: Home, Items, Warranties, Settings, item detail, the Add/Edit form with scanning and product lookup, and the account screens.
- `lib/services/` – product catalog lookups (Open Icecat, UPCitemdb) and on-device label reading.
- `packages/text_reader/` – on-device text recognition plugin (Apple Vision on iOS, ML Kit on Android).
- `supabase/schema.sql` – database and photo storage setup.
- `lib/theme.dart` – the light and dark colour palettes.
- `assets/` – Archivo font files and the icon source images.

## Icons

```bash
python3 scripts/generate-icons.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Checks

```bash
flutter analyze
flutter test
```
