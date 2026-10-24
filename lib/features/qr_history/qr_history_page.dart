import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String? _contentTypeFilter;

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

  Future<void> _copyContent(String content) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Conteúdo copiado para a área de transferência.'),
          ),
        );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Não foi possível copiar o conteúdo.')),
        );
    }
  }

  Future<void> _showDetails(QrRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalhes da leitura - ${record.contentType}'),
        content: SingleChildScrollView(child: SelectableText(record.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _copyContent(record.content);
            },
            child: const Text('Copiar conteúdo'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico de leituras?'),
        content: const Text(
          'Todos os registros de leitura deste dispositivo serão removidos. A biblioteca de QR Codes salvos será preservada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar histórico'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteAllReadHistory();
      _reload();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Nao foi possivel limpar o historico.');
      }
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
                      tooltip: 'Limpar histórico de leituras',
                      onPressed: _confirmClearHistory,
                      icon: const Icon(Icons.delete_sweep_outlined),
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
                DropdownButtonFormField<String?>(
                  key: const ValueKey('qr-history-filter'),
                  initialValue: _contentTypeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de conteudo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos os tipos'),
                    ),
                    DropdownMenuItem<String?>(value: 'url', child: Text('URL')),
                    DropdownMenuItem<String?>(
                      value: 'phone',
                      child: Text('Telefone'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'email',
                      child: Text('E-mail'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'whatsapp',
                      child: Text('WhatsApp'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'wifi',
                      child: Text('Wi-Fi'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'vcard',
                      child: Text('Contato'),
                    ),
                    DropdownMenuItem<String?>(value: 'sms', child: Text('SMS')),
                    DropdownMenuItem<String?>(
                      value: 'text',
                      child: Text('Texto'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _contentTypeFilter = value),
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
                      final allRecords = (snapshot.data ?? const <QrRecord>[])
                          .where(
                            (record) =>
                                record.operation == QrRecordOperation.read,
                          )
                          .toList(growable: false);
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
                            final matchesType =
                                _contentTypeFilter == null ||
                                record.contentType == _contentTypeFilter;
                            return matchesText && matchesType;
                          })
                          .toList(growable: false);
                      if (records.isEmpty) {
                        return const Center(
                          child: Text(
                            'As leituras realizadas aparecerão aqui.',
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
                              onTap: () => _showDetails(record),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                      'qr-history-copy-${record.id}',
                                    ),
                                    tooltip: 'Copiar conteúdo',
                                    onPressed: () =>
                                        _copyContent(record.content),
                                    icon: const Icon(Icons.copy_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir do histórico',
                                    onPressed: () => _confirmDelete(record),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
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
