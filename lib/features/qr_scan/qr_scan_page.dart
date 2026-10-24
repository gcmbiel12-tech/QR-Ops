import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import 'qr_image_decoder.dart';
import '../../domain/qr_content_interpreter.dart';
import '../../domain/qr_record.dart';
import '../../domain/qr_record_repository.dart';

@immutable
class QrScanResult {
  const QrScanResult({required this.value, required this.format});

  final String value;
  final String format;
}

typedef QrScanPreviewBuilder = Widget Function(
  BuildContext context,
  ValueChanged<QrScanResult> onResult,
  ValueChanged<String> onError,
);
typedef QrScanUrlLauncher = Future<bool> Function(Uri uri);

class QrScanPage extends StatefulWidget {
  const QrScanPage({
    super.key,
    required this.isActive,
    this.previewBuilder,
    this.repository,
    this.onRecordRead,
    this.urlLauncher,
  });

  final bool isActive;
  final QrRecordRepository? repository;
  final VoidCallback? onRecordRead;
  final QrScanPreviewBuilder? previewBuilder;
  final QrScanUrlLauncher? urlLauncher;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  late final MobileScannerController _controller;
  final ImagePicker _imagePicker = ImagePicker();

  QrScanResult? _result;
  String? _errorMessage;

  bool _isStarting = false;
  bool _cameraEnabled = false;
  bool _hasRead = false;
  bool _isDraggingImage = false;

  int _startAttempt = 0;

  bool get _usesTestPreview => widget.previewBuilder != null;

  bool get _supportsCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _supportsImageAnalysis =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _supportsFileDrop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();

    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      // An empty format list enables every format supported by the plugin.
    );
  }

  @override
  void didUpdateWidget(covariant QrScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive && !widget.isActive) {
      _startAttempt++;
      _cameraEnabled = false;
      _isStarting = false;
      _stopCamera();
    }
  }

  @override
  void dispose() {
    _startAttempt++;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startScanning() async {
    if (!mounted || !widget.isActive) return;
    if (_isStarting || _cameraEnabled) return;

    if (!_usesTestPreview && !_supportsCamera) {
      setState(() {
        _errorMessage =
            'A câmera não está disponível nesta versão. '
            'Use o aplicativo Android ou a versão Web do QR Ops.';
      });
      return;
    }

    final attempt = ++_startAttempt;

    setState(() {
      _result = null;
      _errorMessage = null;
      _hasRead = false;
      _isStarting = !_usesTestPreview;
    });

    // O preview de teste não utiliza hardware.
    if (_usesTestPreview) {
      setState(() {
        _isStarting = false;
        _cameraEnabled = true;
      });
      return;
    }

    try {
      await _controller.start();

      if (!mounted) return;
      if (attempt != _startAttempt) {
        // A navegação ou o botão Parar pode invalidar a inicialização
        // enquanto o plugin ainda está concluindo start(). Garante que a
        // câmera não permaneça ativa após essa tentativa ter sido cancelada.
        await _stopCamera();
        return;
      }

      final scannerError = _controller.value.error;

      if (scannerError != null) {
        _setError(_messageForScannerError(scannerError));
        return;
      }

      setState(() {
        _isStarting = false;
        _cameraEnabled = true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      if (attempt != _startAttempt) {
        await _stopCamera();
        return;
      }
      _setError(_messageForStartError(error));
    }
  }

  Future<void> _stopScanning() async {
    _startAttempt++;

    if (mounted) {
      setState(() {
        _cameraEnabled = false;
        _isStarting = false;
      });
    }

    await _stopCamera();
  }

  Future<void> _stopCamera() async {
    if (_usesTestPreview || !_supportsCamera) return;

    if (!_controller.value.isRunning && !_controller.value.isStarting) {
      return;
    }

    try {
      await _controller.stop();
    } on Object {
      // A câmera pode já ter sido interrompida.
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_hasRead || !widget.isActive || !_cameraEnabled) return;
    _acceptCapture(capture);
  }

  void _acceptCapture(BarcodeCapture capture, {bool fromImage = false}) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;

      _acceptResult(
        QrScanResult(value: value, format: _formatLabel(barcode.format)),
        fromImage: fromImage,
      );
      return;
    }
  }

  Future<void> _pickImageAndScan() async {
    if (!mounted || !widget.isActive || _hasRead || _isStarting) return;

    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (!mounted || image == null || !widget.isActive) return;

      setState(() {
        _errorMessage = null;
        _isStarting = true;
      });

      if (kIsWeb) {
        await _scanQrFromImageBytes(await image.readAsBytes());
        return;
      }

      if (!_supportsImageAnalysis) {
        throw UnsupportedError(
          'Image analysis is not supported on this platform.',
        );
      }

      final capture = await _controller.analyzeImage(image.path);
      if (!mounted || !widget.isActive) return;
      if (capture == null ||
          capture.barcodes.every(
            (item) => item.rawValue == null || item.rawValue!.isEmpty,
          )) {
        setState(() {
          _isStarting = false;
          _errorMessage = 'Não encontramos um QR Code ou código de barras nessa imagem. Tente outra imagem mais nítida.';
        });
        return;
      }

      setState(() => _isStarting = false);
      _acceptCapture(capture, fromImage: true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _errorMessage = error is UnsupportedError
            ? 'A leitura de imagens não é suportada nesta plataforma.'
            : 'Não foi possível ler essa imagem. Use PNG, JPG ou WebP e tente novamente.';
      });
    }
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    if (!mounted || !widget.isActive || _hasRead || _isStarting) return;

    final files = details.files.where((file) {
      final type = file.mimeType?.toLowerCase() ?? '';
      final name = file.name.toLowerCase();
      return type.startsWith('image/') ||
          name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.webp') ||
          name.endsWith('.bmp') ||
          name.endsWith('.gif');
    });
    final imageFile = files.isEmpty ? null : files.first;

    if (imageFile == null) {
      setState(() {
        _isDraggingImage = false;
        _errorMessage = 'Arraste um arquivo de imagem (PNG, JPG ou WebP).';
      });
      return;
    }

    setState(() {
      _isDraggingImage = false;
      _errorMessage = null;
      _isStarting = true;
    });

    try {
      await _scanQrFromImageBytes(await imageFile.readAsBytes());
    } on Object {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _errorMessage =
            'Não foi possível ler essa imagem. Tente outro arquivo.';
      });
    }
  }

  Future<void> _scanQrFromImageBytes(Uint8List bytes) async {
    if (!mounted || !widget.isActive) return;

    try {
      final value = decodeQrFromImageBytes(bytes);
      if (!mounted || !widget.isActive) return;
      setState(() => _isStarting = false);
      _acceptResult(
        QrScanResult(value: value, format: 'QR Code'),
        fromImage: true,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _errorMessage = 'Não encontramos um QR Code legível nessa imagem. Tente uma imagem mais nítida, sem cortes e com bom contraste.';
      });
    }
  }

  void _acceptResult(QrScanResult result, {bool fromImage = false}) {
    if (_hasRead || !widget.isActive || result.value.isEmpty) return;

    // O preview simulado continua compatível com os testes existentes.
    if (!_usesTestPreview && !_cameraEnabled && !fromImage) return;

    _hasRead = true;
    _startAttempt++;

    setState(() {
      _result = result;
      _errorMessage = null;
      _isStarting = false;
      _cameraEnabled = false;
    });

    // Interrompe a câmera assim que o código é reconhecido.
    unawaited(_stopCamera());

    if (widget.repository != null) {
      unawaited(_persistResult(result));
    }
  }

  Future<void> _persistResult(QrScanResult result) async {
    try {
      await widget.repository!.insert(
        QrRecord.read(
          content: result.value,
          symbology: result.format.toLowerCase().replaceAll(' ', '_'),
          contentType: const QrContentInterpreter()
              .interpret(result.value)
              .kind
              .name,
        ),
      );

      if (mounted) {
        widget.onRecordRead?.call();
      }
    } on Object {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A leitura foi exibida, mas não foi possível '
            'salvá-la no histórico.',
          ),
        ),
      );
    }
  }

  void _setError(String message) {
    if (!mounted) return;

    _startAttempt++;

    setState(() {
      _errorMessage = message;
      _isStarting = false;
      _cameraEnabled = false;
    });

    unawaited(_stopCamera());
  }

  String _messageForScannerError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'A permissão da câmera foi negada. Autorize o acesso '
            'nas configurações do aplicativo ou navegador e tente novamente.',
      MobileScannerErrorCode.unsupported =>
        'Nenhuma câmera compatível foi encontrada. '
            'Conecte ou habilite uma câmera e tente novamente.',
      _ => _messageForStartError(error),
    };
  }

  String _messageForStartError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('permission') ||
        message.contains('notallowederror') ||
        message.contains('denied')) {
      return 'O acesso à câmera foi negado. Permita o uso '
          'da câmera nas configurações do navegador ou aplicativo.';
    }

    if (message.contains('notfounderror') ||
        message.contains('no camera') ||
        message.contains('camera not found')) {
      return 'Nenhuma câmera foi encontrada. Conecte uma webcam '
          'ou habilite a câmera do dispositivo.';
    }

    if (message.contains('notreadableerror') ||
        message.contains('could not start video source') ||
        message.contains('in use')) {
      return 'A câmera está indisponível ou sendo usada por outro '
          'aplicativo. Feche os outros aplicativos que utilizam a câmera.';
    }

    return 'Não foi possível iniciar a câmera. Verifique as permissões '
        'e se outro aplicativo está utilizando a câmera.';
  }

  String _formatLabel(BarcodeFormat format) => switch (format) {
    BarcodeFormat.qrCode => 'QR Code',
    BarcodeFormat.dataMatrix => 'Data Matrix',
    BarcodeFormat.aztec => 'Aztec',
    BarcodeFormat.pdf417 => 'PDF417',
    BarcodeFormat.ean8 => 'EAN-8',
    BarcodeFormat.ean13 => 'EAN-13',
    BarcodeFormat.upcA => 'UPC-A',
    BarcodeFormat.upcE => 'UPC-E',
    BarcodeFormat.code128 => 'Code 128',
    BarcodeFormat.code39 => 'Code 39',
    BarcodeFormat.code93 => 'Code 93',
    BarcodeFormat.codabar => 'Codabar',
    BarcodeFormat.dataBar => 'DataBar',
    BarcodeFormat.dataBarExpanded => 'DataBar expandido',
    BarcodeFormat.maxiCode => 'MaxiCode',
    // ignore: deprecated_member_use
    BarcodeFormat.itf => 'ITF',
    _ => 'Código de barras',
  };

  Future<void> _copyResult() async {
    final result = _result;
    if (result == null) return;

    await Clipboard.setData(ClipboardData(text: result.value));

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Conte\u00FAdo copiado.')));
  }

  Future<void> _confirmOpenResultAction(Uri uri) async {
    const allowedSchemes = {
      'http',
      'https',
      'tel',
      'mailto',
      'sms',
      'whatsapp',
    };
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) return;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar ação externa'),
        content: Text(
          'O QR Code contém uma ação do tipo ${uri.scheme.toUpperCase()}. '
          'Deseja abrir um aplicativo compatível? Nenhuma mensagem será enviada pelo QR Ops.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await _openResultUrl(uri);
  }

  Future<void> _openResultUrl(Uri uri) async {
    try {
      final openUrl =
          widget.urlLauncher ??
          (value) => launcher.launchUrl(
            value,
            mode: launcher.LaunchMode.externalApplication,
          );
      final opened = await openUrl(uri);
      if (!opened) throw StateError('O navegador não confirmou a abertura.');
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir este link no navegador.'),
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    if (!_cameraEnabled || _usesTestPreview) return;

    try {
      await _controller.switchCamera();
    } on Object catch (error) {
      if (mounted) {
        _setError(_messageForStartError(error));
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (!_cameraEnabled || _usesTestPreview) return;

    try {
      await _controller.toggleTorch();
    } on Object catch (error) {
      if (mounted) {
        _setError(_messageForStartError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ler código', style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Aponte a câmera para um QR Code ou código de barras.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                _buildSecurityHint(textTheme),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDropZone(),
                        if (_isStarting) ...[
                          const SizedBox(height: 12),
                          const Center(
                            child: CircularProgressIndicator(
                              semanticsLabel: 'Iniciando a câmera',
                            ),
                          ),
                        ],
                        if (_errorMessage case final message?) ...[
                          const SizedBox(height: 12),
                          _MessageCard(
                            key: const ValueKey('qr-scan-error'),
                            icon: Icons.error_outline_rounded,
                            message: message,
                            isError: true,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const ValueKey('qr-scan-retry'),
                            onPressed: _startScanning,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Tentar novamente'),
                          ),
                        ] else if (_result case final result?) ...[
                          const SizedBox(height: 12),
                          _ResultCard(
                            result: result,
                            onCopy: _copyResult,
                            onOpenUrl: _confirmOpenResultAction,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const ValueKey('qr-scan-again'),
                            onPressed: _startScanning,
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: const Text('Ler novamente'),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          const _MessageCard(
                            icon: Icons.center_focus_strong_rounded,
                            message: 'Posicione o código na área da câmera para fazer a leitura.',
                          ),
                          const SizedBox(height: 8),
                          _buildCameraActions(),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('qr-scan-pick-image'),
                            onPressed: _isStarting ? null : _pickImageAndScan,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Ler de uma imagem'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityHint(TextTheme textTheme) {
    if (!kIsWeb) return const SizedBox.shrink();

    return Text(
      'No computador, selecione uma imagem ou arraste o arquivo para a área do leitor. Para usar a câmera, permita o acesso quando o navegador solicitar.',
      key: const ValueKey('qr-scan-web-permission-hint'),
      style: textTheme.bodySmall,
    );
  }

  Widget _buildDropZone() {
    if (!_supportsFileDrop) return _buildPreview();

    return DropTarget(
      enable: widget.isActive && !_hasRead,
      onDragEntered: (_) => setState(() => _isDraggingImage = true),
      onDragExited: (_) => setState(() => _isDraggingImage = false),
      onDragDone: _handleDroppedFiles,
      child: Stack(
        children: [
          _buildPreview(),
          if (_isDraggingImage)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onPrimary,
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 44,
                        color: Colors.white,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Solte a imagem aqui',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final builder = widget.previewBuilder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 300,
        child: _result != null
            ? const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              )
            : builder != null
            ? builder(context, _acceptResult, _setError)
            : !_supportsCamera
            ? const _MessageCard(
                key: ValueKey('qr-scan-platform-limit'),
                icon: Icons.info_outline_rounded,
                message: 'A leitura pela câmera não está disponível nesta versão do Windows. Use o QR Ops no navegador ou em um dispositivo compatível.',
              )
            : MobileScanner(
                controller: _controller,
                onDetect: _handleCapture,
                onDetectError: (error, _) {
                  _setError(_messageForStartError(error));
                },
                errorBuilder: _buildScannerError,
              ),
      ),
    );
  }

  Widget _buildScannerError(
    BuildContext context,
    MobileScannerException error,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MessageCard(
            icon: Icons.videocam_off_outlined,
            message: _messageForScannerError(error),
            isError: true,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _startScanning,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraActions() {
    if (!_usesTestPreview && !_supportsCamera) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final cameraCount = state.availableCameras ?? 0;
        final canUseTorch = state.torchState != TorchState.unavailable;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_isStarting)
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-cancel-start'),
                onPressed: _stopScanning,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar inicialização'),
              )
            else if (_cameraEnabled)
              FilledButton.icon(
                key: const ValueKey('qr-scan-stop'),
                onPressed: _stopScanning,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Parar câmera'),
              )
            else
              FilledButton.icon(
                key: const ValueKey('qr-scan-start'),
                onPressed: _startScanning,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _usesTestPreview ? 'Ativar leitor' : 'Ativar câmera',
                ),
              ),
            if (_cameraEnabled && !_usesTestPreview && cameraCount > 1)
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-switch-camera'),
                onPressed: _switchCamera,
                icon: const Icon(Icons.cameraswitch_rounded),
                label: const Text('Frontal / traseira'),
              ),
            if (_cameraEnabled && !_usesTestPreview && canUseTorch)
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-torch'),
                onPressed: _toggleTorch,
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flashlight_off_rounded
                      : Icons.flashlight_on_rounded,
                ),
                label: Text(
                  state.torchState == TorchState.on
                      ? 'Desligar lanterna'
                      : 'Lanterna',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onCopy,
    required this.onOpenUrl,
  });

  final QrScanResult result;
  final VoidCallback onCopy;
  final ValueChanged<Uri> onOpenUrl;

  QrContentInterpretation get _interpretation {
    const numericRetailFormats = {'EAN-8', 'EAN-13', 'UPC-A', 'UPC-E'};
    if (numericRetailFormats.contains(result.format)) {
      return QrContentInterpretation(
        kind: QrContentKind.text,
        rawValue: result.value,
      );
    }
    return const QrContentInterpreter().interpret(result.value);
  }

  String get _kindLabel => switch (_interpretation.kind) {
    QrContentKind.url => 'Link',
    QrContentKind.phone => 'Telefone',
    QrContentKind.email => 'E-mail',
    QrContentKind.whatsapp => 'WhatsApp',
    QrContentKind.wifi => 'Rede Wi-Fi',
    QrContentKind.vcard => 'Contato (vCard)',
    QrContentKind.sms => 'SMS legado',
    QrContentKind.text => 'Texto',
  };

  String? get _actionLabel => switch (_interpretation.kind) {
    QrContentKind.url => 'Abrir link',
    QrContentKind.phone => 'Abrir discador',
    QrContentKind.email => 'Preparar e-mail',
    QrContentKind.whatsapp => 'Abrir WhatsApp',
    QrContentKind.sms => 'Abrir aplicativo de SMS',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final interpretation = _interpretation;
    final uri = interpretation.uri;
    return Card(
      key: const ValueKey('qr-scan-result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Formato: ${result.format}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text('Tipo identificado: $_kindLabel'),
            const SizedBox(height: 8),
            if (interpretation.kind == QrContentKind.wifi) ...[
              for (final entry in interpretation.fields.entries)
                if (entry.key != 'P' && entry.key != 'H')
                  Text(
                    '${switch (entry.key) {
                      'S' => 'Rede',
                      'T' => 'Segurança',
                      _ => entry.key,
                    }}: ${entry.value}',
                  ),
              if (interpretation.fields.containsKey('P'))
                const Text(
                  'A senha está presente no código. Copie o conteúdo apenas se necessário.',
                ),
            ],
            if (interpretation.kind == QrContentKind.vcard)
              for (final entry in interpretation.fields.entries)
                Text('${entry.key}: ${entry.value}'),
            SelectableText(
              result.value,
              key: const ValueKey('qr-scan-result-value'),
              onTap: uri == null ? null : () => onOpenUrl(uri),
              style: uri == null
                  ? null
                  : TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
            ),
            if (_actionLabel != null && uri != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-context-action'),
                onPressed: () => onOpenUrl(uri),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(_actionLabel!),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('qr-scan-copy'),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Theme.of(context).colorScheme.error : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
