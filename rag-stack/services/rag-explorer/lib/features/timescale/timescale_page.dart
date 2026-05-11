import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timescale_notifier.dart';
import 'timescale_dialogs.dart';
import 'widgets/session_list.dart';
import 'widgets/session_details.dart';

class TimescalePage extends ConsumerWidget {
  const TimescalePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timescaleAsync = ref.watch(timescaleNotifierProvider);

    return timescaleAsync.when(
      data: (state) => Scaffold(
        appBar: AppBar(
          title: const Text('TimescaleDB Explorer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.merge_type),
              onPressed: () => TimescaleDialogs.showMergeDialog(context, state.availableTags).then((val) {
                if (val != null) {
                  ref.read(timescaleNotifierProvider.notifier).mergeTags(val['source_tag_ids'], val['target_tag_id']);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tag merge initiated')));
                }
              }),
              tooltip: 'Maintenance: Merge Tags',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(timescaleNotifierProvider.notifier).refresh(),
            ),
          ],
        ),
        body: Row(
          children: [
            SizedBox(
              width: 300,
              child: SessionList(
                sessions: state.sessions,
                selectedSession: state.selectedSession,
                onSelect: (s) => ref.read(timescaleNotifierProvider.notifier).selectSession(s),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: state.selectedSession == null
                ? const Center(child: Text('Select a session to view details'))
                : SessionDetails(
                    session: state.selectedSession!,
                    health: state.currentHealth,
                    auditLogs: state.auditLogs,
                    isLoading: state.isLoadingDetails,
                  ),
            ),
          ],
        ),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, stack) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }
}
