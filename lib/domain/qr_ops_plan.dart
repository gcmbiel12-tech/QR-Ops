enum QrOpsPlan { free, professional }

/// Centralized product capabilities. Null quotas mean "not defined yet".
class QrOpsPlanCapabilities {
  const QrOpsPlanCapabilities({
    required this.customLogo,
    required this.adFree,
    required this.pngResolutions,
    required this.enabledContentTypes,
    required this.customVisualColors,
    required this.visualModelIds,
    required this.visualPaletteIds,
    required this.visualFrames,
    this.monthlyCreationQuota,
    this.localHistoryLimit,
  });

  final bool customLogo;
  final bool adFree;
  final List<int> pngResolutions;
  final Set<String> enabledContentTypes;
  final bool customVisualColors;
  final Set<String> visualModelIds;
  final Set<String> visualPaletteIds;
  final Set<String> visualFrames;
  final int? monthlyCreationQuota;
  final int? localHistoryLimit;
}

class QrOpsPlans {
  QrOpsPlans._();

  static const pngResolutions = <int>[256, 512, 1024, 2048];

  // SMS remains in the supported types for existing records and compatibility.
  static const supportedContentTypes = <String>{
    'text',
    'url',
    'phone',
    'email',
    'wifi',
    'whatsapp',
  };

  static const basicVisualModels = <String>{
    'creator-clean',
    'business-blue',
    'event-scan',
  };
  static const allVisualModels = <String>{
    ...basicVisualModels,
    'creator-pop',
    'business-minimal',
    'commerce-blue',
    'commerce-green',
    'event-contact',
    'creator-floral',
  };
  static const basicVisualPalettes = <String>{
    'classic',
    'corporate-blue',
    'blue-white',
  };
  static const allVisualPalettes = <String>{
    ...basicVisualPalettes,
    'purple-pink',
    'green-white',
    'minimal',
    'berry',
    'ocean',
    'forest',
    'sunset',
    'lavender',
    'charcoal',
  };
  static const basicVisualFrames = <String>{'none', 'simple', 'text'};
  static const allVisualFrames = <String>{
    ...basicVisualFrames,
    'floral',
    'botanical',
    'stars',
    'hearts',
    'confetti',
  };

  static const free = QrOpsPlanCapabilities(
    customLogo: false,
    adFree: false,
    pngResolutions: pngResolutions,
    enabledContentTypes: supportedContentTypes,
    customVisualColors: false,
    visualModelIds: basicVisualModels,
    visualPaletteIds: basicVisualPalettes,
    visualFrames: basicVisualFrames,
    monthlyCreationQuota: null,
    localHistoryLimit: null,
  );

  static const professional = QrOpsPlanCapabilities(
    customLogo: true,
    adFree: true,
    pngResolutions: pngResolutions,
    enabledContentTypes: supportedContentTypes,
    customVisualColors: true,
    visualModelIds: allVisualModels,
    visualPaletteIds: allVisualPalettes,
    visualFrames: allVisualFrames,
    monthlyCreationQuota: null,
    localHistoryLimit: null,
  );

  static QrOpsPlanCapabilities forPlan(QrOpsPlan plan) => switch (plan) {
    QrOpsPlan.free => free,
    QrOpsPlan.professional => professional,
  };
}
