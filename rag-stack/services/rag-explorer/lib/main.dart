import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  runApp(
    const ProviderScope(
      child: RagExplorerApp(),
    ),
  );
}

class RagExplorerApp extends ConsumerWidget {
  const RagExplorerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AppScaffold();
  }
}
