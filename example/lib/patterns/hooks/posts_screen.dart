import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

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
      body: _body(context, state, query.value),
      floatingActionButton: const _HookCreateFab(),
    );
  }

  Widget _body(BuildContext context, dynamic state, String q) {
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

/// Demonstrates the mutation hook side. Same optimistic pattern as
/// `CreatePostFab` but expressed via the hook indirection.
class _HookCreateFab extends HookWidget {
  const _HookCreateFab();

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: 'A new post');
    final mut = useSwrlyMutation<Post, String>(Api.instance.createPost);

    return FloatingActionButton.extended(
      icon: mut.state.isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.add),
      label: const Text('New post'),
      onPressed: mut.state.isLoading
          ? null
          : () async {
              final title = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('New post'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (title != null && title.isNotEmpty) {
                await mut.mutate(title);
                // Refetch on success — mirrors `onSettled` in MutationBuilder.
                postsQuery.invalidate();
              }
            },
    );
  }
}
