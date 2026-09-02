import 'package:flutter/material.dart';

import 'api.dart';

/// Small AppBar action that shows the live network-call count. When a
/// `QueryBuilder` serves from cache, this number does NOT move — the
/// demo is that visible.
class NetworkPill extends StatelessWidget {
  const NetworkPill({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_outlined, size: 14, color: scheme.onPrimaryContainer),
            const SizedBox(width: 6),
            ValueListenableBuilder<int>(
              valueListenable: Api.instance.calls,
              builder: (_, n, __) => Text(
                'dio: $n',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
