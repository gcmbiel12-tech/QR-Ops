import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/qr_auth_gateway.dart';
import '../../domain/qr_record_repository.dart';
import '../../data/qr_sync_service.dart';

class QrAccountPage extends StatefulWidget {
  const QrAccountPage({
    super.key,
    required this.auth,
    this.syncService,
    this.repository,
    this.themeMode = ThemeMode.light,
    this.onThemeModeChanged,
  });

  final QrAuthGateway? auth;
  final QrSyncService? syncService;
  final QrRecordRepository? repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<QrAccountPage> createState() => _QrAccountPageState();
}

enum _AuthMode { signIn, signUp, resetPassword }

class _QrAccountPageState extends State<QrAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  String? _message;
  String? _error;
  bool _syncBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
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

  Future<void> _signInWithGoogle() async {
    final auth = widget.auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await auth.signInWithGoogle();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível iniciar o login com Google. Verifique a configuração do provedor e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableSync(
    QrAuthUser user, {
    required bool importExisting,
  }) async {
    final sync = widget.syncService;
    if (sync == null) {
      setState(
        () => _error =
            'A fila de sincronização não está disponível neste ambiente.',
      );
      return;
    }
    var consent = true;
    if (importExisting) {
      final records = await sync.localRecordsForImport(user.id);
      if (!mounted) return;
      consent =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Importar dados locais?'),
              content: Text(
                'Importar até ${records.length} registros locais para ${user.email}? O envio começa após sua confirmação.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Autorizar importação'),
                ),
              ],
            ),
          ) ??
          false;
    } else {
      consent =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Ativar sincronização?'),
              content: const Text(
                'Sincronizar apenas novas alterações. Os dados existentes não serão importados.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Ativar'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!consent || !mounted) return;
    setState(() {
      _syncBusy = true;
      _error = null;
      _message = null;
    });
    try {
      await sync.enable(
        ownerId: user.id,
        importExistingLocalData: importExisting,
        consentGranted: true,
      );
      final report = await sync.syncOnce(user.id);
      final pending = await sync.pendingCount(user.id);
      if (mounted)
        setState(
          () => _message =
              'Sincronização ativada. Aplicadas: ${report.applied}; conflitos: ${report.conflicts}; pendentes: $pending.',
        );
    } on Object {
      if (mounted)
        setState(
          () => _error = 'Não foi possível ativar ou sincronizar. As operações pendentes foram preservadas para nova tentativa.',
        );
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _syncNow(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    setState(() {
      _syncBusy = true;
      _error = null;
    });
    try {
      final report = await sync.syncOnce(user.id);
      final pending = await sync.pendingCount(user.id);
      if (mounted)
        setState(
          () => _message =
              'Resultado: ${report.applied} aplicadas, ${report.conflicts} conflitos, ${report.deferred} adiadas; pendentes: $pending.',
        );
    } on Object {
      if (mounted)
        setState(
          () => _error = 'Falha de sincronização. Os dados locais e a fila foram preservados.',
        );
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _togglePause(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    final paused = await sync.isPaused(user.id);
    await sync.setPaused(user.id, !paused);
    if (mounted)
      setState(
        () => _message = paused
            ? 'Sincronização retomada.'
            : 'Sincronização pausada. A fila foi preservada.',
      );
    if (paused) await _syncNow(user);
  }

  Future<void> _disableSync(QrAuthUser user) async {
    final sync = widget.syncService;
    if (sync == null) return;
    await sync.disable(user.id);
    if (mounted)
      setState(
        () => _message = 'Sincronização desativada. Os dados locais, remotos e operações pendentes foram preservados.',
      );
  }

  Future<void> _exportLocalData() async {
    final repository = widget.repository;
    if (repository == null) {
      setState(() => _error = 'O armazenamento local não está disponível.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exportar meus dados?'),
        content: const Text(
          'O arquivo conterá até os 1.000 registros mais recentes vinculados a esta conta. Registros antigos ainda sem vínculo com uma conta não serão incluídos; eles podem ser associados a esta conta pela opção de importação. O arquivo será salvo somente após sua confirmação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exportar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final records = await repository.listLatest(limit: 1000);
      final exportedAt = DateTime.now().toUtc();
      final payload = {
        'format': 'qrops-local-export-v1',
        'exported_at': exportedAt.toIso8601String(),
        'scope': 'account_local_records',
        'record_limit': 1000,
        'records': records
            .map(
              (record) => {
                'id': record.id,
                'operation': record.operation.name,
                'symbology': record.symbology,
                'content_type': record.contentType,
                'content': record.content,
                'name': record.name,
                'description': record.description,
                'created_at': record.createdAt.toUtc().toIso8601String(),
                'revision': record.revision,
              },
            )
            .toList(growable: false),
      };
      final date = exportedAt.toIso8601String().replaceAll(':', '-');
      await FileSaver.instance.saveFile(
        name: 'qrops-dados-da-conta-$date',
        bytes: Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
        ),
        fileExtension: 'json',
        customMimeType: 'application/json',
      );
      if (mounted) {
        setState(
          () => _message =
              'Exportação preparada: ${records.length} registros locais.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível exportar os dados locais. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDisplayName(QrAuthUser user) async {
    final auth = widget.auth;
    if (auth == null) return;
    _displayName.text = user.displayName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar nome'),
        content: TextField(
          controller: _displayName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Nome'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _displayName.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome para salvar.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await auth.updateDisplayName(name);
      if (mounted) setState(() => _message = 'Nome atualizado.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível atualizar o nome. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordRecoveryLink(QrAuthUser user) async {
    final auth = widget.auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      await auth.sendPasswordReset(email: user.email);
      if (mounted) {
        setState(
          () => _message =
              'Se o e-mail estiver habilitado para recuperação, enviaremos um link para ${user.email}.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível solicitar o link de recuperação. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount(QrAuthUser user) async {
    final auth = widget.auth;
    final sync = widget.syncService;
    if (auth == null) return;
    if (sync == null) {
      setState(
        () => _error = 'A limpeza local da conta não está disponível. Não é seguro excluir a conta neste momento.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir conta e dados?'),
        content: const Text(
          'Esta ação é permanente. A conta e os QR Codes armazenados na nuvem serão excluídos. Também serão removidos os registros e operações de sincronização desta conta neste dispositivo. Dados locais sem vínculo com a conta serão preservados. Por segurança, é necessário ter entrado novamente nos últimos 5 minutos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir permanentemente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    var deletedOnServer = false;
    try {
      await auth.deleteAccount();
      deletedOnServer = true;
      await sync.purgeLocalAccount(user.id);
      if (mounted) {
        setState(() => _message = 'Conta e dados excluídos com sucesso.');
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is StateError ? error.message : null;
      setState(
        () => _error = deletedOnServer
            ? 'A conta foi excluída no servidor, mas não foi possível limpar os dados locais deste dispositivo. Não entre em outra conta neste dispositivo até concluir a limpeza.'
            : message ?? 'Não foi possível excluir a conta. Verifique a conexão e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
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
              'Autenticação indisponível. Biblioteca e histórico seguem neste dispositivo.',
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
                      user == null ? _title : 'Minha Conta',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (user == null)
                      const Text(
                        'Entre ou crie uma conta. A sincronização só ocorre após sua autorização.',
                        textAlign: TextAlign.center,
                      )
                    else ...[
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                user.displayName ?? 'Nome não informado',
                              ),
                              subtitle: const Text('Nome'),
                              trailing: IconButton(
                                tooltip: 'Editar nome',
                                onPressed: _busy
                                    ? null
                                    : () => _editDisplayName(user),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.email_outlined),
                              title: Text(user.email),
                              subtitle: const Text('E-mail'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.login_outlined),
                              title: Text(
                                user.provider == 'google'
                                    ? 'Google'
                                    : 'E-mail e senha',
                              ),
                              subtitle: const Text('Método de acesso'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.dark_mode_outlined),
                          title: const Text('Tema escuro'),
                          subtitle: const Text(
                            'Preferência salva neste dispositivo',
                          ),
                          value: widget.themeMode == ThemeMode.dark,
                          onChanged: widget.onThemeModeChanged == null
                              ? null
                              : (enabled) => widget.onThemeModeChanged!(
                                  enabled ? ThemeMode.dark : ThemeMode.light,
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 8),
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
                                  future: widget.syncService!.pendingCount(
                                    user.id,
                                  ),
                                  builder: (context, pendingSnapshot) => Text(
                                    'Sincronização: ${!enabled ? 'desativada' : 'ativada'} · operações pendentes: ${pendingSnapshot.data ?? '…'}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                FutureBuilder<DateTime?>(
                                  future: widget.syncService!.lastSyncAt(
                                    user.id,
                                  ),
                                  builder: (context, lastSyncSnapshot) {
                                    final lastSync = lastSyncSnapshot.data;
                                    return Text(
                                      lastSync == null
                                          ? 'Última sincronização concluída: ainda não registrada'
                                          : 'Última sincronização concluída: ${_formatDateTime(lastSync.toLocal())}',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                if (!enabled) ...[
                                  FilledButton.icon(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _enableSync(
                                            user,
                                            importExisting: true,
                                          ),
                                    icon: const Icon(
                                      Icons.cloud_upload_outlined,
                                    ),
                                    label: const Text(
                                      'Ativar e importar dados locais',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _enableSync(
                                            user,
                                            importExisting: false,
                                          ),
                                    child: const Text(
                                      'Ativar sem importar dados existentes',
                                    ),
                                  ),
                                ] else ...[
                                  FilledButton.icon(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _syncNow(user),
                                    icon: const Icon(Icons.sync),
                                    label: const Text('Sincronizar agora'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _enableSync(
                                            user,
                                            importExisting: true,
                                          ),
                                    child: const Text(
                                      'Importar dados locais pendentes',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _togglePause(user),
                                    child: const Text(
                                      'Pausar / retomar sincronização',
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: _syncBusy
                                        ? null
                                        : () => _disableSync(user),
                                    child: const Text(
                                      'Desativar sincronização',
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _exportLocalData,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Exportar meus dados (JSON)'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _sendPasswordRecoveryLink(user),
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const Text('Enviar link para alterar senha'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sair da conta'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _busy || _syncBusy || widget.syncService == null
                            ? null
                            : () => _deleteAccount(user),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Excluir conta e dados'),
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
                            if (_mode != _AuthMode.resetPassword) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const ValueKey('google-login'),
                                onPressed: _busy ? null : _signInWithGoogle,
                                icon: const Icon(Icons.g_mobiledata, size: 28),
                                label: const Text('Continuar com Google'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ],
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
