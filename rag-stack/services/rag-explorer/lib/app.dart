import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Import features
import 'features/chat/chat_page.dart';
import 'features/ingestion/ingestion_page.dart';
import 'features/memory/memory_page.dart';
import 'features/s3_browser/s3_page.dart';
import 'features/timescale/timescale_page.dart';
import 'features/qdrant/qdrant_page.dart';
import 'features/models/models_page.dart';
import 'features/observability/observability_page.dart';
import 'features/settings/settings_page.dart';
import 'app_config_provider.dart';
import 'config/app_config.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/chat',
    navigatorKey: _rootNavigatorKey,
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainScaffold(child: child);
        },
        routes: [
          GoRoute(path: '/chat', builder: (context, state) => const ChatPage()),
          GoRoute(path: '/ingestion', builder: (context, state) => const IngestionPage()),
          GoRoute(path: '/memory', builder: (context, state) => const MemoryPage()),
          GoRoute(path: '/s3', builder: (context, state) => const S3Page()),
          GoRoute(path: '/timescale', builder: (context, state) => const TimescalePage()),
          GoRoute(path: '/qdrant', builder: (context, state) => const QdrantPage()),
          GoRoute(path: '/models', builder: (context, state) => const ModelsPage()),
          GoRoute(path: '/observability', builder: (context, state) => const ObservabilityPage()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
        ],
      ),
    ],
  );
});

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);

    return MaterialApp.router(
      title: 'RAG Pipeline Explorer',
      themeMode: config.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _isPinned = true;
  bool _isHovered = false;

  final List<String> _routes = [
    '/chat',
    '/ingestion',
    '/memory',
    '/s3',
    '/timescale',
    '/qdrant',
    '/models',
    '/observability',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int selectedIndex = _routes.indexOf(location);
    if (selectedIndex == -1) selectedIndex = 0;

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(selectedIndex),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildSidebar(int selectedIndex) {
    final bool isExtended = _isPinned || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isExtended ? 250 : 72,
        child: Column(
          children: [
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: isExtended ? const Text('Pin Menu') : null,
              onTap: () => setState(() => _isPinned = !_isPinned),
            ),
            const Divider(),
            Expanded(
              child: NavigationRail(
                extended: isExtended,
                selectedIndex: selectedIndex,
                onDestinationSelected: (int index) {
                  context.go(_routes[index]);
                },
                labelType: NavigationRailLabelType.none,
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.chat), label: Text('Chat')),
                  NavigationRailDestination(icon: Icon(Icons.upload_file), label: Text('Ingestion')),
                  NavigationRailDestination(icon: Icon(Icons.memory), label: Text('Memory')),
                  NavigationRailDestination(icon: Icon(Icons.storage), label: Text('S3 Browser')),
                  NavigationRailDestination(icon: Icon(Icons.table_chart), label: Text('TimescaleDB')),
                  NavigationRailDestination(icon: Icon(Icons.hub), label: Text('Qdrant')),
                  NavigationRailDestination(icon: Icon(Icons.compare), label: Text('Model Comparison')),
                  NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Observability')),
                  NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
