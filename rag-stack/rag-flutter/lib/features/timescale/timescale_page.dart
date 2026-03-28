import 'package:flutter/material.dart';

class TimescalePage extends StatelessWidget {
  const TimescalePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TimescaleDB Explorer')),
      body: const Center(child: Text('TimescaleDB Explorer (Phase 2)')),
    );
  }
}
