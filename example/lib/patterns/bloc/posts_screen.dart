import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:swrly/swrly.dart';

import '../shared/network_pill.dart';
import '../shared/queries.dart';
import '../shared/widgets.dart';
import 'search_cubit.dart';

/// Pattern: **Bloc / Cubit** × swrly.
///
/// - `SearchCubit` (`Cubit<String>`) owns the search filter — client state.
/// - `swrly` owns the posts list, detail, and create mutation.
///
/// If you already have a `Bloc` that handles a domain state machine
/// (checkout, upload wizard, playback), keep it. Move only the *fetch
/// caching* concern to swrly — usually that lives in the repository layer
/// the Bloc talks to.
class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(),
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
        title: const Text('Bloc + swrly'),
        actions: const [NetworkPill()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search posts (client state via Cubit)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => context.read<SearchCubit>().setQuery(v),
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
          return BlocBuilder<SearchCubit, String>(
            builder: (context, query) {
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
            },
          );
        },
      ),
      floatingActionButton: const CreatePostFab(),
    );
  }
}
