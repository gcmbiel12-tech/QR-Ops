import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/qr_auth_gateway.dart';

class SupabaseQrAuthGateway implements QrAuthGateway {
  SupabaseQrAuthGateway(this.client);

  final SupabaseClient client;

  @override
  QrAuthUser? get currentUser => _mapUser(client.auth.currentUser);

  @override
  Stream<QrAuthUser?> get authStateChanges => client.auth.onAuthStateChange.map(
    (state) => _mapUser(state.session?.user),
  );

  @override
  Future<void> signIn({required String email, required String password}) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    final launched = await client.auth.signInWithOAuth(OAuthProvider.google);
    if (!launched) {
      throw StateError('Não foi possível iniciar a autenticação com Google.');
    }
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    await client.auth.signUp(email: email.trim(), password: password);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    await client.auth.resetPasswordForEmail(email.trim());
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final normalized = displayName.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(displayName, 'displayName', 'Informe um nome.');
    }
    await client.auth.updateUser(
      UserAttributes(data: {'display_name': normalized}),
    );
  }

  @override
  Future<void> deleteAccount() async {
    try {
      final response = await client.functions.invoke('delete-account');
      final data = response.data;
      if (response.status < 200 ||
          response.status >= 300 ||
          data is! Map ||
          data['success'] != true) {
        throw StateError('O servidor não confirmou a exclusão da conta.');
      }
    } on FunctionException catch (error) {
      if (error.status == 401) {
        throw StateError(
          'Por segurança, entre novamente na sua conta e repita a exclusão.',
        );
      }
      if (error.status == 404) {
        throw StateError(
          'O serviço de exclusão ainda não foi publicado no Supabase.',
        );
      }
      rethrow;
    }
    await client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  QrAuthUser? _mapUser(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName =
        [metadata['display_name'], metadata['full_name'], metadata['name']]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final identities = user.identities;
    final provider =
        user.appMetadata['provider'] as String? ??
        (identities != null && identities.isNotEmpty
            ? identities.first.provider
            : 'email');
    return QrAuthUser(
      id: user.id,
      email: user.email ?? '',
      displayName: displayName.isEmpty ? null : displayName,
      provider: provider,
    );
  }
}
