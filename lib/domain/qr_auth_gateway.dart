class QrAuthUser {
  const QrAuthUser({required this.id, required this.email});

  final String id;
  final String email;
}

/// Authentication boundary; it does not own or replace local QR storage.
abstract interface class QrAuthGateway {
  QrAuthUser? get currentUser;

  Stream<QrAuthUser?> get authStateChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signUp({required String email, required String password});

  Future<void> sendPasswordReset({required String email});

  Future<void> signOut();
}
