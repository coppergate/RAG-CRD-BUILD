import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'qdrant_notifier.dart';
import 'widgets/collection_card.dart';
import '../../core/models/metrics.dart';

class QdrantPage extends ConsumerWidget {
  const QdrantPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qdrantAsync = ref.watch(qdrantNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qdrant Vector Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(qdrantNotifierProvider.notifier).refresh(),
          ),
        ],
      ),
      body: qdrantAsync.when(
        data: (state) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: state.collections.length,
          itemBuilder: (context, index) {
            final coll = state.collections[index];
            return CollectionCard(
              name: coll['name'],
              stats: coll['stats'] as QdrantStats,
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
