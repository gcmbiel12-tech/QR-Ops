import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_app_config.dart';
import '../data/supabase_qr_auth_gateway.dart';
import '../data/qr_record_repository_factory.dart';
import '../data/qr_sync_outbox_factory.dart';
import '../data/qr_sync_service.dart';
import '../data/supabase_qr_sync_transport.dart';
import '../domain/qr_auth_gateway.dart';
import '../domain/qr_record_repository.dart';
import '../domain/sync_owner_context.dart';
import 'qr_ops_app.dart';

class QrOpsBootstrap extends StatefulWidget {
  const QrOpsBootstrap({super.key, this.openRepository});

  final Future<QrRecordRepository> Function()? openRepository;

  @override
  State<QrOpsBootstrap> createState() => _QrOpsBootstrapState();
}

class _QrOpsBootstrapState extends State<QrOpsBootstrap> {
  QrRecordRepository? _repository;
  QrAuthGateway? _authGateway;
  QrSyncService? _syncService;
  final SyncOwnerContext _syncOwnerContext = SyncOwnerContext();
  StreamSubscription<QrAuthUser?>? _authSubscription;
  Timer? _syncTimer;
  bool _startupFailed = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      final repository = await (widget.openRepository ?? () =>
          openQrRecordRepository(syncOwnerContext: _syncOwnerContext))();
      // Local-first Free history retention: UTC cutoff, read entries only.
      try {
        await repository.pruneReadHistoryBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 7)),
        );
      } on Object {
        // A cleanup failure must not make existing local data inaccessible.
      }
      QrAuthGateway? authGateway;
      QrSyncService? syncService;
      if (SupabaseAppConfig.isConfigured) {
        try {
          SupabaseAppConfig.validate();
          try {
            Supabase.instance.client;
          } on Object {
            await Supabase.initialize(
              url: SupabaseAppConfig.url,
              publishableKey: SupabaseAppConfig.publishableKey,
            );
          }
          final client = Supabase.instance.client;
          authGateway = SupabaseQrAuthGateway(client);
          _syncOwnerContext.update(authGateway.currentUser?.id);
          try {
            syncService = QrSyncService(
              localRepository: repository,
              outbox: await openQrSyncOutbox(),
              transport: SupabaseQrSyncTransport(client),
            );
          } on Object {
            // Local mode remains usable if the durable sync store cannot open.
          }
        } on Object {
          // Authentication is optional; local storage must remain available.
        }
      }
      if (!mounted) return;
      _authSubscription?.cancel();
      _authSubscription = authGateway?.authStateChanges.listen((user) {
        _syncOwnerContext.update(user?.id);
        if (user != null) unawaited(_trySync(user.id));
      });
      _syncTimer?.cancel();
      if (syncService != null) {
        _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
          final user = authGateway?.currentUser;
          if (user != null) unawaited(_trySync(user.id));
        });
      }
      setState(() {
        _repository = repository;
        _authGateway = authGateway;
        _syncService = syncService;
        _startupFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _startupFailed = true);
    }
  }

  Future<void> _trySync(String ownerId) async {
    try {
      await _syncService?.syncOnce(ownerId);
    } on Object {
      // Keep local data and the persistent outbox; the next timer/manual retry can resume.
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _repository = null;
      _startupFailed = false;
    });
    _initializeDatabase();
  }

  @override
  Widget build(BuildContext context) {
    if (_repository case final repository?) {
      return QrOpsApp(
        repository: repository,
        authGateway: _authGateway,
        syncService: _syncService,
      );
    }
    if (_startupFailed) return _DatabaseErrorPage(onRetry: _retry);

    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Preparando o armazenamento local',
          ),
        ),
      ),
    );
  }
}

class _DatabaseErrorPage extends StatelessWidget {
  const _DatabaseErrorPage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storage_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Não foi possível preparar o armazenamento local.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tente novamente. Nenhum dado pessoal foi enviado.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
