import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 's3_notifier.dart';
import 'widgets/file_list.dart';
import 'widgets/s3_filter_bar.dart';

class S3Page extends ConsumerWidget {
  const S3Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s3Async = ref.watch(s3NotifierProvider);
    final notifier = ref.read(s3NotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('S3 Browser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.refresh(),
          ),
          if (s3Async.value?.selectedFilePaths.isNotEmpty ?? false)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDelete(context, notifier, s3Async.value!.selectedFilePaths.length),
            ),
        ],
      ),
      body: s3Async.when(
        data: (state) => Column(
          children: [
            S3FilterBar(
              availableTags: state.availableTags,
              selectedTags: state.selectedTags,
              availableSessions: state.availableSessions,
              selectedSession: state.selectedSession,
              onTagsChanged: (tags) => notifier.setTags(tags),
              onSessionChanged: (sess) => notifier.setSession(sess),
            ),
            const Divider(height: 1),
            if (state.selectedFilePaths.isNotEmpty)
              _buildSelectionActions(state, notifier),
            Expanded(
              child: state.isLoading 
                ? const Center(child: CircularProgressIndicator())
                : FileList(
                    files: state.files,
                    selectedPaths: state.selectedFilePaths,
                    onToggle: (path) => notifier.toggleFileSelection(path),
                  ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildSelectionActions(S3State state, S3Notifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Row(
        children: [
          Text('${state.selectedFilePaths.length} files selected'),
          const Spacer(),
          TextButton(onPressed: () => notifier.clearSelection(), child: const Text('Clear')),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => notifier.selectAll(state.files),
            child: const Text('Select All'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, S3Notifier notifier, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete $count objects from S3?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      notifier.deleteSelected();
    }
  }
}
