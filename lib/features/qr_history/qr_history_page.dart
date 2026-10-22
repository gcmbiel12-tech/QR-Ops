import 'package:flutter/material.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

class QrHistoryPage extends StatefulWidget {
  const QrHistoryPage({
    super.key,
    required this.repository,
    required this.refreshToken,
    required this.isActive,
  });

  final QrRecordRepository repository;
  final int refreshToken;
  final bool isActive;

  @override
  State<QrHistoryPage> createState() => _QrHistoryPageState();
}

class _QrHistoryPageState extends State<QrHistoryPage> {
  Future<List<QrRecord>>? _records;
  String? _error;
  String _searchQuery = '';
  QrRecordOperation? _operationFilter;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _records = widget.repository.listLatest();
  }

  @override
  void didUpdateWidget(covariant QrHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) return;
    if (!oldWidget.isActive || oldWidget.refreshToken != widget.refreshToken) {
      _records = widget.repository.listLatest();
      _error = null;
    }
  }

  void _reload() {
    setState(() {
      _error = null;
      _records = widget.repository.listLatest();
    });
  }

  Future<void> _confirmDelete(QrRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir do histórico?'),
        content: const Text('Esta ação remove o registro deste dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.repository.deleteById(record.id);
      _reload();
    } on Object {
      setState(() => _error = 'Não foi possível excluir este registro.');
    }
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Histórico local',
                        style: textTheme.headlineMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar histórico',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Os registros permanecem neste dispositivo.'),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('qr-history-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Pesquisar conteúdo',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<QrRecordOperation?>(
                  key: const ValueKey('qr-history-filter'),
                  initialValue: _operationFilter,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de registro',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<QrRecordOperation?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem<QrRecordOperation?>(
                      value: QrRecordOperation.create,
                      child: Text('Criados'),
                    ),
                    DropdownMenuItem<QrRecordOperation?>(
                      value: QrRecordOperation.read,
                      child: Text('Lidos'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _operationFilter = value),
                ),
                const SizedBox(height: 16),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: FutureBuilder<List<QrRecord>>(
                    future: _records,
                    builder: (context, snapshot) {
                      if (_records == null) {
                        return const Center(
                          child: Text(
                            'Abra o histórico para carregar os registros.',
                          ),
                        );
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Text('Carregando histórico…'),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Não foi possível carregar o histórico.'),
                        );
                      }
                      final allRecords = snapshot.data ?? const <QrRecord>[];
                      final records = allRecords
                          .where((record) {
                            final matchesText =
                                _searchQuery.isEmpty ||
                                record.content.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                record.symbology.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                record.contentType.toLowerCase().contains(
                                  _searchQuery,
                                );
                            final matchesOperation =
                                _operationFilter == null ||
                                record.operation == _operationFilter;
                            return matchesText && matchesOperation;
                          })
                          .toList(growable: false);
                      if (records.isEmpty) {
                        return const Center(
                          child: Text(
                            'Os códigos criados e lidos aparecerão aqui.',
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: const Icon(Icons.qr_code_2_rounded),
                              title: Text(
                                record.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${record.operation == QrRecordOperation.read ? 'Lido' : 'Criado'} • ${_formatDate(record.createdAt)}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Excluir do histórico',
                                onPressed: () => _confirmDelete(record),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          );
                        },
                      );
                    },
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
