Map<String, dynamic> stringKeyMap(Map<dynamic, dynamic> value) {
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, dynamic>? mapOrNull(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return stringKeyMap(value);
  return null;
}

/// Maps a decoded JSON array into models, skipping anything that is not an
/// object.
///
/// `jsonDecode` hands back `List<dynamic>`, and a single malformed element must
/// not take the whole page down: a browse that degrades to `[]` is the
/// convention, but a browse that drops one row and renders the other 49 is
/// better still. A non-list [raw] (null, an error envelope, an unwrapped map)
/// yields `const []`.
///
/// Top-level and pure, so it is safe to call from inside an `Isolate.run`
/// closure.
List<T> jsonObjects<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! List) return const [];
  return raw
      .map(mapOrNull)
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList(growable: false);
}

String? stringOrNull(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? doubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}

/// Reads a flag that APIs express as a bool, `"true"`/`"false"` or `"1"`/`"0"`,
/// defaulting to false for everything else.
///
/// Deliberately *not* `parse_utils.parseBool`: that one treats any non-zero
/// number as true, which is right for qBittorrent's integer flags and wrong for
/// the JSON-RPC payloads that reach here, where a stray `2` means "not the
/// value I know about" rather than "yes".
bool boolOrFalse(dynamic value) {
  if (value is bool) return value;
  final s = '$value'.toLowerCase();
  return s == 'true' || s == '1';
}

double? queueProgress(
  Map<dynamic, dynamic> item, {
  bool parseStrings = true,
  bool includeSizeLeftAlias = true,
}) {
  final rawSizeLeft =
      item['sizeleft'] ?? (includeSizeLeftAlias ? item['sizeLeft'] : null);
  final size = parseStrings
      ? doubleOrNull(item['size'])
      : (item['size'] as num?)?.toDouble();
  final sizeLeft = parseStrings
      ? doubleOrNull(rawSizeLeft)
      : (rawSizeLeft as num?)?.toDouble();
  if (size == null || size <= 0 || sizeLeft == null) return null;
  return ((size - sizeLeft) / size).clamp(0.0, 1.0).toDouble();
}
