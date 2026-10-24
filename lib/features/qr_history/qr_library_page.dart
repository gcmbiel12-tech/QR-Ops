import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';
import '../qr_create/qr_code_download.dart';
import '../qr_create/qr_creation_service.dart';
import '../qr_create/qr_png_exporter.dart';

/// Saved QR Codes are records explicitly created by the user; scanned items
/// remain in the separate reading history.
class QrLibraryPage extends StatefulWidget {
  const QrLibraryPage({
    super.key,
    required this.repository,
    required this.refreshToken,
  });

  final QrRecordRepository repository;
  final int refreshToken;

  @override
  State<QrLibraryPage> createState() => _QrLibraryPageState();
}

class _QrLibraryPageState extends State<QrLibraryPage> {
  late Future<List<QrRecord>> _records;
  String _query = '';
  String _type = 'all';
  bool _oldestFirst = false;

  @override
  void initState() {
    super.initState();
    _records = _load();
  }

  @override
  void didUpdateWidget(covariant QrLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.repository != widget.repository) {
      _records = _load();
    }
  }

  Future<List<QrRecord>> _load() async {
    final all = await widget.repository.listLatest(limit: 10000);
    return all
        .where((record) => record.operation == QrRecordOperation.create)
        .toList(growable: false);
  }

  void _reload() => setState(() => _records = _load());

  Future<void> _copy(QrRecord record) async {
    await Clipboard.setData(ClipboardData(text: record.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Conteúdo copiado.')));
  }

  Future<void> _exportPng(QrRecord record) async {
    try {
      final matrix = QrCreationService(widget.repository)
          .encode(record.content);
      final bytes = await const QrPngExporter().export(matrix, dimension: 1024);
      final safeName = (record.name.trim().isEmpty ? 'qr-code' : record.name)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final filename = '${safeName.isEmpty ? 'qr-code' : safeName}.png';
      await downloadQrCodePng(bytes, filename: filename);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PNG exportado.')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel exportar PNG nesta plataforma.'),
          ),
        );
      }
    }
  }

  Future<void> _details(QrRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          record.name.trim().isEmpty ? 'Detalhes do QR Code' : record.name,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.description.trim().isNotEmpty)
                Text(record.description),
              if (record.description.trim().isNotEmpty)
                const SizedBox(height: 12),
              SelectableText(record.content),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _copy(record);
            },
            child: const Text('Copiar conteúdo'),
          ),
        ],
      ),
    );
  }

  Future<void> _editMetadata(QrRecord record) async {
    final nameController = TextEditingController(text: record.name);
    final descriptionController = TextEditingController(
      text: record.description,
    );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Editar detalhes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descricao',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final updated = QrRecord(
        id: record.id,
        operation: record.operation,
        symbology: record.symbology,
        contentType: record.contentType,
        content: record.content,
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        createdAt: record.createdAt,
      );
      final success = await widget.repository.updateById(updated);
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O QR Code nao foi encontrado.')),
        );
        return;
      }
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Detalhes atualizados.')));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel atualizar os detalhes.'),
          ),
        );
      }
    } finally {
      nameController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _delete(QrRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir QR Code salvo?'),
        content: const Text(
          'Esta ação remove o item da biblioteca local. O histórico de leituras não será alterado.',
        ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel excluir o QR Code.')),
        );
      }
    }
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Biblioteca de QR Codes',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar biblioteca',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const Text(
                  'QR Codes criados e salvos neste dispositivo. Leituras ficam no Histórico.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('qr-library-search'),
                  decoration: const InputDecoration(
                    labelText: 'Buscar nome, conteúdo ou tipo',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('qr-library-filter'),
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Todos os tipos'),
                          ),
                          DropdownMenuItem(value: 'url', child: Text('URL')),
                          DropdownMenuItem(
                            value: 'image',
                            child: Text('Imagem'),
                          ),
                          DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                          DropdownMenuItem(value: 'text', child: Text('Texto')),
                        ],
                        onChanged: (value) =>
                            setState(() => _type = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _oldestFirst
                          ? 'Mais recentes primeiro'
                          : 'Mais antigos primeiro',
                      onPressed: () =>
                          setState(() => _oldestFirst = !_oldestFirst),
                      icon: Icon(
                        _oldestFirst
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<QrRecord>>(
                    future: _records,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Text('Carregando biblioteca...'),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Nao foi possivel carregar a biblioteca.',
                              ),
                              TextButton(
                                onPressed: _reload,
                                child: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        );
                      }
                      final all = snapshot.data ?? const <QrRecord>[];
                      final filtered = all.where((record) {
                        final matchesQuery =
                            _query.isEmpty ||
                            record.content.toLowerCase().contains(_query) ||
                            record.name.toLowerCase().contains(_query) ||
                            record.description.toLowerCase().contains(_query) ||
                            record.contentType.toLowerCase().contains(_query) ||
                            record.id.toLowerCase().contains(_query);
                        return matchesQuery &&
                            (_type == 'all' || record.contentType == _type);
                      }).toList();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            all.isEmpty
                                ? 'Sua biblioteca esta vazia. Crie e salve um QR Code.'
                                : 'Nenhum QR Code corresponde a busca.',
                          ),
                        );
                      }
                      if (_oldestFirst) {
                        filtered.sort(
                          (a, b) => a.createdAt.compareTo(b.createdAt),
                        );
                      }
                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final record = filtered[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.qr_code_2_rounded),
                              title: Text(
                                record.name.trim().isEmpty
                                    ? record.content
                                    : record.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${record.contentType.toUpperCase()} • ${_date(record.createdAt)}',
                                  ),
                                  if (record.description.trim().isNotEmpty)
                                    Text(
                                      record.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              onTap: () => _details(record),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Acoes do QR Code',
                                onSelected: (action) {
                                  if (action == 'copy') _copy(record);
                                  if (action == 'details') _details(record);
                                  if (action == 'edit') _editMetadata(record);
                                  if (action == 'export') _exportPng(record);
                                  if (action == 'delete') _delete(record);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'details',
                                    child: Text('Ver detalhes'),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar nome e descricao'),
                                  ),

                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text('Copiar conteudo'),
                                  ),
                                  PopupMenuItem(
                                    value: 'export',
                                    child: Text('Exportar PNG'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Excluir'),
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
