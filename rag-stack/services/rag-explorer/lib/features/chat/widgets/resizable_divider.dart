import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat_notifier.dart';

class ResizableDivider extends ConsumerWidget {
  const ResizableDivider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(
      chatProvider.select((s) => s.value?.metadataPanelWidth ?? 350.0),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final newWidth = width - details.delta.dx;
          ref
              .read(chatProvider.notifier)
              .setMetadataPanelWidth(newWidth.clamp(100.0, 800.0));
        },
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: const VerticalDivider(width: 1),
        ),
      ),
    );
  }
}
