/// Loads a JSON fixture from `test/fixtures/<path>`.
///
/// `flutter test` runs with the package root as the working directory, so the
/// relative path resolves regardless of which test file loads it. Fixtures are
/// the recorded shape of a service response, built from the official API docs
/// and replaceable with a live capture, used to keep model parsing honest. The
/// loader is the demo world's own, so tests and the world read them one way.
library;

export 'package:cupola/demo/world/fixtures.dart'
    show jsonFixture, jsonFixtureList, jsonFixtureMap;
