import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'post.dart';

/// Minimal API surface shared across the pattern demos.
///
/// The full-featured demo (`example/lib/main.dart`) has retry toggles,
/// failure injection, etc. The per-pattern demos want a tiny counter you
/// can watch in the AppBar so cache hits are visible, and nothing else.
class Api {
  Api._();
  static final Api instance = Api._();

  final _dio = Dio(BaseOptions(
    baseUrl: 'https://jsonplaceholder.typicode.com',
    connectTimeout: const Duration(seconds: 10),
  ));

  /// Bumps on every real HTTP call. A `QueryBuilder` cache hit does NOT
  /// touch this — that's the whole point of the demo.
  final ValueNotifier<int> calls = ValueNotifier<int>(0);

  Future<T> _bump<T>(Future<T> Function() run) async {
    // Defer the notifier write past the current build.
    await Future<void>.microtask(() {});
    calls.value += 1;
    return run();
  }

  Future<List<Post>> fetchPosts() => _bump(() async {
        final r = await _dio.get<List<dynamic>>('/posts', queryParameters: {
          '_limit': 20,
        });
        return r.data!
            .cast<Map<String, dynamic>>()
            .map(Post.fromJson)
            .toList();
      });

  Future<Post> fetchPost(int id) => _bump(() async {
        final r = await _dio.get<Map<String, dynamic>>('/posts/$id');
        return Post.fromJson(r.data!);
      });

  Future<Post> createPost(String title) => _bump(() async {
        final r = await _dio.post<Map<String, dynamic>>('/posts',
            data: {'title': title, 'body': 'created from pattern demo'});
        return Post(
          id: (r.data?['id'] as int?) ?? 101,
          title: title,
          body: 'created from pattern demo',
        );
      });
}
