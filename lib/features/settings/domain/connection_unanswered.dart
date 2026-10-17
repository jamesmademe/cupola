import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// A request to a connection that has an address away, made after the route
/// probe knocked at both of its addresses and neither answered: unanswered at
/// the address in use too.
///
/// The error of such a request on every client built through `guardedDio`
/// (`UnansweredMark`, from the snapshot `UnansweredAddresses` keeps), and the
/// verdict of a readout of the connection (`diagnoseSavedInstance`).
/// Recognised through its [reason], [ServiceFailureReason.unreachableAtBoth]:
/// red, `Did not answer`, `Radarr did not answer at home or away`, and the
/// two addresses under it ([failureDetail]).
///
/// [toString] is a marker for logs and tests, never drawn.
class ConnectionUnanswered
    implements Exception, HasFailureReason, HasFailureDetail {
  const ConnectionUnanswered({required this.home, required this.away});

  /// The connection's address at home, as a row shows it
  /// (`ServiceKey.extractHost`): `nas.home.arpa:7878`.
  final String home;

  /// Its address away from home, the same way: `radarr.example.net`.
  final String away;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.unreachableAtBoth;

  /// Where nothing answered, one address a line, each with where it is:
  /// `At home · nas.home.arpa:7878` and `Away · radarr.example.net`.
  @override
  String get failureDetail => unansweredAddressLines(home: home, away: away);

  @override
  String toString() => 'Connection unanswered at home or away';
}

/// The two addresses nothing answered at, one a line, as the red names them:
/// `At home · nas.home.arpa:7878` and `Away · radarr.example.net`.
String unansweredAddressLines({required String home, required String away}) =>
    'At home\u00A0· ${UrlUtils.hostInProse(home)}\n'
    'Away\u00A0· ${UrlUtils.hostInProse(away)}';
