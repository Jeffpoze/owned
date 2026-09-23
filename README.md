# Owned

Know what you own. Know what's covered. Keep the proof.

A Flutter app for iOS and Android. See `AGENTS.md` for the product spec and build order, and `prototype/owned.html` for the reference web prototype.

## Run it

An account is required to use the app, so it needs a Supabase project (see below).

```bash
flutter pub get
flutter run --dart-define-from-file=supabase.json             # phone or simulator
flutter run --release --dart-define-from-file=supabase.json   # runs without this computer
```

In VS Code, the "Owned" launch configuration passes the keys for you.

## Supabase setup (once)

1. Create a project at supabase.com.
2. SQL Editor: run `supabase/schema.sql` (items table, photo bucket, and rules so each account only sees its own data).
3. Authentication → URL Configuration → Redirect URLs: add `com.jeffpoze.owned://login-callback`.
4. Authentication → Sign In / Providers → Email: keep "Confirm email" on.
5. Copy `supabase.example.json` to `supabase.json` and fill in the Project URL and publishable key
   (Project Settings → API Keys). `supabase.json` is git-ignored.

iOS builds sign with the Personal Team set in `ios/Runner.xcodeproj`. Android builds need Android Studio (for the Android SDK).

## Layout

- `lib/domain/` – pure logic ported from the prototype: warranty status, proof levels, attention rules, plain-language search, handoff sheet, CSV export, example data.
- `lib/state/` – accounts (sign-up, email verification, sign-in), the item store (saved to the account, cached on the phone), and app settings (light/dark mode).
- `lib/ui/` – screens: create account, sign in, check your email, Home, Items, Warranties, Settings, item detail, and the Add/Edit form.
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
