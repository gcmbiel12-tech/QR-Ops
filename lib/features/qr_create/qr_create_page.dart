import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const _visibleTypes = <QrContentType>[
    QrContentType.text,
    QrContentType.url,
    QrContentType.phone,
    QrContentType.email,
    QrContentType.wifi,
  ];

  static const _descriptions = <QrContentType, String>{
    QrContentType.text: 'Compartilhe textos e informações.',
    QrContentType.url: 'Direcione para um site.',
    QrContentType.phone: 'Facilite o contato por telefone.',
    QrContentType.email: 'Prepare um e-mail com assunto e mensagem.',
    QrContentType.wifi: 'Compartilhe o acesso à rede Wi-Fi.',
  };

  static const _icons = <QrContentType, IconData>{
    QrContentType.text: Icons.text_fields,
    QrContentType.url: Icons.language,
    QrContentType.phone: Icons.phone,
    QrContentType.email: Icons.email_outlined,
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
  int _pngResolution = 1024;
  Uint8List? _customLogoBytes;
  double _logoFraction = 0.12;
  bool _logoLoading = false;
  static const _savedLogoKey = 'qr_ops_custom_logo_base64_v1';

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
    _loadSavedLogo();
  }

  Future<void> _loadSavedLogo() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_savedLogoKey);
      if (!mounted || encoded == null) return;
      final bytes = base64Decode(encoded);
      if (_isSupportedImage(bytes)) setState(() => _customLogoBytes = bytes);
    } on Object {
      // A corrupt or unavailable preference must not prevent QR creation.
    }
  }

  bool _isSupportedImage(Uint8List bytes) {
    final png =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    final webp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || webp;
  }

  Future<void> _pickCustomLogo() async {
    if (_logoLoading) return;
    setState(() => _logoLoading = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 1024 * 1024 || !_isSupportedImage(bytes)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use uma imagem PNG, JPEG ou WebP de até 1 MB.'),
            ),
          );
        }
        return;
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_savedLogoKey, base64Encode(bytes));
      if (mounted) setState(() => _customLogoBytes = bytes);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível carregar a imagem.')),
        );
      }
    } finally {
      if (mounted) setState(() => _logoLoading = false);
    }
  }

  Future<void> _restoreDefaultLogo() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_savedLogoKey);
      if (mounted) setState(() => _customLogoBytes = null);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível restaurar a logo padrão.'),
          ),
        );
      }
    }
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
      final bytes = widget.pngExportHandler != null
          ? await widget.pngExportHandler!(preview)
          : await const QrPngExporter().export(
              preview,
              dimension: _pngResolution,
              foreground: _foregrounds[_foregroundName]!,
              background: _backgrounds[_backgroundName]!,
              logoBytes: _customLogoBytes,
              logoFraction: _customLogoBytes == null ? 0.14 : _logoFraction,
            );
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
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Criar QR Code', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Escolha o que deseja compartilhar. O QR Code será montado '
                  'com os dados que você informar.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: colors.primaryContainer,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 40,
                          color: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comece por um modelo',
                                style: textTheme.titleLarge?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Selecione uma opção abaixo para preencher '
                                'os detalhes.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Modelos de QR Code', style: textTheme.titleLarge),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 560 ? 2 : 1;
                    const spacing = 12.0;
                    final cardWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final type in _visibleTypes)
                          SizedBox(
                            width: cardWidth,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: ValueKey('qr-type-${type.name}'),
                                onTap: () {
                                  _changeType(type);
                                  setState(() => _typeSelected = true);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: colors.secondaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          _icons[type],
                                          color: colors.onSecondaryContainer,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              type.label,
                                              style: textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _descriptions[type]!,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('qr-png-resolution'),
                  initialValue: _pngResolution,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Resolução do PNG',
                    helperText: 'Define as dimensões do arquivo exportado.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 256, child: Text('256 × 256 px')),
                    DropdownMenuItem(value: 512, child: Text('512 × 512 px')),
                    DropdownMenuItem(
                      value: 1024,
                      child: Text('1024 × 1024 px'),
                    ),
                    DropdownMenuItem(
                      value: 2048,
                      child: Text('2048 × 2048 px'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _pngResolution = value);
                  },
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const ValueKey('qr-logo-settings'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Logo central'),
                  subtitle: Text(
                    _customLogoBytes == null
                        ? 'Logo padrão QR Ops'
                        : 'Logo personalizada',
                  ),
                  leading: SizedBox.square(
                    dimension: 40,
                    child: _customLogoBytes == null
                        ? Image.asset(
                            'web/icons/Icon-512.png',
                            fit: BoxFit.contain,
                          )
                        : Image.memory(_customLogoBytes!, fit: BoxFit.contain),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _logoLoading ? null : _pickCustomLogo,
                        icon: _logoLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.image_outlined),
                        label: Text(
                          _logoLoading ? 'Carregando...' : 'Escolher logo',
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _customLogoBytes == null
                            ? null
                            : _restoreDefaultLogo,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restaurar logo padrão'),
                      ),
                    ),
                    if (_customLogoBytes != null)
                      Row(
                        children: [
                          const Text('Tamanho da logo carregada'),
                          Expanded(
                            child: Slider(
                              value: _logoFraction,
                              min: 0.08,
                              max: 0.14,
                              divisions: 6,
                              label: '${(_logoFraction * 100).round()}%',
                              onChanged: (value) =>
                                  setState(() => _logoFraction = value),
                            ),
                          ),
                        ],
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'PNG, JPEG ou WebP · até 1 MB · salvo neste dispositivo',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      logoBytes: _customLogoBytes,
                      logoFraction: _customLogoBytes == null
                          ? 0.14
                          : _logoFraction,
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
