import 'package:flutter/material.dart';

class QdrantPage extends StatelessWidget {
  const QdrantPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Qdrant Vector Explorer')),
      body: const Center(child: Text('Qdrant Vector Explorer (Phase 2)')),
    );
  }
}
