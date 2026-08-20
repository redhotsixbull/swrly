import 'package:flutter/foundation.dart';

typedef QueryKey = List<Object?>;

@immutable
class QueryKeyHash {
  const QueryKeyHash(this.value);
  final String value;

  static QueryKeyHash of(QueryKey key) => QueryKeyHash(_serialize(key));

  @override
  bool operator ==(Object other) =>
      other is QueryKeyHash && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

String _serialize(Object? node) {
  if (node == null) return 'null';
  if (node is String) return '"$node"';
  if (node is num || node is bool) return node.toString();
  if (node is List) {
    final parts = node.map(_serialize).join(',');
    return '[$parts]';
  }
  if (node is Map) {
    final keys = node.keys.toList()
      ..sort((a, b) => a.toString().compareTo(b.toString()));
    final parts = keys.map((k) => '${_serialize(k)}:${_serialize(node[k])}').join(',');
    return '{$parts}';
  }
  return node.toString();
}

bool queryKeyStartsWith(QueryKey key, QueryKey prefix) {
  if (prefix.length > key.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (_serialize(key[i]) != _serialize(prefix[i])) return false;
  }
  return true;
}
