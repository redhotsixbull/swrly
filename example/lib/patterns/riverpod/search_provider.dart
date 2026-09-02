import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pure **client state** — the current search filter. Riverpod owns this.
///
/// Deliberately NOT a `FutureProvider<List<Post>>` — server state lives in
/// swrly (`postsQuery`), and the two systems coexist without either
/// wrapping the other.
final searchProvider = StateProvider<String>((ref) => '');
