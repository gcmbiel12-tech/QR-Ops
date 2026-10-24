import 'package:flutter/material.dart';

import '../../domain/qr_record_repository.dart';
import 'qr_history_page.dart';
import 'qr_library_page.dart';

class QrOrganizePage extends StatefulWidget {
  const QrOrganizePage({
    super.key,
    required this.repository,
    required this.refreshToken,
    required this.isActive,
  });
  final QrRecordRepository repository;
  final int refreshToken;
  final bool isActive;

  @override
  State<QrOrganizePage> createState() => _QrOrganizePageState();
}

class _QrOrganizePageState extends State<QrOrganizePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: 0)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: Colors.transparent,
        child: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.folder_outlined), text: 'Biblioteca'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Histórico'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            QrLibraryPage(
              repository: widget.repository,
              refreshToken: widget.refreshToken,
            ),
            QrHistoryPage(
              repository: widget.repository,
              refreshToken: widget.refreshToken,
              isActive: widget.isActive && _tabs.index == 1,
            ),
          ],
        ),
      ),
    ],
  );
}
