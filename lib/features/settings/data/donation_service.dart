import 'dart:io';

import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
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
  // ever live in App Store Connect, they're now orphaned there (harmless),
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

  static InAppPurchasePlatform? _store;

  /// The App Store, registered on first use. Only StoreKit is a dependency
  /// (see `pubspec.yaml`), so this is reached on iOS alone, behind [usesIAP].
  static InAppPurchasePlatform get _appStore {
    if (_store == null) {
      InAppPurchaseStoreKitPlatform.registerPlatform();
      _store = InAppPurchasePlatform.instance;
    }
    return _store!;
  }

  /// Purchase updates from the App Store.
  static Stream<List<PurchaseDetails>> get purchaseStream =>
      _appStore.purchaseStream;

  /// How long the sheet waits for the store before it falls back to Ko-fi. A
  /// sideloaded build talks to a store that knows nothing of it, and a silent
  /// one must not leave the sheet spinning.
  static const Duration storeTimeout = Duration(seconds: 8);

  /// Queries the App Store for the configured products.
  /// Throws if the store is unavailable or does not answer in [storeTimeout].
  static Future<ProductDetailsResponse> fetchProducts() async {
    final available = await _appStore.isAvailable().timeout(storeTimeout);
    if (!available) {
      throw Exception('App Store is not available on this device.');
    }
    return _appStore.queryProductDetails(productIds).timeout(storeTimeout);
  }

  /// Initiates a consumable purchase for the given [product].
  static Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _appStore.buyConsumable(purchaseParam: param);
  }

  /// Marks a completed purchase as delivered so the App Store does not retry.
  static Future<void> complete(PurchaseDetails purchase) async {
    await _appStore.completePurchase(purchase);
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
