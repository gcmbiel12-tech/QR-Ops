import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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

class QrScanPage extends StatefulWidget {
  const QrScanPage({
    super.key,
    required this.isActive,
    this.previewBuilder,
  });

  final bool isActive;

  /// Allows scanner behavior to be tested without requesting camera hardware.
  final QrScanPreviewBuilder? previewBuilder;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  static const _formats = [
    BarcodeFormat.qrCode,
    BarcodeFormat.ean8,
    BarcodeFormat.ean13,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.codabar,
    BarcodeFormat.itf,
  ];

  late final MobileScannerController _controller;
  QrScanResult? _result;
  String? _errorMessage;
  bool _isStarting = false;
  bool _hasRead = false;
  int _startAttempt = 0;

  bool get _usesTestPreview => widget.previewBuilder != null;
  bool get _supportsCamera =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      formats: _formats,
    );
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) unawaited(_startScanning());
      });
    }
  }

  @override
  void didUpdateWidget(covariant QrScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive) {
      unawaited(_startScanning());
    } else {
      _startAttempt++;
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
    if (!widget.isActive) return;
    if (!_usesTestPreview && !_supportsCamera) {
      setState(() => _isStarting = false);
      return;
    }
    final attempt = ++_startAttempt;
    setState(() {
      _result = null;
      _errorMessage = null;
      _hasRead = false;
      _isStarting = !_usesTestPreview;
    });

    if (_usesTestPreview) return;

    try {
      await _controller.start();
      if (!mounted || attempt != _startAttempt) return;
      final scannerError = _controller.value.error;
      if (scannerError != null) {
        _setError(_messageForScannerError(scannerError));
        return;
      }
      setState(() => _isStarting = false);
    } on Object catch (error) {
      if (!mounted || attempt != _startAttempt) return;
      _setError(_messageForStartError(error));
    }
  }

  void _stopCamera() {
    if (_usesTestPreview ||
        !_supportsCamera ||
        (!_controller.value.isRunning && !_controller.value.isStarting)) {
      return;
    }
    unawaited(_controller.stop().catchError((Object _) {}));
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_hasRead || !widget.isActive) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _acceptResult(
        QrScanResult(value: value, format: _formatLabel(barcode.format)),
      );
      return;
    }
  }

  void _acceptResult(QrScanResult result) {
    if (_hasRead || !widget.isActive || result.value.isEmpty) return;
    _hasRead = true;
    setState(() {
      _result = result;
      _errorMessage = null;
      _isStarting = false;
    });
    if (!_usesTestPreview) {
      unawaited(_controller.stop().catchError((Object _) {}));
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isStarting = false;
    });
    if (!_usesTestPreview) {
      unawaited(_controller.stop().catchError((Object _) {}));
    }
  }

  String _messageForScannerError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'A permissão da câmera foi negada. Autorize o acesso à câmera nas '
            'configurações do aplicativo ou do navegador e tente novamente.',
      MobileScannerErrorCode.unsupported =>
        'Nenhuma câmera compatível foi encontrada. Conecte ou habilite uma '
            'câmera e tente novamente.',
      _ => _messageForStartError(error),
    };
  }

  String _messageForStartError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') ||
        message.contains('notallowederror') ||
        message.contains('denied')) {
      return 'O acesso à câmera foi negado. Permita o uso da câmera nas '
          'configurações do navegador ou do aplicativo e tente novamente.';
    }
    if (message.contains('notfounderror') ||
        message.contains('no camera') ||
        message.contains('camera not found')) {
      return 'Nenhuma câmera foi encontrada. Conecte uma webcam ou habilite '
          'a câmera do dispositivo e tente novamente.';
    }
    if (message.contains('notreadableerror') ||
        message.contains('could not start video source') ||
        message.contains('in use')) {
      return 'A câmera está indisponível ou sendo usada por outro aplicativo. '
          'Feche outros aplicativos ou abas que usam a câmera e tente novamente.';
    }
    return 'Não foi possível iniciar a câmera. Verifique a conexão, a '
        'permissão e se outro aplicativo está usando a câmera; depois tente novamente.';
  }

  String _formatLabel(BarcodeFormat format) => switch (format) {
    BarcodeFormat.qrCode => 'QR Code',
    BarcodeFormat.ean8 => 'EAN-8',
    BarcodeFormat.ean13 => 'EAN-13',
    BarcodeFormat.upcA => 'UPC-A',
    BarcodeFormat.upcE => 'UPC-E',
    BarcodeFormat.code128 => 'Code 128',
    BarcodeFormat.code39 => 'Code 39',
    BarcodeFormat.code93 => 'Code 93',
    BarcodeFormat.codabar => 'Codabar',
    BarcodeFormat.itf => 'ITF',
    _ => 'Código de barras',
  };

  Future<void> _copyResult() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result.value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conteúdo copiado.')),
    );
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } on Object catch (error) {
      if (mounted) _setError(_messageForStartError(error));
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } on Object catch (error) {
      if (mounted) _setError(_messageForStartError(error));
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
                  'Aponte a câmera para um QR Code ou código de barras. '
                  'O conteúdo será lido apenas neste dispositivo.',
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
                        _buildPreview(),
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
                          _ResultCard(result: result, onCopy: _copyResult),
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
                            message: 'Mantenha o código dentro da área da câmera. '
                                'Se não for reconhecido, ajuste a distância e a iluminação.',
                          ),
                          const SizedBox(height: 8),
                          _buildCameraActions(),
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
      'No navegador, permita o acesso à câmera. O site precisa estar em HTTPS '
      'ou em um contexto seguro compatível (como localhost).',
      key: const ValueKey('qr-scan-web-permission-hint'),
      style: textTheme.bodySmall,
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
                message: 'A câmera não está disponível no executável Windows. '
                    'Abra a versão Web do QR Ops em um navegador para usar uma webcam.',
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

  Widget _buildScannerError(BuildContext context, MobileScannerException error) {
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
    if (_usesTestPreview) return const SizedBox.shrink();
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
            if (cameraCount > 1)
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-switch-camera'),
                onPressed: _switchCamera,
                icon: const Icon(Icons.cameraswitch_rounded),
                label: const Text('Trocar câmera'),
              ),
            if (canUseTorch)
              OutlinedButton.icon(
                key: const ValueKey('qr-scan-torch'),
                onPressed: _toggleTorch,
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flashlight_off_rounded
                      : Icons.flashlight_on_rounded,
                ),
                label: Text(
                  state.torchState == TorchState.on ? 'Desligar lanterna' : 'Lanterna',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onCopy});

  final QrScanResult result;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('qr-scan-result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Formato: ${result.format}', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SelectableText(result.value, key: const ValueKey('qr-scan-result-value')),
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
            Expanded(child: Text(message, style: TextStyle(color: color))),
          ],
        ),
      ),
    );
  }
}
