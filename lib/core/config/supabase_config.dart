/// Compile-time backend configuration.
///
/// Values arrive through `--dart-define-from-file=supabase.env.json`, which is
/// gitignored; `supabase.env.example.json` documents the two keys. Nothing here
/// needs a build-time secret: the publishable key is designed to ship inside a
/// client binary and Row Level Security, not secrecy, is what protects the data.
///
/// Passing an empty URL is not a silent failure. [assertConfigured] turns it
/// into a startup error screen, the same way a failed Firebase init used to.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static void assertConfigured() {
    if (isConfigured) return;
    throw StateError(
      'Supabase is not configured. Run the app with '
      '--dart-define-from-file=supabase.env.json '
      '(copy supabase.env.example.json and fill in the project URL and '
      'publishable key).',
    );
  }
}
