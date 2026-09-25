# Owned

**Know what you own. Know what's covered. Keep the proof.**

Owned is an iOS and Android app for keeping a digital inventory of everything a household owns: what each item is, the proof of purchase, warranty coverage, maintenance, and ownership history (including items bought used or sold on). It is not an AI app. The value is good data organization built on the phone's camera, barcode scanner and notifications.

## Current state

The app is a Flutter project (`lib/`, `ios/`, `android/`). See Roadmap below for what's done and what's next. Accounts and sync are built but on hold: without Supabase keys in `supabase.json` the app skips sign-in and saves items and photos on the phone. The web prototype at `prototype/owned.html` stays the reference for screens, copy, the warranty and proof logic, the plain-language search parser, and the example data. Ignore its hosting-runtime code (the db, assets, sample and downloads calls made in `boot()`); that was the hosting runtime for the web version and has no place in the native app.

## Stack (decided)

- **App:** Flutter (Dart) for iOS and Android from one codebase. State with `provider` (ChangeNotifier stores in `lib/state/`), navigation with `go_router`, local storage with `shared_preferences` until Supabase sync lands. Pure logic lives in `lib/domain/` with unit tests in `test/`.
- **Scanning:** `mobile_scanner` for barcodes (live, and in still photos). Label text is read on the device by the local `packages/text_reader` plugin: Apple Vision on iOS, Google ML Kit on Android. (The `google_mlkit_text_recognition` package was dropped: its iOS build has no Apple Silicon simulator slice.) Field extraction rules are in `lib/domain/label_parser.dart`.
- **Product catalog (development):** `lib/services/catalog.dart`. Exact lookups (barcode, or brand + model from a scan) try Open Icecat first: free, no daily limit, manufacturer images licensed for this use, but no Apple. Then UPCitemdb's free trial API (no key, ~100 requests a day per network), which also powers the as-you-type suggestions in Name and Model; the app narrows cached results instead of re-searching and stops for the day once the limit is hit. Before launch, move lookups to a server function with a licensed catalog plan, and build Owned's own shared product catalog from products users confirm.
- **Background removal:** on-device subject lifting (iOS Vision foreground mask via a small platform channel, Android ML Kit subject segmentation) for the fallback product image.
- **Backend:** Supabase (`supabase_flutter`) for auth, Postgres, file storage (photos, receipts, product images) and household sharing.
- **Server functions:** receipt parsing and product/catalog lookups run server-side so API keys never ship in the app.
- **Payments:** deferred. No RevenueCat, subscriptions, paywalls or free/paid checks for now (see Pricing).
- **Icons and splash:** `scripts/generate-icons.py` draws the source images; `flutter_launcher_icons` and `flutter_native_splash` (config in `pubspec.yaml`) generate the platform assets.

## Screens

Mirror the prototype:

- **Home:** the item count and estimated value in a "tag" hero; a Needs attention list (warranties expiring within 60 days, return windows ending within 7 days, new purchases missing receipts, maintenance due within 14 days); Recently added; and a search box.
- **Items:** filter chips (All, Under warranty, Expiring soon, Return window, Missing receipt, Maintenance due, Bought used, Sold) and plain-language search.
- **Warranties (warranty wallet):** items with a warranty, sorted by time left, colour-coded by status.
- **Item detail:** product image, identity (brand, model, serial, kind, room), warranty status with its explanation, ownership, proof, maintenance ("Done today"), notes, and actions (Edit, Copy handoff sheet, Mark as sold, Delete).
- **Add (new items), step by step:** 1) What is it? (scan barcode, photograph label, photo, name/brand/model/serial with catalog suggestions); 2) How did you get it? (photograph receipt, new/used/gift, date, price each, how many with a live total, store, original purchase for used items); 3) Proof and warranty; 4) Where is it? (kind, room, and optional More details: value now, maintenance, notes); then an Added screen showing the real warranty status, proof strength, what was paid and the value, with View item and Add another. Back steps back through the flow.
- **Edit (existing items):** the full form on one screen, with the same scan buttons at the top.
- **Settings:** Appearance (System / Light / Dark), your data (CSV export, example home), how warranty status works; later the account.
- **Sign in / create account:** required on first open. Email and password sign-up with email verification, then sign-in (Supabase auth). Keep the user signed in between launches, and let the phone save the password (iCloud Keychain / Google Password Manager autofill).

## Data model (per item)

id, name, brand, model, serial, category, room, acquisition (new | used | gift), acquired (date), price (for one), quantity (default 1; total = price × quantity), retailer, originalPurchase (date), originalRetailer, value, warrantyMonths, warrantySource (receipt | typical | guess), mfrConfirmed, transfer (unknown | transferable | conditional | non), returnDays, evidence[] {kind, assetId?}, maintenance[] {task, everyMonths, lastDone}, notes, officialImage, userPhoto, sold, soldOn, createdAt.

## Warranty rules (critical; don't simplify these)

- The warranty starts at the **original purchase**. For used or gifted items, never count it from the date the user got the item. If the original purchase date is unknown, the status is Estimated with "start date unknown".
- The five statuses:
  - **Verified:** the manufacturer confirmed coverage.
  - **Documented:** strong proof (receipt, invoice, registration) establishes the start date.
  - **Estimated:** the length is known, but exact coverage isn't (weak or no proof, the manufacturer's typical length, or a used item whose warranty doesn't transfer).
  - **Unknown:** no warranty length is recorded.
  - **Expired:** coverage was established and has ended.
- For used items, show a transferability caveat: transferable, conditional (needs proof of the original purchase), non-transferable, or unknown.
- A warranty length inferred from a manufacturer's typical terms is always Estimated until a document backs it.
- Never tell a user they're covered when the app doesn't actually know.

## Proof levels

- **Strong:** original receipt, retailer invoice, manufacturer registration.
- **Moderate:** marketplace transaction, card or bank statement, order confirmation email, receipt from the seller.
- **Weak:** photo of the product, the user's own record of the date.

A missing receipt is never a blocker. It just lowers confidence.

## Scanning pipeline

1. **Barcode first.** Serial labels often encode the serial and model in a barcode; a retail UPC identifies the exact product.
2. **On-device OCR.** Then extract fields with rules: text after "Model", "MOD", "S/N" or "Serial", plus per-brand serial patterns.
3. **Cloud fallback.** Receipts, and labels the phone couldn't read, go to a server function (a receipt-parsing service or a vision model) that returns structured JSON: retailer, date, line items, return days, warranty months.
4. **Confirm.** Always show the extracted fields for the user to confirm before saving.

## Product image pipeline

The requirement: scanning an Apple TV shows a picture of an Apple TV.

1. Identify the product from the UPC barcode (best) or from brand + model number.
2. Look it up in a licensed catalog: UPC lookup services (Barcode Lookup, Go-UPC, UPCitemdb) or Icecat (manufacturer images, searchable by brand + model). Check each service's terms, copy the image into our own storage, and never hotlink. Never scrape image search results or manufacturer websites.
3. Fallback: the user's own photo with the background removed on-device, placed on a clean backdrop.
4. Store both images per item: the official image as the thumbnail and the user's photo as proof of ownership and condition. Tapping the image toggles between them.

## Search

Plain-language search with no AI, using pattern rules over the data (see `runQuery` in the prototype). It should handle queries like "everything I bought from IKEA", "what appliances do I have", "which things are still under warranty", "no receipt", "tvs in the living room" and "over $1000". Show the filters it understood.

## Ownership transfer

- **Now:** Copy handoff sheet, a text summary of the item (brand, model, serial, original purchase, warranty, documents).
- **Later:** a QR transfer. The seller generates a code, the buyer scans it, the record and documents move to the buyer's account, and the seller keeps a "sold" record.

## Pricing

Deferred. Owned is free while it's built and tested on iOS and Android. Don't add subscriptions, RevenueCat, paywalls, item limits or premium-only features, and don't design the architecture around them. Monetization gets revisited once both platforms are solid with real-world use.

## Later features (not in the MVP)

- A "Check used product" flow to run before buying something used: scan the serial to see the estimated manufacture date and likely warranty status.
- Importing receipts from email and PDFs.
- Warranty lookups with manufacturers where public tools exist.
- Notifications for expiring warranties, closing return windows and maintenance.

## Roadmap

Done so far: Flutter project and all screens; warranty, proof and attention logic with tests; barcode and on-device OCR scanning; Supabase auth and sync (built, on hold); product image lookup and background removal (development catalog).

1. **Add Item flow redesign.** Fast, step by step: identify the item (scan first), how you got it, proof and warranty, where it is, then a done screen. Keep the existing scanning, OCR, catalog lookup, receipt parsing and warranty logic. Don't ask for what the app can fill in. The done screen shows the status the rules actually give (Documented, Estimated…), never Verified unless the manufacturer confirmed it. Editing an existing item keeps the full form.
2. **Product / Item architecture, done together:** separate generic product data (brand, model, UPC, images, specs) from each owned item (serial, purchase, proof, warranty, room, condition); server-side catalog lookups; Supabase sync; a migration plan before real users have lots of data.
3. **Onboarding and account management:** a clear first action after sign-in (scan your first item, or explore the example home); in-app account deletion; data export and recovery.
4. **Notifications:** warranty expiry, return windows, maintenance, with user-controlled levels (Essential / Normal / Off).
5. **Crash reporting and reliability testing, before outside testers:** crash reporting; sync failures; offline; OCR failures; camera and scanner edge cases; bad or missing product matches; large inventories; denied permissions; the app killed during scanning, upload or sync.
6. **Wide testing on iOS and Android:** newer and older iPhones, inexpensive Android phones, different cameras and OS versions, poor or no internet, large inventories, French and English. Distribution (TestFlight, Play internal testing) gets set up when it's time for outside testers.
7. **App Store and Play Store launch.**

When a step needs accounts, API keys or manual setup (Apple/Google developer accounts, Supabase, catalog APIs), stop and explain exactly what to do.
