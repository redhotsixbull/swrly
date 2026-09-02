import 'package:swrly/swrly.dart';

import 'api.dart';
import 'post.dart';

/// Query definitions live in one place — see doc/CONVENTIONS.md §5.
/// Every pattern reuses these so the *only* thing that changes across
/// demos is how the surrounding client state is managed.

final postsQuery = Query<List<Post>>(
  key: const ['posts'],
  fn: () => Api.instance.fetchPosts(),
  staleTime: const Duration(seconds: 30),
);

final postQuery = QueryFamily<Post, int>(
  prefix: const ['post'],
  fn: (id) => Api.instance.fetchPost(id),
  staleTime: const Duration(minutes: 1),
);
