import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

import 'api.dart';
import 'post.dart';
import 'queries.dart';

/// UI bits shared across pattern demos. They talk only to `swrly` (server
/// state), never to any state management library — so patterns differ only
/// in how *client* state (search text, etc.) is threaded to them.

class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, required this.onTap});
  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(child: Text('${post.id}')),
      title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(post.body, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Opens the shared post-detail modal. Uses `postQuery(id)` — the second
/// tap on the same post within its `staleTime` is instant (no network).
void showPostDetail(BuildContext context, int id) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _PostDetailSheet(id: id),
  );
}

class _PostDetailSheet extends StatelessWidget {
  const _PostDetailSheet({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: QueryBuilder.of(
          postQuery(id),
          builder: (context, state, refetch) {
            if (state.isLoading && !state.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.isError && !state.hasData) {
              return Center(child: Text('${state.error}'));
            }
            final p = state.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(child: Text('${p.id}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Post #${p.id}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(p.title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(p.body),
                const Spacer(),
                Text(
                  'Re-open within staleTime → served from cache (dio counter stays put).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// FAB that runs a create mutation with optimistic insert + auto rollback.
/// Same code across every pattern — mutations are pure swrly.
class CreatePostFab extends StatelessWidget {
  const CreatePostFab({super.key});

  @override
  Widget build(BuildContext context) {
    return MutationBuilder<Post, String>(
      mutationFn: (title) => Api.instance.createPost(title),
      onMutate: (title) {
        final prev =
            QueryClient.instance.getQueryData<List<Post>>(['posts']) ??
                const <Post>[];
        final draft = Post(id: -1, title: title, body: 'saving…');
        QueryClient.instance
            .setQueryData<List<Post>>(['posts'], [draft, ...prev]);
        return () => QueryClient.instance
            .setQueryData<List<Post>>(['posts'], prev); // auto rollback
      },
      onSuccess: (post, _) {
        final cur = QueryClient.instance.getQueryData<List<Post>>(['posts']) ??
            const <Post>[];
        QueryClient.instance.setQueryData<List<Post>>(
          ['posts'],
          [post, ...cur.where((p) => p.id != -1)],
        );
      },
      builder: (context, mutate, state) => FloatingActionButton.extended(
        icon: state.isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add),
        label: const Text('New post'),
        onPressed: state.isLoading
            ? null
            : () async {
                final title = await _promptTitle(context);
                if (title != null && title.isNotEmpty) mutate(title);
              },
      ),
    );
  }
}

Future<String?> _promptTitle(BuildContext context) async {
  final controller = TextEditingController(text: 'A new post');
  final result = await showDialog<String>(
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
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Helper: filter the current posts list by a search query. Kept out of
/// individual patterns so the client-state code shrinks to the essentials.
List<Post> filterPosts(List<Post> posts, String query) {
  if (query.isEmpty) return posts;
  final q = query.toLowerCase();
  return posts.where((p) =>
      p.title.toLowerCase().contains(q) || p.body.toLowerCase().contains(q))
      .toList();
}
