import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swrly/swrly.dart';

import '../shared/network_pill.dart';
import '../shared/queries.dart';
import '../shared/widgets.dart';
import 'search_provider.dart';

/// Pattern: **Riverpod** × swrly.
///
/// - Riverpod owns the search filter (client state) via `StateProvider`.
/// - `swrly` owns the posts list, detail, and create mutation.
///
/// Notice what's NOT here: no `FutureProvider.family` for the posts list,
/// no `AsyncNotifier` re-implementing staleTime. `swrly` gives you those
/// out of the box, so Riverpod can go back to what it's best at:
/// client-state composition and DI.
///
/// Wire order (this screen is pushed inside its own `ProviderScope` from
/// `patterns_home.dart`).
class PostsScreen extends ConsumerWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riverpod + swrly'),
        actions: const [NetworkPill()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts (client state via StateProvider)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  ref.read(searchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: QueryBuilder.of(
        postsQuery,
        builder: (context, state, refetch) {
          if (state.isLoading && !state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.isError && !state.hasData) {
            return Center(child: Text('${state.error}'));
          }
          final posts = state.data ?? const [];
          // Consumer for the search — only this subtree rebuilds on typing.
          return Consumer(builder: (context, ref, _) {
            final query = ref.watch(searchProvider);
            final filtered = filterPosts(posts, query);
            return RefreshIndicator(
              onRefresh: refetch,
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => PostTile(
                  post: filtered[i],
                  onTap: () => showPostDetail(context, filtered[i].id),
                ),
              ),
            );
          });
        },
      ),
      floatingActionButton: const CreatePostFab(),
    );
  }
}
