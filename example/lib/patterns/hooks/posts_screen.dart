import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:swrly/swrly.dart';

import '../shared/api.dart';
import '../shared/network_pill.dart';
import '../shared/post.dart';
import '../shared/queries.dart';
import '../shared/widgets.dart';
import 'use_swrly.dart';

/// Pattern: **flutter_hooks** × swrly.
///
/// - Search filter (client state): `useState<String>('')`.
/// - Posts list (server state): `useSwrlyQuery(postsQuery)` — canonical
///   snippet from `use_swrly.dart`. **NOT shipped by the `swrly` package**;
///   see `doc/CONVENTIONS.md §10`.
class PostsScreen extends HookWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final query = useState<String>('');
    final state = useSwrlyQuery(postsQuery);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hooks + swrly'),
        actions: const [NetworkPill()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts (client state via useState)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => query.value = v,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _list(context, state, query.value)),
          const _HookCreateRow(),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, QueryState<List<Post>> state, String q) {
    if (state.isLoading && !state.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isError && !state.hasData) {
      return Center(child: Text('${state.error}'));
    }
    final filtered = filterPosts(state.data ?? const <Post>[], q);
    return RefreshIndicator(
      onRefresh: () => postsQuery.refetch().then((_) {}),
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => PostTile(
          post: filtered[i],
          onTap: () => showPostDetail(context, filtered[i].id),
        ),
      ),
    );
  }
}

/// Same shape as `CreatePostRow` in the shared widgets — inline, no dialog —
/// but written with the hook-flavored surface so the pattern demonstrates
/// `useSwrlyMutation` alongside `useSwrlyQuery`.
class _HookCreateRow extends HookWidget {
  const _HookCreateRow();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: 'A new post');
    final mut = useSwrlyMutation<Post, String>(Api.instance.createPost);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'New post title',
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: mut.state.isLoading
                ? null
                : () async {
                    final title = controller.text.trim();
                    if (title.isEmpty) return;
                    await mut.mutate(title);
                    // `useSwrlyQuery` registers as a real subscriber, so
                    // invalidate() correctly triggers a refetch through the
                    // hook's stream listener. Use MutationBuilder for full
                    // optimistic + rollback semantics.
                    postsQuery.invalidate();
                  },
            child: mut.state.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}
