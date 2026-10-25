import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';
import 'ocr_engine.dart';
import 'ocr_pdf_engine.dart';

class QrOcrPage extends StatefulWidget {
  const QrOcrPage({
    super.key,
    required this.repository,
    required this.onRecordSaved,
    this.recognizeImage,
    this.initialImageBytes,
  });

  final QrRecordRepository repository;
  final VoidCallback onRecordSaved;
  final OcrRecognizeImage? recognizeImage;
  final Uint8List? initialImageBytes;

  @override
  State<QrOcrPage> createState() => _QrOcrPageState();
}

class _QrOcrPageState extends State<QrOcrPage> {
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  final _resultController = TextEditingController();
  Uint8List? _imageBytes;
  Uint8List? _pdfBytes;
  String? _sourceFileName;
  bool get _isPdfSelected => _pdfBytes != null;
  QrRecord? _savedRecord;
  String? _message;
  bool _busy = false;
  bool _appendResult = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.initialImageBytes;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 95);
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _message = 'A imagem selecionada está vazia.');
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _pdfBytes = null;
        _sourceFileName = image.name;
        _message =
            'Imagem pronta. Pressione Scanear para iniciar o reconhecimento.';
      });
    } on Object {
      if (mounted) {
        setState(
          () => _message = source == ImageSource.camera
              ? 'Não foi possível abrir a câmera. Verifique as permissões ou escolha uma imagem.'
              : 'Não foi possível abrir essa imagem. Tente outro arquivo.',
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'bmp',
          'tif',
          'tiff',
          'pdf',
        ],
      );
      if (files.isEmpty || !mounted) return;
      final file = files.single;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(
          () => _message = 'Não foi possível ler o arquivo selecionado.',
        );
        return;
      }
      final isPdf = file.extension?.toLowerCase() == 'pdf';
      setState(() {
        _sourceFileName = file.name;
        _imageBytes = isPdf ? null : bytes;
        _pdfBytes = isPdf ? bytes : null;
        _savedRecord = null;
        _message = isPdf
            ? 'PDF carregado. Pressione Scanear para extrair o texto e reconhecer páginas digitalizadas.'
            : 'Imagem pronta. Pressione Scanear para iniciar o reconhecimento.';
      });
    } on Object {
      if (mounted) {
        setState(
          () => _message = 'Não foi possível abrir o arquivo. Tente uma imagem ou PDF não protegido por senha.',
        );
      }
    }
  }

  Future<String> _recognizePdf(Uint8List bytes) async {
    if (!kIsWeb) {
      throw UnsupportedError(
        'A leitura de PDF está disponível no QR Ops Web. No aplicativo nativo, converta as páginas em imagens para usar o OCR.',
      );
    }
    return recognizePdfText(bytes);
  }

  Future<void> _scan() async {
    final bytes = _imageBytes;
    final pdfBytes = _pdfBytes;
    if (_busy || (bytes == null && pdfBytes == null)) return;
    setState(() {
      _busy = true;
      _message = 'Reconhecendo texto localmente…';
    });
    try {
      final recognize = widget.recognizeImage ?? recognizeImageText;
      final recognized = pdfBytes != null
          ? await _recognizePdf(pdfBytes)
          : await recognize(bytes!);
      if (!mounted) return;
      final trimmed = recognized.trim();
      final shouldAppend =
          _appendResult &&
          _resultController.text.trim().isNotEmpty &&
          trimmed.isNotEmpty;
      setState(() {
        if (shouldAppend) {
          _resultController.text = '${_resultController.text}\n$trimmed';
        } else {
          _resultController.text = recognized;
          _savedRecord = null;
        }
        _appendResult = false;
        _message = trimmed.isEmpty
            ? 'Nenhum texto reconhecido. Tente uma imagem mais nítida ou com melhor iluminação.'
            : 'Revise e corrija o texto reconhecido antes de salvar ou exportar.';
      });
    } on UnsupportedError {
      if (mounted) {
        setState(
          () => _message = 'O OCR não está disponível nesta plataforma.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = 'O reconhecimento falhou. Tente outra imagem ou uma nova captura.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final text = _resultController.text;
    if (_busy || text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final current = _savedRecord;
      if (current == null) {
        _savedRecord = await widget.repository.insert(
          QrRecord.ocr(content: text, name: _nameController.text.trim()),
        );
      } else {
        final updated = QrRecord(
          id: current.id,
          operation: QrRecordOperation.ocr,
          symbology: current.symbology,
          contentType: 'ocr_text',
          content: text,
          name: _nameController.text.trim(),
          description: current.description,
          createdAt: current.createdAt,
          revision: current.revision,
        );
        final success = await widget.repository.updateById(updated);
        if (!success) throw StateError('O registro OCR não foi encontrado.');
        _savedRecord = updated;
      }
      if (!mounted) return;
      widget.onRecordSaved();
      setState(() => _message = 'Texto OCR salvo localmente em Organizar.');
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível salvar o texto OCR.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final text = _resultController.text;
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _message = 'Texto copiado.');
    } on Object {
      if (mounted) {
        setState(() => _message = 'Não foi possível copiar o texto.');
      }
    }
  }

  Future<void> _download() async {
    final text = _resultController.text;
    if (text.isEmpty || _busy) return;
    try {
      await FileSaver.instance.saveFile(
        name: 'qr-ops-texto-reconhecido',
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileExtension: 'txt',
        mimeType: MimeType.text,
      );
      if (mounted) {
        setState(() => _message = 'Arquivo TXT preparado para salvar.');
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível baixar o arquivo TXT nesta plataforma.',
        );
      }
    }
  }

  Future<void> _share() async {
    final text = _resultController.text;
    if (text.trim().isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'Texto reconhecido pelo QR Ops'),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _message =
              'O compartilhamento não está disponível neste momento.',
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _resultController.text.trim().isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scanear texto',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Escolha uma imagem ou tire uma foto. O OCR só começa quando você pressionar Scanear. A imagem de origem fica apenas em memória e não é salva no histórico.',
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 6),
                  Text(
                    'No navegador, a biblioteca OCR e o idioma português são baixados sob demanda de um CDN público; a imagem é processada no próprio navegador e não é enviada para esse serviço.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('ocr-pick-image'),
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Imagem / PDF'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('ocr-take-photo'),
                      onPressed:
                          _busy ||
                              (!kIsWeb &&
                                  defaultTargetPlatform ==
                                      TargetPlatform.windows)
                          ? null
                          : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Tirar foto'),
                    ),
                  ],
                ),
                if (_imageBytes != null || _pdfBytes != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 180,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isPdfSelected
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 52,
                              ),
                              const SizedBox(height: 8),
                              Text(_sourceFileName ?? 'PDF selecionado'),
                              const Text(
                                'O texto será extraído de todas as páginas (até 30).',
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('ocr-scan-button'),
                    onPressed: _busy ? null : _scan,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(_busy ? 'Reconhecendo…' : 'Scanear'),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Semantics(liveRegion: true, child: Text(_message!)),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ocr-name'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do resultado (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ocr-result-text'),
                  controller: _resultController,
                  minLines: 6,
                  maxLines: 16,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Texto reconhecido — revise antes de usar',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                if (hasText) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _appendResult,
                    onChanged: (value) =>
                        setState(() => _appendResult = value ?? false),
                    title: const Text(
                      'Acrescentar a próxima leitura ao texto atual',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('ocr-save'),
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          _savedRecord == null
                              ? 'Salvar em Organizar'
                              : 'Salvar alterações',
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('ocr-download'),
                        onPressed: _busy ? null : _download,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Baixar TXT'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('ocr-share'),
                        onPressed: _busy ? null : _share,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartilhar'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('ocr-copy'),
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copiar'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('ocr-repeat'),
                        onPressed: _busy
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Repetir leitura'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
