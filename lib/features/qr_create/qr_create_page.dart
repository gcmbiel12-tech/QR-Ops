import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr/qr.dart' as qr;

import 'qr_code_download.dart';
import 'qr_code_preview.dart';
import 'qr_png_exporter.dart';
import 'qr_creation_service.dart';
import 'qr_visual_config.dart';

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
    'Azul corporativo': Color(0xFF12345A),
    'Azul': Color(0xFF0756A5),
    'Roxo': Color(0xFF542078),
    'Verde': Color(0xFF14532D),
    'Grafite': Color(0xFF292524),
  };

  static const _backgrounds = <String, Color>{
    'Branco': Color(0xFFFFFFFF),
    'Rosa claro': Color(0xFFFFF5FA),
    'Marfim': Color(0xFFFFFDF5),
  };

  static const _visibleTypes = <QrContentType>[
    QrContentType.text,
    QrContentType.url,
    QrContentType.phone,
    QrContentType.email,
    QrContentType.wifi,
    QrContentType.whatsapp,
  ];

  static const _descriptions = <QrContentType, String>{
    QrContentType.text: 'Compartilhe textos e informações.',
    QrContentType.url: 'Direcione para um site.',
    QrContentType.phone: 'Facilite o contato por telefone.',
    QrContentType.email: 'Prepare um e-mail com assunto e mensagem.',
    QrContentType.wifi: 'Compartilhe o acesso à rede Wi-Fi.',
    QrContentType.whatsapp:
        'Abra uma conversa com mensagem opcional pré-preenchida.',
  };

  static const _icons = <QrContentType, IconData>{
    QrContentType.text: Icons.text_fields,
    QrContentType.url: Icons.language,
    QrContentType.phone: Icons.phone,
    QrContentType.email: Icons.email_outlined,
    QrContentType.wifi: Icons.wifi,
    QrContentType.whatsapp: Icons.chat,
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
  Color _foregroundColor = const Color(0xFF000000);
  Color _backgroundColor = const Color(0xFFFFFFFF);
  String _selectedModelId = 'creator-clean';
  QrFrameStyle _frame = QrFrameStyle.none;
  String _callToAction = '';
  String _foregroundHexInput = '#000000';
  String _backgroundHexInput = '#FFFFFF';
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

  void _applyModel(QrVisualModel model) {
    final palette = QrVisualLibrary.palette(model.paletteId);
    final foregroundName = _foregrounds.entries
        .where((entry) => entry.value == palette.foreground)
        .firstOrNull
        ?.key;
    final backgroundName = _backgrounds.entries
        .where((entry) => entry.value == palette.background)
        .firstOrNull
        ?.key;
    setState(() {
      _selectedModelId = model.id;
      if (foregroundName != null) _foregroundName = foregroundName;
      if (backgroundName != null) _backgroundName = backgroundName;
      _foregroundColor = palette.foreground;
      _backgroundColor = palette.background;
      _foregroundHexInput = _hexColor(palette.foreground);
      _backgroundHexInput = _hexColor(palette.background);
      _frame = model.frame;
      _callToAction = '';
    });
  }

  String _hexColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Color? _parseHexColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
    return Color(0xFF000000 | int.parse(normalized, radix: 16))
        .withValues(alpha: 1);
  }

  void _applyCustomColors() {
    final foreground = _parseHexColor(_foregroundHexInput);
    final background = _parseHexColor(_backgroundHexInput);
    if (foreground == null || background == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe as cores no formato #RRGGBB.')),
      );
      return;
    }
    if (contrastRatio(foreground, background) < 4.5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Contraste insuficiente. Use uma combinação com pelo menos 4,5:1.',
          ),
        ),
      );
      return;
    }
    final foregroundEntry = _foregrounds.entries
        .where((entry) => entry.value == foreground)
        .firstOrNull;
    final backgroundEntry = _backgrounds.entries
        .where((entry) => entry.value == background)
        .firstOrNull;
    setState(() {
      _foregroundColor = foreground;
      _backgroundColor = background;
      _foregroundName = foregroundEntry?.key ?? 'Personalizada';
      _backgroundName = backgroundEntry?.key ?? 'Personalizada';
    });
  }

  Future<void> _pickColor({required bool foreground}) async {
    final initial = foreground ? _foregroundColor : _backgroundColor;
    final hsv = HSVColor.fromColor(initial);
    var hue = hsv.hue;
    var saturation = hsv.saturation;
    var value = hsv.value;
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          final color = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
          return AlertDialog(
            title: Text(
              foreground ? 'Escolher cor do QR' : 'Escolher cor do fundo',
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    key: const ValueKey('qr-hue-wheel'),
                    onPanDown: (details) => _updateWheel(
                      details.localPosition,
                      (h, s) => updateDialog(() {
                        hue = h;
                        saturation = s;
                      }),
                    ),
                    onPanUpdate: (details) => _updateWheel(
                      details.localPosition,
                      (h, s) => updateDialog(() {
                        hue = h;
                        saturation = s;
                      }),
                    ),
                    child: CustomPaint(
                      size: const Size(220, 220),
                      painter: _HueWheelPainter(
                        hue: hue,
                        saturation: saturation,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_hexColor(color))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 74, child: Text('Luminosidade')),
                      Expanded(
                        child: Slider(
                          value: value,
                          min: 0.15,
                          max: 1,
                          onChanged: (next) => updateDialog(() => value = next),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Selecione a tonalidade no círculo e ajuste a luminosidade.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, color),
                child: const Text('Usar esta cor'),
              ),
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    if (foreground && contrastRatio(picked, _backgroundColor) < 4.5 ||
        !foreground && contrastRatio(_foregroundColor, picked) < 4.5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Essa combinação tem pouco contraste para leitura. Ajuste a outra cor e tente novamente.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (foreground) {
        _foregroundColor = picked;
        _foregroundName = 'Personalizada';
        _foregroundHexInput = _hexColor(picked);
      } else {
        _backgroundColor = picked;
        _backgroundName = 'Personalizada';
        _backgroundHexInput = _hexColor(picked);
      }
    });
  }

  void _updateWheel(
    Offset position,
    void Function(double hue, double saturation) update,
  ) {
    const center = 110.0;
    final dx = position.dx - center;
    final dy = position.dy - center;
    final radius = math.sqrt(dx * dx + dy * dy);
    if (radius > 108) return;
    final hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    update(hue, (radius / 108).clamp(0.12, 1.0));
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
              foreground: _foregroundColor,
              background: _backgroundColor,
              logoBytes: _customLogoBytes,
              logoFraction: _customLogoBytes == null ? 0.14 : _logoFraction,
              frame: _frame,
              callToAction: _callToAction,
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
    QrContentType.whatsapp => [
      _field(
        controller: _valueController,
        key: const ValueKey('qr-content-field-whatsapp-phone'),
        label: 'Telefone do WhatsApp com código do país',
        hint: '+55 11 99999-9999',
        keyboardType: TextInputType.phone,
      ),
      _field(
        controller: _secondaryController,
        key: const ValueKey('qr-content-field-whatsapp-message'),
        label: 'Mensagem pré-preenchida (opcional)',
        hint: 'Olá! Gostaria de mais informações.',
        multiline: true,
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Use o telefone em formato internacional, incluindo + e código do país.',
        ),
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
                Text('Modelos visuais', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Escolha um estilo. O conteúdo preenchido será preservado.',
                ),
                const SizedBox(height: 12),
                for (final category in QrVisualCategory.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(category.label, style: textTheme.titleSmall),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final model in QrVisualLibrary.models.where(
                        (item) => item.category == category,
                      ))
                        SizedBox(
                          width: 250,
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('qr-model-${model.id}'),
                              onTap: () => _applyModel(model),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: QrVisualLibrary.palette(
                                          model.paletteId,
                                        ).background,
                                        border: Border.all(
                                          color: QrVisualLibrary.palette(
                                            model.paletteId,
                                          ).foreground,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.qr_code_2,
                                        color: QrVisualLibrary.palette(
                                          model.paletteId,
                                        ).foreground,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            model.name,
                                            style: textTheme.labelLarge,
                                          ),
                                          Text(
                                            model.description,
                                            style: textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_selectedModelId == model.id)
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('qr-style-reset'),
                  onPressed: () =>
                      _applyModel(QrVisualLibrary.model('creator-clean')),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Voltar ao estilo padrão'),
                ),
                const SizedBox(height: 20),
                Text('Personalizar', style: textTheme.titleMedium),
                const SizedBox(height: 12),
                Card(
                  key: const ValueKey('qr-color-personalization-banner'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.secondaryContainer,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface
                                .withValues(alpha: .82),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.palette_rounded,
                            size: 28,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Crie uma paleta só sua',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 19,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Escolha cada tonalidade na roda de cores ou '
                                'digite seus códigos HEX para combinar com '
                                'sua marca, perfil ou evento.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _ColorFeatureTag(
                                    icon: Icons.color_lens_outlined,
                                    label: 'Roda cromática',
                                  ),
                                  _ColorFeatureTag(
                                    icon: Icons.tag_rounded,
                                    label: 'Código HEX',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Paletas prontas',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '1 toque',
                      style: textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final palette in QrVisualLibrary.palettes)
                      Tooltip(
                        message: palette.name,
                        child: InkWell(
                          key: ValueKey('qr-palette-${palette.id}'),
                          customBorder: const CircleBorder(),
                          onTap: () {
                            setState(() {
                              _foregroundColor = palette.foreground;
                              _backgroundColor = palette.background;
                              _foregroundName = palette.name;
                              _backgroundName = palette.name;
                              _foregroundHexInput = _hexColor(
                                palette.foreground,
                              );
                              _backgroundHexInput = _hexColor(
                                palette.background,
                              );
                            });
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  palette.foreground,
                                  palette.foreground,
                                  palette.background,
                                  palette.background,
                                ],
                                stops: const [0, .48, .52, 1],
                              ),
                              border: Border.all(
                                color:
                                    _foregroundColor == palette.foreground &&
                                        _backgroundColor == palette.background
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).dividerColor,
                                width:
                                    _foregroundColor == palette.foreground &&
                                        _backgroundColor == palette.background
                                    ? 3
                                    : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Personalize manualmente',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Seu estilo',
                      style: textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Toque em uma cor para abrir a roda cromática. Você também '
                  'pode informar o código exato da sua identidade visual.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('qr-pick-foreground'),
                      onPressed: () => _pickColor(foreground: true),
                      icon: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _foregroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      label: Text(
                        'Cor do QR ($_foregroundName) ${_hexColor(_foregroundColor)}',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('qr-pick-background'),
                      onPressed: () => _pickColor(foreground: false),
                      icon: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _backgroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      label: Text(
                        'Fundo ($_backgroundName) ${_hexColor(_backgroundColor)}',
                      ),
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Inserir cores por código HEX'),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey(
                              'qr-foreground-hex-$_foregroundHexInput',
                            ),
                            initialValue: _foregroundHexInput,
                            decoration: const InputDecoration(
                              labelText: 'Cor do QR',
                              border: OutlineInputBorder(),
                              hintText: '#123456',
                            ),
                            onChanged: (value) => _foregroundHexInput = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey(
                              'qr-background-hex-$_backgroundHexInput',
                            ),
                            initialValue: _backgroundHexInput,
                            decoration: const InputDecoration(
                              labelText: 'Fundo',
                              border: OutlineInputBorder(),
                              hintText: '#FFFFFF',
                            ),
                            onChanged: (value) => _backgroundHexInput = value,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('qr-apply-custom-colors'),
                        onPressed: _applyCustomColors,
                        icon: const Icon(Icons.color_lens_outlined),
                        label: const Text('Aplicar cores HEX'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<QrFrameStyle>(
                  isExpanded: true,
                  key: ValueKey('qr-frame-style-${_frame.name}'),
                  initialValue: _frame,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Moldura e chamada para ação',
                  ),
                  items: [
                    for (final frame in QrFrameStyle.values)
                      DropdownMenuItem(value: frame, child: Text(frame.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _frame = value;
                      _callToAction = '';
                    });
                  },
                ),
                if (_frame.hasCallToAction) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey(
                      'qr-frame-call-to-action-${_frame.name}-$_selectedModelId',
                    ),
                    initialValue: _callToAction,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Texto da chamada para ação',
                      helperText: 'O texto aparece abaixo do QR Code.',
                    ),
                    onChanged: (value) => setState(() => _callToAction = value),
                  ),
                ],
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
                      foreground: _foregroundColor,
                      background: _backgroundColor,
                      logoBytes: _customLogoBytes,
                      frame: _frame,
                      callToAction: _callToAction,
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

class _ColorFeatureTag extends StatelessWidget {
  const _ColorFeatureTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter({required this.hue, required this.saturation});

  final double hue;
  final double saturation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 2;
    for (var degree = 0; degree < 360; degree++) {
      final paint = Paint()
        ..color = HSVColor.fromAHSV(1, degree.toDouble(), 1, 1).toColor()
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final start = (degree - 90) * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.pi / 180 * 1.5,
        false,
        paint,
      );
    }
    final selectedRadius = radius * saturation;
    final point = Offset(
      center.dx + math.cos(hue * math.pi / 180) * selectedRadius,
      center.dy + math.sin(hue * math.pi / 180) * selectedRadius,
    );
    canvas.drawCircle(point, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      point,
      6,
      Paint()..color = HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) =>
      oldDelegate.hue != hue || oldDelegate.saturation != saturation;
}
