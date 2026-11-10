import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/qr_auth_gateway.dart';
import '../domain/qr_record_repository.dart';
import '../data/qr_sync_service.dart';
import '../features/navigation/qr_ops_shell.dart';
import 'theme/app_theme.dart';

class QrOpsApp extends StatefulWidget {
  const QrOpsApp({
    super.key,
    required this.repository,
    this.authGateway,
    this.syncService,
  });

  final QrRecordRepository repository;
  final QrAuthGateway? authGateway;
  final QrSyncService? syncService;

  @override
  State<QrOpsApp> createState() => _QrOpsAppState();
}

class _QrOpsAppState extends State<QrOpsApp> {
  static const _themePreferenceKey = 'qr_ops_theme_mode';
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_themePreferenceKey);
      if (!mounted) return;
      setState(() {
        _themeMode = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
      });
    } on Object {
      // The app remains usable with the default light theme.
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _themePreferenceKey,
        mode == ThemeMode.dark ? 'dark' : 'light',
      );
    } on Object {
      // Keep the selected theme for this session if persistence is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: QrOpsShell(
        repository: widget.repository,
        authGateway: widget.authGateway,
        syncService: widget.syncService,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
