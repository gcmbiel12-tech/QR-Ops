import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QR Ops', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Sua base para operações com códigos QR.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fundação inicial',
                                style: textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'A navegação e o armazenamento local estão '
                                'preparados. Já é possível criar QR Codes e consultar o '
                                'histórico local. A leitura pela câmera será adicionada '
                                'em uma etapa futura.',
                                style: textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Áreas do aplicativo', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                _AreaShortcut(
                  icon: Icons.qr_code_2_rounded,
                  title: 'Criar',
                  description: 'Gere um QR Code e salve no histórico local.',
                  onTap: () => onNavigate(1),
                ),
                _AreaShortcut(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Ler',
                  description: 'Leitura pela câmera, planejada.',
                  onTap: () => onNavigate(2),
                ),
                _AreaShortcut(
                  icon: Icons.folder_rounded,
                  title: 'Organizar',
                  description:
                      'Consulte e remova QR Codes salvos neste dispositivo.',
                  onTap: () => onNavigate(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaShortcut extends StatelessWidget {
  const _AreaShortcut({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(description),
          trailing: const Icon(Icons.arrow_forward_rounded),
        ),
      ),
    );
  }
}
