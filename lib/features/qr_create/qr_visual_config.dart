import 'package:flutter/material.dart';

enum QrVisualCategory {
  creators('Redes sociais e criadores'),
  business('Empresas e profissionais'),
  commerce('Comércio e serviços'),
  events('Eventos e divulgação');

  const QrVisualCategory(this.label);
  final String label;
}

enum QrFrameStyle {
  none('Sem moldura', ''),
  simple('Clássica', ''),
  floral('Flores', ''),
  botanical('Folhas botânicas', ''),
  stars('Estrelas', ''),
  hearts('Corações', ''),
  confetti('Confetes', ''),
  text('Moldura com texto', '');

  const QrFrameStyle(this.label, this.defaultCallToAction);
  final String label;
  final String defaultCallToAction;

  bool get hasCallToAction => this == QrFrameStyle.text;
}

class QrVisualPalette {
  const QrVisualPalette({
    required this.id,
    required this.name,
    required this.foreground,
    required this.background,
  });

  final String id;
  final String name;
  final Color foreground;
  final Color background;
}

class QrVisualModel {
  const QrVisualModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.paletteId,
    required this.frame,
  });

  final String id;
  final String name;
  final String description;
  final QrVisualCategory category;
  final String paletteId;
  final QrFrameStyle frame;
}

/// Central registry for reusable styles. A model only changes visual settings,
/// never the content encoded in the QR matrix.
class QrVisualLibrary {
  QrVisualLibrary._();

  static const palettes = <QrVisualPalette>[
    QrVisualPalette(
      id: 'classic',
      name: 'Preto e branco',
      foreground: Color(0xFF000000),
      background: Color(0xFFFFFFFF),
    ),
    QrVisualPalette(
      id: 'corporate-blue',
      name: 'Azul corporativo',
      foreground: Color(0xFF12345A),
      background: Color(0xFFFFFFFF),
    ),
    QrVisualPalette(
      id: 'blue-white',
      name: 'Azul e branco',
      foreground: Color(0xFF0756A5),
      background: Color(0xFFFFFFFF),
    ),
    QrVisualPalette(
      id: 'purple-pink',
      name: 'Roxo e rosa claro',
      foreground: Color(0xFF542078),
      background: Color(0xFFFFF5FA),
    ),
    QrVisualPalette(
      id: 'green-white',
      name: 'Verde e branco',
      foreground: Color(0xFF14532D),
      background: Color(0xFFFFFFFF),
    ),
    QrVisualPalette(
      id: 'minimal',
      name: 'Minimalista quente',
      foreground: Color(0xFF292524),
      background: Color(0xFFFFFDF5),
    ),
    QrVisualPalette(
      id: 'berry',
      name: 'Vinho e creme',
      foreground: Color(0xFF721C35),
      background: Color(0xFFFFF7ED),
    ),
    QrVisualPalette(
      id: 'ocean',
      name: 'Oceano',
      foreground: Color(0xFF064E63),
      background: Color(0xFFEFFBFF),
    ),
    QrVisualPalette(
      id: 'forest',
      name: 'Floresta',
      foreground: Color(0xFF17452B),
      background: Color(0xFFF3F9F0),
    ),
    QrVisualPalette(
      id: 'sunset',
      name: 'Pôr do sol',
      foreground: Color(0xFF7C2D12),
      background: Color(0xFFFFF7ED),
    ),
    QrVisualPalette(
      id: 'lavender',
      name: 'Lavanda',
      foreground: Color(0xFF4C1D95),
      background: Color(0xFFF5F0FF),
    ),
    QrVisualPalette(
      id: 'charcoal',
      name: 'Grafite e gelo',
      foreground: Color(0xFF20262E),
      background: Color(0xFFF5F7FA),
    ),
  ];

  static const models = <QrVisualModel>[
    QrVisualModel(
      id: 'creator-pop',
      name: 'Criador vibrante',
      description: 'Lavanda com moldura de estrelas.',
      category: QrVisualCategory.creators,
      paletteId: 'purple-pink',
      frame: QrFrameStyle.stars,
    ),
    QrVisualModel(
      id: 'creator-clean',
      name: 'Perfil minimalista',
      description: 'Contraste clássico, sem moldura.',
      category: QrVisualCategory.creators,
      paletteId: 'classic',
      frame: QrFrameStyle.none,
    ),
    QrVisualModel(
      id: 'creator-floral',
      name: 'Floral delicado',
      description: 'Tons suaves e detalhes de flores.',
      category: QrVisualCategory.creators,
      paletteId: 'lavender',
      frame: QrFrameStyle.floral,
    ),
    QrVisualModel(
      id: 'business-blue',
      name: 'Corporativo azul',
      description: 'Azul sóbrio com moldura discreta.',
      category: QrVisualCategory.business,
      paletteId: 'corporate-blue',
      frame: QrFrameStyle.simple,
    ),
    QrVisualModel(
      id: 'business-minimal',
      name: 'Profissional essencial',
      description: 'Tons quentes e aparência minimalista.',
      category: QrVisualCategory.business,
      paletteId: 'minimal',
      frame: QrFrameStyle.text,
    ),
    QrVisualModel(
      id: 'commerce-green',
      name: 'Serviços em verde',
      description: 'Verde escuro com folhas botânicas.',
      category: QrVisualCategory.commerce,
      paletteId: 'forest',
      frame: QrFrameStyle.botanical,
    ),
    QrVisualModel(
      id: 'commerce-blue',
      name: 'Cardápio e avaliações',
      description: 'Azul nítido com moldura geométrica.',
      category: QrVisualCategory.commerce,
      paletteId: 'ocean',
      frame: QrFrameStyle.simple,
    ),
    QrVisualModel(
      id: 'event-scan',
      name: 'Convite festivo',
      description: 'Moldura com confetes para eventos.',
      category: QrVisualCategory.events,
      paletteId: 'sunset',
      frame: QrFrameStyle.confetti,
    ),
    QrVisualModel(
      id: 'event-contact',
      name: 'Romântico',
      description: 'Detalhes de coração em tons de vinho.',
      category: QrVisualCategory.events,
      paletteId: 'berry',
      frame: QrFrameStyle.hearts,
    ),
  ];

  static QrVisualPalette palette(String id) =>
      palettes.firstWhere((palette) => palette.id == id);

  static QrVisualModel model(String id) =>
      models.firstWhere((model) => model.id == id);
}

/// WCAG relative-luminance contrast ratio. QR colors below 4.5:1 are rejected.
double contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
