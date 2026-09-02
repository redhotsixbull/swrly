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

/// Inline "create post" row — same shape as the main demo's `_CreatePostForm`.
///
/// Deliberately NOT a FAB-with-dialog: opening a dialog and running the
/// mutation after the dialog closes creates a widget-tree teardown race
/// (Flutter asserts `_dependents.isEmpty` in `framework.dart` at unmount).
/// Keeping the input inline sidesteps that entirely and matches the
/// proven pattern in `main.dart`.
class CreatePostRow extends StatefulWidget {
  const CreatePostRow({super.key});

  @override
  State<CreatePostRow> createState() => _CreatePostRowState();
}

class _CreatePostRowState extends State<CreatePostRow> {
  final _controller = TextEditingController(text: 'A new post');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: MutationBuilder<Post, String>(
        mutationFn: (title) => Api.instance.createPost(title),
        onMutate: (title) {
          final prev = QueryClient.instance
                  .getQueryData<List<Post>>(const ['posts']) ??
              const <Post>[];
          final draft = Post(id: -1, title: title, body: 'saving…');
          QueryClient.instance
              .setQueryData<List<Post>>(const ['posts'], [draft, ...prev]);
          return () => QueryClient.instance
              .setQueryData<List<Post>>(const ['posts'], prev); // auto rollback
        },
        onSuccess: (post, _) {
          final cur = QueryClient.instance
                  .getQueryData<List<Post>>(const ['posts']) ??
              const <Post>[];
          QueryClient.instance.setQueryData<List<Post>>(
            const ['posts'],
            [post, ...cur.where((p) => p.id != -1)],
          );
        },
        builder: (context, mutate, state) => Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'New post title',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  state.isLoading ? null : () => mutate(_controller.text),
              child: state.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper: filter the current posts list by a search query. Kept out of
/// individual patterns so the client-state code shrinks to the essentials.
List<Post> filterPosts(List<Post> posts, String query) {
  if (query.isEmpty) return posts;
  final q = query.toLowerCase();
  return posts
      .where((p) =>
          p.title.toLowerCase().contains(q) ||
          p.body.toLowerCase().contains(q))
      .toList();
}
