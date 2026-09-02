import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:swrly/swrly.dart';

import '../shared/network_pill.dart';
import '../shared/queries.dart';
import '../shared/widgets.dart';
import 'search_notifier.dart';

/// Pattern: **Provider** × swrly.
///
/// - `SearchNotifier` (ChangeNotifier) owns the search text — that's
///   client state.
/// - `swrly` owns the posts list, the post detail, and the create mutation
///   — that's server state.
///
/// The `ChangeNotifier` intentionally has no `posts` field, no
/// `isLoading` bool, no error. Trying to mirror the server into a notifier
/// is exactly the antipattern that leads to stale/duplicated state.
class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchNotifier(),
      child: const _PostsScreenBody(),
    );
  }
}

class _PostsScreenBody extends StatelessWidget {
  const _PostsScreenBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider + swrly'),
        actions: const [NetworkPill()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts (client state via ChangeNotifier)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => context.read<SearchNotifier>().setQuery(v),
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
          // Consumer here — only this subtree rebuilds when the search
          // changes; the outer QueryBuilder doesn't refire the request.
          return Consumer<SearchNotifier>(
            builder: (_, search, __) {
              final filtered = filterPosts(posts, search.query);
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
            },
          );
        },
      ),
      floatingActionButton: const CreatePostFab(),
    );
  }
}
