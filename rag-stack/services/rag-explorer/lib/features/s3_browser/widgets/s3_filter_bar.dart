import 'package:flutter/material.dart';
import '../../../core/models/tag.dart';
import '../../../core/models/session.dart';
import '../../../core/widgets/tag_picker_dialog.dart';

class S3FilterBar extends StatelessWidget {
  final List<String> availableBuckets;
  final String? selectedBucket;
  final List<Tag> availableTags;
  final List<Tag> selectedTags;
  final List<Session> availableSessions;
  final Session? selectedSession;
  final Function(String?) onBucketChanged;
  final Function(List<Tag>) onTagsChanged;
  final Function(Session?) onSessionChanged;

  const S3FilterBar({
    super.key,
    required this.availableBuckets,
    required this.selectedBucket,
    required this.availableTags,
    required this.selectedTags,
    required this.availableSessions,
    this.selectedSession,
    required this.onBucketChanged,
    required this.onTagsChanged,
    required this.onSessionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBucketFilter(),
          const SizedBox(height: 16),
          _buildTagFilter(),
          const SizedBox(height: 16),
          _buildSessionFilter(),
        ],
      ),
    );
  }

  Widget _buildBucketFilter() {
    return Row(
      children: [
        const Text('Bucket: ', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String?>(
            value: selectedBucket,
            isExpanded: true,
            hint: const Text('Select a bucket'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All Buckets'),
              ),
              ...availableBuckets.map(
                (bucket) => DropdownMenuItem<String?>(
                  value: bucket,
                  child: Text(bucket),
                ),
              ),
            ],
            onChanged: onBucketChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildTagFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Filter by Tags:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: availableTags.isEmpty
                  ? null
                  : () async {
                      final chosen = await showTagPickerDialog(
                        context: context,
                        title: 'Select S3 filter tags',
                        availableTags: availableTags,
                        selectedTags: selectedTags,
                      );
                      if (chosen == null) return;
                      onTagsChanged(chosen);
                    },
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Pick Tags'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectedTags.isEmpty
              ? [
                  const Text(
                    'No tags selected.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ]
              : selectedTags
                  .map(
                    (tag) => InputChip(
                      label: Text(tag.name),
                      onDeleted: () {
                        final newSelected = List<Tag>.from(selectedTags)
                          ..remove(tag);
                        onTagsChanged(newSelected);
                      },
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  Widget _buildSessionFilter() {
    return Row(
      children: [
        const Text(
          'Filter by Session: ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<Session>(
            value: selectedSession,
            hint: const Text('All Sessions'),
            isExpanded: true,
            items: [
              const DropdownMenuItem<Session>(
                value: null,
                child: Text('All Sessions'),
              ),
              ...availableSessions.map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.name ?? 'Session ${s.id}'),
                ),
              ),
            ],
            onChanged: onSessionChanged,
          ),
        ),
      ],
    );
  }
}
