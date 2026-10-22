import 'package:flutter/foundation.dart';

/// Runtime configuration for the Supabase project.
/// Supply values through --dart-define. Never provide service_role to Flutter.
abstract final class SupabaseAppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured =>
      url.startsWith('https://') && publishableKey.isNotEmpty;

  static void validate() {
    if (!isConfigured) {
      throw StateError('Supabase nao configurado. Informe SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.');
    }
    if (kReleaseMode && publishableKey.toLowerCase().contains('service_role')) {
      throw StateError('Uma chave privilegiada nao pode ser usada no cliente.');
    }
  }
}
