import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/data/qr_sync_service.dart';
import 'package:qr_ops/domain/qr_auth_gateway.dart';
import 'package:qr_ops/features/auth/qr_account_page.dart';

void main() {
  testWidgets(
    'shows configuration guidance and never simulates a real session',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: QrAccountPage(auth: null)),
      );

      expect(find.textContaining('Autenticação indisponível.'), findsOneWidget);
      expect(
        find.textContaining('Biblioteca e histórico seguem neste dispositivo.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    },
  );

  testWidgets('validates and submits login, then clears session on logout', (
    tester,
  ) async {
    final auth = _FakeAuthGateway();
    await tester.pumpWidget(MaterialApp(home: QrAccountPage(auth: auth)));

    await tester.tap(find.text('Entrar').last);
    await tester.pumpAndSettle();
    expect(auth.signInCalls, 0);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'long-password',
    );
    await tester.tap(find.text('Entrar').last);
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(auth.currentUser?.email, 'a@example.com');
    expect(find.text('Minha Conta'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Sair da conta'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(auth.currentUser, isNull);
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
  });

  testWidgets('starts Google authentication from the account form', (
    tester,
  ) async {
    final auth = _FakeAuthGateway();
    await tester.pumpWidget(MaterialApp(home: QrAccountPage(auth: auth)));

    await tester.tap(find.byKey(const ValueKey('google-login')));
    await tester.pumpAndSettle();

    expect(auth.googleSignInCalls, 1);
  });

  testWidgets('shows account identity and saves the display name', (
    tester,
  ) async {
    final auth = _FakeAuthGateway();
    await tester.pumpWidget(MaterialApp(home: QrAccountPage(auth: auth)));

    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'long-password',
    );
    await tester.tap(find.text('Entrar').last);
    await tester.pumpAndSettle();

    expect(find.text('a@example.com'), findsOneWidget);
    expect(find.text('E-mail e senha'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar nome'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Gabriel Teste');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Gabriel Teste'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Enviar link para alterar senha'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar link para alterar senha'));
    await tester.pumpAndSettle();
    expect(auth.resetCalls, 1);
  });

  testWidgets('changes the local theme preference from account settings', (
    tester,
  ) async {
    final auth = _FakeAuthGateway();
    final selectedModes = <ThemeMode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: QrAccountPage(auth: auth, onThemeModeChanged: selectedModes.add),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'long-password',
    );
    await tester.tap(find.text('Entrar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    expect(selectedModes, [ThemeMode.dark]);
  });

  testWidgets(
    'deletes the account only after explicit confirmation and purges local data',
    (tester) async {
      final auth = _FakeAuthGateway();
      final sync = _FakeSyncService();
      await tester.pumpWidget(
        MaterialApp(
          home: QrAccountPage(auth: auth, syncService: sync),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'long-password',
      );
      await tester.tap(find.text('Entrar').last);
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir conta e dados'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir conta e dados?'), findsOneWidget);
      expect(auth.deleteAccountCalls, 0);
      await tester.tap(find.text('Excluir permanentemente'));
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 1);
      expect(sync.purgedOwner, 'user-1');
      expect(auth.currentUser, isNull);
    },
  );

  testWidgets('supports registration and password recovery requests', (
    tester,
  ) async {
    final auth = _FakeAuthGateway();
    await tester.pumpWidget(MaterialApp(home: QrAccountPage(auth: auth)));

    await tester.tap(find.text('Criar conta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'long-password',
    );
    await tester.ensureVisible(find.text('Cadastrar'));
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();
    expect(auth.signUpCalls, 1);
    expect(find.textContaining('Cadastro enviado'), findsOneWidget);

    await tester.tap(find.text('Esqueci minha senha'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-password')), findsNothing);
    await tester.ensureVisible(find.text('Enviar instruções'));
    await tester.tap(find.text('Enviar instruções'));
    await tester.pumpAndSettle();
    expect(auth.resetCalls, 1);
    expect(find.textContaining('instruções de recuperação'), findsOneWidget);
  });

  testWidgets('reports service failures without claiming success', (
    tester,
  ) async {
    final auth = _FakeAuthGateway()..failSignIn = true;
    await tester.pumpWidget(MaterialApp(home: QrAccountPage(auth: auth)));
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'long-password',
    );
    await tester.ensureVisible(find.text('Entrar').last);
    await tester.tap(find.text('Entrar').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-error')), findsOneWidget);
    expect(find.text('Sessão iniciada.'), findsNothing);
  });
}

class _FakeSyncService extends Fake implements QrSyncService {
  String? purgedOwner;

  @override
  Future<bool> isEnabled(String ownerId) async => false;

  @override
  Future<int> pendingCount(String ownerId) async => 0;

  @override
  Future<DateTime?> lastSyncAt(String ownerId) async => null;

  @override
  Future<void> purgeLocalAccount(String ownerId) async {
    purgedOwner = ownerId;
  }
}

class _FakeAuthGateway implements QrAuthGateway {
  final _controller = StreamController<QrAuthUser?>.broadcast(sync: true);
  QrAuthUser? _user;
  int signInCalls = 0;
  int googleSignInCalls = 0;
  int signUpCalls = 0;
  int resetCalls = 0;
  int signOutCalls = 0;
  int deleteAccountCalls = 0;
  bool failSignIn = false;

  @override
  QrAuthUser? get currentUser => _user;

  @override
  Stream<QrAuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    if (failSignIn) throw StateError('service unavailable');
    _user = QrAuthUser(id: 'user-1', email: email);
    _controller.add(_user);
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCalls++;
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    signUpCalls++;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    resetCalls++;
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    _user = QrAuthUser(
      id: _user!.id,
      email: _user!.email,
      displayName: displayName,
      provider: _user!.provider,
    );
    _controller.add(_user);
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    _user = null;
    _controller.add(null);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    _controller.add(null);
  }
}
