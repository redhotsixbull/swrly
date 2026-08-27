// Compile-check for the Dart snippets in README.md / doc/API.md.
// Nothing here asserts behaviour — the point is that every API the docs show
// actually exists with the shown name, arity and types. If a snippet is edited,
// edit it here too.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swrly/swrly.dart';

class Post {
  Post(this.title);
  final String title;
  static Post fromJson(Object? json) => Post('$json');
  static Post draft(String title) => Post(title);
}

class PostPage {
  PostPage(this.n);
  final int n;
}

class _Api {
  Future<List<Post>> getPosts({int? page, String? q}) async => [Post('a')];
  Future<Post> getPost(int id) async => Post('$id');
  Future<PostPage> getPosts2({required int page, required String q}) async =>
      PostPage(page);
}

final api = _Api();

void main() {
  test('README snippets compile', () async {
    final client = QueryClient();

    // --- "Using swrly without widgets" -------------------------------------
    final posts = await client.fetchQuery<List<Post>>(
      key: const ['posts'],
      fn: () => api.getPosts(),
      staleTime: const Duration(seconds: 30),
    );
    expect(posts, isNotEmpty);

    const id = 3;
    await client.fetchQuery<Post>(
      key: ['post', id],
      fn: () => api.getPost(id),
    );

    final cached = client.getQueryData<List<Post>>(['posts']);
    final state = client.stateOf<List<Post>>(['posts']);
    expect(cached, isNotNull);
    expect(state.isSuccess, isTrue);

    final sub = client
        .observe<List<Post>>(['posts'])
        .listen((state) => state.status.toString());
    await sub.cancel();

    // --- "Define a query once" ---------------------------------------------
    final postsQuery = Query<List<Post>>(
      key: const ['posts'],
      fn: () => api.getPosts(),
      staleTime: const Duration(seconds: 30),
      client: client,
    );

    await postsQuery.fetch();
    await postsQuery.refetch();
    postsQuery.invalidate();
    postsQuery.setData(const <Post>[]);
    postsQuery.remove();
    postsQuery.copyWith(staleTime: Duration.zero);
    expect(postsQuery.data, anyOf(isNull, isA<List<Post>>()));
    expect(postsQuery.state, isA<QueryState<List<Post>>>());
    expect(postsQuery.stream, isA<Stream<QueryState<List<Post>>>>());

    // --- "Parameterised queries" -------------------------------------------
    final postQuery = QueryFamily<Post, int>(
      prefix: const ['post'],
      fn: (id) => api.getPost(id),
      client: client,
    );

    await postQuery(3).fetch();
    postQuery(3).invalidate();
    postQuery.invalidateAll();
    postQuery.removeAll();
    expect(postQuery.keyFor(3), ['post', 3]);

    final pageQuery = QueryFamily<PostPage, (int, String)>(
      prefix: const ['posts'],
      argKey: (a) => [a.$1, a.$2],
      fn: (a) => api.getPosts2(page: a.$1, q: a.$2),
      client: client,
    );
    expect(pageQuery.keyFor((2, 'flutter')), ['posts', 2, 'flutter']);

    // --- client-level prefix APIs named in the README ----------------------
    client.invalidateQueries(const ['posts']);
    client.invalidateQueriesWhere((key) => key.first == 'posts');
    client.removeQueries(const ['posts']);
    client.removeQueriesWhere((key) => key.first == 'posts');
    client.setQueryData<List<Post>>(['posts'], const <Post>[]);
    client.clear();
  });

  testWidgets('README widget snippets compile', (tester) async {
    final client = QueryClient();
    final postsQuery = Query<List<Post>>(
      key: const ['posts'],
      fn: () => api.getPosts(),
      staleTime: const Duration(seconds: 30),
      client: client,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            // Quick start
            QueryBuilder<List<Post>>(
              client: client,
              queryKey: const ['posts-widget'],
              queryFn: () => api.getPosts(),
              staleTime: const Duration(seconds: 30),
              builder: (context, state, refetch) {
                if (state.isLoading && !state.hasData) return const Text('…');
                if (state.isError && !state.hasData) {
                  return Text('Error: ${state.error}');
                }
                return Text('${state.data!.length} '
                    '${state.isFetching} '
                    '${state.isPlaceholderData}');
              },
            ),
            // QueryBuilder.of
            QueryBuilder.of(
              postsQuery,
              builder: (ctx, state, refetch) => Text('${state.status}'),
            ),
            // Mutations
            // NB: MutationBuilder has no `client` parameter — the README's
            // mutation snippets go through QueryClient.instance, matching it.
            MutationBuilder<Post, String>(
              mutationFn: (title) async => Post(title),
              onMutate: (title) {
                final prev = client.getQueryData<List<Post>>(['posts']) ?? [];
                client.setQueryData<List<Post>>(
                    ['posts'], [Post.draft(title), ...prev]);
                return () => client.setQueryData<List<Post>>(['posts'], prev);
              },
              onSuccess: (post, _) {
                final current = client.getQueryData<List<Post>>(['posts']) ?? [];
                client.setQueryData<List<Post>>(['posts'], [post, ...current]);
              },
              onSettled: (_) => client.invalidateQueries(['posts']),
              builder: (context, mutate, state) => GestureDetector(
                onTap: state.isLoading ? null : () => mutate('t'),
                child: Text(state.isLoading ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.clear();
  });
}
