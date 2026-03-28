import 'package:flutter/material.dart';

class MemoryPage extends StatelessWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Explorer')),
      body: const Center(child: Text('Memory Explorer (Phase 3)')),
    );
  }
}
