import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rag_explorer/features/chat/chat_notifier.dart';
import 'package:rag_explorer/features/memory/memory_contracts.dart';
import 'package:rag_explorer/features/memory/memory_notifier.dart';
import 'package:rag_explorer/features/memory/memory_page.dart';
import 'package:rag_explorer/core/models/session.dart';

class _FakeChatNotifier extends ChatNotifier {
  @override
  Future<ChatState> build() async => ChatState(
    sessions: [
      Session(
        createdAt: DateTime.utc(2026, 1, 1),
        id: 1,
        lastActiveAt: DateTime.utc(2026, 1, 1),
        name: 'Demo Session',
      ),
    ],
  );
}

class _FakeMemoryNotifier extends MemoryNotifier {
  @override
  MemoryState build() {
    return const MemoryState(scope: MemoryScope(sessionId: 1));
  }
}

void main() {
  testWidgets('renders the memory explorer shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith(() => _FakeChatNotifier()),
          memoryProvider.overrideWith(() => _FakeMemoryNotifier()),
        ],
        child: const MaterialApp(home: MemoryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Memory Explorer'), findsOneWidget);
    expect(find.text('Demo Session'), findsOneWidget);
    expect(find.text('Write Memory'), findsOneWidget);
    expect(find.text('Retrieve Context'), findsOneWidget);
  });
}
