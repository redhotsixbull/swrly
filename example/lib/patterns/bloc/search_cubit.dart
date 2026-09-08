import 'package:flutter_bloc/flutter_bloc.dart';

/// Pure **client state** — the current search filter. A Cubit is the
/// minimal Bloc shape and fits client state without ceremony.
///
/// Deliberately NOT a Bloc that fetches posts. The moment you write a
/// `PostsBloc` with `LoadPosts` / `PostsLoading` / `PostsLoaded` /
/// `PostsError` states, you're rebuilding what `swrly` already gives you
/// as `QueryState`.
class SearchCubit extends Cubit<String> {
  SearchCubit() : super('');

  void setQuery(String q) {
    if (q == state) return;
    emit(q);
  }
}
