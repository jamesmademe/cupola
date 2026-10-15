import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/onboarding/presentation/requester_sign_in_screen.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';

/// What the Home stands in as, so a test can tell the way in has left for it.
const onboardingHomeStandIn = Key('onboarding-home-stand-in');

/// The way in, mounted as the app mounts it: the Welcome at `/welcome`,
/// Connect at `/welcome/connect`, the sign-in with an account at
/// `/welcome/sign-in`, and a stand-in for the Home to leave for.
///
/// The screen asks the router whether it can pop (to show a Back on the
/// Welcome), and leaves for the Home with `go`, so neither can run without
/// one. The real router's own redirects are tested in `router_test.dart`; this
/// one has none, which is what lets a case start anywhere.
///
/// [initialLocation] `/home` and then `router.push('/welcome')` is a Welcome
/// opened from inside the app ("Revisit onboarding"), with a page to go back
/// to.
GoRouter onboardingRouter({
  String initialLocation = ServiceRoutes.welcome,
  CertificateProber certificateProber = neverFindsACertificate,
  LocalNetworkProbe localNetworkProbe = nothingGatesTheNetwork,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: ServiceRoutes.welcome,
      builder: (_, _) => OnboardingScreen(
        certificateProber: certificateProber,
        localNetworkProbe: localNetworkProbe,
      ),
      routes: [
        GoRoute(
          path: 'connect',
          builder: (_, _) => OnboardingScreen(
            entry: OnboardingEntry.connect,
            certificateProber: certificateProber,
            localNetworkProbe: localNetworkProbe,
          ),
        ),
        GoRoute(
          path: 'sign-in',
          builder: (_, _) =>
              RequesterSignInScreen(certificateProber: certificateProber),
        ),
      ],
    ),
    GoRoute(
      path: ServiceRoutes.home,
      builder: (_, _) => const Scaffold(
        body: Center(child: Text('Home', key: onboardingHomeStandIn)),
      ),
    ),
  ],
);

/// The default certificate prober for the way in's tests.
///
/// The real one opens a live `SecureSocket` for any probe-worthy failure, and
/// nothing here points at a real TLS host, so a `.lan` or scheme-less address
/// that fails at the fake client would otherwise reach a socket
/// `flutter_test` cannot intercept and hang on a pending timer. None of these
/// tests exercise the trust flow itself, so "no certificate found" is the
/// correct fake, not only a convenient one.
Future<UntrustedCertificateProbe?> neverFindsACertificate(
  String rawUrl, {
  String pinnedFingerprint = '',
}) async => null;

/// Stands in for the host OS. A widget test must not depend on whether the
/// machine running it gates the local network, and the real probe would spend
/// a whole deadline of simulated time waiting on a channel with nothing
/// listening.
Future<LocalNetworkAccess> nothingGatesTheNetwork(
  String rawUrl, {
  Duration timeout = Duration.zero,
}) async => LocalNetworkAccess.unrestricted;
