import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/app_constants.dart';
import '../../common/document_actions.dart' show showSnack;
import '../../common/zip_preview_sheet.dart' show formatBytes;
import '../../models/models.dart';
import '../../services/services.dart';
import '../../theme/app_theme.dart';

/// A plan's space as people say it: "500 MB", "5 GB".
String _planSize(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  return bytes >= gb && bytes % gb == 0
      ? '${bytes ~/ gb} GB'
      : bytes % mb == 0
      ? '${bytes ~/ mb} MB'
      : formatBytes(bytes);
}

Future<void> openPlansScreen(BuildContext context, {StorageSummary? summary}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlansScreen(summary: summary)),
  );
}

/// The plan's medal: grey for Pocket, blue for Folio, gold for Vault.
class PlanMedal extends StatelessWidget {
  const PlanMedal({super.key, required this.plan, this.size = 20});

  final AppPlan plan;
  final double size;

  static Color colorFor(AppPlan plan) => switch (plan.id) {
    AppPlan.pro => const Color(0xFFE8B84A),
    AppPlan.premium => const Color(0xFF6FA2FF),
    _ => AppTheme.mutedText,
  };

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.workspace_premium_rounded,
      size: size,
      color: colorFor(plan),
    );
  }
}

/// The plan's medal and name next to the greeting; opens the plans.
class PlanChip extends StatelessWidget {
  const PlanChip({super.key, this.summary});

  final StorageSummary? summary;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPlan>(
      valueListenable: PlanService.current,
      builder: (context, plan, _) {
        final color = PlanMedal.colorFor(plan);
        return Tooltip(
          message: AppConstants.plansSeePlans.tr(),
          child: Material(
            color: color.withValues(alpha: 0.14),
            shape: StadiumBorder(
              side: BorderSide(color: color.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openPlansScreen(context, summary: summary),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlanMedal(plan: plan, size: 17),
                    const SizedBox(width: 4),
                    Text(
                      plan.name,
                      style: TextStyle(
                        color: plan.isFree ? AppTheme.text : color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The plans on a page of their own, opened from "See plans" prompts.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key, this.summary});

  /// The library's current use, shown above the plans when known.
  final StorageSummary? summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background, AppTheme.backgroundBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        AppConstants.plansTitle.tr(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                // Compact enough to take in at once: usage, period, the
                // cards side by side, and little else.
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [PlansPanel(summary: summary)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pocket / Folio / Vault side by side, bought straight from their cards
/// (App Store / Google Play through Adapty). Shown on the profile page and
/// on [PlansScreen].
class PlansPanel extends StatefulWidget {
  const PlansPanel({super.key, this.summary});

  /// The library's current use, shown above the plans when given.
  final StorageSummary? summary;

  @override
  State<PlansPanel> createState() => _PlansPanelState();
}

class _PlansPanelState extends State<PlansPanel> {
  BillingPeriod _period = BillingPeriod.yearly;
  List<PlanProduct> _products = const [];
  String? _busyPlanId;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    PlanService.refresh();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (!AdaptyService.isAvailable) return;
    try {
      final products = await AdaptyService.loadProducts();
      if (mounted) setState(() => _products = products);
    } catch (_) {
      // Prices fall back to the reference ones; buying says what's wrong.
    }
  }

  PlanProduct? _productFor(String planId, BillingPeriod period) {
    for (final product in _products) {
      if (product.planId == planId && product.period == period) return product;
    }
    return null;
  }

  String _price(AppPlan plan, BillingPeriod period) {
    if (plan.isFree) return AppConstants.plansFreePrice.tr();
    final storePrice = _productFor(plan.id, period)?.localizedPrice;
    if (storePrice != null && storePrice.isNotEmpty) return storePrice;
    // A language alone ("pt") formats like Brazil; the reference prices
    // are in euros, so use the European variant of each language.
    const euroLocales = {
      'pt': 'pt_PT',
      'es': 'es_ES',
      'fr': 'fr_FR',
      'en': 'en_IE',
    };
    final language = context.locale.languageCode;
    return NumberFormat.simpleCurrency(
      locale: euroLocales[language] ?? context.locale.toString(),
      name: 'EUR',
    ).format(plan.priceCents(period) / 100);
  }

  /// How much cheaper a year is than twelve months, from the store prices
  /// when both are known.
  int _yearlySavingPercent() {
    final plan = PlanService.catalog.plans.lastWhere(
      (plan) => !plan.isFree,
      orElse: () => PlanService.catalog.plans.last,
    );
    var monthly = plan.priceMonthlyCents / 100;
    var yearly = plan.priceYearlyCents / 100;
    final storeMonthly = _productFor(plan.id, BillingPeriod.monthly);
    final storeYearly = _productFor(plan.id, BillingPeriod.yearly);
    if (storeMonthly != null && storeYearly != null) {
      monthly = storeMonthly.product.price.amount;
      yearly = storeYearly.product.price.amount;
    }
    if (monthly <= 0) return 0;
    return (100 - yearly / (monthly * 12) * 100).round().clamp(0, 99);
  }

  Future<void> _choose(AppPlan plan) async {
    if (!AdaptyService.isAvailable) {
      showSnack(context, AppConstants.plansUnavailable.tr());
      return;
    }
    setState(() => _busyPlanId = plan.id);
    try {
      if (_products.isEmpty) await _loadProducts();
      final product = _productFor(plan.id, _period);
      if (product == null) {
        if (mounted) showSnack(context, AppConstants.plansUnavailable.tr());
        return;
      }
      final outcome = await PlanService.buy(product);
      if (!mounted) return;
      switch (outcome) {
        case PurchaseOutcome.purchased:
          showSnack(
            context,
            AppConstants.plansPurchased.tr(namedArgs: {'plan': plan.name}),
          );
        case PurchaseOutcome.pending:
          showSnack(context, AppConstants.plansPending.tr());
        case PurchaseOutcome.cancelled:
          break;
      }
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.plansFailed.tr());
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  Future<void> _restore() async {
    if (!AdaptyService.isAvailable) {
      showSnack(context, AppConstants.plansUnavailable.tr());
      return;
    }
    setState(() => _restoring = true);
    try {
      await PlanService.restore();
      if (!mounted) return;
      showSnack(
        context,
        AppConstants.plansRestored.tr(
          namedArgs: {'plan': PlanService.current.value.name},
        ),
      );
    } catch (_) {
      if (mounted) showSnack(context, AppConstants.plansFailed.tr());
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Cancelling or switching to free happens in the store's own settings.
  Future<void> _manageSubscription() async {
    final uri = Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPlan>(
      valueListenable: PlanService.current,
      builder: (context, current, _) => _buildContent(current),
    );
  }

  Widget _buildContent(AppPlan current) {
    final catalog = PlanService.catalog;
    final summary = widget.summary?.withLimit(current.storageBytes);
    final storeName = Platform.isIOS ? 'App Store' : 'Google Play';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary != null) ...[
          _UsageBar(summary: summary, plan: current),
          const SizedBox(height: 12),
        ],
        _PeriodSwitch(
          period: _period,
          savingPercent: _yearlySavingPercent(),
          onChanged: (period) => setState(() => _period = period),
        ),
        const SizedBox(height: 12),
        // Side by side, the middle plan (the one recommended, as plans
        // are usually laid out) centred first, its neighbours peeking in.
        _PlanCarousel(
          initialIndex: catalog.plans.length ~/ 2,
          cards: [
            for (var i = 0; i < catalog.plans.length; i++)
              _PlanCard(
                plan: catalog.plans[i],
                previous: i > 0 ? catalog.plans[i - 1] : null,
                comingSoon: catalog.comingSoon,
                price: _price(catalog.plans[i], _period),
                period: _period,
                isCurrent: catalog.plans[i].id == current.id,
                isRecommended: i == catalog.plans.length ~/ 2,
                busy: _busyPlanId == catalog.plans[i].id,
                enabled: _busyPlanId == null && !_restoring,
                onChoose: () => _choose(catalog.plans[i]),
                onManage: current.isFree ? null : _manageSubscription,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _restoring || _busyPlanId != null ? null : _restore,
              child: _restoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppConstants.plansRestore.tr()),
            ),
            if (!current.isFree)
              TextButton(
                onPressed: _manageSubscription,
                child: Text(AppConstants.plansManage.tr()),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppConstants.plansLegal.tr(namedArgs: {'store': storeName}),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.dimText,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.summary, required this.plan});

  final StorageSummary summary;
  final AppPlan plan;

  @override
  Widget build(BuildContext context) {
    final color = summary.usedRatio > 0.85
        ? AppTheme.destructive
        : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                plan.name,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                AppConstants.plansUsage.tr(
                  namedArgs: {
                    'used': formatBytes(summary.countedBytes),
                    'limit': _planSize(summary.limitBytes),
                  },
                ),
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: summary.countedBytes == 0
                  ? 0
                  : summary.usedRatio.clamp(0.01, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.surfaceSoft,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({
    required this.period,
    required this.savingPercent,
    required this.onChanged,
  });

  final BillingPeriod period;
  final int savingPercent;
  final ValueChanged<BillingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(BillingPeriod value, String label, {String? badge}) {
      final selected = value == period;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: () => onChanged(value),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: selected
                      ? AppTheme.accent.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              // Narrow spaces (the profile page, large text) shrink the
              // label and its badge instead of overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? AppTheme.text : AppTheme.mutedText,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceStrong,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          option(BillingPeriod.monthly, AppConstants.plansMonthly.tr()),
          option(
            BillingPeriod.yearly,
            AppConstants.plansYearly.tr(),
            badge: savingPercent > 0
                ? AppConstants.plansSave.tr(
                    namedArgs: {'percent': '$savingPercent'},
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// Plan cards in a horizontal row that snaps one card into the centre,
/// with dots underneath. Cards are as tall as the tallest.
class _PlanCarousel extends StatefulWidget {
  const _PlanCarousel({required this.cards, required this.initialIndex});

  final List<Widget> cards;
  final int initialIndex;

  @override
  State<_PlanCarousel> createState() => _PlanCarouselState();
}

class _PlanCarouselState extends State<_PlanCarousel> {
  static const _gap = 12.0;

  final _controller = ScrollController();
  late int _index = widget.initialIndex;
  double _extent = 0;
  bool _positioned = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_extent <= 0) return;
    final index = (_controller.offset / _extent).round().clamp(
      0,
      widget.cards.length - 1,
    );
    if (index != _index) setState(() => _index = index);
  }

  void _goTo(int index) {
    _controller.animateTo(
      index * _extent,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final cardWidth = math.min(300.0, viewport * 0.84);
        final side = (viewport - cardWidth) / 2;
        _extent = cardWidth + _gap;
        if (!_positioned) {
          _positioned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_controller.hasClients) {
              _controller.jumpTo(widget.initialIndex * _extent);
            }
          });
        }
        return Column(
          children: [
            SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: _SnapPhysics(extent: _extent),
              // Room for the recommended card's shadow inside the clip.
              padding: EdgeInsets.fromLTRB(side, 4, side, 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      SizedBox(width: cardWidth, child: widget.cards[i]),
                    ],
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.cards.length; i++)
                  GestureDetector(
                    onTap: () => _goTo(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == _index ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? AppTheme.accent
                              : AppTheme.text.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Ends every fling on a card boundary.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.extent, super.parent});

  final double extent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * extent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.previous,
    required this.comingSoon,
    required this.price,
    required this.period,
    required this.isCurrent,
    required this.isRecommended,
    required this.busy,
    required this.enabled,
    required this.onChoose,
    required this.onManage,
  });

  final AppPlan plan;

  /// The plan below this one; its features are summed up in one line.
  final AppPlan? previous;
  final Set<PlanFeature> comingSoon;
  final String price;
  final BillingPeriod period;
  final bool isCurrent;
  final bool isRecommended;
  final bool busy;
  final bool enabled;
  final VoidCallback onChoose;

  /// Set when the account pays for a plan: the free card then leads to the
  /// store's subscription settings, where it is cancelled.
  final VoidCallback? onManage;

  static const _taglines = {
    AppPlan.free: AppConstants.plansTaglineFree,
    AppPlan.premium: AppConstants.plansTaglinePremium,
    AppPlan.pro: AppConstants.plansTaglinePro,
  };

  static const _featureKeys = {
    PlanFeature.autoBackup: AppConstants.plansFeatureAutoBackup,
    PlanFeature.watermark: AppConstants.plansFeatureWatermark,
    PlanFeature.pdfTools: AppConstants.plansFeaturePdfTools,
    PlanFeature.hiddenAlbums: AppConstants.plansFeatureHiddenAlbums,
    PlanFeature.deviceSync: AppConstants.plansFeatureDeviceSync,
    PlanFeature.secureSharing: AppConstants.plansFeatureSecureSharing,
    PlanFeature.documentRequests: AppConstants.plansFeatureDocumentRequests,
    PlanFeature.aiAssistant: AppConstants.plansFeatureAiAssistant,
    PlanFeature.prioritySupport: AppConstants.plansFeaturePrioritySupport,
  };

  List<Widget> _features() {
    final rows = <Widget>[
      _FeatureRow(
        icon: Icons.folder_outlined,
        text: AppConstants.plansStorage.tr(
          namedArgs: {'size': _planSize(plan.storageBytes)},
        ),
        strong: true,
      ),
      _FeatureRow(
        icon: Icons.notifications_active_outlined,
        text: plan.maxActiveReminders == null
            ? AppConstants.plansRemindersUnlimited.tr()
            : AppConstants.plansRemindersLimited.tr(
                namedArgs: {'count': '${plan.maxActiveReminders}'},
              ),
      ),
      if (!plan.has(PlanFeature.autoBackup))
        _FeatureRow(
          icon: Icons.backup_outlined,
          text: AppConstants.plansBackupManual.tr(),
        ),
    ];

    final below = previous;
    if (below != null && !below.isFree) {
      rows.add(
        _FeatureRow(
          icon: Icons.add_circle_outline_rounded,
          text: AppConstants.plansEverythingIn.tr(
            namedArgs: {'plan': below.name},
          ),
        ),
      );
    }
    for (final feature in PlanFeature.values) {
      if (feature == PlanFeature.unlimitedReminders) continue;
      if (!plan.has(feature) || (below?.has(feature) ?? false)) continue;
      final key = _featureKeys[feature];
      if (key == null) continue;
      rows.add(
        _FeatureRow(
          icon: Icons.check_circle_outline_rounded,
          text: key.tr(namedArgs: {'count': '${plan.maxDevices}'}),
          comingSoon: comingSoon.contains(feature),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final highlight = isRecommended && !isCurrent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent
              ? AppTheme.success.withValues(alpha: 0.6)
              : highlight
              ? AppTheme.accent.withValues(alpha: 0.75)
              : AppTheme.border,
          width: highlight || isCurrent ? 1.5 : 1,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (_taglines[plan.id] ?? AppConstants.plansTaglineFree)
                          .tr(),
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                _Badge(
                  label: AppConstants.plansCurrent.tr(),
                  color: AppTheme.success,
                )
              else if (isRecommended)
                _Badge(
                  label: AppConstants.plansRecommended.tr(),
                  color: AppTheme.accent,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  price,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!plan.isFree) ...[
                const SizedBox(width: 4),
                Text(
                  (period == BillingPeriod.yearly
                          ? AppConstants.plansPerYear
                          : AppConstants.plansPerMonth)
                      .tr(),
                  style: const TextStyle(color: AppTheme.mutedText),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: AppTheme.border.withValues(alpha: 0.8)),
          const SizedBox(height: 8),
          ..._features(),
          const SizedBox(height: 14),
          // Cards in a row share the tallest one's height; the buttons line
          // up at the bottom.
          const Spacer(),
          _action(),
        ],
      ),
    );
  }

  Widget _action() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    const size = Size.fromHeight(44);

    if (isCurrent) {
      return OutlinedButton(
        onPressed: null,
        style: OutlinedButton.styleFrom(minimumSize: size, shape: shape),
        child: Text(AppConstants.plansCurrent.tr()),
      );
    }
    if (plan.isFree) {
      return OutlinedButton(
        onPressed: onManage,
        style: OutlinedButton.styleFrom(minimumSize: size, shape: shape),
        child: Text(AppConstants.plansManage.tr()),
      );
    }
    final label = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(AppConstants.plansChoose.tr(namedArgs: {'plan': plan.name}));
    if (isRecommended) {
      return FilledButton(
        onPressed: enabled ? onChoose : null,
        style: FilledButton.styleFrom(minimumSize: size, shape: shape),
        child: label,
      );
    }
    return OutlinedButton(
      onPressed: enabled ? onChoose : null,
      style: OutlinedButton.styleFrom(
        minimumSize: size,
        shape: shape,
        foregroundColor: AppTheme.text,
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.6)),
      ),
      child: label,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.text,
    this.strong = false,
    this.comingSoon = false,
  });

  final IconData icon;
  final String text;
  final bool strong;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: comingSoon ? AppTheme.dimText : AppTheme.primarySoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: comingSoon ? AppTheme.mutedText : AppTheme.text,
                fontSize: 14,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (comingSoon)
            _Badge(
              label: AppConstants.plansComingSoon.tr(),
              color: AppTheme.dimText,
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == AppTheme.dimText ? AppTheme.mutedText : color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
