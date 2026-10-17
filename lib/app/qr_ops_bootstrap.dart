import 'package:flutter/material.dart';

import '../data/qr_record_repository_factory.dart';
import '../domain/qr_record_repository.dart';
import 'qr_ops_app.dart';

class QrOpsBootstrap extends StatefulWidget {
  const QrOpsBootstrap({super.key, this.openRepository});

  final Future<QrRecordRepository> Function()? openRepository;

  @override
  State<QrOpsBootstrap> createState() => _QrOpsBootstrapState();
}

class _QrOpsBootstrapState extends State<QrOpsBootstrap> {
  QrRecordRepository? _repository;
  bool _startupFailed = false;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      final repository =
          await (widget.openRepository ?? openQrRecordRepository)();
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _startupFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _startupFailed = true);
    }
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
      return QrOpsApp(repository: repository);
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
