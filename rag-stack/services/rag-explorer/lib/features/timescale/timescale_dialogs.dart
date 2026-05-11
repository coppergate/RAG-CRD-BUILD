import 'package:flutter/material.dart';
import '../../core/models/tag.dart';

class TimescaleDialogs {
  static Future<Map<String, dynamic>?> showMergeDialog(BuildContext context, List<Tag> tags) {
    List<int> sourceTagIds = [];
    int? targetTagId;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Merge Tags (Maintenance)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Select source tags to merge FROM:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: tags.map((t) => FilterChip(
                    label: Text(t.name, style: const TextStyle(fontSize: 10)),
                    selected: sourceTagIds.contains(t.id),
                    onSelected: (val) {
                      setDialogState(() {
                        if (val) sourceTagIds.add(t.id);
                        else sourceTagIds.remove(t.id);
                      });
                    },
                  )).toList(),
                ),
                const Divider(height: 32),
                const Text('Select target tag to merge INTO:'),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: targetTagId,
                  isExpanded: true,
                  hint: const Text('Select target tag'),
                  items: tags.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (val) => setDialogState(() => targetTagId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (sourceTagIds.isNotEmpty && targetTagId != null && !sourceTagIds.contains(targetTagId))
                ? () => Navigator.pop(context, {
                    'source_tag_ids': sourceTagIds,
                    'target_tag_id': targetTagId,
                  })
                : null,
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }
}
