import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

/// Centralised constants and helpers for the donation flow.
///
/// Platform routing:
/// - iOS   → In-App Purchase (required by App Store guideline 3.1.1)
/// - Other → Ko-fi external URL (permitted on Android by Google Play policy;
///           no restrictions on macOS direct distribution)
class DonationService {
  DonationService._();

  // ── External donation URL ─────────────────────────────────────────────────

  static final Uri kofiUri = Uri.parse('https://ko-fi.com/matthwlabs');

  // ── In-App Purchase product IDs (must match App Store Connect exactly) ────
  //
  // Bundle ID: com.matthwlabs.cupola
  // Product type: Consumable (allows repeated purchases)
  //
  // Moved from the pre-rebrand com.matthw.1.seekarr.tip.* ids. If those were
  // ever live in App Store Connect, they're now orphaned there — harmless,
  // but the equivalent com.matthwlabs.cupola.tip.* products need creating
  // fresh in App Store Connect before a real purchase can succeed.

  static const String tipSmallId = 'com.matthwlabs.cupola.tip.small';
  static const String tipMediumId = 'com.matthwlabs.cupola.tip.medium';
  static const String tipLargeId = 'com.matthwlabs.cupola.tip.large';

  static const Set<String> productIds = {tipSmallId, tipMediumId, tipLargeId};

  // ── Platform helpers ──────────────────────────────────────────────────────

  /// Whether this platform requires IAP instead of an external URL.
  static bool get usesIAP => Platform.isIOS;

  // ── URL launch helper ─────────────────────────────────────────────────────

  /// Opens the Ko-fi page in the default browser.
  /// Returns `true` on success, `false` if the URL could not be launched.
  static Future<bool> launchKofi() async {
    return launchUrl(kofiUri, mode: LaunchMode.externalApplication);
  }

  // ── IAP helpers ───────────────────────────────────────────────────────────

  /// Queries the App Store for the configured products.
  /// Throws if the store is unavailable.
  static Future<ProductDetailsResponse> fetchProducts() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      throw Exception('App Store is not available on this device.');
    }
    return InAppPurchase.instance.queryProductDetails(productIds);
  }

  /// Initiates a consumable purchase for the given [product].
  static Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await InAppPurchase.instance.buyConsumable(purchaseParam: param);
  }

  /// Marks a completed purchase as delivered so the App Store does not retry.
  static Future<void> complete(PurchaseDetails purchase) async {
    await InAppPurchase.instance.completePurchase(purchase);
  }
}

/// Human-readable metadata for a single donation tier shown in the UI.
class DonationTier {
  const DonationTier({
    required this.productId,
    required this.label,
    required this.description,
  });

  final String productId;
  final String label;
  final String description;

  static const List<DonationTier> all = [
    DonationTier(
      productId: DonationService.tipSmallId,
      label: 'One coffee',
      description: 'A small thank-you',
    ),
    DonationTier(
      productId: DonationService.tipMediumId,
      label: 'A few coffees',
      description: 'Keeps the lights on',
    ),
    DonationTier(
      productId: DonationService.tipLargeId,
      label: 'Big round',
      description: 'You\'re amazing',
    ),
  ];
}
