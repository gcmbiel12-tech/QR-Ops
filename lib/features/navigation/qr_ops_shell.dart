import 'package:flutter/material.dart';

import '../../domain/qr_record_repository.dart';
import '../home/home_page.dart';
import '../qr_create/qr_create_page.dart';
import '../qr_create/qr_creation_service.dart';
import '../qr_scan/qr_scan_page.dart';
import '../qr_history/qr_history_page.dart';

class _Area {
  const _Area({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class QrOpsShell extends StatefulWidget {
  const QrOpsShell({super.key, required this.repository});

  final QrRecordRepository repository;

  @override
  State<QrOpsShell> createState() => _QrOpsShellState();
}

class _QrOpsShellState extends State<QrOpsShell> {
  static const _areas = [
    _Area(
      label: 'Início',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _Area(
      label: 'Criar',
      icon: Icons.qr_code_2_outlined,
      selectedIcon: Icons.qr_code_2_rounded,
    ),
    _Area(
      label: 'Ler',
      icon: Icons.qr_code_scanner_outlined,
      selectedIcon: Icons.qr_code_scanner_rounded,
    ),
    _Area(
      label: 'Organizar',
      icon: Icons.folder_open_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
  ];

  int _selectedIndex = 0;
  int _historyRefreshToken = 0;
  late final QrCreationService _creationService;

  @override
  void initState() {
    super.initState();
    _creationService = QrCreationService(widget.repository);
  }

  void _selectArea(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;

        return Scaffold(
          body: Row(
            children: [
              if (useRail)
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectArea,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final area in _areas) _railDestination(area),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    HomePage(onNavigate: _selectArea),
                    QrCreatePage(
                      service: _creationService,
                      onRecordCreated: () =>
                          setState(() => _historyRefreshToken++),
                    ),
                    QrScanPage(
                      isActive: _selectedIndex == 2,
                    ),
                    QrHistoryPage(
                      repository: widget.repository,
                      refreshToken: _historyRefreshToken,
                      isActive: _selectedIndex == 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectArea,
                  destinations: [
                    for (final area in _areas) _bottomDestination(area),
                  ],
                ),
        );
      },
    );
  }

  NavigationDestination _bottomDestination(_Area area) {
    return NavigationDestination(
      icon: Icon(area.icon, key: ValueKey('nav-${area.label.toLowerCase()}')),
      selectedIcon: Icon(area.selectedIcon),
      label: area.label,
    );
  }

  NavigationRailDestination _railDestination(_Area area) {
    return NavigationRailDestination(
      icon: Icon(area.icon, key: ValueKey('nav-${area.label.toLowerCase()}')),
      selectedIcon: Icon(area.selectedIcon),
      label: Text(area.label),
    );
  }
}
