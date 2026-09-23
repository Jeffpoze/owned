/// Supabase project settings, passed at build time:
///
///     flutter run --dart-define-from-file=supabase.json
///
/// `supabase.json` is git-ignored; copy `supabase.example.json` to create it.
/// The publishable key is safe to ship in the app: row-level security in the
/// database decides what each signed-in user can read and write.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

bool get supabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

/// Where email links (verification, password reset) send the user back into the app.
const authRedirectUrl = 'com.jeffpoze.owned://login-callback';
