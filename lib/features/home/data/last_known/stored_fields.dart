/// How a codec reads a stored record: field by field, strictly.
///
/// A last drawing is read from a file the app wrote a while ago, perhaps in
/// another version. A record is either read whole or not at all: a field that
/// is there with the wrong type, a required one that is missing, an instant
/// that does not parse, a name the enum no longer has, marks the whole record
/// [isBroken], and the codec answers null for it, never half an object.
library;

import 'package:cupola/features/settings/domain/service_key.dart';

final class StoredFields {
  /// The fields of [json], or a record that is broken from the start when
  /// [json] is not a map at all.
  StoredFields(Object? json)
    : _json = json is Map ? json : const {},
      _broken = json is! Map;

  final Map<Object?, Object?> _json;
  final List<StoredFields> _records = [];
  bool _broken;

  /// Whether anything read so far, in this record or in one nested in it,
  /// could not be read whole.
  bool get isBroken => _broken || _records.any((record) => record.isBroken);

  /// The text at [key]; null when absent. With [required], an absent or empty
  /// one breaks the record.
  String? text(String key, {bool required = false}) {
    final value = _typed<String>(key);
    if (required && (value == null || value.isEmpty)) _broken = true;
    return value;
  }

  /// The whole number at [key]; null when absent.
  int? whole(String key, {bool required = false}) {
    final value = _typed<int>(key);
    if (required && value == null) _broken = true;
    return value;
  }

  /// The flag at [key]; null when absent.
  bool? flag(String key, {bool required = false}) {
    final value = _typed<bool>(key);
    if (required && value == null) _broken = true;
    return value;
  }

  /// The instant at [key] (an ISO string), on the device's clock; null when
  /// absent.
  DateTime? instant(String key, {bool required = false}) {
    final raw = _typed<String>(key);
    if (raw == null) {
      if (required) _broken = true;
      return null;
    }
    final at = DateTime.tryParse(raw);
    if (at == null) _broken = true;
    return at?.toLocal();
  }

  /// The member of [values] named at [key]; a name nobody knows breaks the
  /// record.
  E? named<E extends Enum>(
    Iterable<E> values,
    String key, {
    bool required = false,
  }) {
    final name = _typed<String>(key);
    if (name == null) {
      if (required) _broken = true;
      return null;
    }
    final value = values.where((each) => each.name == name).firstOrNull;
    if (value == null) _broken = true;
    return value;
  }

  /// The service named at [key].
  ServiceKey? service(String key, {bool required = false}) =>
      named(ServiceKey.values, key, required: required);

  /// The record at [key], read with its own [StoredFields]; null when
  /// absent. A record that cannot be read whole breaks this one.
  StoredFields? record(String key) {
    final value = _json[key];
    if (value == null) return null;
    return StoredFields(value).._attachTo(this);
  }

  void _attachTo(StoredFields parent) => parent._records.add(this);

  /// The list at [key]; null when absent. A list that is not a list breaks
  /// the record.
  List<Object?>? list(String key, {bool required = false}) {
    final value = _typed<List<Object?>>(key);
    if (required && value == null) _broken = true;
    return value;
  }

  /// What is at [key], for a nested value another codec reads whole.
  Object? raw(String key) => _json[key];

  T? _typed<T>(String key) {
    final value = _json[key];
    if (value is T) return value;
    if (value != null) _broken = true;
    return null;
  }
}
