import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

import '../shared/network_pill.dart';
import '../shared/queries.dart';
import '../shared/widgets.dart';

/// Pattern: **Plain StatefulWidget** — `setState` for client state,
/// `swrly` for server state.
///
/// - Client state (`_query`): search text held in a `String` field, mutated
///   via `setState` in `onChanged`. That's the whole ceremony.
/// - Server state (posts list, post detail, create): all `swrly` —
///   `QueryBuilder.of(postsQuery)` / `QueryBuilder.of(postQuery(id))` /
///   `MutationBuilder` in `CreatePostFab`.
///
/// The key idea: `setState` is fine for local UI state that this screen owns.
/// It is not fine for the posts list — that's shared, cached, invalidatable
/// data → server state → swrly.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plain + swrly'),
        actions: const [NetworkPill()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts (client state via setState)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
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
          final filtered = filterPosts(state.data ?? const [], _query);
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
      ),
      floatingActionButton: const CreatePostFab(),
    );
  }
}
