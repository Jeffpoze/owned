# Owned

Know what you own. Know what's covered. Keep the proof.

Owned is a digital inventory of everything your household owns: what each item is, what it cost, the proof you bought it, whether it's still under warranty, and when it needs maintenance. It's for the moment you need that information: a broken appliance, an insurance claim, a move, or selling something on.

It isn't an AI app. It organizes your data well, using the phone's camera, barcode scanner and on-device text reading.

## Features

- **Scan to add.** Scan a barcode or photograph the model/serial label. Owned fills in the details and shows a picture of the actual product.
- **Keep the proof.** Attach receipts, invoices and photos. Each item shows how strong its proof is (strong, moderate or weak). A missing receipt never blocks you; it only lowers confidence.
- **Honest warranty status.** Verified, Documented, Estimated, Unknown or Expired, always counted from the original purchase. Owned never says you're covered when it doesn't actually know.
- **Used and gifted items.** Records the original purchase and whether the warranty transfers to you.
- **Quantities.** Log 3 light bulbs at one price each and Owned works out the total.
- **Needs attention.** Warranties running out, return windows closing, receipts missing, maintenance due.
- **Plain-language search.** "everything I bought from IKEA", "tvs in the living room", "no receipt", "over $1000".
- **Handoff sheet and CSV export.** Pass an item's history to a buyer, or take all your data with you.

## Status

Early development and testing on iOS and Android. Free while it's being built. Nothing is sold and there are no paid tiers.

---

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

iOS builds sign with the Personal Team set in `ios/Runner.xcodeproj`. Local Android builds need Android Studio (for the Android SDK).

## Layout

- `lib/domain/` – pure logic ported from the prototype: warranty status, proof levels, attention rules, plain-language search, handoff sheet, CSV export, example data.
- `lib/state/` – the item store (saved on the phone) and app settings (light/dark mode).
- `lib/ui/` – screens: Home, Items, Warranties, Settings, item detail, and the Add/Edit form with scanning and product lookup.
- `lib/services/` – product catalog lookups (Open Icecat, UPCitemdb) and on-device label reading.
- `packages/text_reader/` – on-device text recognition plugin (Apple Vision on iOS, ML Kit on Android).
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
