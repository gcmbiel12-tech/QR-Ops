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
  Future<void> signUp({required String email, required String password}) async {
    await client.auth.signUp(email: email.trim(), password: password);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    await client.auth.resetPasswordForEmail(email.trim());
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  QrAuthUser? _mapUser(User? user) {
    if (user == null) return null;
    return QrAuthUser(id: user.id, email: user.email ?? '');
  }
}
