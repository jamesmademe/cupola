import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/features/settings/data/donation_service.dart';

/// Bottom sheet for in-app donations on iOS.
///
/// On open it fetches products from the App Store, shows the available tiers,
/// and manages the full purchase lifecycle (buying → completing → thank-you).
///
/// Not used on macOS / Android: those platforms open the Ko-fi URL directly.
class DonationSheet extends StatefulWidget {
  const DonationSheet({super.key});

  @override
  State<DonationSheet> createState() => _DonationSheetState();
}

class _DonationSheetState extends State<DonationSheet> {
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  bool _thanked = false;
  String? _errorMessage;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _subscribeToPurchaseStream();
    _fetchProducts();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  // ── IAP setup ─────────────────────────────────────────────────────────────

  void _subscribeToPurchaseStream() {
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (_) {
        if (mounted) {
          setState(() {
            _purchasing = false;
            _errorMessage =
                'The store did not complete the purchase. You have not been '
                'charged.';
          });
        }
      },
    );
  }

  Future<void> _fetchProducts() async {
    try {
      final response = await DonationService.fetchProducts();
      if (!mounted) return;

      // If no products were returned the App Store is reachable but the IAP
      // products haven't been configured in App Store Connect yet (or the app
      // isn't live). Signal the parent to fall back to the Ko-fi URL.
      if (response.productDetails.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _products = response.productDetails;
        _loading = false;
      });
    } catch (_) {
      // Store unavailable: fall back to Ko-fi.
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  // ── Purchase handling ─────────────────────────────────────────────────────

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await DonationService.complete(purchase);
          if (mounted) setState(() => _thanked = true);

        case PurchaseStatus.error:
          await DonationService.complete(purchase);
          if (mounted) {
            setState(() {
              _purchasing = false;
              _errorMessage = 'Purchase failed. You have not been charged.';
            });
          }

        case PurchaseStatus.canceled:
          await DonationService.complete(purchase);
          if (mounted) setState(() => _purchasing = false);

        case PurchaseStatus.pending:
          break;
      }
    }
  }

  Future<void> _startPurchase(ProductDetails product) async {
    setState(() {
      _purchasing = true;
      _errorMessage = null;
    });
    await DonationService.buy(product);
    // Result arrives via _handlePurchaseUpdate.
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the [ProductDetails] for a given [DonationTier], or null if not
  /// yet loaded / not found in the App Store response.
  ProductDetails? _productFor(DonationTier tier) {
    try {
      return _products.firstWhere((p) => p.id == tier.productId);
    } catch (_) {
      return null;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _thanked ? _buildThankYou(context) : _buildMain(context),
    );
  }

  Widget _buildMain(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cupola is free. If it saves you time, a tip helps keep it updated.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Tiers / loading / error ──────────────────────────────────────
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_errorMessage != null && _products.isEmpty)
          _buildError(context)
        else
          _buildTierList(context),
      ],
    );
  }

  Widget _buildTierList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tier in DonationTier.all) ...[
          _buildTierTile(context, tier),
          if (tier != DonationTier.all.last)
            Divider(height: 1, color: colorScheme.outlineVariant),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInlineError(context),
        ],
      ],
    );
  }

  Widget _buildTierTile(BuildContext context, DonationTier tier) {
    final product = _productFor(tier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Product not returned by the App Store (not yet configured in
    // App Store Connect). Show a disabled placeholder.
    if (product == null) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        title: Text(
          tier.label,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(tier.description),
        trailing: Text(
          '—',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        enabled: false,
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      title: Text(tier.label, style: textTheme.bodyMedium),
      subtitle: Text(
        tier.description,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: _purchasing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              product.price,
              style: textTheme.bodyMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
      onTap: _purchasing ? null : () => _startPurchase(product),
    );
  }

  // Both messages come from the purchase stream: the store answered and the
  // purchase did not go through. That is a fault, not an unreachable store:
  // an unreachable store never gets this far, the sheet falls back to Ko-fi.
  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: FaultNote.fault(
          message: _errorMessage!,
          surface: _sheetSurface(context),
        ),
      ),
    );
  }

  Widget _buildInlineError(BuildContext context) {
    return FaultNote.fault(
      message: _errorMessage!,
      surface: _sheetSurface(context),
    );
  }

  // `AppBottomSheet` paints `surfaceContainer` in both themes.
  Color _sheetSurface(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainer;

  Widget _buildThankYou(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      key: const ValueKey('thanks'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            size: 48,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Thank you',
            style: textTheme.titleLarge!.weight(FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your support means a lot and helps keep Cupola alive.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
