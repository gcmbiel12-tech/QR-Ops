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
  static const _foregrounds = <String, Color>{
    'Preto': Color(0xFF000000),
    'Azul': Color(0xFF102A43),
    'Verde': Color(0xFF174D36),
  };
  static const _backgrounds = <String, Color>{
    'Branco': Color(0xFFFFFFFF),
    'Marfim': Color(0xFFFFFDF5),
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController()..addListener(_updatePreview);
    _secondaryController = TextEditingController()..addListener(_updatePreview);
    _tertiaryController = TextEditingController()..addListener(_updatePreview);
  }

  @override
  void dispose() {
    _valueController
      ..removeListener(_updatePreview)
      ..dispose();
    _secondaryController
      ..removeListener(_updatePreview)
      ..dispose();
    _tertiaryController
      ..removeListener(_updatePreview)
      ..dispose();
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
    QrContentProblem.tooLong => 'O conteúdo é longo demais para um QR Code.',
  };

  void _changeType(QrContentType type) {
    _fieldsByType[_type] = [
      _valueController.text,
      _secondaryController.text,
      _tertiaryController.text,
    ];
    final fields = _fieldsByType[type]!;
    setState(() => _type = type);
    _valueController.text = fields[0];
    _secondaryController.text = fields[1];
    _tertiaryController.text = fields[2];
    _updatePreview();
  }

  void _updatePreview() {
    try {
      final encoded = widget.service.compose(_draft);
      final image = widget.service.encode(encoded.value);
      setState(() {
        _preview = image;
        _validationMessage = null;
      });
    } on QrContentException catch (error) {
      setState(() {
        _preview = null;
        _validationMessage = _messageFor(error.problem);
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
        setState(() => _validationMessage = _messageFor(error.problem));
      }
    } on Object {
      if (mounted) {
        setState(
          () => _saveError = 'Não foi possível salvar no histórico local.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    Key? key,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool multiline = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 4 : 1,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: hint,
        alignLabelWithHint: multiline,
      ),
    ),
  );

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
        label: 'Endereço do site',
        hint: 'https://exemplo.com.br',
        keyboardType: TextInputType.url,
      ),
    ],
    QrContentType.phone => [
      _field(
        controller: _valueController,
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
            setState(() => _security = value);
            _updatePreview();
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
          setState(() => _hiddenNetwork = value ?? false);
          _updatePreview();
        },
      ),
      const Text(
        'A senha fica somente no QR Code e no histórico local deste dispositivo.',
      ),
    ],
  };

  Widget _colorDropdown({
    required String label,
    required String value,
    required Map<String, Color> options,
    required ValueChanged<String?> onChanged,
  }) => Expanded(
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
                const Text('O conteúdo e o QR Code ficam neste dispositivo.'),
                const SizedBox(height: 24),
                DropdownButtonFormField<QrContentType>(
                  key: const ValueKey('qr-content-type'),
                  initialValue: _type,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Tipo de conteúdo',
                  ),
                  items: QrContentType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _changeType(value);
                  },
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
                      onChanged: (value) =>
                          setState(() => _foregroundName = value!),
                    ),
                    const SizedBox(width: 12),
                    _colorDropdown(
                      label: 'Fundo',
                      value: _backgroundName,
                      options: _backgrounds,
                      onChanged: (value) =>
                          setState(() => _backgroundName = value!),
                    ),
                  ],
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
