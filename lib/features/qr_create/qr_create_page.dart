import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart' as qr;

import 'qr_code_download.dart';
import 'qr_code_preview.dart';
import 'qr_png_exporter.dart';
import 'qr_creation_service.dart';

typedef QrPngDownloadHandler = Future<void> Function(
  Uint8List bytes, {
  required String filename,
});
typedef QrPngExportHandler = Future<Uint8List> Function(qr.QrImage image);

class QrCreatePage extends StatefulWidget {
  const QrCreatePage({
    super.key,
    required this.service,
    required this.onRecordCreated,
    this.downloadHandler,
    this.pngExportHandler,
  });

  final QrCreationService service;
  final VoidCallback onRecordCreated;
  final QrPngDownloadHandler? downloadHandler;
  final QrPngExportHandler? pngExportHandler;

  @override
  State<QrCreatePage> createState() => _QrCreatePageState();
}

class _QrCreatePageState extends State<QrCreatePage> {
  static const _foregrounds = <String, Color>{
    'Preto': Color(0xFF000000),
    'Azul': Color(0xFF102A43),
    'Verde': Color(0xFF174D36),
  };

  static const _backgrounds = <String, Color>{
    'Branco': Color(0xFFFFFFFF),
    'Marfim': Color(0xFFFFFDF5),
  };

  static const _descriptions = <QrContentType, String>{
    QrContentType.text: 'Compartilhe textos e informações.',
    QrContentType.url: 'Direcione para um site.',
    QrContentType.phone: 'Facilite o contato por telefone.',
    QrContentType.email: 'Prepare um e-mail com assunto e mensagem.',
    QrContentType.sms: 'Compartilhe uma mensagem SMS.',
    QrContentType.wifi: 'Compartilhe o acesso à rede Wi-Fi.',
  };

  static const _icons = <QrContentType, IconData>{
    QrContentType.text: Icons.text_fields,
    QrContentType.url: Icons.language,
    QrContentType.phone: Icons.phone,
    QrContentType.email: Icons.email_outlined,
    QrContentType.sms: Icons.sms_outlined,
    QrContentType.wifi: Icons.wifi,
  };

  late final TextEditingController _valueController;
  late final TextEditingController _secondaryController;
  late final TextEditingController _tertiaryController;

  late final Map<QrContentType, List<String>> _fieldsByType = {
    for (final type in QrContentType.values) type: ['', '', ''],
  };

  QrContentType _type = QrContentType.text;
  String _security = 'WPA';
  bool _hiddenNetwork = false;
  String _foregroundName = 'Preto';
  String _backgroundName = 'Branco';

  qr.QrImage? _preview;
  String? _validationMessage;
  String? _saveError;
  String? _downloadError;

  bool _typeSelected = false;
  bool _saving = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
    _secondaryController = TextEditingController();
    _tertiaryController = TextEditingController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _secondaryController.dispose();
    _tertiaryController.dispose();
    super.dispose();
  }

  QrContentDraft get _draft => QrContentDraft(
    type: _type,
    value: _valueController.text,
    secondary: _secondaryController.text,
    tertiary: _tertiaryController.text,
    wifiSecurity: _security,
    hiddenNetwork: _hiddenNetwork,
  );

  String _messageFor(QrContentProblem problem) => switch (problem) {
    QrContentProblem.empty => 'Preencha o conteúdo para gerar o QR Code.',
    QrContentProblem.invalid => 'Confira os dados informados para este tipo.',
    QrContentProblem.urlSchemeRequired =>
      'A URL precisa começar com http:// ou https://.',
    QrContentProblem.malformedUrl =>
      'A URL está malformada ou contém caracteres inválidos.',
    QrContentProblem.tooLong => 'O conteúdo é longo demais para um QR Code.',
  };

  void _invalidatePreview() {
    if (_preview == null && _validationMessage == null) return;

    setState(() {
      _preview = null;
      _validationMessage = null;
      _saveError = null;
      _downloadError = null;
    });
  }

  void _changeType(QrContentType type) {
    _fieldsByType[_type] = [
      _valueController.text,
      _secondaryController.text,
      _tertiaryController.text,
    ];

    final fields = _fieldsByType[type]!;

    setState(() {
      _type = type;
      _preview = null;
      _validationMessage = null;
      _saveError = null;
      _downloadError = null;
    });

    _valueController.text = fields[0];
    _secondaryController.text = fields[1];
    _tertiaryController.text = fields[2];
  }

  void _createQr() {
    if (_saving) return;

    try {
      final encoded = widget.service.compose(_draft);
      final image = widget.service.encode(encoded.value);

      setState(() {
        _preview = image;
        _validationMessage = null;
        _saveError = null;
        _downloadError = null;
      });
    } on QrContentException catch (error) {
      setState(() {
        _preview = null;
        _validationMessage = _messageFor(error.problem);
      });
    }
  }

  Future<void> _downloadPng() async {
    final preview = _preview;
    if (_downloading || preview == null) return;

    setState(() {
      _downloading = true;
      _downloadError = null;
    });

    try {
      final export = widget.pngExportHandler ?? const QrPngExporter().export;
      final bytes = await export(preview);
      final download = widget.downloadHandler ?? downloadQrCodePng;
      await download(bytes, filename: 'qr-code.png');
    } on Object {
      if (mounted) {
        setState(() {
          _downloadError = 'Não foi possível baixar o PNG. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _preview == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
      _downloadError = null;
    });

    try {
      final encoded = widget.service.compose(_draft);

      await widget.service.create(
        encoded.value,
        contentType: encoded.type.storageValue,
      );

      if (!mounted) return;

      widget.onRecordCreated();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code salvo no histórico local.')),
      );
    } on QrContentException catch (error) {
      if (mounted) {
        setState(() {
          _preview = null;
          _validationMessage = _messageFor(error.problem);
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saveError = 'Não foi possível salvar no histórico local.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    Key? key,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: keyboardType,
        minLines: multiline ? 2 : 1,
        maxLines: multiline ? 4 : 1,
        onChanged: (_) => _invalidatePreview(),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          hintText: hint,
          alignLabelWithHint: multiline,
        ),
      ),
    );
  }

  List<Widget> _contentFields() => switch (_type) {
    QrContentType.text => [
      _field(
        controller: _valueController,
        key: const ValueKey('qr-content-field'),
        label: 'Texto',
        hint: 'Digite o conteúdo que será codificado',
        multiline: true,
      ),
    ],
    QrContentType.url => [
      _field(
        controller: _valueController,
        key: const ValueKey('qr-content-field-url'),
        label: 'Endereço do site',
        hint: 'https://exemplo.com.br',
        keyboardType: TextInputType.url,
      ),
    ],
    QrContentType.phone => [
      _field(
        controller: _valueController,
        key: const ValueKey('qr-content-field-phone'),
        label: 'Telefone',
        hint: '+55 11 99999-9999',
        keyboardType: TextInputType.phone,
      ),
    ],
    QrContentType.email => [
      _field(
        controller: _valueController,
        label: 'E-mail',
        hint: 'nome@exemplo.com.br',
        keyboardType: TextInputType.emailAddress,
      ),
      _field(controller: _secondaryController, label: 'Assunto (opcional)'),
      _field(
        controller: _tertiaryController,
        label: 'Mensagem (opcional)',
        multiline: true,
      ),
    ],
    QrContentType.sms => [
      _field(
        controller: _valueController,
        label: 'Telefone',
        hint: '+55 11 99999-9999',
        keyboardType: TextInputType.phone,
      ),
      _field(
        controller: _secondaryController,
        label: 'Mensagem (opcional)',
        multiline: true,
      ),
    ],
    QrContentType.wifi => [
      _field(
        controller: _valueController,
        label: 'Nome da rede (SSID)',
        hint: 'Nome visível da rede',
      ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String>(
          key: const ValueKey('qr-wifi-security'),
          initialValue: _security,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Segurança da rede',
          ),
          items: const [
            DropdownMenuItem(value: 'WPA', child: Text('WPA / WPA2 / WPA3')),
            DropdownMenuItem(value: 'WEP', child: Text('WEP')),
            DropdownMenuItem(value: 'nopass', child: Text('Sem senha')),
          ],
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _security = value;
              _preview = null;
              _validationMessage = null;
              _saveError = null;
            });
          },
        ),
      ),
      if (_security != 'nopass')
        _field(
          controller: _secondaryController,
          label: 'Senha da rede',
          keyboardType: TextInputType.visiblePassword,
        ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Rede oculta'),
        value: _hiddenNetwork,
        onChanged: (value) {
          setState(() {
            _hiddenNetwork = value ?? false;
            _preview = null;
            _validationMessage = null;
            _saveError = null;
          });
        },
      ),
      const Text(
        'A senha fica somente no QR Code e no histórico local '
        'deste dispositivo.',
      ),
    ],
  };

  Widget _colorDropdown({
    required String label,
    required String value,
    required Map<String, Color> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
        items: options.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.key)),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTypeSelection(TextTheme textTheme) {
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
                const Text('Escolha o tipo de conteúdo do seu QR Code.'),
                const SizedBox(height: 24),
                for (final type in QrContentType.values) ...[
                  Card(
                    child: ListTile(
                      key: ValueKey('qr-type-${type.name}'),
                      leading: Icon(_icons[type], size: 30),
                      title: Text(type.label),
                      subtitle: Text(_descriptions[type]!),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _changeType(type);
                        setState(() => _typeSelected = true);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (!_typeSelected) {
      return _buildTypeSelection(textTheme);
    }

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
                const Text('O conteúdo e o QR Code ficam neste dispositivo.'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tipo: ${_type.label}',
                        style: textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _typeSelected = false;
                                _preview = null;
                                _validationMessage = null;
                                _saveError = null;
                              });
                            },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Trocar tipo'),
                    ),
                  ],
                ),
                ..._contentFields(),
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
                const SizedBox(height: 20),
                Text('Aparência', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _colorDropdown(
                      label: 'Cor do código',
                      value: _foregroundName,
                      options: _foregrounds,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _foregroundName = value);
                      },
                    ),
                    const SizedBox(width: 12),
                    _colorDropdown(
                      label: 'Fundo',
                      value: _backgroundName,
                      options: _backgrounds,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _backgroundName = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('qr-create-button'),
                  onPressed: _saving ? null : _createQr,
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Criar QR'),
                ),
                if (_preview case final preview?) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: QrCodePreview(
                      image: preview,
                      foreground: _foregrounds[_foregroundName]!,
                      background: _backgrounds[_backgroundName]!,
                    ),
                  ),
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
                    label: Text(
                      _saving ? 'Salvando...' : 'Salvar no histórico',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('qr-download-png-button'),
                    onPressed: _saving || _downloading ? null : _downloadPng,
                    icon: _downloading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(
                      _downloading ? 'Preparando PNG...' : 'Baixar PNG',
                    ),
                  ),
                ],
                if (_downloadError case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    key: const ValueKey('qr-download-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
