import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/qr_auth_gateway.dart';
import '../../domain/qr_record_repository.dart';
import '../../data/qr_sync_service.dart';

class QrAccountPage extends StatefulWidget {
  const QrAccountPage({super.key, required this.auth, this.syncService, this.repository});

  final QrAuthGateway? auth;
  final QrSyncService? syncService;
  final QrRecordRepository? repository;

  @override
  State<QrAccountPage> createState() => _QrAccountPageState();
}

enum _AuthMode { signIn, signUp, resetPassword }

class _QrAccountPageState extends State<QrAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  String? _message;
  String? _error;
  bool _syncBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = widget.auth;
    if (auth == null || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      switch (_mode) {
        case _AuthMode.signIn:
          await auth.signIn(email: _email.text, password: _password.text);
          if (mounted) setState(() => _message = 'Sessão iniciada.');
        case _AuthMode.signUp:
          await auth.signUp(email: _email.text, password: _password.text);
          if (mounted) {
            setState(
              () => _message = 'Cadastro enviado. Se a confirmação de e-mail estiver ativa, confirme o endereço antes de entrar.',
            );
          }
        case _AuthMode.resetPassword:
          await auth.sendPasswordReset(email: _email.text);
          if (mounted) {
            setState(
              () => _message = 'Se o endereço estiver cadastrado, as instruções de recuperação serão enviadas conforme a configuração do projeto.',
            );
          }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível concluir a operação. Verifique a conexão e a configuração do serviço.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableSync(QrAuthUser user, {required bool importExisting}) async {
    final sync = widget.syncService;
    if (sync == null) {
      setState(() => _error = 'A fila de sincronização não está disponível neste ambiente.');
      return;
    }
    var consent = true;
    if (importExisting) {
      final records = await sync.localRecords();
      if (!mounted) return;
      consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importar dados locais?'),
          content: Text('Serão enfileirados até ${records.length} registros locais (biblioteca e histórico) para a conta ${user.email}. Os dados só serão enviados após esta confirmação. O histórico mantém a retenção de sete dias.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Autorizar importação')),
          ],
        ),
      ) ?? false;
    } else {
      consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ativar sincronização?'),
          content: const Text('Somente novas alterações feitas enquanto esta conta estiver conectada serão sincronizadas. Os registros locais existentes não serão importados.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ativar')),
          ],
        ),
      ) ?? false;
    }
    if (!consent || !mounted) return;
    setState(() { _syncBusy = true; _error = null; _message = null; });
    try {
      await sync.enable(ownerId: user.id, importExistingLocalData: importExisting, consentGranted: true);
      final report = await sync.syncOnce(user.id);
      final pending = await sync.pendingCount(user.id);
      if (mounted) setState(() => _message = 'Sincronização ativada. Aplicadas: ${report.applied}; conflitos: ${report.conflicts}; pendentes: $pending.');
    } on Object {
      if (mounted) setState(() => _error = 'Não foi possível ativar ou sincronizar. As operações pendentes foram preservadas para nova tentativa.');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _syncNow(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    setState(() { _syncBusy = true; _error = null; });
    try {
      final report = await sync.syncOnce(user.id);
      final pending = await sync.pendingCount(user.id);
      if (mounted) setState(() => _message = 'Resultado: ${report.applied} aplicadas, ${report.conflicts} conflitos, ${report.deferred} adiadas; pendentes: $pending.');
    } on Object {
      if (mounted) setState(() => _error = 'Falha de sincronização. Os dados locais e a fila foram preservados.');
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _togglePause(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    final paused = await sync.isPaused(user.id);
    await sync.setPaused(user.id, !paused);
    if (mounted) setState(() => _message = paused ? 'Sincronização retomada.' : 'Sincronização pausada. A fila foi preservada.');
    if (paused) await _syncNow(user);
  }

  Future<void> _disableSync(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    await sync.disable(user.id);
    if (mounted) setState(() => _message = 'Sincronização desativada. Os dados locais, remotos e operações pendentes foram preservados.');
  }

  Future<void> _signOut() async {
    final auth = widget.auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await auth.signOut();
      if (mounted) setState(() => _message = 'Sessão encerrada.');
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível encerrar a sessão. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    if (auth == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conta QR Ops')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'A autenticação ainda não está configurada neste ambiente. Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY com --dart-define e valide as URLs de redirecionamento no painel Supabase. A biblioteca e o histórico continuam disponíveis localmente.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Conta QR Ops')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StreamBuilder<QrAuthUser?>(
              stream: auth.authStateChanges,
              initialData: auth.currentUser,
              builder: (context, snapshot) {
                final user = snapshot.data;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  shrinkWrap: true,
                  children: [
                    Icon(
                      user == null
                          ? Icons.lock_outline
                          : Icons.verified_user_outlined,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user == null ? _title : 'Sessão autenticada',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user == null
                          ? 'Entre na sua conta ou crie uma. A biblioteca local continua neste dispositivo; ela não será enviada automaticamente.'
                          : 'Conta: ${user.email}\nOs QR Codes locais continuam armazenados neste dispositivo. A sincronização ainda não está ativada.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (snapshot.hasError)
                      const Text('Não foi possível ler o estado da sessão.'),
                    if (user != null) ...[
                      if (widget.syncService != null) ...[
                        FutureBuilder<bool>(
                          future: widget.syncService!.isEnabled(user.id),
                          builder: (context, enabledSnapshot) {
                            final enabled = enabledSnapshot.data ?? false;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FutureBuilder<int>(
                                  future: widget.syncService!.pendingCount(user.id),
                                  builder: (context, pendingSnapshot) => Text(
                                    'Sincronização: ${!enabled ? 'desativada' : 'ativada'} · operações pendentes: ${pendingSnapshot.data ?? '…'}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (!enabled) ...[
                                  FilledButton.icon(
                                    onPressed: _syncBusy ? null : () => _enableSync(user, importExisting: true),
                                    icon: const Icon(Icons.cloud_upload_outlined),
                                    label: const Text('Ativar e importar dados locais'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy ? null : () => _enableSync(user, importExisting: false),
                                    child: const Text('Ativar sem importar dados existentes'),
                                  ),
                                ] else ...[
                                  FilledButton.icon(
                                    onPressed: _syncBusy ? null : () => _syncNow(user),
                                    icon: const Icon(Icons.sync),
                                    label: const Text('Sincronizar agora'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy ? null : () => _togglePause(user),
                                    child: const Text('Pausar / retomar sincronização'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy ? null : () => _disableSync(user),
                                    child: const Text('Desativar sincronização'),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        onPressed: _busy ? null : _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sair da conta'),
                      ),
                    ] else ...[
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              key: const ValueKey('auth-email'),
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (!email.contains('@') ||
                                    email.endsWith('@')) {
                                  return 'Informe um e-mail válido.';
                                }
                                return null;
                              },
                            ),
                            if (_mode != _AuthMode.resetPassword) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const ValueKey('auth-password'),
                                controller: _password,
                                obscureText: true,
                                autofillHints: _mode == _AuthMode.signIn
                                    ? const [AutofillHints.password]
                                    : const [AutofillHints.newPassword],
                                decoration: const InputDecoration(
                                  labelText: 'Senha',
                                ),
                                validator: (value) {
                                  if ((value ?? '').length < 8) {
                                    return 'Use pelo menos 8 caracteres.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(_actionLabel),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _changeMode(
                                      _mode == _AuthMode.signIn
                                          ? _AuthMode.signUp
                                          : _AuthMode.signIn,
                                    ),
                              child: Text(
                                _mode == _AuthMode.signUp
                                    ? 'Já tenho uma conta'
                                    : 'Criar conta',
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _changeMode(
                                      _mode == _AuthMode.resetPassword
                                          ? _AuthMode.signIn
                                          : _AuthMode.resetPassword,
                                    ),
                              child: Text(
                                _mode == _AuthMode.resetPassword
                                    ? 'Voltar para login'
                                    : 'Esqueci minha senha',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(_message!, textAlign: TextAlign.center),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const ValueKey('auth-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String get _title => switch (_mode) {
    _AuthMode.signIn => 'Entrar',
    _AuthMode.signUp => 'Criar conta',
    _AuthMode.resetPassword => 'Recuperar senha',
  };

  String get _actionLabel => switch (_mode) {
    _AuthMode.signIn => 'Entrar',
    _AuthMode.signUp => 'Cadastrar',
    _AuthMode.resetPassword => 'Enviar instruções',
  };
}
