import 'package:flutter/material.dart';

import '../models/tag.dart';

Future<List<Tag>?> showTagPickerDialog({
  required BuildContext context,
  required String title,
  required List<Tag> availableTags,
  required List<Tag> selectedTags,
}) {
  final workingSelection = <Tag>{...selectedTags};

  return showDialog<List<Tag>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              height: 420,
              child: availableTags.isEmpty
                  ? const Center(child: Text('No tags available.'))
                  : ListView.builder(
                      itemCount: availableTags.length,
                      itemBuilder: (context, index) {
                        final tag = availableTags[index];
                        final isSelected = workingSelection.contains(tag);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(tag.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                workingSelection.add(tag);
                              } else {
                                workingSelection.remove(tag);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  workingSelection.clear();
                  Navigator.pop(dialogContext, <Tag>[]);
                },
                child: const Text('Clear'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext, workingSelection.toList());
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
}
