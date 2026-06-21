import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rag_explorer/core/models/tag.dart';
import 'package:rag_explorer/features/chat/widgets/chat_input_bar.dart';

void main() {
  testWidgets('Enter submits and shift-enter inserts a newline', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController(text: 'Hello');
    var sendCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            enabled: true,
            isStreaming: false,
            controller: controller,
            onSend: () => sendCount++,
            onStop: () {},
            planner: 'llama3.1:latest',
            executor: 'llama3.1:latest',
            embeddingModel: 'all-minilm:l6-v2',
            availableModels: const ['llama3.1:latest'],
            availableEmbeddingModels: const ['all-minilm:l6-v2'],
            availableTags: const [Tag(id: 1, name: 'general')],
            selectedTags: const [],
            onPlannerChanged: (_) {},
            onExecutorChanged: (_) {},
            onEmbeddingModelChanged: (_) {},
            onTagAdded: (_) {},
            onTagRemoved: (_) {},
            memoryMode: 'off',
            onMemoryModeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.text, 'Hello\n');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sendCount, 1);

    controller.dispose();
  });
}
