import 'package:flutter_test/flutter_test.dart';

import 'package:all_docs/models/plan.dart';

void main() {
  test('the built-in catalog matches the agreed plans', () {
    const catalog = PlanCatalog.builtIn;
    expect(catalog.plans.map((p) => p.name), ['Pocket', 'Folio', 'Vault']);

    final pocket = catalog.byId(AppPlan.free);
    expect(pocket.storageBytes, 500 * 1024 * 1024);
    expect(pocket.maxActiveReminders, 3);
    expect(pocket.has(PlanFeature.autoBackup), isFalse);

    final folio = catalog.byId(AppPlan.premium);
    expect(folio.storageBytes, 5 * 1024 * 1024 * 1024);
    expect(folio.maxActiveReminders, isNull);
    expect(folio.has(PlanFeature.autoBackup), isTrue);

    final vault = catalog.byId(AppPlan.pro);
    expect(vault.storageBytes, 50 * 1024 * 1024 * 1024);
    expect(vault.features.containsAll(folio.features), isTrue);
  });

  test('an unknown plan id reads as the free plan', () {
    expect(PlanCatalog.builtIn.byId('gold').id, AppPlan.free);
    expect(PlanCatalog.builtIn.byId(null).id, AppPlan.free);
  });

  test('upgrades follow the price order', () {
    const catalog = PlanCatalog.builtIn;
    expect(catalog.isUpgrade(AppPlan.free, AppPlan.premium), isTrue);
    expect(catalog.isUpgrade(AppPlan.premium, AppPlan.pro), isTrue);
    expect(catalog.isUpgrade(AppPlan.pro, AppPlan.premium), isFalse);
  });

  test('reads the backend catalog and ignores features it does not know', () {
    final catalog = PlanCatalog.fromJson({
      'currentPlanId': 'premium',
      'plans': [
        {
          'id': 'free',
          'name': 'Pocket',
          'priceMonthlyCents': 0,
          'priceYearlyCents': 0,
          'currency': 'EUR',
          'storageBytes': 100,
          'maxActiveReminders': 3,
          'maxDevices': 1,
          'features': <String>[],
        },
        {
          'id': 'premium',
          'name': 'Folio',
          'priceMonthlyCents': 199,
          'priceYearlyCents': 1599,
          'currency': 'EUR',
          'storageBytes': 1000,
          'maxActiveReminders': null,
          'maxDevices': 2,
          'features': ['autoBackup', 'teleportation'],
        },
      ],
      'comingSoon': ['watermark'],
    });
    expect(catalog.plans, hasLength(2));
    expect(catalog.byId('premium').features, {PlanFeature.autoBackup});
    expect(catalog.comingSoon, {PlanFeature.watermark});

    final roundTrip = PlanCatalog.fromJson(catalog.toJson());
    expect(roundTrip.byId('premium').storageBytes, 1000);
    expect(roundTrip.byId('free').maxActiveReminders, 3);
  });
}
