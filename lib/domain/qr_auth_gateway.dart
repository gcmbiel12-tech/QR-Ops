class QrAuthUser {
  const QrAuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.provider,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? provider;
}

/// Authentication boundary; it does not own or replace local QR storage.
abstract interface class QrAuthGateway {
  QrAuthUser? get currentUser;

  Stream<QrAuthUser?> get authStateChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signInWithGoogle();

  Future<void> signUp({required String email, required String password});

  Future<void> sendPasswordReset({required String email});

  Future<void> updateDisplayName(String displayName);

  Future<void> deleteAccount();

  Future<void> signOut();
}
