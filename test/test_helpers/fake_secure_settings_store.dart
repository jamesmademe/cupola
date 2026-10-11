import 'package:flutter/services.dart' show PlatformException;
import 'package:cupola/features/settings/data/settings_service.dart';

class FakeSecureSettingsStore implements SecureSettingsStore {
  final Map<String, String> _storage = {};

  /// When non-null, every [write] and [delete] throws this message wrapped in
  /// an [Exception]. Used to simulate Keychain / secure-storage failures in
  /// widget tests that need to exercise the error UI path.
  String? failureMessage;

  /// Everything stored, for a test that asks what is in the store rather
  /// than what one key holds.
  Map<String, String> get entries => Map.unmodifiable(_storage);

  @override
  Future<void> delete({required String key}) async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage.clear();
  }

  /// Keys whose [read] throws, as a Keychain that will not hand one entry
  /// over does; [unreadableAll] makes every read throw.
  final Set<String> unreadable = {};
  bool unreadableAll = false;

  @override
  Future<String?> read({required String key}) async {
    if (unreadableAll || unreadable.contains(key)) {
      throw PlatformException(code: '-25308', message: 'Interaction refused.');
    }
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage[key] = value;
  }
}
