import 'package:flutter/material.dart';
import '../../../core/models/metrics.dart';

class FileList extends StatelessWidget {
  final List<VirtualFile> files;
  final Set<String> selectedPaths;
  final Function(String) onToggle;

  const FileList({
    super.key,
    required this.files,
    required this.selectedPaths,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const Center(child: Text('No files found in S3.'));
    }

    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = selectedPaths.contains(file.path);

        return ListTile(
          leading: Checkbox(
            value: isSelected,
            onChanged: (_) => onToggle(file.path),
          ),
          title: Text(file.path),
          subtitle: Text(
            'Bucket: ${file.bucket} | Tags: ${file.tags.join(", ")}',
          ),
          trailing: Text(file.status),
          onTap: () => onToggle(file.path),
        );
      },
    );
  }
}
