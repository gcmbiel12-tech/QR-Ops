import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_ops/domain/qr_auth_gateway.dart';
import 'package:qr_ops/features/auth/qr_account_page.dart';

void main() {
  testWidgets(
    'shows configuration guidance and never simulates a real session',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: QrAccountPage(auth: null)),
      );

      expect(find.textContaining('ainda não está configurada'), findsOneWidget);
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
    expect(find.text('Sessão autenticada'), findsOneWidget);

    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(auth.currentUser, isNull);
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
  });

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

class _FakeAuthGateway implements QrAuthGateway {
  final _controller = StreamController<QrAuthUser?>.broadcast(sync: true);
  QrAuthUser? _user;
  int signInCalls = 0;
  int signUpCalls = 0;
  int resetCalls = 0;
  int signOutCalls = 0;
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
  Future<void> signUp({required String email, required String password}) async {
    signUpCalls++;
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    resetCalls++;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _user = null;
    _controller.add(null);
  }
}
