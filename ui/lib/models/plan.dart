/// What a plan offers beyond space. Mirrors `PlanFeature` in the backend's
/// src/lib/plans.ts (same names, sent as strings).
enum PlanFeature {
  autoBackup,
  unlimitedReminders,
  watermark,
  pdfTools,
  hiddenAlbums,
  deviceSync,
  secureSharing,
  documentRequests,
  aiAssistant,
  prioritySupport;

  static PlanFeature? fromName(String name) {
    for (final feature in values) {
      if (feature.name == name) return feature;
    }
    return null;
  }
}

enum BillingPeriod { monthly, yearly }

/// One subscription plan. [id] is the account's plan as the backend stores
/// it (free/premium/pro); [name] is what the user sees (Pocket/Folio/Vault).
class AppPlan {
  const AppPlan({
    required this.id,
    required this.name,
    required this.priceMonthlyCents,
    required this.priceYearlyCents,
    required this.storageBytes,
    required this.maxActiveReminders,
    required this.maxDevices,
    required this.features,
  });

  static const free = 'free';
  static const premium = 'premium';
  static const pro = 'pro';

  final String id;
  final String name;

  /// Reference prices in EUR cents; the store's localized price wins when
  /// it's known.
  final int priceMonthlyCents;
  final int priceYearlyCents;

  /// How much the library may hold on this phone (the recycle bin aside).
  final int storageBytes;

  /// Expiry reminders that can be scheduled at once; null = no limit.
  final int? maxActiveReminders;
  final int maxDevices;
  final Set<PlanFeature> features;

  bool get isFree => id == free;
  bool has(PlanFeature feature) => features.contains(feature);

  int priceCents(BillingPeriod period) =>
      period == BillingPeriod.yearly ? priceYearlyCents : priceMonthlyCents;

  factory AppPlan.fromJson(Map<String, dynamic> json) {
    return AppPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      priceMonthlyCents: (json['priceMonthlyCents'] as num).toInt(),
      priceYearlyCents: (json['priceYearlyCents'] as num).toInt(),
      storageBytes: (json['storageBytes'] as num).toInt(),
      maxActiveReminders: (json['maxActiveReminders'] as num?)?.toInt(),
      maxDevices: (json['maxDevices'] as num?)?.toInt() ?? 1,
      features: {
        for (final name in (json['features'] as List? ?? const []))
          ?PlanFeature.fromName(name.toString()),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'priceMonthlyCents': priceMonthlyCents,
    'priceYearlyCents': priceYearlyCents,
    'storageBytes': storageBytes,
    'maxActiveReminders': maxActiveReminders,
    'maxDevices': maxDevices,
    'features': [for (final feature in features) feature.name],
  };
}

/// The plans on offer, cheapest first, and which listed features the app
/// doesn't have yet.
class PlanCatalog {
  const PlanCatalog({required this.plans, required this.comingSoon});

  final List<AppPlan> plans;
  final Set<PlanFeature> comingSoon;

  static const _mb = 1024 * 1024;
  static const _gb = 1024 * _mb;

  static const _folioFeatures = {
    PlanFeature.autoBackup,
    PlanFeature.unlimitedReminders,
    PlanFeature.watermark,
    PlanFeature.pdfTools,
    PlanFeature.hiddenAlbums,
  };

  /// Used until the backend's catalog has been fetched once (and offline).
  /// Keep in step with PLANS in the backend's src/lib/plans.ts.
  static const builtIn = PlanCatalog(
    plans: [
      AppPlan(
        id: AppPlan.free,
        name: 'Pocket',
        priceMonthlyCents: 0,
        priceYearlyCents: 0,
        storageBytes: 500 * _mb,
        maxActiveReminders: 3,
        maxDevices: 1,
        features: {},
      ),
      AppPlan(
        id: AppPlan.premium,
        name: 'Folio',
        priceMonthlyCents: 199,
        priceYearlyCents: 1599,
        storageBytes: 5 * _gb,
        maxActiveReminders: null,
        maxDevices: 2,
        features: _folioFeatures,
      ),
      AppPlan(
        id: AppPlan.pro,
        name: 'Vault',
        priceMonthlyCents: 499,
        priceYearlyCents: 3999,
        storageBytes: 50 * _gb,
        maxActiveReminders: null,
        maxDevices: 3,
        features: {
          ..._folioFeatures,
          PlanFeature.deviceSync,
          PlanFeature.secureSharing,
          PlanFeature.documentRequests,
          PlanFeature.aiAssistant,
          PlanFeature.prioritySupport,
        },
      ),
    ],
    comingSoon: {PlanFeature.deviceSync, PlanFeature.secureSharing},
  );

  /// The plan with [id], or the free plan for an unknown id.
  AppPlan byId(String? id) {
    return plans.firstWhere(
      (plan) => plan.id == id,
      orElse: () =>
          plans.firstWhere((plan) => plan.isFree, orElse: () => plans.first),
    );
  }

  /// Plans are ordered by price, so this is "is [a] above [b]".
  bool isUpgrade(String from, String to) {
    final ids = [for (final plan in plans) plan.id];
    return ids.indexOf(to) > ids.indexOf(from);
  }

  factory PlanCatalog.fromJson(Map<String, dynamic> json) {
    final plans = [
      for (final plan in (json['plans'] as List))
        AppPlan.fromJson((plan as Map).cast<String, dynamic>()),
    ];
    if (plans.isEmpty) return builtIn;
    return PlanCatalog(
      plans: plans,
      comingSoon: {
        for (final name in (json['comingSoon'] as List? ?? const []))
          ?PlanFeature.fromName(name.toString()),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'plans': [for (final plan in plans) plan.toJson()],
    'comingSoon': [for (final feature in comingSoon) feature.name],
  };
}
