/// Runtime configuration for Supabase.
/// Use --dart-define. Never put a service-role/secret key in the client.
abstract final class SupabaseAppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || parsedUrl.host.isEmpty ||
        publishableKey.isEmpty || _isPrivilegedKey(publishableKey)) {
      return false;
    }
    if (parsedUrl.scheme == 'https') return true;
    // Plain HTTP is permitted only for local development endpoints.
    return parsedUrl.scheme == 'http' &&
        (parsedUrl.host == '127.0.0.1' ||
         parsedUrl.host == 'localhost' ||
         parsedUrl.host == '::1');
  }

  static void validate() {
    if (_isPrivilegedKey(publishableKey)) {
      throw StateError('Uma chave privilegiada/secret não pode ser usada no cliente Flutter.');
    }
    if (!isConfigured) {
      throw StateError(
        'Supabase não configurado. Use SUPABASE_URL HTTPS; HTTP é permitido somente em loopback local.',
      );
    }
  }

  static bool _isPrivilegedKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.contains('service_role') ||
        normalized.startsWith('sb_secret_');
  }
}
