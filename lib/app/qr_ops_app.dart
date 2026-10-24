import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/qr_auth_gateway.dart';
import '../domain/qr_record_repository.dart';
import '../data/qr_sync_service.dart';
import '../features/navigation/qr_ops_shell.dart';
import 'theme/app_theme.dart';

class QrOpsApp extends StatelessWidget {
  const QrOpsApp({super.key, required this.repository, this.authGateway, this.syncService});

  final QrRecordRepository repository;
  final QrAuthGateway? authGateway;
  final QrSyncService? syncService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: QrOpsShell(
        repository: repository,
        authGateway: authGateway,
        syncService: syncService,
      ),
    );
  }
}
