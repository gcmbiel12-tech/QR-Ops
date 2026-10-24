import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

class QrBatchScanPage extends StatefulWidget {
  const QrBatchScanPage({
    super.key,
    required this.repository,
    required this.onRecordsSaved,
  });

  final QrRecordRepository repository;
  final VoidCallback onRecordsSaved;

  @override
  State<QrBatchScanPage> createState() => _QrBatchScanPageState();
}

class _QrBatchScanPageState extends State<QrBatchScanPage> {
  late final MobileScannerController _controller;
  final List<String> _items = [];
  final Set<String> _seen = {};
  bool _running = false;
  bool _finished = false;
  bool _allowDuplicates = false;
  bool _saving = false;
  String? _message;
  String? _lastValue;
  DateTime? _lastCaptureAt;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running || _finished || _saving) return;
    try {
      await _controller.start();
      if (mounted) {
        setState(() {
          _running = true;
          _message = 'Leitura ativa. Posicione um código diante da câmera.';
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = 'Não foi possível iniciar a câmera. Verifique as permissões do dispositivo.',
        );
      }
    }
  }

  Future<void> _pause() async {
    if (!_running) return;
    await _controller.stop();
    if (mounted) {
      setState(() {
        _running = false;
        _message = 'Leitura pausada. Pressione Retomar para continuar.';
      });
    }
  }

  Future<void> _finish() async {
    await _pause();
    if (mounted) {
      setState(() {
        _finished = true;
        _message = 'Revise os resultados antes de salvar ou exportar.';
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_running || _finished) return;
    final barcode = capture.barcodes
        .where((value) => value.rawValue?.trim().isNotEmpty ?? false)
        .firstOrNull;
    final value = barcode?.rawValue?.trim();
    if (value == null) return;
    final now = DateTime.now();
    if (value == _lastValue &&
        _lastCaptureAt != null &&
        now.difference(_lastCaptureAt!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastValue = value;
    _lastCaptureAt = now;
    if (!_allowDuplicates && !_seen.add(value)) {
      if (mounted) {
        setState(
          () =>
              _message = 'Código duplicado ignorado. Total: ${_items.length}.',
        );
      }
      return;
    }
    _seen.add(value);
    if (mounted) {
      setState(() {
        _items.add(value);
        _message = 'Código adicionado ao lote (${_items.length}).';
      });
    }
  }

  Future<void> _remove(int index) async {
    setState(() {
      _items.removeAt(index);
      _seen
        ..clear()
        ..addAll(_items);
    });
  }

  Future<void> _clear() async {
    if (_items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar lote?'),
        content: Text(
          'Serão removidos ${_items.length} resultados temporários. O histórico salvo não será alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar lote'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _items.clear();
      _seen.clear();
      _message = 'Lote limpo.';
    });
  }

  Future<void> _saveHistory() async {
    if (_saving || _items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvar leituras no histórico?'),
        content: Text(
          '${_items.length} resultados serão adicionados ao histórico local. A retenção existente do histórico será mantida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar no histórico'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    var saved = 0;
    var failed = 0;
    try {
      for (final item in _items) {
        try {
          await widget.repository.insert(
            QrRecord.read(content: item, symbology: 'qr'),
          );
          saved++;
        } on Object {
          failed++;
        }
      }
      if (saved > 0) widget.onRecordsSaved();
      if (mounted) {
        setState(
          () => _message =
              '$saved de ${_items.length} leituras salvas.${failed == 0 ? '' : ' Falhas: $failed.'}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _message = 'Conteúdo copiado.');
  }

  Future<void> _download() async {
    if (_items.isEmpty) return;
    final text = _items
        .asMap()
        .entries
        .map(
          (entry) =>
              '${entry.key + 1};${entry.value.replaceAll(';', ',').replaceAll('\n', ' ')}',
        )
        .join('\n');
    try {
      await FileSaver.instance.saveFile(
        name: 'qr-ops-leituras-lote',
        bytes: Uint8List.fromList(utf8.encode('numero;conteudo\n$text')),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) {
        setState(() => _message = 'Arquivo CSV preparado para salvar.');
      }
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível exportar o CSV.');
      }
    }
  }

  Future<void> _share() async {
    if (_items.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _items
              .asMap()
              .entries
              .map((entry) => '${entry.key + 1}. ${entry.value}')
              .join('\n'),
          subject: 'Leituras em massa — QR Ops',
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível abrir o compartilhamento.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Leitura em massa')),
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
                  'A câmera não registra leituras ao abrir esta tela. Pressione Iniciar leitura para começar. A captura é sequencial; a detecção de vários códigos no mesmo quadro não é prometida.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _finished
                        ? const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Icon(Icons.fact_check_outlined, size: 48),
                            ),
                          )
                        : MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                            errorBuilder: (context, error) => Center(
                              child: Text(
                                'Câmera indisponível: ${error.errorCode.name}',
                              ),
                            ),
                          ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowDuplicates,
                  onChanged: _running || _finished
                      ? null
                      : (value) =>
                            setState(() => _allowDuplicates = value ?? false),
                  title: const Text('Permitir códigos duplicados'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_running && !_finished)
                      FilledButton.icon(
                        key: const ValueKey('qr-batch-scan-start'),
                        onPressed: _saving ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Iniciar leitura'),
                      ),
                    if (_running)
                      OutlinedButton.icon(
                        key: const ValueKey('qr-batch-scan-pause'),
                        onPressed: _pause,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pausar'),
                      ),
                    if (!_running && !_finished && _items.isNotEmpty)
                      FilledButton.icon(
                        key: const ValueKey('qr-batch-scan-resume'),
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Retomar'),
                      ),
                    if (!_finished && (_running || _items.isNotEmpty))
                      OutlinedButton.icon(
                        key: const ValueKey('qr-batch-scan-finish'),
                        onPressed: _finish,
                        icon: const Icon(Icons.check),
                        label: const Text('Finalizar e revisar'),
                      ),
                    if (_items.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Limpar lote'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_items.length} códigos capturados',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(
                          _items[index],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Resultado ${index + 1}'),
                            content: SelectableText(_items[index]),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Fechar'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _copy(_items[index]);
                                },
                                child: const Text('Copiar'),
                              ),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remover do lote',
                          onPressed: _running ? null : () => _remove(index),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_finished && _items.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('qr-batch-scan-save'),
                        onPressed: _saving ? null : _saveHistory,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'Salvando…' : 'Salvar no histórico',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copy(_items.join('\n')),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar todos'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('qr-batch-scan-download'),
                        onPressed: _download,
                        icon: const Icon(Icons.download),
                        label: const Text('Baixar CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share),
                        label: const Text('Compartilhar'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
