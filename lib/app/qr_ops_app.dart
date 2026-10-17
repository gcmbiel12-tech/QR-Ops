import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/qr_record_repository.dart';
import '../features/navigation/qr_ops_shell.dart';
import 'theme/app_theme.dart';

class QrOpsApp extends StatelessWidget {
  const QrOpsApp({super.key, required this.repository});

  final QrRecordRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: QrOpsShell(repository: repository),
    );
  }
}
