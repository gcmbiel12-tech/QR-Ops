import 'package:flutter/material.dart';

import 'qr_batch_export_service.dart';
import 'qr_batch_parser.dart';
import 'qr_code_preview.dart';
import 'qr_creation_service.dart';

class QrBatchCreatePage extends StatefulWidget {
  const QrBatchCreatePage({
    super.key,
    required this.service,
    required this.onRecordsCreated,
  });

  final QrCreationService service;
  final VoidCallback onRecordsCreated;

  @override
  State<QrBatchCreatePage> createState() => _QrBatchCreatePageState();
}

class _QrBatchCreatePageState extends State<QrBatchCreatePage> {
  static const _maxItems = 500;
  final _inputController = TextEditingController();
  final _parser = const QrBatchParser(maxItems: _maxItems);
  List<String> _items = const [];
  Set<int> _selected = {};
  List<String> _duplicates = const [];
  List<String> _errors = const [];
  List<String> _parseErrors = const [];
  bool _hyphenLiteral = false;
  bool _saving = false;
  String _size = 'Médio';

  int get _previewSize => switch (_size) {
    'Pequeno' => 72,
    'Grande' => 144,
    _ => 104,
  };

  void _parse() {
    final result = _parser.parse(
      _inputController.text,
      hyphenIsLiteral: _hyphenLiteral,
    );
    final validationErrors = _validateItems(result.items, result.errors);
    setState(() {
      _items = result.items;
      _selected = result.items.isEmpty
          ? <int>{}
          : Set<int>.from(List<int>.generate(result.items.length, (i) => i));
      _duplicates = result.duplicates;
      _parseErrors = result.errors;
      _errors = validationErrors;
    });
  }

  List<String> _validateItems(List<String> items, List<String> parserErrors) {
    final errors = [...parserErrors];
    for (final item in items) {
      try {
        widget.service.encode(item);
      } on Object {
        errors.add(
          'O conteúdo "${item.length > 32 ? '${item.substring(0, 32)}…' : item}" não pode ser codificado em um QR Code.',
        );
      }
    }
    return errors;
  }

  void _toggle(int index, bool selected) {
    setState(() {
      _selected = Set<int>.from(_selected);
      if (selected) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  void _remove(int index) {
    setState(() {
      final next = [..._items]..removeAt(index);
      _items = next;
      _selected = {
        for (final oldIndex in _selected)
          if (oldIndex < index)
            oldIndex
          else if (oldIndex > index)
            oldIndex - 1,
      };
      _duplicates = _findDuplicates(next);
      _errors = _validateItems(next, _parseErrors);
    });
  }

  List<String> _findDuplicates(List<String> items) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final item in items) {
      if (!seen.add(item)) duplicates.add(item);
    }
    return duplicates.toList();
  }

  Future<void> _edit(int index) async {
    final controller = TextEditingController(text: _items[index]);
    try {
      final updated = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Editar código'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Conteúdo do QR Code',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );
      if (updated == null || !mounted) return;
      if (updated.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O conteúdo não pode ficar vazio.')),
        );
        return;
      }
      try {
        widget.service.encode(updated);
      } on Object {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O conteúdo não pode ser codificado em um QR Code.'),
          ),
        );
        return;
      }
      setState(() {
        final next = [..._items];
        next[index] = updated;
        _items = next;
        _duplicates = _findDuplicates(next);
      });
    } finally {
      controller.dispose();
    }
  }

  Future<void> _saveSelected() async {
    if (_saving || _selected.isEmpty || _errors.isNotEmpty) return;
    final selectedItems = [
      for (var i = 0; i < _items.length; i++)
        if (_selected.contains(i)) _items[i],
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salvar QR Codes selecionados?'),
        content: Text(
          'Serão salvos ${selectedItems.length} QR Codes na biblioteca local.'
          '${_duplicates.isEmpty ? '' : '\nA prévia contém ${_duplicates.length} código(s) duplicado(s), mantidos conforme sua escolha.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salvar selecionados'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    var saved = 0;
    final failures = <String>[];
    try {
      for (final item in selectedItems) {
        try {
          await widget.service.create(item, contentType: 'text');
          saved++;
        } on Object {
          failures.add(item);
        }
      }
      if (!mounted) return;
      if (saved > 0) widget.onRecordsCreated();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resultado do salvamento'),
          content: Text(
            '$saved de ${selectedItems.length} QR Codes salvos.'
            '${failures.isEmpty ? '' : '\nFalhas: ${failures.length}. Os itens com falha continuam na prévia.'}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _export(String action) async {
    if (_saving || _items.isEmpty || _errors.isNotEmpty) return;
    final selectedOnly = action.endsWith('-selected');
    final contents = <String>[
      for (var i = 0; i < _items.length; i++)
        if (!selectedOnly || _selected.contains(i)) _items[i],
    ];
    if (contents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um QR Code para exportar.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      const exporter = QrBatchExportService();
      if (action.startsWith('zip')) {
        await exporter.saveZip(contents, widget.service, size: _size);
      } else {
        await exporter.savePdf(
          contents,
          widget.service,
          size: _size,
          labelSheet: action.contains('labels'),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contents.length} QR Codes exportados.')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível concluir a exportação. Nenhum item foi removido da prévia.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _items.isNotEmpty && _selected.length == _items.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Criação em massa')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Informe códigos separados por linha, vírgula ou ponto e vírgula, ou intervalos como 1001-1020. Revise os itens antes de confirmar.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('qr-batch-input'),
                    controller: _inputController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Códigos para gerar',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hyphenLiteral,
                    onChanged: (value) =>
                        setState(() => _hyphenLiteral = value ?? false),
                    title: const Text(
                      'Tratar hífen como parte do código (não como intervalo)',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const ValueKey('qr-batch-preview'),
                      onPressed: _saving ? null : _parse,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Gerar prévia'),
                    ),
                  ),
                  if (_errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _errors.join('\n'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_items.length} itens • ${_selected.length} selecionados',
                          ),
                        ),
                        DropdownButton<String>(
                          value: _size,
                          onChanged: (value) =>
                              setState(() => _size = value ?? 'Médio'),
                          items: const [
                            DropdownMenuItem(
                              value: 'Pequeno',
                              child: Text('Pequeno'),
                            ),
                            DropdownMenuItem(
                              value: 'Médio',
                              child: Text('Médio'),
                            ),
                            DropdownMenuItem(
                              value: 'Grande',
                              child: Text('Grande'),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _selected = allSelected
                                ? <int>{}
                                : Set<int>.from(
                                    List<int>.generate(_items.length, (i) => i),
                                  ),
                          ),
                          child: Text(
                            allSelected
                                ? 'Desmarcar todos'
                                : 'Selecionar todos',
                          ),
                        ),
                      ],
                    ),
                    if (_duplicates.isNotEmpty)
                      Text(
                        'Duplicatas detectadas: ${_duplicates.join(', ')}. Elas foram mantidas para sua decisão.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          Widget preview;
                          try {
                            preview = QrCodePreview(
                              image: widget.service.encode(item),
                              size: _previewSize.toDouble(),
                            );
                          } on Object {
                            preview = SizedBox(
                              width: _previewSize.toDouble(),
                              height: _previewSize.toDouble(),
                              child: const Icon(Icons.error_outline),
                            );
                          }
                          return Card(
                            child: ListTile(
                              key: ValueKey('qr-batch-item-$index'),
                              leading: Checkbox(
                                value: _selected.contains(index),
                                onChanged: (value) =>
                                    _toggle(index, value ?? false),
                              ),
                              title: Text(
                                item,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: preview,
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Ações do item',
                                onSelected: (action) {
                                  if (action == 'edit') _edit(index);
                                  if (action == 'remove') _remove(index);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remover'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('qr-batch-save-selected'),
                          onPressed:
                              _saving || _selected.isEmpty || _errors.isNotEmpty
                              ? null
                              : _saveSelected,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? 'Processando…'
                                : 'Salvar selecionados (${_selected.length})',
                          ),
                        ),
                        PopupMenuButton<String>(
                          enabled: !_saving && _errors.isEmpty,
                          tooltip: 'Exportar QR Codes',
                          onSelected: _export,
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'zip-selected',
                              child: Text('ZIP dos selecionados'),
                            ),
                            const PopupMenuItem(
                              value: 'pdf-labels-selected',
                              child: Text('PDF etiquetas dos selecionados'),
                            ),
                            const PopupMenuItem(
                              value: 'pdf-report-selected',
                              child: Text('PDF relatório dos selecionados'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'zip-all',
                              child: Text('ZIP de todos'),
                            ),
                            const PopupMenuItem(
                              value: 'pdf-labels-all',
                              child: Text('PDF etiquetas de todos'),
                            ),
                            const PopupMenuItem(
                              value: 'pdf-report-all',
                              child: Text('PDF relatório de todos'),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_outlined),
                                SizedBox(width: 8),
                                Text('Exportar'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Expanded(
                      child: Center(
                        child: Text('A prévia dos códigos aparecerá aqui.'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
