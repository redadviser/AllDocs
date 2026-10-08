import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan.dart';
import 'adapty_service.dart';
import 'api_helpers.dart';
import 'auth_service.dart';
import 'local_mode_config.dart';

/// The signed-in account's plan and the plans on offer.
///
/// The plan itself is decided by the backend (from Adapty's webhook or
/// POST /api/plans/sync); the app only caches it, so limits keep working
/// offline, and never sets it on its own.
class PlanService {
  const PlanService._();

  static const _catalogKey = 'plans.catalog.v1';

  static PlanCatalog catalog = PlanCatalog.builtIn;

  /// The account's current plan; every limit in the app reads this.
  static final current = ValueNotifier<AppPlan>(
    PlanCatalog.builtIn.byId(AppPlan.free),
  );

  static Future<void>? _refreshing;
  static Timer? _profileChangeDebounce;

  /// Applies what's cached (catalog + the account's plan), then ties store
  /// purchases to the account and refreshes from the backend in the
  /// background. Called once a session is known (app start, login).
  static Future<void> onSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_catalogKey);
    if (cached != null) {
      try {
        catalog = PlanCatalog.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      } catch (_) {
        catalog = PlanCatalog.builtIn;
      }
    }
    current.value = catalog.byId(await AuthService.plan());

    AdaptyService.onProfileChanged = _onStoreProfileChanged;
    unawaited(_connect());
  }

  static Future<void> _connect() async {
    if (await AuthService.userId() == null) {
      await AuthService.refreshAccount();
    }
    final userId = await AuthService.userId();
    if (userId != null) {
      try {
        await AdaptyService.identify(userId, email: await AuthService.email());
      } catch (error) {
        debugPrint('[Plans] store identify failed: $error');
      }
    }
    await refresh();
  }

  static void onSignedOut() {
    AdaptyService.onProfileChanged = null;
    current.value = catalog.byId(AppPlan.free);
  }

  /// Fetches the catalog and the account's plan. Best effort: offline, the
  /// cached values stay.
  static Future<void> refresh() {
    return _refreshing ??= _fetch(
      '/api/plans',
      post: false,
    ).then((_) {}).whenComplete(() => _refreshing = null);
  }

  /// Has the backend re-read the plan from the store. After a purchase the
  /// store can take a few seconds to report it, so this retries until
  /// [expectPlanId] shows up (or gives up and keeps what it has).
  static Future<void> syncFromStore({String? expectPlanId}) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      // Without the server-side key the backend can't ask Adapty, but its
      // webhook still updates the plan: read what it has.
      if (!await _fetch('/api/plans/sync', post: true)) await refresh();
      if (expectPlanId == null || current.value.id == expectPlanId) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  static Future<bool> _fetch(String path, {required bool post}) async {
    if (LocalModeConfig.isLocalOnly) return false;
    try {
      final token = await AuthService.tokenStore.read();
      if (token == null) return false;
      final headers = ApiHelpers.headersWithToken(token);
      final res = post
          ? await ApiHelpers.post(path, headers: headers)
          : await ApiHelpers.get(path, headers: headers);
      if (res.statusCode != 200) {
        debugPrint('[Plans] $path answered ${res.statusCode}');
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      catalog = PlanCatalog.fromJson(data);
      final planId = data['currentPlanId']?.toString() ?? AppPlan.free;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_catalogKey, jsonEncode(catalog.toJson()));
      await AuthService.setPlan(planId);
      current.value = catalog.byId(planId);
      return true;
    } catch (error) {
      debugPrint('[Plans] $path failed: $error');
      return false;
    }
  }

  /// Buys [product] and, once the store confirms, has the backend apply it.
  static Future<PurchaseOutcome> buy(PlanProduct product) async {
    final outcome = await AdaptyService.purchase(
      product,
      isUpgrade: catalog.isUpgrade(current.value.id, product.planId),
    );
    if (outcome == PurchaseOutcome.purchased) {
      await syncFromStore(expectPlanId: product.planId);
    }
    return outcome;
  }

  static Future<void> restore() async {
    await AdaptyService.restorePurchases();
    await syncFromStore();
  }

  // Renewals, expiries and purchases finished outside the plans screen.
  static void _onStoreProfileChanged() {
    _profileChangeDebounce?.cancel();
    _profileChangeDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(syncFromStore()),
    );
  }
}
