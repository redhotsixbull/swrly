import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:swrly/swrly.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swrly example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

// ── Real HTTP via dio, instrumented so the cache is *visible* ────────────────
// swrly wraps these dio calls as query functions. `calls` only increments when
// a request actually goes to the network — a cache hit does NOT touch dio, so
// the counter stays put. Each request also logs its round-trip time; cache hits
// are instant (no log line at all).

final _dio = Dio(BaseOptions(
  baseUrl: 'https://jsonplaceholder.typicode.com',
  connectTimeout: const Duration(seconds: 10),
));

class Post {
  Post({required this.id, required this.title, required this.body});
  final int id;
  final String title;
  final String body;
  factory Post.fromJson(Map<String, dynamic> j) =>
      Post(id: j['id'] as int, title: j['title'] as String, body: j['body'] as String);
}

class Net {
  static final ValueNotifier<int> calls = ValueNotifier<int>(0);
  static final ValueNotifier<List<String>> log = ValueNotifier<List<String>>([]);

  /// When > 0, the next N `_timed` calls throw before hitting the network, to
  /// demo swrly's retry + backoff. Each failed attempt still counts as a
  /// request (so you can watch the counter tick up and the query recover).
  static final ValueNotifier<int> failNext = ValueNotifier<int>(0);

  static void note(String m) {
    final next = [...log.value, m];
    log.value = next.length > 10 ? next.sublist(next.length - 10) : next;
  }

  static Future<T> _timed<T>(String label, Future<T> Function() run) async {
    calls.value += 1;
    final id = calls.value;
    note('▶ #$id  $label …');
    final sw = Stopwatch()..start();
    try {
      if (failNext.value > 0) {
        failNext.value -= 1;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        throw Exception('simulated failure (retry demo)');
      }
      final r = await run();
      note('✓ #$id  $label  ${sw.elapsedMilliseconds}ms');
      return r;
    } catch (_) {
      note('✗ #$id  $label  failed → will retry');
      rethrow;
    }
  }

  static Future<List<Post>> fetchPosts() => _timed('GET /posts', () async {
        final r = await _dio.get<List<dynamic>>('/posts',
            queryParameters: {'_limit': 12});
        return r.data!
            .cast<Map<String, dynamic>>()
            .map(Post.fromJson)
            .toList();
      });

  static Future<Post> fetchPost(int id) => _timed('GET /posts/$id', () async {
        final r = await _dio.get<Map<String, dynamic>>('/posts/$id');
        return Post.fromJson(r.data!);
      });

  static Future<Post> createPost(String title) => _timed('POST /posts', () async {
        final r = await _dio.post<Map<String, dynamic>>('/posts',
            data: {'title': title, 'body': 'created via dio'});
        return Post(
            id: (r.data?['id'] as int?) ?? 101, title: title, body: 'created via dio');
      });
}

// ── UI ──────────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _staleSeconds = 30;

  @override
  Widget build(BuildContext context) {
    final stale = Duration(seconds: _staleSeconds);
    return Scaffold(
      appBar: AppBar(
        title: const Text('swrly + dio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear cache',
            onPressed: () {
              QueryClient.instance.clear();
              Net.note('🗑 cache cleared');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const _NetworkPanel(),
          const Divider(height: 1),
          _Controls(
            staleSeconds: _staleSeconds,
            onStale: (v) => setState(() => _staleSeconds = v),
            onInvalidate: () {
              Net.note('♻ invalidateQueries([posts])');
              QueryClient.instance.invalidateQueries(const ['posts']);
            },
            onFailNext: () {
              Net.failNext.value = 2;
              Net.note('💥 next 2 requests will fail → retry should recover');
              QueryClient.instance.invalidateQueries(const ['posts']);
            },
          ),
          const Divider(height: 1),
          Expanded(child: _PostsList(staleTime: stale)),
          const Divider(height: 1),
          _CreatePostForm(),
        ],
      ),
    );
  }
}

/// The metric + log that make the cache observable.
class _NetworkPanel extends StatelessWidget {
  const _NetworkPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              const Text('dio requests: ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ValueListenableBuilder<int>(
                valueListenable: Net.calls,
                builder: (_, n, __) => Text('$n',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: scheme.primary)),
              ),
              const Spacer(),
              const Text('cache hit = no request',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 88,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: Net.log,
              builder: (_, lines, __) => ListView(
                reverse: true,
                children: [
                  for (final l in lines.reversed)
                    Text(l,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.staleSeconds,
    required this.onStale,
    required this.onInvalidate,
    required this.onFailNext,
  });

  final int staleSeconds;
  final ValueChanged<int> onStale;
  final VoidCallback onInvalidate;
  final VoidCallback onFailNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Text('staleTime:'),
          const SizedBox(width: 8),
          SegmentedButton<int>(
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            segments: const [
              ButtonSegment(value: 0, label: Text('0s')),
              ButtonSegment(value: 30, label: Text('30s')),
            ],
            selected: {staleSeconds},
            onSelectionChanged: (s) => onStale(s.first),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Fail next'),
            onPressed: onFailNext,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('Invalidate'),
            onPressed: onInvalidate,
          ),
        ],
      ),
    );
  }
}

class _PostsList extends StatelessWidget {
  const _PostsList({required this.staleTime});
  final Duration staleTime;

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<List<Post>>(
      queryKey: const ['posts'],
      queryFn: Net.fetchPosts,
      staleTime: staleTime,
      // Retry up to 3× with a short visible backoff so the "Fail next" button
      // demonstrates recovery (watch the log: ✗ … ✗ … ✓).
      retry: 3,
      retryDelay: (attempt) => Duration(milliseconds: 300 * attempt),
      builder: (context, state, refetch) {
        if (state.isLoading && !state.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.isError && !state.hasData) {
          return _ErrorView(error: state.error, onRetry: refetch);
        }
        final posts = state.data ?? const <Post>[];
        return Stack(
          children: [
            ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = posts[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text('${p.id}')),
                  title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text(p.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  // Detail is a SEPARATE query keyed by id → cached per post.
                  // Re-opening the same post within staleTime is instant (no
                  // dio call); a different post fetches once and caches.
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _PostDetail(id: p.id, staleTime: staleTime),
                  ),
                );
              },
            ),
            if (state.isFetching)
              const Positioned(
                top: 8,
                right: 8,
                child: Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 6),
                  Text('refetching…', style: TextStyle(fontSize: 11)),
                ]),
              ),
          ],
        );
      },
    );
  }
}

class _PostDetail extends StatelessWidget {
  const _PostDetail({required this.id, required this.staleTime});
  final int id;
  final Duration staleTime;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: QueryBuilder<Post>(
          queryKey: ['post', id], // keyed by id
          queryFn: () => Net.fetchPost(id),
          staleTime: staleTime,
          builder: (context, state, refetch) {
            if (state.isLoading && !state.hasData) {
              return const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('fetching from network…'),
                ]),
              );
            }
            if (state.isError && !state.hasData) {
              return _ErrorView(error: state.error, onRetry: refetch);
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
                Text('Re-open this post within staleTime → served from cache '
                    '(no dio request).',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 44),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('$error', textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class _CreatePostForm extends StatefulWidget {
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
        mutationFn: Net.createPost,
        onMutate: (title) {
          // Optimistic insert *before* the request. Snapshot the list and
          // return a rollback closure — swrly runs it automatically if the
          // create fails (dio counter doesn't move for the optimistic write).
          final prev =
              QueryClient.instance.getQueryData<List<Post>>(const ['posts']) ??
                  const <Post>[];
          final optimistic = Post(id: -1, title: title, body: 'saving…');
          QueryClient.instance
              .setQueryData<List<Post>>(const ['posts'], [optimistic, ...prev]);
          Net.note('＋ onMutate → optimistic "$title" prepended');
          return () {
            QueryClient.instance.setQueryData<List<Post>>(const ['posts'], prev);
            Net.note('↩ rollback → optimistic post removed (create failed)');
          };
        },
        onSuccess: (post, _) {
          // Reconcile: swap the optimistic placeholder (id -1) for the server
          // post, still with no refetch.
          final current =
              QueryClient.instance.getQueryData<List<Post>>(const ['posts']) ??
                  const <Post>[];
          QueryClient.instance.setQueryData<List<Post>>(
            const ['posts'],
            [post, ...current.where((p) => p.id != -1)],
          );
          Net.note('✓ create → reconciled with server #${post.id}');
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
              onPressed: state.isLoading ? null : () => mutate(_controller.text),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
