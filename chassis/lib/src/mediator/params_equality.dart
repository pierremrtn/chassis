/// Internal helpers backing the structural equality of messages
/// (see `Command.==` / `Query.==`). Not exported.
library;

/// Shallow map equality: same keys, values compared with `==`.
bool paramsEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

/// Order-insensitive hash of the map's entries, so two messages built with
/// the same params hash identically regardless of map insertion order.
int paramsHash(Map<String, Object?> params) {
  var hash = 0;
  for (final entry in params.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
