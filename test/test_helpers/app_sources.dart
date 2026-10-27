/// Whether [path] is the demo world (`lib/demo/world/`), which stands in for
/// the servers: its strings, sizes, episode codes, addresses and cookies are
/// what a Radarr or a Seerr answers, not what Cupola says or does. A guard
/// that reads the app's own code under `lib/` skips it.
bool isServerStandIn(String path) => path.startsWith('lib/demo/world/');
