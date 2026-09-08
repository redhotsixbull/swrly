import 'package:flutter/foundation.dart';

/// Pure **client state** — the current search filter. Deliberately holds
/// nothing about posts (that's server state → `swrly`).
class SearchNotifier extends ChangeNotifier {
  String _query = '';
  String get query => _query;

  void setQuery(String v) {
    if (v == _query) return;
    _query = v;
    notifyListeners();
  }
}
