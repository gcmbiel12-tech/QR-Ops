import 'package:flutter/material.dart';
import 'package:qr/qr.dart' as qr;

import 'qr_code_preview.dart';
import 'qr_creation_service.dart';

class QrCreatePage extends StatefulWidget {
  const QrCreatePage({
    super.key,
    required this.service,
    required this.onRecordCreated,
  });

  final QrCreationService service;
  final VoidCallback onRecordCreated;

  @override
  State<QrCreatePage> createState() => _QrCreatePageState();
}

class _QrCreatePageState extends State<QrCreatePage> {
  late final TextEditingController _controller;
  qr.QrImage? _preview;
  String? _validationMessage;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_updatePreview);
    _updatePreview();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updatePreview)
      ..dispose();
    super.dispose();
  }

  void _updatePreview() {
    try {
      final image = widget.service.encode(_controller.text);
      setState(() {
        _preview = image;
        _validationMessage = null;
      });
    } on QrContentException catch (error) {
      setState(() {
        _preview = null;
        _validationMessage = switch (error.problem) {
          QrContentProblem.empty => 'Digite o conteúdo para gerar o QR Code.',
          QrContentProblem.tooLong =>
            'O conteúdo é longo demais para um QR Code.',
        };
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.service.create(_controller.text);
      if (!mounted) return;
      widget.onRecordCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code salvo no histórico local.')),
      );
    } on QrContentException catch (error) {
      if (!mounted) return;
      setState(() {
        _validationMessage = switch (error.problem) {
          QrContentProblem.empty => 'Digite o conteúdo para gerar o QR Code.',
          QrContentProblem.tooLong =>
            'O conteúdo é longo demais para um QR Code.',
        };
      });
    } on Object {
      if (!mounted) return;
      setState(
        () => _saveError = 'Não foi possível salvar no histórico local.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Criar QR Code', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'O conteúdo e o QR Code ficam neste dispositivo.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('qr-content-field'),
                  controller: _controller,
                  minLines: 2,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Conteúdo',
                    hintText: 'Digite um texto ou endereço para codificar',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_validationMessage case final message?) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    key: const ValueKey('qr-validation-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_preview case final preview?) ...[
                  const SizedBox(height: 24),
                  Center(child: QrCodePreview(image: preview)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('qr-save-button'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Salvando…' : 'Salvar no histórico'),
                  ),
                ],
                if (_saveError case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
