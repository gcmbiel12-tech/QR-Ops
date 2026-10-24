import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

class QrOcrLibraryPage extends StatefulWidget {
  const QrOcrLibraryPage({
    super.key,
    required this.repository,
    required this.refreshToken,
  });

  final QrRecordRepository repository;
  final int refreshToken;

  @override
  State<QrOcrLibraryPage> createState() => _QrOcrLibraryPageState();
}

class _QrOcrLibraryPageState extends State<QrOcrLibraryPage> {
  late Future<List<QrRecord>> _records;
  String _query = '';
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _records = _load();
  }

  @override
  void didUpdateWidget(covariant QrOcrLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.repository != widget.repository) {
      _records = _load();
    }
  }

  Future<List<QrRecord>> _load() async =>
      (await widget.repository.listLatest(limit: 10000))
          .where((record) => record.operation == QrRecordOperation.ocr)
          .toList(growable: false);

  void _reload() => setState(() => _records = _load());

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Texto copiado.')));
    }
  }

  Future<void> _download(String text, String filename) async {
    await FileSaver.instance.saveFile(
      name: filename,
      bytes: Uint8List.fromList(utf8.encode(text)),
      fileExtension: 'txt',
      mimeType: MimeType.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arquivo TXT preparado para salvar.')),
      );
    }
  }

  Future<void> _share(String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Texto OCR do QR Ops'),
    );
  }

  Future<void> _details(QrRecord record) async {
    final name = TextEditingController(text: record.name);
    final text = TextEditingController(text: record.content);
    var saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: Text(
              record.name.trim().isEmpty ? 'Texto reconhecido' : record.name,
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Nome (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: text,
                      minLines: 6,
                      maxLines: 14,
                      decoration: const InputDecoration(
                        labelText: 'Texto OCR editável',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A imagem original não é armazenada. Abrir este item não executa OCR novamente.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              TextButton.icon(
                onPressed: text.text.isEmpty ? null : () => _copy(text.text),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
              TextButton.icon(
                onPressed: text.text.isEmpty
                    ? null
                    : () => _download(
                        text.text,
                        'qr-ops-ocr-${record.id.substring(0, 8)}',
                      ),
                icon: const Icon(Icons.download),
                label: const Text('Baixar TXT'),
              ),
              TextButton.icon(
                onPressed: text.text.isEmpty ? null : () => _share(text.text),
                icon: const Icon(Icons.share),
                label: const Text('Compartilhar'),
              ),
              FilledButton(
                onPressed: saving || text.text.trim().isEmpty
                    ? null
                    : () async {
                        updateDialog(() => saving = true);
                        try {
                          final updated = QrRecord(
                            id: record.id,
                            operation: QrRecordOperation.ocr,
                            symbology: 'text',
                            contentType: 'ocr_text',
                            content: text.text,
                            name: name.text.trim(),
                            description: record.description,
                            createdAt: record.createdAt,
                            revision: record.revision,
                          );
                          final success = await widget.repository.updateById(
                            updated,
                          );
                          if (!success) {
                            throw StateError(
                              'O registro OCR não foi encontrado.',
                            );
                          }
                          if (mounted) _reload();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Alterações salvas.'),
                              ),
                            );
                          }
                        } on Object {
                          updateDialog(() => saving = false);
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Não foi possível salvar as alterações.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(saving ? 'Salvando…' : 'Salvar alterações'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      text.dispose();
    }
  }

  Future<void> _deleteSelected(List<QrRecord> records) async {
    final selected = records
        .where((record) => _selectedIds.contains(record.id))
        .toList();
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir textos OCR selecionados?'),
        content: Text(
          '${selected.length} registros OCR serão removidos deste dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir selecionados'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var deleted = 0;
    var failed = 0;
    for (final record in selected) {
      try {
        if (await widget.repository.deleteById(record.id)) {
          deleted++;
        } else {
          failed++;
        }
      } on Object {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _selectedIds.removeAll(selected.map((record) => record.id)));
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$deleted de ${selected.length} textos excluídos.${failed == 0 ? '' : ' Falhas: $failed.'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
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
                      'Textos reconhecidos',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Atualizar textos OCR',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const Text(
                'Textos OCR salvos manualmente. Abrir ou pesquisar não inicia novo reconhecimento.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('ocr-library-search'),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Pesquisar nome ou texto',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<QrRecord>>(
                  future: _records,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Não foi possível carregar os textos OCR.'),
                      );
                    }
                    final all = snapshot.data ?? const <QrRecord>[];
                    final records = all
                        .where(
                          (record) =>
                              _query.isEmpty ||
                              record.content.toLowerCase().contains(_query) ||
                              record.name.toLowerCase().contains(_query),
                        )
                        .toList();
                    if (records.isEmpty) {
                      return const Center(
                        child: Text('Os textos OCR salvos aparecerão aqui.'),
                      );
                    }
                    final selectedCount = records
                        .where((record) => _selectedIds.contains(record.id))
                        .length;
                    return Column(
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              '$selectedCount selecionados de ${records.length}',
                            ),
                            TextButton(
                              key: const ValueKey(
                                'ocr-library-select-filtered',
                              ),
                              onPressed: () => setState(() {
                                if (selectedCount == records.length) {
                                  _selectedIds.removeAll(
                                    records.map((record) => record.id),
                                  );
                                } else {
                                  _selectedIds.addAll(
                                    records.map((record) => record.id),
                                  );
                                }
                              }),
                              child: Text(
                                selectedCount == records.length
                                    ? 'Desmarcar resultados'
                                    : 'Selecionar resultados filtrados',
                              ),
                            ),
                            if (selectedCount > 0)
                              TextButton.icon(
                                onPressed: () => _copy(
                                  records
                                      .where(
                                        (record) =>
                                            _selectedIds.contains(record.id),
                                      )
                                      .map((record) => record.content)
                                      .join('\n\n---\n\n'),
                                ),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copiar selecionados'),
                              ),
                            if (selectedCount > 0)
                              TextButton.icon(
                                onPressed: () => _deleteSelected(records),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Excluir selecionados'),
                              ),
                          ],
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final record = records[index];
                              return Card(
                                child: ListTile(
                                  leading: Checkbox(
                                    key: ValueKey(
                                      'ocr-library-select-${record.id}',
                                    ),
                                    value: _selectedIds.contains(record.id),
                                    onChanged: (value) => setState(() {
                                      if (value ?? false) {
                                        _selectedIds.add(record.id);
                                      } else {
                                        _selectedIds.remove(record.id);
                                      }
                                    }),
                                  ),
                                  title: Text(
                                    record.name.trim().isEmpty
                                        ? record.content
                                        : record.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${record.createdAt.toLocal()} • ${record.content.length} caracteres',
                                  ),
                                  onTap: () => _details(record),
                                  trailing: IconButton(
                                    tooltip: 'Abrir e editar texto OCR',
                                    onPressed: () => _details(record),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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
