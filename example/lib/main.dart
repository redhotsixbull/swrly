import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swrly example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const PostsPage(),
    );
  }
}

// -- Fake API ----------------------------------------------------------------

class Post {
  Post({required this.id, required this.title, required this.body});
  final int id;
  final String title;
  final String body;
}

final _rng = Random();
int _nextId = 4;

Future<List<Post>> fetchPosts() async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (_rng.nextInt(6) == 0) {
    throw Exception('Random network failure — hit refetch to retry');
  }
  return [
    Post(id: 1, title: 'swrly is real', body: 'Server state ≠ client state.'),
    Post(id: 2, title: 'Cache invalidation', body: 'Prefix-based is enough for v0.1.'),
    Post(id: 3, title: 'Refetch on resume', body: 'Handled via WidgetsBindingObserver.'),
  ];
}

Future<Post> createPost(String title) async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
  return Post(id: _nextId++, title: title, body: 'Just created.');
}

// -- UI ----------------------------------------------------------------------

class PostsPage extends StatelessWidget {
  const PostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('swrly'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear cache',
            onPressed: () {
              QueryClient.instance.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: QueryBuilder<List<Post>>(
              queryKey: const ['posts'],
              queryFn: fetchPosts,
              staleTime: const Duration(seconds: 30),
              builder: (context, state, refetch) {
                if (state.isLoading && !state.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.isError && !state.hasData) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 8),
                        Text('${state.error}'),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: refetch,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final posts = state.data ?? const <Post>[];
                return RefreshIndicator(
                  onRefresh: refetch,
                  child: Stack(
                    children: [
                      ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: posts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => ListTile(
                          leading: CircleAvatar(child: Text('${posts[i].id}')),
                          title: Text(posts[i].title),
                          subtitle: Text(posts[i].body),
                        ),
                      ),
                      if (state.isFetching)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          const _CreatePostForm(),
        ],
      ),
    );
  }
}

class _CreatePostForm extends StatefulWidget {
  const _CreatePostForm();

  @override
  State<_CreatePostForm> createState() => _CreatePostFormState();
}

class _CreatePostFormState extends State<_CreatePostForm> {
  final _controller = TextEditingController(text: 'A new post');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: MutationBuilder<Post, String>(
        mutationFn: createPost,
        onSuccess: (post, _) {
          QueryClient.instance.invalidateQueries(const ['posts']);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Created post #${post.id}')),
          );
        },
        builder: (context, mutate, state) => Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'New post title',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: state.isLoading
                  ? null
                  : () => mutate(_controller.text),
              child: state.isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
