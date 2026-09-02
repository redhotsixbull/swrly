import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bloc/posts_screen.dart' as bloc_pattern;
import 'hooks/posts_screen.dart' as hooks_pattern;
import 'plain/posts_screen.dart' as plain_pattern;
import 'provider/posts_screen.dart' as provider_pattern;
import 'riverpod/posts_screen.dart' as riverpod_pattern;

/// Entry screen for browsing state-management patterns. Each row navigates
/// to a self-contained demo showing `swrly` (server state) + that pattern
/// (client state) side by side.
class PatternsHome extends StatelessWidget {
  const PatternsHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patterns')),
      body: ListView(
        children: [
          const _SectionHeader('State management × swrly'),
          _PatternTile(
            title: 'Plain (StatefulWidget)',
            subtitle: 'setState for client state, swrly for server state',
            builder: (_) => const plain_pattern.PostsScreen(),
          ),
          _PatternTile(
            title: 'Provider',
            subtitle: 'ChangeNotifier owns client state, swrly owns server state',
            builder: (_) => const provider_pattern.PostsScreen(),
          ),
          _PatternTile(
            title: 'Riverpod',
            subtitle: 'StateProvider for client state, swrly for server state',
            builder: (_) => const ProviderScope(
              child: riverpod_pattern.PostsScreen(),
            ),
          ),
          _PatternTile(
            title: 'Bloc / Cubit',
            subtitle: 'Cubit owns client state, swrly owns server state',
            builder: (_) => const bloc_pattern.PostsScreen(),
          ),
          _PatternTile(
            title: 'flutter_hooks',
            subtitle: 'useState + canonical useSwrlyQuery snippet',
            builder: (_) => const hooks_pattern.PostsScreen(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'All demos share the same shape: search field (client state) filters '
              'a cached posts list (server state), tap opens a cached detail, '
              'FAB creates optimistically with automatic rollback.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Colors.grey),
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.title,
    required this.subtitle,
    required this.builder,
  });
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: builder),
      ),
    );
  }
}
