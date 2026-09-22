import 'dart:collection';

/// A cache entry holding a [value] and an [expiresAt] timestamp.
class CacheEntry<V> {
  final V value;
  final DateTime expiresAt;

  CacheEntry(this.value, Duration ttl)
      : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Generic in-memory LRU-like cache with per-entry Time-To-Live (TTL) and maximum entry capacity.
class CacheManager<K, V> {
  final int maxSize;
  final Duration defaultTtl;
  final LinkedHashMap<K, CacheEntry<V>> _cache =
      LinkedHashMap<K, CacheEntry<V>>();

  CacheManager({
    this.maxSize = 100,
    this.defaultTtl = const Duration(minutes: 5),
  });

  /// The current number of unexpired entries in the cache.
  int get length {
    _pruneExpired();
    return _cache.length;
  }

  /// Whether the cache contains an unexpired value for [key].
  bool containsKey(K key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// Retrieves the value for [key], or null if missing or expired.
  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    // Re-insert to mark as recently accessed
    _cache.remove(key);
    _cache[key] = entry;
    return entry.value;
  }

  /// Puts [value] into the cache for [key] with an optional custom [ttl].
  void put(K key, V value, [Duration? ttl]) {
    _pruneExpired();
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = CacheEntry(value, ttl ?? defaultTtl);
  }

  /// Retrieves the value for [key], or computes it via [ifAbsent] and caches the result.
  Future<V> getOrCompute(
    K key,
    Future<V> Function() ifAbsent, {
    Duration? ttl,
  }) async {
    final cached = get(key);
    if (cached != null) return cached;

    final computed = await ifAbsent();
    put(key, computed, ttl);
    return computed;
  }

  /// Removes an entry from the cache.
  V? remove(K key) => _cache.remove(key)?.value;

  /// Clears all entries from the cache.
  void clear() => _cache.clear();

  void _pruneExpired() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }
}
