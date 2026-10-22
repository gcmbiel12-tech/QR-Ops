enum QrOpsPlan { free, professional }

/// Centralized product capabilities. Null quotas mean "not defined yet".
class QrOpsPlanCapabilities {
  const QrOpsPlanCapabilities({
    required this.customLogo,
    required this.adFree,
    required this.pngResolutions,
    required this.enabledContentTypes,
    this.monthlyCreationQuota,
    this.localHistoryLimit,
  });

  final bool customLogo;
  final bool adFree;
  final List<int> pngResolutions;
  final Set<String> enabledContentTypes;
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
  };

  static const free = QrOpsPlanCapabilities(
    customLogo: false,
    adFree: false,
    pngResolutions: pngResolutions,
    enabledContentTypes: supportedContentTypes,
    monthlyCreationQuota: null,
    localHistoryLimit: null,
  );

  static const professional = QrOpsPlanCapabilities(
    customLogo: true,
    adFree: true,
    pngResolutions: pngResolutions,
    enabledContentTypes: supportedContentTypes,
    monthlyCreationQuota: null,
    localHistoryLimit: null,
  );

  static QrOpsPlanCapabilities forPlan(QrOpsPlan plan) => switch (plan) {
    QrOpsPlan.free => free,
    QrOpsPlan.professional => professional,
  };
}
