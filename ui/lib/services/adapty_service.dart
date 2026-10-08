import 'dart:async';
import 'dart:io';

import 'package:adapty_flutter/adapty_flutter.dart';
import 'package:flutter/foundation.dart';

import '../models/plan.dart';

/// A store product for one plan and billing period, with the price the
/// store shows in the user's own currency.
class PlanProduct {
  const PlanProduct({
    required this.planId,
    required this.period,
    required this.product,
  });

  final String planId;
  final BillingPeriod period;
  final AdaptyPaywallProduct product;

  String? get localizedPrice => product.price.localizedString;
}

enum PurchaseOutcome { purchased, pending, cancelled }

/// App Store / Google Play subscriptions through Adapty (as in AllPhotos).
///
/// Adapty setup this expects:
/// - access levels `premium` (Folio) and `pro` (Vault);
/// - one placement ([_placementId], default `alldocs_plans`) whose paywall
///   holds the four products: Folio and Vault, monthly and yearly. On iOS
///   all four go in one subscription group, so changing plan replaces the
///   current subscription instead of adding a second one.
///
/// The buyer is identified with the AllDocs user id, which is what the
/// backend's webhook and POST /api/plans/sync look the account up by.
class AdaptyService {
  const AdaptyService._();

  static const String _publicSdkKey = String.fromEnvironment(
    'ADAPTY_PUBLIC_SDK_KEY',
  );
  static const String _placementId = String.fromEnvironment(
    'ADAPTY_PLACEMENT_PLANS',
    defaultValue: 'alldocs_plans',
  );

  static final Adapty _adapty = Adapty();
  static Future<void>? _activation;
  static String? _identifiedUserId;
  static StreamSubscription<AdaptyProfile>? _profileUpdates;

  /// Called whenever Adapty reports a changed profile (a purchase, renewal
  /// or expiry noticed by the SDK).
  static void Function()? onProfileChanged;

  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// False in builds without `--dart-define=ADAPTY_PUBLIC_SDK_KEY=...`:
  /// plans are shown but can't be bought.
  static bool get isAvailable =>
      isSupportedPlatform && _publicSdkKey.trim().isNotEmpty;

  static Future<void> initialize() {
    if (!isAvailable) return Future.value();
    return _activation ??= _activate().catchError((Object error) {
      _activation = null;
      debugPrint('[Adapty] activation failed: $error');
    });
  }

  static Future<void> _activate() async {
    var alreadyActive = false;
    if (kDebugMode) {
      try {
        alreadyActive = await _adapty.isActivated();
      } catch (_) {}
    }
    if (alreadyActive) {
      // Hot restart: the native SDK kept running.
      _adapty.setupAfterHotRestart();
    } else {
      await _adapty.activate(
        configuration: AdaptyConfiguration(apiKey: _publicSdkKey)
          ..withLogLevel(
            kDebugMode ? AdaptyLogLevel.verbose : AdaptyLogLevel.error,
          )
          ..withAppleIdfaCollectionDisabled(true)
          ..withGoogleAdvertisingIdCollectionDisabled(true),
      );
    }
    _profileUpdates ??= _adapty.didUpdateProfileStream.listen(
      (_) => onProfileChanged?.call(),
      onError: (Object error) => debugPrint('[Adapty] profile error: $error'),
    );
  }

  /// Ties purchases on this phone to the AllDocs account [userId].
  static Future<void> identify(String userId, {String? email}) async {
    if (!isAvailable || userId.isEmpty) return;
    await initialize();
    if (_identifiedUserId == userId) return;
    await _adapty.identify(
      userId,
      // Apple accepts only a UUID here; AllDocs user ids are UUIDs.
      iosAppAccountToken: _looksLikeUuid(userId) ? userId : null,
      androidObfuscatedAccountId: userId,
    );
    _identifiedUserId = userId;
    if (email != null && email.isNotEmpty) {
      try {
        await _adapty.updateProfile(
          (AdaptyProfileParametersBuilder()..setEmail(email)).build(),
        );
      } catch (error) {
        debugPrint('[Adapty] updateProfile failed: $error');
      }
    }
  }

  static Future<void> logout() async {
    _identifiedUserId = null;
    if (!isAvailable || _activation == null) return;
    try {
      await _activation;
      await _adapty.logout();
    } catch (_) {}
  }

  /// The four plan products with their store prices; empty when the store
  /// can't be reached or Adapty isn't set up.
  static Future<List<PlanProduct>> loadProducts() async {
    if (!isAvailable) return const [];
    await initialize();
    final paywall = await _adapty.getPaywall(
      placementId: _placementId,
      fetchPolicy: AdaptyPaywallFetchPolicy.reloadRevalidatingCacheData,
      loadTimeout: const Duration(seconds: 10),
    );
    unawaited(_adapty.logShowPaywall(paywall: paywall).catchError((_) {}));
    final products = await _adapty.getPaywallProducts(paywall: paywall);
    return [
      for (final product in products)
        if (_planIdOf(product) case final planId?)
          PlanProduct(
            planId: planId,
            period: _periodOf(product),
            product: product,
          ),
    ];
  }

  /// Buys [product]. On Android, a current subscription to another plan is
  /// replaced (prorated on an upgrade, at the end of the paid period on a
  /// downgrade) rather than kept alongside.
  static Future<PurchaseOutcome> purchase(
    PlanProduct product, {
    required bool isUpgrade,
  }) async {
    await initialize();
    final result = await _adapty.makePurchase(
      product: product.product,
      parameters: await _androidReplacement(isUpgrade: isUpgrade),
    );
    return switch (result) {
      AdaptyPurchaseResultSuccess() => PurchaseOutcome.purchased,
      AdaptyPurchaseResultPending() => PurchaseOutcome.pending,
      AdaptyPurchaseResultUserCancelled() => PurchaseOutcome.cancelled,
    };
  }

  /// Restores purchases made with this store account (new phone, reinstall).
  static Future<void> restorePurchases() async {
    await initialize();
    await _adapty.restorePurchases();
  }

  static Future<AdaptyPurchaseParameters?> _androidReplacement({
    required bool isUpgrade,
  }) async {
    if (!Platform.isAndroid) return null;
    String? current;
    try {
      final profile = await _adapty.getProfile();
      for (final level in profile.accessLevels.values) {
        if (level.isActive && !level.isRefund && level.store == 'play_store') {
          current = level.vendorProductId;
          break;
        }
      }
    } catch (_) {}
    if (current == null || current.isEmpty) return null;
    return (AdaptyPurchaseParametersBuilder()..setSubscriptionUpdateParams(
          AdaptyAndroidSubscriptionUpdateParameters(
            current,
            isUpgrade
                ? AdaptyAndroidSubscriptionUpdateReplacementMode
                      .withTimeProration
                : AdaptyAndroidSubscriptionUpdateReplacementMode.deferred,
          ),
        ))
        .build();
  }

  static String? _planIdOf(AdaptyPaywallProduct product) {
    final level = product.accessLevelId.toLowerCase();
    if (level == AppPlan.pro || level.contains('vault')) return AppPlan.pro;
    if (level == AppPlan.premium || level.contains('folio')) {
      return AppPlan.premium;
    }
    return null;
  }

  static BillingPeriod _periodOf(AdaptyPaywallProduct product) {
    final unit = product.subscription?.period.unit;
    if (unit == AdaptyPeriodUnit.year) return BillingPeriod.yearly;
    if (unit == AdaptyPeriodUnit.month) return BillingPeriod.monthly;
    final id = product.vendorProductId.toLowerCase();
    return RegExp('year|annual|anual').hasMatch(id)
        ? BillingPeriod.yearly
        : BillingPeriod.monthly;
  }

  static bool _looksLikeUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
