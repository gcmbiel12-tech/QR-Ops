import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QR Ops', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Tudo pronto para o próximo passo.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  color: colors.primaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 42,
                          color: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'O que vamos criar hoje?',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Gere um QR Code, leia um código ou consulte os itens salvos.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                key: const ValueKey('home-start-creating'),
                                onPressed: () => onNavigate(1),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Ir para criação'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Acesso rápido',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _AreaShortcut(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Ler um código',
                  description: 'Leia QR Codes e códigos de barras.',
                  onTap: () => onNavigate(2),
                ),
                _AreaShortcut(
                  icon: Icons.folder_rounded,
                  title: 'Organizar códigos',
                  description: 'Consulte os códigos salvos neste dispositivo.',
                  onTap: () => onNavigate(3),
                ),
                const SizedBox(height: 20),
                Text(
                  'Mais recursos serão adicionados aqui.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
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
